import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'languages.dart';
import 'models.dart';
import 'services/recorder_service.dart';
import 'services/stt_service.dart';
import 'services/translation_service.dart';

enum RecState { idle, preparing, listening }

/// 全局应用状态：录音 + 实时识别 + 离线翻译 + 历史记录。
class AppState extends ChangeNotifier with WidgetsBindingObserver {
  static const _kHistory = 'vt_history_v1';
  static const _kSource = 'vt_source';
  static const _kTarget = 'vt_target';
  static const _kSaveAudio = 'vt_save_audio';
  static const _kKeepAwake = 'vt_keep_awake';
  static const _maxSessions = 200;

  final SttService _stt = SttService();
  final RecorderService _recorder = RecorderService();
  final TranslationService _translator = TranslationService();
  final Uuid _uuid = const Uuid();

  SharedPreferences? _prefs;

  RecState state = RecState.idle;
  String statusHint = '';
  String lastError = '';

  LanguageOption sourceLang = langByCode('english');
  LanguageOption targetLang = langByCode('chinese');

  bool saveAudio = true;
  bool keepAwake = true;

  /// 当前会话（进行中或刚结束、仍显示在主页的会话）。
  Session? currentSession;
  final List<Segment> segments = [];
  String partialSource = '';
  String partialTranslation = '';
  double level = 0; // dBFS，约 -100..0

  List<Session> history = [];

  DateTime? _sessionStart;
  Timer? _ticker;
  Timer? _errorRestartTimer;
  DateTime _lastRestart = DateTime.fromMillisecondsSinceEpoch(0);
  int _restartCount = 0;
  int _partialSeq = 0;
  bool _disposed = false;

  bool get isBusy => state != RecState.idle;
  bool get isListening => state == RecState.listening;
  bool get sameLanguage => sourceLang.code == targetLang.code;
  int get elapsedSec =>
      _sessionStart == null ? 0 : DateTime.now().difference(_sessionStart!).inSeconds;

  TranslationService get translator => _translator;

  // ---------------------------------------------------------------- lifecycle

  Future<void> loadAll() async {
    _prefs = await SharedPreferences.getInstance();
    sourceLang = langByCode(_prefs!.getString(_kSource) ?? 'english');
    targetLang = langByCode(_prefs!.getString(_kTarget) ?? 'chinese');
    saveAudio = _prefs!.getBool(_kSaveAudio) ?? true;
    keepAwake = _prefs!.getBool(_kKeepAwake) ?? true;
    try {
      final raw = _prefs!.getStringList(_kHistory) ?? const [];
      history = raw.map((e) {
        try {
          return Session.fromJson(Map<String, dynamic>.from(jsonDecode(e) as Map));
        } catch (_) {
          return null;
        }
      }).whereType<Session>().toList();
    } catch (_) {
      history = [];
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _errorRestartTimer?.cancel();
    _translator.dispose();
    _recorder.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- settings

  Future<void> setSourceLang(LanguageOption l) async {
    if (isBusy) return;
    sourceLang = l;
    await _prefs?.setString(_kSource, l.code);
    notifyListeners();
  }

  Future<void> setTargetLang(LanguageOption l) async {
    if (isBusy) return;
    targetLang = l;
    await _prefs?.setString(_kTarget, l.code);
    notifyListeners();
  }

  Future<void> swapLanguages() async {
    if (isBusy) return;
    final s = sourceLang;
    sourceLang = targetLang;
    targetLang = s;
    await _prefs?.setString(_kSource, sourceLang.code);
    await _prefs?.setString(_kTarget, targetLang.code);
    notifyListeners();
  }

  Future<void> setSaveAudio(bool v) async {
    saveAudio = v;
    await _prefs?.setBool(_kSaveAudio, v);
    notifyListeners();
  }

  Future<void> setKeepAwake(bool v) async {
    keepAwake = v;
    await _prefs?.setBool(_kKeepAwake, v);
    notifyListeners();
  }

  // ---------------------------------------------------------------- recording

  Future<void> start() async {
    if (isBusy) return;
    lastError = '';
    state = RecState.preparing;
    statusHint = '正在初始化语音识别…';
    segments.clear();
    partialSource = '';
    partialTranslation = '';
    level = 0;
    notifyListeners();

    try {
      final ok = await _stt.ensureInit(onStatus: _onSttStatus, onError: _onSttError);
      if (!ok) {
        throw Exception('语音识别不可用：请检查麦克风权限，或设备不支持语音识别');
      }

      if (!sameLanguage) {
        statusHint = '正在准备离线翻译模型（首次约需 30MB/语言）…';
        notifyListeners();
        await _translator.ensureModels(sourceLang, targetLang);
      }

      String? audioFile;
      if (saveAudio) {
        statusHint = '正在开始录音…';
        notifyListeners();
        audioFile = await _beginRecording();
      }

      currentSession = Session(
        id: _uuid.v4(),
        startedAt: DateTime.now(),
        sourceCode: sourceLang.code,
        targetCode: targetLang.code,
        audioFileName: audioFile,
      );

      if (keepAwake) {
        unawaited(WakelockPlus.enable());
      }

      _sessionStart = DateTime.now();
      _restartCount = 0;
      state = RecState.listening;
      statusHint = '';
      notifyListeners();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!_disposed) notifyListeners();
      });
      _listen();
    } catch (e) {
      state = RecState.idle;
      statusHint = '';
      lastError = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
    }
  }

  Future<String?> _beginRecording() async {
    try {
      final dir = await recordingsDir();
      final name = '${_uuid.v4()}.m4a';
      final path = '${dir.path}${Platform.pathSeparator}$name';
      final ok = await _recorder.start(path);
      return ok ? name : null;
    } catch (_) {
      return null;
    }
  }

  void _listen() {
    if (_disposed || state != RecState.listening) return;
    _stt.listen(
      onResult: _onResult,
      onSoundLevel: (db) {
        level = db;
        notifyListeners();
      },
      localeId: sourceLang.sttLocale,
    );
  }

  Future<void> stop() async {
    if (state == RecState.idle) return;
    state = RecState.idle;
    statusHint = '';
    _ticker?.cancel();
    _ticker = null;
    _errorRestartTimer?.cancel();
    try {
      _stt.stop();
    } catch (_) {}
    notifyListeners();

    if (currentSession != null) {
      currentSession!.durationSec = elapsedSec;
      await _recorder.stop();
      if (keepAwake) {
        unawaited(WakelockPlus.disable());
      }
      if (currentSession!.segments.isNotEmpty || currentSession!.hasAudio) {
        _upsertSession(currentSession!);
      }
    }
    _sessionStart = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------- stt callbacks

  void _onSttStatus(String status) {
    if (_disposed || state != RecState.listening) return;
    // Android 静音数秒、iOS 约一分钟后会话会被系统结束，这里自动重启实现长时间连续识别。
    if (status == 'notListening' || status == 'done') {
      if (!_stt.isListening) {
        final now = DateTime.now();
        if (now.difference(_lastRestart).inMilliseconds > 20000) {
          _restartCount = 0;
        }
        _lastRestart = now;
        _restartCount++;
        if (_restartCount > 60) {
          lastError = '识别服务频繁中断，已停止。请稍后重试。';
          stop();
          return;
        }
        _listen();
      }
    }
  }

  void _onSttError(stt.SpeechRecognitionError error) {
    if (_disposed || state != RecState.listening) return;
    if (error.permanent) {
      lastError = '语音识别出错：${error.errorMsg}';
      stop();
      return;
    }
    // 临时错误（如 no-speech）：稍后自动重启。
    _errorRestartTimer?.cancel();
    _errorRestartTimer = Timer(const Duration(milliseconds: 500), () {
      if (!_disposed && state == RecState.listening && !_stt.isListening) {
        _listen();
      }
    });
  }

  void _onResult(stt.SpeechRecognitionResult result) {
    if (_disposed || state != RecState.listening) return;
    if (result.finalResult) {
      final text = result.recognizedWords.trim();
      if (text.isNotEmpty) {
        final seg = Segment(source: text, translated: '', at: DateTime.now());
        segments.add(seg);
        currentSession?.segments.add(seg);
        partialSource = '';
        partialTranslation = '';
        notifyListeners();
        _persistCurrent();
        if (!sameLanguage) {
          _translateSegment(seg);
        }
      }
    } else {
      partialSource = result.recognizedWords;
      notifyListeners();
      _translatePartial(partialSource);
    }
  }

  Future<void> _translateSegment(Segment seg) async {
    try {
      final t = await _translator.translate(sourceLang, targetLang, seg.source);
      if (_disposed) return;
      seg.translated = t;
      notifyListeners();
      _persistCurrent();
    } catch (_) {
      if (_disposed) return;
      seg.translated = '（翻译失败，点击重试）';
      notifyListeners();
    }
  }

  Future<void> retrySegment(Segment seg) async {
    if (sameLanguage) return;
    seg.translated = '';
    notifyListeners();
    await _translateSegment(seg);
  }

  Future<void> _translatePartial(String text) async {
    if (sameLanguage || text.trim().isEmpty) {
      _partialSeq++;
      partialTranslation = '';
      notifyListeners();
      return;
    }
    final seq = ++_partialSeq;
    try {
      final t = await _translator.translate(sourceLang, targetLang, text);
      if (_disposed || seq != _partialSeq) return;
      partialTranslation = t;
      notifyListeners();
    } catch (_) {/* 部分结果翻译失败可忽略 */}
  }

  // ---------------------------------------------------------------- history

  Future<Directory> recordingsDir() async {
    final doc = await getApplicationDocumentsDirectory();
    final dir = Directory('${doc.path}${Platform.pathSeparator}recordings');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  Future<String> audioPathOf(Session s) async {
    final dir = await recordingsDir();
    return '${dir.path}${Platform.pathSeparator}${s.audioFileName}';
  }

  void _upsertSession(Session s) {
    final idx = history.indexWhere((e) => e.id == s.id);
    if (idx >= 0) {
      history[idx] = s;
    } else {
      history.insert(0, s);
    }
    while (history.length > _maxSessions) {
      final removed = history.removeLast();
      _deleteAudioFile(removed);
    }
    _persistHistory();
    notifyListeners();
  }

  void _persistCurrent() {
    final s = currentSession;
    if (s == null) return;
    _upsertSession(s);
  }

  Future<void> _persistHistory() async {
    try {
      final raw = history.map((e) => jsonEncode(e.toJson())).toList();
      await _prefs?.setStringList(_kHistory, raw);
    } catch (_) {}
  }

  void _deleteAudioFile(Session s) {
    if (!s.hasAudio) return;
    recordingsDir().then((d) {
      final f = File('${d.path}${Platform.pathSeparator}${s.audioFileName}');
      if (f.existsSync()) f.deleteSync();
    }).catchError((_) {});
  }

  Future<void> deleteSession(String id) async {
    final idx = history.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    final s = history.removeAt(idx);
    _deleteAudioFile(s);
    if (currentSession?.id == id) {
      currentSession = null;
      segments.clear();
    }
    await _persistHistory();
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState == AppLifecycleState.resumed) {
      // 从后台回到前台时，识别会话可能已被系统中断，自动续听。
      if (state == RecState.listening && !_stt.isListening) {
        _listen();
      }
    }
  }
}
