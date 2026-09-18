import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../languages.dart';
import '../widgets.dart';

/// 设置页。
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          _section(context, '翻译'),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
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
                const SizedBox(width: 8),
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
          SwitchListTile(
            title: const Text('同时保存录音文件'),
            subtitle: const Text('录音保存在本机应用目录，可在历史中回放，不联网上传'),
            value: s.saveAudio,
            onChanged: (v) => context.read<AppState>().setSaveAudio(v),
          ),
          SwitchListTile(
            title: const Text('录音时保持屏幕常亮'),
            subtitle: const Text('适合会议、上课等长时间场景'),
            value: s.keepAwake,
            onChanged: (v) => context.read<AppState>().setKeepAwake(v),
          ),
          _section(context, '离线翻译模型'),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '翻译由 Google ML Kit 端上模型完成，下载后完全离线运行、免费不限量。可按需管理已下载的语言模型。',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const _ModelManager(),
          _section(context, '关于'),
          const ListTile(
            dense: true,
            title: Text('声译通 VoiceTrans'),
            subtitle: Text('版本 1.0.0 · 免费开源（MIT）'),
          ),
          ListTile(
            dense: true,
            title: const Text('工作原理'),
            subtitle: Text(
              '实时识别由系统语音服务提供（Android RecognitionService / iOS Speech，免费）；'
              '翻译使用端上离线模型；录音保存在本机。无账号、无云端上传。',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(
          title,
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(color: Theme.of(context).colorScheme.primary),
        ),
      );
}

/// 语言模型的下载 / 删除管理。
class _ModelManager extends StatefulWidget {
  const _ModelManager();

  @override
  State<_ModelManager> createState() => _ModelManagerState();
}

class _ModelManagerState extends State<_ModelManager> {
  final Map<String, bool> _downloaded = {};
  final Set<String> _working = {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final t = context.read<AppState>().translator;
    for (final l in kLanguages) {
      final ok = await t.isModelDownloaded(l);
      if (!mounted) return;
      setState(() => _downloaded[l.code] = ok);
    }
  }

  Future<void> _download(LanguageOption l) async {
    setState(() => _working.add(l.code));
    try {
      await context.read<AppState>().translator.downloadModel(l);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _working.remove(l.code);
      _downloaded[l.code] = true;
    });
  }

  Future<void> _delete(LanguageOption l) async {
    setState(() => _working.add(l.code));
    try {
      await context.read<AppState>().translator.deleteModel(l);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _working.remove(l.code);
      _downloaded[l.code] = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        for (final l in kLanguages)
          ListTile(
            dense: true,
            leading: Text(l.emoji, style: const TextStyle(fontSize: 20)),
            title: Text(l.label),
            trailing: _working.contains(l.code)
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : (_downloaded[l.code] ?? false)
                    ? TextButton.icon(
                        icon: const Icon(Icons.check_circle, size: 18, color: Colors.green),
                        label: const Text('已下载'),
                        onPressed: () => _delete(l),
                      )
                    : TextButton(
                        onPressed: () => _download(l),
                        child: const Text('下载'),
                      ),
          ),
      ],
    );
  }
}
