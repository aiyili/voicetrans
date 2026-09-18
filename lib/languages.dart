/// 支持的语言列表。
/// code: google_mlkit_translation 的 TranslateLanguage 枚举名；
/// bcpCode: ML Kit 语言模型代码；sttLocale: speech_to_text 识别用的 localeId。
class LanguageOption {
  final String code;
  final String bcpCode;
  final String label;
  final String emoji;
  final String sttLocale;

  const LanguageOption(this.code, this.bcpCode, this.label, this.emoji, this.sttLocale);
}

const kLanguages = <LanguageOption>[
  LanguageOption('english', 'en', '英语', '🇺🇸', 'en-US'),
  LanguageOption('chinese', 'zh', '中文（简体）', '🇨🇳', 'zh-CN'),
  LanguageOption('japanese', 'ja', '日语', '🇯🇵', 'ja-JP'),
  LanguageOption('korean', 'ko', '韩语', '🇰🇷', 'ko-KR'),
  LanguageOption('french', 'fr', '法语', '🇫🇷', 'fr-FR'),
  LanguageOption('german', 'de', '德语', '🇩🇪', 'de-DE'),
  LanguageOption('spanish', 'es', '西班牙语', '🇪🇸', 'es-ES'),
  LanguageOption('russian', 'ru', '俄语', '🇷🇺', 'ru-RU'),
  LanguageOption('portuguese', 'pt', '葡萄牙语', '🇧🇷', 'pt-BR'),
  LanguageOption('italian', 'it', '意大利语', '🇮🇹', 'it-IT'),
  LanguageOption('thai', 'th', '泰语', '🇹🇭', 'th-TH'),
  LanguageOption('vietnamese', 'vi', '越南语', '🇻🇳', 'vi-VN'),
  LanguageOption('indonesian', 'id', '印尼语', '🇮🇩', 'id-ID'),
  LanguageOption('hindi', 'hi', '印地语', '🇮🇳', 'hi-IN'),
  LanguageOption('arabic', 'ar', '阿拉伯语', '🇸🇦', 'ar-SA'),
];

LanguageOption langByCode(String code) {
  for (final l in kLanguages) {
    if (l.code == code) return l;
  }
  return kLanguages.first;
}
