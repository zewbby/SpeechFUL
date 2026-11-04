import 'package:flutter/widgets.dart';

/// A device-local interface preference; content and account identity are separate.
enum AppLanguage {
  simplifiedChinese(
    'zh-Hans',
    '简体中文',
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
  ),
  traditionalChinese(
    'zh-Hant',
    '繁體中文',
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ),
  english('en', 'English', Locale('en')),
  japanese('ja', '日本語', Locale('ja'));

  const AppLanguage(this.code, this.nativeName, this.locale);
  final String code;
  final String nativeName;
  final Locale locale;

  static AppLanguage? tryParse(Object? value) => switch (value) {
    'zh' || 'zh-CN' || 'zh-SG' || 'zh-Hans' => simplifiedChinese,
    'zh-TW' || 'zh-HK' || 'zh-MO' || 'zh-Hant' => traditionalChinese,
    'en' || 'en-US' || 'en-GB' => english,
    'ja' || 'ja-JP' => japanese,
    _ => null,
  };
}

/// Translations of an explicit Simplified Chinese UI source, in this fixed order.
typedef UiTranslation = (String traditional, String english, String japanese);
