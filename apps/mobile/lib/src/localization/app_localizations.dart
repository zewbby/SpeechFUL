import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../auth/auth_presentation.dart';
import 'translation_catalog.dart';

export 'app_language.dart';
export 'translation_catalog.dart' show translateUi, uiTranslations;

const appLocalizationDelegates = [
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

const appSupportedLocales = [
  Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
  Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  Locale('en'),
  Locale('ja'),
];

String hhText(
  BuildContext context,
  String source, {
  Map<String, Object?> args = const {},
}) => translateUi(
  source,
  AuthPresentationScope.maybeOf(context)?.language ??
      AppLanguage.simplifiedChinese,
  args: args,
);
