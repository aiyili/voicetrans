import 'languages.dart';

/// 一句被最终确认的识别结果 + 其译文。
class Segment {
  String source;
  String translated;
  final DateTime at;

  Segment({required this.source, this.translated = '', required this.at});

  Map<String, dynamic> toJson() => {
        's': source,
        't': translated,
        'a': at.toIso8601String(),
      };

  Segment.fromJson(Map<String, dynamic> json)
      : source = json['s'] as String? ?? '',
        translated = json['t'] as String? ?? '',
        at = DateTime.tryParse(json['a'] as String? ?? '') ?? DateTime.now();
}

/// 一次录音翻译会话。
class Session {
  final String id;
  final DateTime startedAt;
  int durationSec;
  final String sourceCode;
  final String targetCode;
  final List<Segment> segments;

  /// 录音文件名（位于应用文档目录 recordings/ 下），可能为空。
  final String? audioFileName;

  Session({
    required this.id,
    required this.startedAt,
    this.durationSec = 0,
    required this.sourceCode,
    required this.targetCode,
    List<Segment>? segments,
    this.audioFileName,
  }) : segments = segments ?? [];

  LanguageOption get sourceLanguage => langByCode(sourceCode);
  LanguageOption get targetLanguage => langByCode(targetCode);
  bool get hasAudio => audioFileName != null && audioFileName!.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        't': startedAt.toIso8601String(),
        'd': durationSec,
        's': sourceCode,
        'g': targetCode,
        'f': audioFileName,
        'segs': segments.map((e) => e.toJson()).toList(),
      };

  Session.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        startedAt = DateTime.tryParse(json['t'] as String? ?? '') ?? DateTime.now(),
        durationSec = json['d'] as int? ?? 0,
        sourceCode = json['s'] as String? ?? 'english',
        targetCode = json['g'] as String? ?? 'chinese',
        audioFileName = json['f'] as String?,
        segments = ((json['segs'] as List?) ?? [])
            .map((e) => Segment.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
}
