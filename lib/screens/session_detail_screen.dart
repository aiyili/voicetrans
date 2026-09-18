import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../widgets.dart';

/// 会话详情：录音回放 + 双语转写。
class SessionDetailScreen extends StatefulWidget {
  final String sessionId;
  const SessionDetailScreen({super.key, required this.sessionId});

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  AudioPlayer? _player;
  String? _audioPath;
  bool _audioReady = false;

  @override
  void initState() {
    super.initState();
    _initAudio();
  }

  Future<void> _initAudio() async {
    final state = context.read<AppState>();
    Session? session;
    for (final s in state.history) {
      if (s.id == widget.sessionId) session = s;
    }
    if (session == null || !session.hasAudio) return;
    try {
      final path = await state.audioPathOf(session);
      if (!File(path).existsSync()) return;
      final player = AudioPlayer();
      await player.setFilePath(path);
      if (!mounted) {
        player.dispose();
        return;
      }
      setState(() {
        _player = player;
        _audioPath = path;
        _audioReady = true;
      });
    } catch (_) {/* 音频不可用时仅展示文本 */}
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _copyAll(Session session) async {
    await Clipboard.setData(ClipboardData(text: sessionToText(session)));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
          content: Text('已复制本次转写'), duration: Duration(seconds: 1)));
  }

  Future<void> _confirmDelete(BuildContext context, AppState state, Session session) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这条记录？'),
        content: const Text('转写与录音文件将一并删除，无法恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!context.mounted) return;
    Navigator.of(context).pop();
    await state.deleteSession(session.id);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    Session? session;
    for (final s in state.history) {
      if (s.id == widget.sessionId) session = s;
    }

    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('记录详情')),
        body: const Center(child: Text('记录不存在或已删除')),
      );
    }

    final theme = Theme.of(context);
    final player = _player;

    return Scaffold(
      appBar: AppBar(
        title: Text(fmtDate(session.startedAt)),
        actions: [
          IconButton(
            tooltip: '复制转写',
            icon: const Icon(Icons.copy),
            onPressed: () => _copyAll(session),
          ),
          IconButton(
            tooltip: '删除',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context, state, session),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '${session.sourceLanguage.emoji} ${session.sourceLanguage.label} → '
              '${session.targetLanguage.emoji} ${session.targetLanguage.label} · '
              '${session.segments.length} 段 · ${fmtDuration(session.durationSec)}'
              '${_audioReady ? ' · 🎙 可回放' : ''}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          if (_audioReady && player != null)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.play_arrow_rounded),
                      iconSize: 32,
                      color: theme.colorScheme.primary,
                      onPressed: () {
                        if (player.playing) {
                          player.pause();
                        } else {
                          player.play();
                        }
                        setState(() {});
                      },
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          _AudioSlider(player: player, onChanged: () => setState(() {})),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: session.segments.isEmpty
                ? const Center(child: Text('本次没有识别到文字，仅保存了录音'))
                : ListView.builder(
                    itemCount: session.segments.length,
                    itemBuilder: (context, i) => SegmentTile(
                      segment: session!.segments[i],
                      showTranslation:
                          session.sourceLanguage.code != session.targetLanguage.code,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _AudioSlider extends StatefulWidget {
  final AudioPlayer player;
  final VoidCallback onChanged;
  const _AudioSlider({required this.player, required this.onChanged});

  @override
  State<_AudioSlider> createState() => _AudioSliderState();
}

class _AudioSliderState extends State<_AudioSlider> {
  @override
  void initState() {
    super.initState();
    widget.player.positionStream.listen((_) {
      if (mounted) widget.onChanged();
    });
    widget.player.playerStateStream.listen((_) {
      if (mounted) widget.onChanged();
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.player;
    final pos = p.position;
    final dur = p.duration ?? Duration.zero;
    final total = dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1.0;
    return Column(
      children: [
        Slider(
          value: pos.inMilliseconds.clamp(0, total).toDouble(),
          max: total,
          onChanged: (v) => p.seek(Duration(milliseconds: v.toInt())),
        ),
        Text(
          '${fmtDuration(pos.inSeconds)} / ${fmtDuration(dur.inSeconds)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
