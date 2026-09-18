import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'languages.dart';
import 'models.dart';

String fmtDuration(int sec) {
  final h = sec ~/ 3600;
  final m = (sec % 3600) ~/ 60;
  final s = sec % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

String fmtDate(DateTime t) => DateFormat('MM-dd HH:mm').format(t);

/// 语言选择按钮 + 底部弹层。
class LanguageButton extends StatelessWidget {
  final LanguageOption lang;
  final String hint;
  final bool enabled;
  final ValueChanged<LanguageOption> onPick;

  const LanguageButton({
    super.key,
    required this.lang,
    required this.hint,
    required this.onPick,
    this.enabled = true,
  });

  void _showSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(hint, style: Theme.of(ctx).textTheme.titleSmall),
            ),
            for (final l in kLanguages)
              ListTile(
                leading: Text(l.emoji, style: const TextStyle(fontSize: 22)),
                title: Text(l.label),
                trailing: l.code == lang.code
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  onPick(l);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: enabled ? () => _showSheet(context) : null,
      icon: Text(lang.emoji, style: const TextStyle(fontSize: 18)),
      // OutlinedButton.icon 内部已用 Flexible 包裹 label，这里不能再套
      label: Text(lang.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        minimumSize: const Size(0, 44),
      ),
    );
  }
}

/// 一段双语文本（原文 + 译文）。
class SegmentTile extends StatelessWidget {
  final Segment segment;
  final bool showTranslation;
  final VoidCallback? onTap;

  const SegmentTile({
    super.key,
    required this.segment,
    this.showTranslation = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              segment.source,
              style: TextStyle(
                fontSize: 15,
                height: 1.45,
                color: theme.colorScheme.onSurface,
              ),
            ),
            if (showTranslation && segment.translated.isNotEmpty) ...[
              const SizedBox(height: 2),
              SelectableText(
                segment.translated,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.45,
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 实时未定稿的识别文本（灰色斜体）。
class PartialTile extends StatelessWidget {
  final String source;
  final String translation;
  final bool showTranslation;

  const PartialTile({
    super.key,
    required this.source,
    required this.translation,
    this.showTranslation = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (source.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            source,
            style: TextStyle(
              fontSize: 15,
              height: 1.45,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (showTranslation && translation.isNotEmpty)
            Text(
              translation,
              style: TextStyle(
                fontSize: 15,
                height: 1.45,
                color: theme.colorScheme.primary.withValues(alpha: 0.55),
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }
}

String sessionToText(Session s) {
  final buf = StringBuffer();
  buf.writeln('声译通 · ${fmtDate(s.startedAt)} · ${s.sourceLanguage.label}→${s.targetLanguage.label}');
  for (final seg in s.segments) {
    buf.writeln();
    buf.writeln(seg.source);
    if (seg.translated.isNotEmpty) buf.writeln(seg.translated);
  }
  return buf.toString();
}
