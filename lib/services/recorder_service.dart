import 'package:record/record.dart';

/// 长时间录音封装：aac/m4a 持续写入文件，时长仅受存储与电量限制。
/// Android 端由 record 插件的前台服务保障后台持续录音。
class RecorderService {
  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;

  bool get isRecording => _recording;

  /// 返回 false 表示没有麦克风权限。
  Future<bool> start(String fullPath) async {
    if (!await _recorder.hasPermission()) return false;
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 44100,
        numOfChannels: 1,
      ),
      path: fullPath,
    );
    _recording = true;
    return true;
  }

  /// 返回录音文件路径。
  Future<String?> stop() async {
    _recording = false;
    try {
      return await _recorder.stop();
    } catch (_) {
      return null;
    }
  }

  Future<void> dispose() => _recorder.dispose();
}
