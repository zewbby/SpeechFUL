import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'auth_store.dart';
import 'auth_wordmark.dart';
import 'welcome_at_mark.dart';
import '../localization/translation_catalog.dart';
import '../localization/translations_auth.dart';

export '../localization/app_language.dart';

const authBrandColor = Color(0xFF00A7E9);

/// Appearance is separate from credential records and never stores form input.
class AuthPresentationController extends ChangeNotifier {
  AuthPresentationController({this.preferences});

  final AuthVault? preferences;
  ThemeMode themeMode = ThemeMode.system;
  AppLanguage _language = AppLanguage.simplifiedChinese;
  AppLanguage get language => _language;
  bool get english => _language == AppLanguage.english;
  set english(bool value) =>
      setLanguage(value ? AppLanguage.english : AppLanguage.simplifiedChinese);
  int _revision = 0;
  int _persistedRevision = 0;
  bool _disposed = false;
  Future<void> _writes = Future<void>.value();

  Future<void> load() async {
    final revision = _revision;
    try {
      final value = await preferences?.read();
      if (value == null || _disposed || revision != _revision) return;
      final record = jsonDecode(value);
      if (record is! Map || record['version'] != 1) return;
      final theme = record['theme'];
      final language = AppLanguage.tryParse(record['language']);
      if (!['system', 'light', 'dark'].contains(theme) || language == null) {
        return;
      }
      themeMode = ThemeMode.values.byName(theme as String);
      _language = language;
      notifyListeners();
    } catch (_) {
      // Optional non-secret preferences must never block authentication.
    }
  }

  void toggleTheme(Brightness brightness) {
    if (_disposed) return;
    themeMode = brightness == Brightness.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    _changed();
  }

  void toggleLanguage() {
    setLanguage(english ? AppLanguage.simplifiedChinese : AppLanguage.english);
  }

  void setLanguage(AppLanguage value) {
    if (_disposed) return;
    _language = value;
    _changed();
  }

  /// Callers that show a save result can await durable preference completion.
  Future<void> get preferencesSaved {
    final revision = _revision;
    return _writes.then((_) {
      if (_persistedRevision < revision) throw const AuthStorageFailure();
    });
  }

  void _changed() {
    final revision = ++_revision;
    notifyListeners();
    final value = jsonEncode({
      'version': 1,
      'theme': themeMode.name,
      'language': language.code,
    });
    _writes = _writes.then((_) async {
      try {
        final storage = preferences;
        if (storage == null) return;
        await storage.write(value);
        _persistedRevision = revision;
      } catch (_) {
        // Appearance remains usable when preference persistence is unavailable.
      }
    });
  }

  String text(String chinese, [String? englishText]) {
    final wait = RegExp(r'^(\d+) 秒后可(重新获取|核对申请)$').firstMatch(chinese);
    if (wait != null) {
      return translateUi(
        wait.group(2) == '重新获取' ? '{seconds} 秒后可重新获取' : '{seconds} 秒后可核对申请',
        language,
        args: {'seconds': wait.group(1)},
      );
    }
    if (chinese.startsWith('私有用户名：')) {
      return translateUi(
        '私有用户名：{username}',
        language,
        args: {'username': chinese.substring(6)},
      );
    }
    if (chinese.startsWith('预计完成时间：')) {
      return translateUi(
        '预计完成时间：{time}',
        language,
        args: {'time': chinese.substring(7)},
      );
    }
    if (english) {
      final translated = englishText ?? authEnglish[chinese];
      if (translated != null) return translated;
    }
    return translateUi(chinese, language);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class AuthPresentationScope
    extends InheritedNotifier<AuthPresentationController> {
  const AuthPresentationScope({
    super.key,
    required AuthPresentationController controller,
    required super.child,
  }) : super(notifier: controller);

  static AuthPresentationController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AuthPresentationScope>()
      ?.notifier;

  static String text(BuildContext context, String chinese, [String? english]) =>
      maybeOf(context)?.text(chinese, english) ?? chinese;
}

ThemeData authPresentationTheme(ThemeData base) {
  final dark = base.brightness == Brightness.dark;
  final foreground = dark ? const Color(0xFFF2F4F7) : const Color(0xFF24272B);
  final background = dark ? const Color(0xFF14171B) : Colors.white;
  final colors = base.colorScheme.copyWith(
    primary: dark ? authBrandColor : const Color(0xFF0076A3),
    onPrimary: dark ? background : Colors.white,
    surface: background,
    onSurface: foreground,
    outline: dark ? const Color(0xFF434B56) : const Color(0xFFD9DDE2),
  );
  return base.copyWith(
    colorScheme: colors,
    scaffoldBackgroundColor: background,
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: background,
      foregroundColor: foreground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: foreground,
      displayColor: foreground,
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      floatingLabelBehavior: FloatingLabelBehavior.always,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colors.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colors.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: authBrandColor, width: 2),
      ),
    ),
  );
}

/// Also supports isolated auth routes and widget harnesses without the app root.
class AuthPresentationHost extends StatefulWidget {
  const AuthPresentationHost({super.key, required this.child});
  final Widget child;

  @override
  State<AuthPresentationHost> createState() => _AuthPresentationHostState();
}

class _AuthPresentationHostState extends State<AuthPresentationHost> {
  final _fallback = AuthPresentationController();

  @override
  void dispose() {
    _fallback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AuthPresentationScope.maybeOf(context) ?? _fallback;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final base = Theme.of(context);
        final dark = controller.themeMode == ThemeMode.system
            ? base.brightness == Brightness.dark
            : controller.themeMode == ThemeMode.dark;
        final themed =
            base.brightness == (dark ? Brightness.dark : Brightness.light)
            ? base
            // The host can update before the root theme animation finishes.
            // Keep component text styles and font fallback consistent while
            // changing brightness; a bare ThemeData breaks TextStyle.lerp.
            : base.copyWith(
                brightness: dark ? Brightness.dark : Brightness.light,
              );
        return AuthPresentationScope(
          controller: controller,
          child: Semantics(
            localeForSubtree: controller.language.locale,
            child: Theme(
              data: authPresentationTheme(themed),
              child: widget.child,
            ),
          ),
        );
      },
    );
  }
}

class AuthThemeButton extends StatelessWidget {
  const AuthThemeButton({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final controller = AuthPresentationScope.maybeOf(context)!;
    return IconButton(
      key: const ValueKey('auth-theme-toggle'),
      tooltip: controller.text(dark ? '切换浅色主题' : '切换深色主题'),
      onPressed: () => controller.toggleTheme(Theme.of(context).brightness),
      icon: Icon(
        dark ? Icons.wb_sunny_outlined : Icons.nightlight_outlined,
        color: authBrandColor,
        size: 26,
      ),
    );
  }
}

class AuthWelcomeScreen extends StatelessWidget {
  const AuthWelcomeScreen({
    super.key,
    required this.onStarted,
    this.showControls = true,
  });

  final VoidCallback onStarted;
  final bool showControls;

  @override
  Widget build(BuildContext context) => AuthPresentationHost(
    child: Builder(
      builder: (context) {
        final controller = AuthPresentationScope.maybeOf(context)!;
        return Scaffold(
          key: const ValueKey('auth-welcome'),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: CustomScrollView(
                  slivers: [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                        child: Column(
                          children: [
                            Align(
                              alignment: Alignment.centerRight,
                              child: _welcomeEntrance(
                                visible: showControls,
                                key: const ValueKey(
                                  'welcome-theme-controls-animation',
                                ),
                                hiddenOffset: -12,
                                child: const AuthThemeButton(),
                              ),
                            ),
                            Expanded(
                              child: Align(
                                alignment: const Alignment(0, -0.45),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 48,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Semantics(
                                        label: controller.text(
                                          '安静手势标志',
                                          'Quiet gesture mark',
                                        ),
                                        image: true,
                                        child: ExcludeSemantics(
                                          child: WelcomeAtMark(
                                            color:
                                                Theme.of(context).brightness ==
                                                    Brightness.dark
                                                ? Colors.white
                                                : Colors.black,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 26),
                                      const AuthWordmark(),
                                      const SizedBox(height: 24),
                                      DefaultTextStyle.merge(
                                        style: const TextStyle(
                                          fontSize: 16,
                                          height: 1.6,
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              controller.text(
                                                '『愿为江水，与君重逢；',
                                                '“May I meet you again as river water;',
                                              ),
                                            ),
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                left: 16,
                                              ),
                                              child: Text(
                                                controller.text(
                                                  '同归沧溟，共载长风』',
                                                  'return to the vast sea on one wind.”',
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            _welcomeEntrance(
                              visible: showControls,
                              key: const ValueKey(
                                'welcome-action-controls-animation',
                              ),
                              hiddenOffset: 12,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextButton(
                                    key: const ValueKey('auth-language-toggle'),
                                    onPressed: controller.toggleLanguage,
                                    child: Text(
                                      controller.english
                                          ? '切换为简体中文'
                                          : 'Continue in English',
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 54,
                                    child: FilledButton(
                                      key: const ValueKey('auth-start'),
                                      onPressed: onStarted,
                                      style: FilledButton.styleFrom(
                                        shape: const StadiumBorder(),
                                      ),
                                      child: Text(
                                        controller.text('开始使用', 'Get started'),
                                        style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

Widget _welcomeEntrance({
  required bool visible,
  required Key key,
  required double hiddenOffset,
  required Widget child,
}) => TweenAnimationBuilder<double>(
  key: key,
  tween: Tween<double>(begin: 0, end: visible ? 1 : 0),
  duration: const Duration(milliseconds: 520),
  curve: Curves.easeOutCubic,
  builder: (context, progress, child) => ExcludeSemantics(
    excluding: !visible,
    child: IgnorePointer(
      ignoring: !visible,
      child: Opacity(
        opacity: progress,
        child: Transform.translate(
          offset: Offset(0, hiddenOffset * (1 - progress)),
          child: child,
        ),
      ),
    ),
  ),
  child: child,
);

/// Compatibility projection for callers of the former English-only catalog.
final authEnglish = Map<String, String>.unmodifiable({
  for (final entry in authTranslations.entries) entry.key: entry.value.$2,
});
