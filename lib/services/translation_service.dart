import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import '../languages.dart';

/// 离线翻译：Google ML Kit 端上翻译模型（每个语言约 30MB，首次联网下载后完全离线、免费、不限量）。
class TranslationService {
  final OnDeviceTranslatorModelManager _modelManager = OnDeviceTranslatorModelManager();
  final Map<String, OnDeviceTranslator> _translators = {};

  OnDeviceTranslator _translatorFor(LanguageOption src, LanguageOption tgt) {
    final key = '${src.code}__${tgt.code}';
    return _translators.putIfAbsent(
      key,
      () => OnDeviceTranslator(
        sourceLanguage: TranslateLanguage.values.byName(src.code),
        targetLanguage: TranslateLanguage.values.byName(tgt.code),
      ),
    );
  }

  Future<void> ensureModels(LanguageOption src, LanguageOption tgt) async {
    await _ensureModel(src);
    await _ensureModel(tgt);
  }

  Future<void> _ensureModel(LanguageOption lang) async {
    bool downloaded = false;
    try {
      downloaded = await _modelManager.isModelDownloaded(lang.bcpCode);
    } catch (_) {/* 部分平台查询失败时直接尝试下载 */}
    if (!downloaded) {
      await _modelManager.downloadModel(lang.bcpCode);
    }
  }

  /// 同语言直接返回原文。
  Future<String> translate(LanguageOption src, LanguageOption tgt, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '';
    if (src.code == tgt.code) return text;
    return _translatorFor(src, tgt).translateText(trimmed);
  }

  // ---- 设置页的模型管理 ----

  Future<bool> isModelDownloaded(LanguageOption lang) async {
    try {
      return await _modelManager.isModelDownloaded(lang.bcpCode);
    } catch (_) {
      return false;
    }
  }

  Future<void> downloadModel(LanguageOption lang) async {
    await _modelManager.downloadModel(lang.bcpCode);
  }

  Future<void> deleteModel(LanguageOption lang) async {
    await _modelManager.deleteModel(lang.bcpCode);
    // 关闭并移除受影响的翻译器，防止继续使用已删除的模型。
    final deadKeys = _translators.keys
        .where((k) => k.startsWith('${lang.code}__') || k.endsWith('__${lang.code}'))
        .toList();
    for (final k in deadKeys) {
      _translators.remove(k)?.close();
    }
  }

  void dispose() {
    for (final t in _translators.values) {
      t.close();
    }
    _translators.clear();
  }
}
