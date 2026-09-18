import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../widgets.dart';
import 'session_detail_screen.dart';

/// 历史会话列表。
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('历史记录')),
      body: s.history.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_rounded, size: 64, color: theme.colorScheme.outline),
                  const SizedBox(height: 12),
                  Text('暂无记录', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text('完成一次录音翻译后会自动保存到这里',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            )
          : ListView.separated(
              itemCount: s.history.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
              itemBuilder: (context, i) {
                final item = s.history[i];
                return Dismissible(
                  key: ValueKey(item.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: theme.colorScheme.errorContainer,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: Icon(Icons.delete_outline, color: theme.colorScheme.onErrorContainer),
                  ),
                  onDismissed: (_) => context.read<AppState>().deleteSession(item.id),
                  child: ListTile(
                    leading: Icon(
                      item.hasAudio ? Icons.headphones_rounded : Icons.chat_bubble_outline_rounded,
                      color: theme.colorScheme.primary,
                    ),
                    title: Text(fmtDate(item.startedAt)),
                    subtitle: Text(
                      '${item.sourceLanguage.emoji}${item.sourceLanguage.label} → '
                      '${item.targetLanguage.emoji}${item.targetLanguage.label} · '
                      '${item.segments.length} 段 · ${fmtDuration(item.durationSec)}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SessionDetailScreen(sessionId: item.id),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}
