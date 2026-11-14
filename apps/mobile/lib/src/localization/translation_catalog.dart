import 'app_language.dart';
import 'translations_auth.dart';
import 'translations_community_settings.dart';
import 'translations_messaging_notifications.dart';
import 'translations_security_identity.dart';

export 'app_language.dart' show AppLanguage, UiTranslation;

/// Only these application-owned sources are translated. Arguments stay verbatim.
/// Shared sources use the last module's wording; each module owns its own keys.
final uiTranslations = Map<String, UiTranslation>.unmodifiable({
  ...authTranslations,
  ...securityIdentityTranslations,
  ...messagingNotificationTranslations,
  ...communitySettingsTranslations,
});

final _placeholder = RegExp(r'\{([A-Za-z][A-Za-z0-9_]*)\}');
final _literalWord = RegExp(r'\p{L}', unicode: true);
final _sourceTemplates =
    [
          for (final (index, source) in uiTranslations.keys.indexed)
            if (_placeholder.hasMatch(source)) _UiSourceTemplate(source, index),
        ]
        .where(
          (template) => _literalWord.hasMatch(
            template.source.replaceAll(_placeholder, ''),
          ),
        )
        .toList()
      ..sort((a, b) {
        final specificity = b.literalLength.compareTo(a.literalLength);
        // List.sort is unstable. Equal-specificity templates must retain
        // catalog order when unrelated category translations are added.
        return specificity != 0
            ? specificity
            : a.sourceOrder.compareTo(b.sourceOrder);
      });

class _UiSourceTemplate {
  _UiSourceTemplate(this.source, this.sourceOrder) {
    final pattern = StringBuffer('^');
    var offset = 0;
    for (final token in _placeholder.allMatches(source)) {
      final literal = source.substring(offset, token.start);
      literalLength += literal.length;
      pattern.write(RegExp.escape(literal));
      pattern.write(r'([\s\S]*?)');
      names.add(token.group(1)!);
      offset = token.end;
    }
    final end = source.substring(offset);
    literalLength += end.length;
    pattern.write(RegExp.escape(end));
    // Unlike $, this requires the absolute end, including trailing newlines.
    pattern.write(r'(?![\s\S])');
    expression = RegExp(pattern.toString());
  }

  final String source;
  final int sourceOrder;
  final names = <String>[];
  late final RegExp expression;
  int literalLength = 0;

  Map<String, Object?>? arguments(String value) {
    final match = expression.firstMatch(value);
    if (match == null) return null;
    final result = <String, Object?>{};
    for (var index = 0; index < names.length; index++) {
      final name = names[index], captured = match.group(index + 1)!;
      if (result.containsKey(name) && result[name] != captured) return null;
      result[name] = captured;
    }
    return result;
  }
}

String translateUi(
  String source,
  AppLanguage language, {
  Map<String, Object?> args = const {},
}) {
  final value = uiTranslations[source];
  // Controllers may retain an already composed application error/status. Match
  // only a registered, anchored source template, never arbitrary widget content.
  if (value == null && args.isEmpty) {
    for (final candidate in _sourceTemplates) {
      final captured = candidate.arguments(source);
      if (captured != null) {
        return translateUi(candidate.source, language, args: captured);
      }
    }
  }
  final template = switch (language) {
    AppLanguage.simplifiedChinese => source,
    AppLanguage.traditionalChinese => value?.$1 ?? source,
    AppLanguage.english => value?.$2 ?? source,
    AppLanguage.japanese => value?.$3 ?? source,
  };
  return template.replaceAllMapped(_placeholder, (match) {
    final key = match.group(1)!;
    return args.containsKey(key) ? '${args[key] ?? ''}' : match.group(0)!;
  });
}
