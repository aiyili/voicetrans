import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
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
  Timer? _restartTimer;
  DateTime _lastRestart = DateTime.fromMillisecondsSinceEpoch(0);
  int _restartCount = 0;
  int _restartSeq = 0;
  int _busyStreak = 0;
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
    _restartTimer?.cancel();
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
        try {
          await _translator.ensureModels(sourceLang, targetLang);
        } catch (_) {
          // 模型暂不可用不阻塞识别：翻译器会在翻译每句时自行重试下载
        }
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
      _busyStreak = 0;
      state = RecState.listening;
      statusHint = '';
      notifyListeners();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!_disposed) notifyListeners();
      });
      // 先 cancel 清掉可能残留的识别会话（上次崩溃/其他应用占用），避免 ERROR_RECOGNIZER_BUSY
      try {
        _stt.cancel();
      } catch (_) {}
      _scheduleRestart();
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

  /// 直接发起一次识别（仅在确定没有活动会话时使用；常规路径走 [_scheduleRestart]）。
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

  /// 统一的重启调度：先 cancel 释放上一个会话，防抖延迟后再发起新识别。
  /// Android 静音数秒、iOS 约一分钟会结束单次识别会话，这里自动续听实现长时间连续识别。
  ///
  /// 插件 Android 实现把所有错误标记为 permanent，因此瞬态错误（busy/no_match/
  /// speech_timeout 等）也经由 [_onSttError] 走到这里：静默重启即可，busy 用指数退避。
  void _scheduleRestart({bool busy = false}) {
    if (_disposed || state != RecState.listening) return;
    if (_stt.isListening) {
      _busyStreak = 0;
      return;
    }

    _restartSeq++;
    final seq = _restartSeq;
    if (busy) {
      _busyStreak++;
      if (_busyStreak > 8) {
        lastError = '识别服务持续繁忙（error_busy）：请稍后重试，或在设置中关闭"同时保存录音"再试';
        stop();
        return;
      }
    } else {
      _busyStreak = 0;
    }

    final now = DateTime.now();
    if (now.difference(_lastRestart).inMilliseconds > 20000) {
      _restartCount = 0;
    }
    _lastRestart = now;
    _restartCount++;
    if (_restartCount > 300) {
      // 保险丝：识别会话在极短时间内被系统反复结束（非正常静音节奏），放弃以免耗电。
      lastError = '识别服务频繁中断，已停止。请稍后重试。';
      stop();
      return;
    }

    final delay = busy
        ? Duration(
            milliseconds:
                (250 * math.pow(1.6, _busyStreak)).clamp(250, 5000).toInt())
        : const Duration(milliseconds: 200);
    _restartTimer?.cancel();
    _restartTimer = Timer(delay, () async {
      if (_disposed || state != RecState.listening || seq != _restartSeq) return;
      if (_stt.isListening) return;
      try {
        _stt.cancel();
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (_disposed || state != RecState.listening || seq != _restartSeq) return;
      if (_stt.isListening) return;
      _listen();
    });
  }

  Future<void> stop() async {
    if (state == RecState.idle) return;
    state = RecState.idle;
    statusHint = '';
    _ticker?.cancel();
    _ticker = null;
    _restartTimer?.cancel();
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

  /// 插件 Android 实现将所有错误都标记为 permanent（写死 true），不能采信；
  /// 真正致命、无法靠重试恢复的错误只有下面这些。
  static const _fatalSttErrors = {
    'error_permission',
    'error_not_initialized',
    'error_language_not_supported',
    'error_language_unavailable',
  };

  static String _friendlySttError(String msg) {
    switch (msg) {
      case 'error_permission':
        return '没有麦克风/语音识别权限，请在系统设置中授权';
      case 'error_not_initialized':
        return '语音识别初始化失败，请重试';
      case 'error_language_not_supported':
      case 'error_language_unavailable':
        return '当前识别语言在此设备上不可用';
      default:
        return '语音识别出错：$msg';
    }
  }

  void _onSttStatus(String status) {
    if (_disposed || state != RecState.listening) return;
    // 会话被系统结束（Android 静音数秒、iOS 约一分钟）后自动续听。
    if (status == 'notListening' || status == 'done') {
      _scheduleRestart();
    }
  }

  void _onSttError(SpeechRecognitionError error) {
    if (_disposed || state != RecState.listening) return;
    if (_fatalSttErrors.contains(error.errorMsg)) {
      lastError = _friendlySttError(error.errorMsg);
      stop();
      return;
    }
    // 瞬态错误（busy / no_match / speech_timeout / client / network 等）：
    // 静默退避重启。安静场景下系统会周期性发 no_match / speech_timeout，属正常节奏。
    _scheduleRestart(busy: error.errorMsg == 'error_busy');
  }

  void _onResult(SpeechRecognitionResult result) {
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 从后台回到前台时，识别会话可能已被系统中断，自动续听。
      if (this.state == RecState.listening) {
        _scheduleRestart();
      }
    }
  }
}
