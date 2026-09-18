import 'package:speech_to_text/speech_to_text.dart' as stt;

/// 语音识别封装：系统级实时识别（Android RecognitionService / iOS Speech）。
/// 系统在静音或约 1 分钟后会结束会话，上层负责自动重启以实现长时间连续识别。
class SttService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _initialized = false;

  bool get isListening => _speech.isListening;

  /// 只允许成功初始化一次；再次调用直接返回上次结果。
  Future<bool> ensureInit({
    void Function(String status)? onStatus,
    void Function(stt.SpeechRecognitionError error)? onError,
  }) async {
    if (_initialized) return true;
    _initialized = await _speech.initialize(
      onStatus: onStatus,
      onError: onError,
    );
    return _initialized;
  }

  void listen({
    required void Function(stt.SpeechRecognitionResult result) onResult,
    void Function(double level)? onSoundLevel,
    String? localeId,
  }) {
    if (!_initialized) return;
    _speech.listen(
      onResult: onResult,
      onSoundLevelChange: onSoundLevel,
      localeId: localeId,
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        listenMode: stt.ListenMode.dictation,
        autoPunctuation: true,
      ),
    );
  }

  void stop() => _speech.stop();
  void cancel() => _speech.cancel();
}
