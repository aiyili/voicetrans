import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../widgets.dart';

/// 主页：实时翻译。
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ScrollController _scroll = ScrollController();
  bool _autoScroll = true;
  int _lastCount = 0;
  String _lastPartial = '';

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _maybeScrollDown() {
    if (!_autoScroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _copyAll(AppState s) async {
    final text = <String>[
      for (final seg in s.segments) ...[seg.source, if (seg.translated.isNotEmpty) seg.translated],
      if (s.partialSource.isNotEmpty) s.partialSource,
    ].join('\n');
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('已复制全部文本'), duration: Duration(seconds: 1)));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final theme = Theme.of(context);

    if (s.segments.length != _lastCount || s.partialSource != _lastPartial) {
      _lastCount = s.segments.length;
      _lastPartial = s.partialSource;
      _maybeScrollDown();
    }

    final levelNorm =
        s.isListening ? ((s.level + 55) / 55).clamp(0.0, 1.0) : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('声译通'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: '复制全部文本',
            icon: const Icon(Icons.copy),
            onPressed: () => _copyAll(s),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 语言选择行
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: LanguageButton(
                      lang: s.sourceLang,
                      hint: '识别语言（源）',
                      enabled: !s.isBusy,
                      onPick: (l) => context.read<AppState>().setSourceLang(l),
                    ),
                  ),
                  IconButton(
                    tooltip: '交换语言',
                    onPressed: s.isBusy ? null : () => context.read<AppState>().swapLanguages(),
                    icon: const Icon(Icons.swap_horiz),
                  ),
                  Expanded(
                    child: LanguageButton(
                      lang: s.targetLang,
                      hint: '翻译为（目标）',
                      enabled: !s.isBusy,
                      onPick: (l) => context.read<AppState>().setTargetLang(l),
                    ),
                  ),
                ],
              ),
            ),

            // 音量指示
            if (s.isListening)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: LinearProgressIndicator(
                  value: levelNorm,
                  minHeight: 3,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

            // 状态行
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  if (s.isListening)
                    const Icon(Icons.circle, size: 10, color: Colors.red)
                  else if (s.isBusy)
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.isListening
                          ? '识别中 ${fmtDuration(s.elapsedSec)}${s.currentSession?.hasAudio == true ? ' · 🎙录音中' : ''}'
                          : (s.statusHint.isNotEmpty
                              ? s.statusHint
                              : (s.lastError.isNotEmpty ? s.lastError : '点击下方按钮开始')),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: s.lastError.isNotEmpty && !s.isListening
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // 转写区
            Expanded(
              child: s.segments.isEmpty &&
                      s.partialSource.isEmpty &&
                      s.currentSession == null
                  ? _EmptyHint(listening: s.isListening)
                  : NotificationListener<ScrollNotification>(
                      onNotification: (n) {
                        if (n is ScrollUpdateNotification && n.metrics.hasContentDimensions) {
                          _autoScroll =
                              n.metrics.pixels >= n.metrics.maxScrollExtent - 140;
                        }
                        return false;
                      },
                      child: ListView.builder(
                        controller: _scroll,
                        itemCount: s.segments.length + 1,
                        itemBuilder: (context, i) {
                          if (i < s.segments.length) {
                            final seg = s.segments[i];
                            return SegmentTile(
                              segment: seg,
                              showTranslation: !s.sameLanguage,
                              onTap: seg.translated == '（翻译失败，点击重试）'
                                  ? () => context.read<AppState>().retrySegment(seg)
                                  : null,
                            );
                          }
                          return PartialTile(
                            source: s.partialSource,
                            translation: s.partialTranslation,
                            showTranslation: !s.sameLanguage,
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.large(
            heroTag: 'mainMic',
            onPressed: s.isBusy ? () => s.stop() : () => s.start(),
            backgroundColor:
                s.isListening ? theme.colorScheme.errorContainer : theme.colorScheme.primaryContainer,
            child: Icon(
              s.isListening ? Icons.stop_rounded : Icons.mic_rounded,
              size: 36,
              color: s.isListening
                  ? theme.colorScheme.onErrorContainer
                  : theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            s.isListening ? '停止' : '开始',
            style: theme.textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final bool listening;
  const _EmptyHint({required this.listening});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(listening ? Icons.graphic_eq : Icons.mic_none_rounded,
                size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              listening ? '请开始说话…' : '长时间录音 · 实时识别 · 离线翻译',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '首次使用某种语言对时会联网下载离线翻译模型（约 30MB/语言），之后翻译完全在本地运行，免费且不限时长。\n录音与转写记录可在「历史」中回放、复制。',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.6),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
