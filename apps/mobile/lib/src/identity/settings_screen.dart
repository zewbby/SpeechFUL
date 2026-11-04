import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hnuhole_image_viewer/image_viewer.dart';

import '../auth/auth_presentation.dart';
import '../design_system/telegram_theme.dart';
import '../localization/app_localizations.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.onManageIdentity,
    required this.onManageSecurity,
    this.onClose,
    this.onManageAccount,
    this.onCloseAccount,
    this.onBlacklist,
    this.supportGalleryWriter,
  });
  final VoidCallback onManageIdentity, onManageSecurity;
  final VoidCallback? onClose, onManageAccount, onCloseAccount, onBlacklist;
  final ViewerGalleryWriter? supportGalleryWriter;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _opening = false;
  void _open(Widget page) =>
      Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => page));
  void _select(_SettingEntry entry) {
    if (!mounted || _opening || ModalRoute.isCurrentOf(context) == false) {
      return;
    }
    _opening = true;
    FocusManager.instance.primaryFocus?.unfocus();
    entry.open();
    WidgetsBinding.instance.addPostFrameCallback((_) => _opening = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = HhTelegramPalette.of(context);
    final entries = <_SettingEntry>[
      _SettingEntry(
        'language',
        Icons.language_outlined,
        '语言',
        () => _open(const _LanguageSettings()),
      ),
      _SettingEntry(
        'blacklist',
        Icons.block_outlined,
        '黑名单',
        widget.onBlacklist ??
            () => _open(
              const _SettingsUnavailable(
                title: '黑名单',
                message: '黑名单暂时不可用，请稍后重试。',
              ),
            ),
      ),
      _SettingEntry(
        'devices',
        Icons.devices_outlined,
        '设备管理',
        widget.onManageSecurity,
      ),
      _SettingEntry(
        'closure',
        Icons.person_off_outlined,
        '账号注销',
        widget.onCloseAccount ??
            widget.onManageAccount ??
            () => _open(
              const _SettingsUnavailable(
                title: '账号注销',
                message: '账号管理暂时不可用，请稍后重试。',
              ),
            ),
      ),
      _SettingEntry(
        'feedback',
        Icons.chat_bubble_outline_rounded,
        '意见反馈',
        () => _open(const _FeedbackSettings()),
      ),
      _SettingEntry(
        'support',
        Icons.favorite_border_rounded,
        '支持我们',
        () => _open(_SupportSettings(gallery: widget.supportGalleryWriter)),
      ),
      _SettingEntry(
        'identity',
        Icons.switch_account_outlined,
        '身份管理',
        widget.onManageIdentity,
      ),
      if (widget.onManageAccount != null)
        _SettingEntry(
          'account',
          Icons.person_outline_rounded,
          '账号与安全',
          widget.onManageAccount!,
        ),
    ];
    return _SettingsPage(
      title: '设置',
      onBack: widget.onClose,
      child: ListView(
        key: const ValueKey('settings-list'),
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        children: [
          for (final entry in entries)
            ListTile(
              key: ValueKey('settings-${entry.id}'),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 22,
                vertical: 6,
              ),
              minLeadingWidth: 26,
              horizontalTitleGap: 20,
              leading: Icon(entry.icon, size: 24, color: p.secondary),
              title: Text(
                hhText(context, entry.title),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: p.ink,
                  height: 1.35,
                ),
              ),
              onTap: () => _select(entry),
            ),
        ],
      ),
    );
  }
}

class _SettingEntry {
  const _SettingEntry(this.id, this.icon, this.title, this.open);
  final String id, title;
  final IconData icon;
  final VoidCallback open;
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({required this.title, required this.child, this.onBack});
  final String title;
  final Widget child;
  final VoidCallback? onBack;
  @override
  Widget build(BuildContext context) {
    final p = HhTelegramPalette.of(context);
    return Scaffold(
      backgroundColor: p.surface,
      appBar: AppBar(
        backgroundColor: p.surface,
        foregroundColor: p.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        leading: BackButton(
          onPressed: onBack ?? () => Navigator.of(context).maybePop(),
        ),
        titleSpacing: 4,
        title: Text(
          hhText(context, title),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: p.ink,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _SettingsUnavailable extends StatelessWidget {
  const _SettingsUnavailable({required this.title, required this.message});
  final String title, message;
  @override
  Widget build(BuildContext context) => _SettingsPage(
    title: title,
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(hhText(context, message)),
    ),
  );
}

class _LanguageSettings extends StatefulWidget {
  const _LanguageSettings();
  @override
  State<_LanguageSettings> createState() => _LanguageSettingsState();
}

class _LanguageSettingsState extends State<_LanguageSettings> {
  String? _message;
  int _revision = 0;
  Future<void> _choose(
    AuthPresentationController controller,
    AppLanguage language,
  ) async {
    final revision = ++_revision;
    setState(() => _message = null);
    controller.setLanguage(language);
    try {
      await controller.preferencesSaved;
    } catch (_) {
      if (mounted && revision == _revision) {
        setState(() => _message = '语言已切换，但未能保存到本机，请重试。');
      }
    }
  }

  @override
  Widget build(BuildContext context) => AuthPresentationHost(
    child: Builder(
      builder: (context) {
        final controller = AuthPresentationScope.maybeOf(context)!;
        final p = HhTelegramPalette.of(context);
        return _SettingsPage(
          title: '语言',
          child: ListView(
            key: const ValueKey('settings-language-page'),
            padding: const EdgeInsets.all(20),
            children: [
              for (final language in AppLanguage.values)
                Semantics(
                  selected: controller.language == language,
                  child: ListTile(
                    key: ValueKey('settings-language-${language.code}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      language.nativeName,
                      style: const TextStyle(fontSize: 17),
                    ),
                    trailing: Icon(
                      controller.language == language
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: controller.language == language
                          ? p.accent
                          : p.secondary,
                    ),
                    onTap: () => _choose(controller, language),
                  ),
                ),
              if (_message != null)
                Semantics(
                  liveRegion: true,
                  child: Text(hhText(context, _message!)),
                ),
            ],
          ),
        );
      },
    ),
  );
}

class _FeedbackSettings extends StatelessWidget {
  const _FeedbackSettings();
  static const email = 'zewbby666@gmail.com';
  @override
  Widget build(BuildContext context) => _SettingsPage(
    title: '意见反馈',
    child: ListView(
      key: const ValueKey('settings-feedback-page'),
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          hhText(context, '联系方式'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 24),
        Text(
          hhText(context, '邮箱'),
          style: TextStyle(color: HhTelegramPalette.of(context).secondary),
        ),
        const SizedBox(height: 8),
        const SelectableText(
          email,
          key: ValueKey('settings-feedback-email'),
          style: TextStyle(fontSize: 18),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          key: const ValueKey('settings-feedback-copy'),
          icon: const Icon(Icons.copy_outlined),
          label: Text(hhText(context, '复制邮箱')),
          onPressed: () async {
            String message;
            try {
              await Clipboard.setData(const ClipboardData(text: email));
              message = '邮箱已复制';
            } catch (_) {
              message = '复制失败，请重试';
            }
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(hhText(context, message))));
            }
          },
        ),
      ],
    ),
  );
}

class _SupportSettings extends StatefulWidget {
  const _SupportSettings({this.gallery});
  final ViewerGalleryWriter? gallery;
  @override
  State<_SupportSettings> createState() => _SupportSettingsState();
}

class _SupportSettingsState extends State<_SupportSettings>
    with WidgetsBindingObserver {
  static const asset = 'assets/support/alipay-receive.jpg';
  late final _saver = ViewerSaveCoordinator(
    gallery: widget.gallery ?? const GalViewerGalleryWriter(),
  );
  bool _busy = false, _foreground = true;
  String? _message;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground =
        state != AppLifecycleState.paused &&
        state != AppLifecycleState.detached;
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final result = await _saver.save(
      itemId: 'speechful-alipay-receive-v1',
      resolveOriginal: () async => ViewerOriginal.bytes(
        (await rootBundle.load(asset)).buffer.asUint8List(),
        ViewerOriginalFormat.jpeg,
      ),
      isCurrent: () =>
          mounted && _foreground && ModalRoute.isCurrentOf(context) != false,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!result.isCurrent) return;
      _message = switch (result.status) {
        ViewerSaveStatus.saved => '收款码已保存到相册',
        ViewerSaveStatus.permissionDenied => '请允许访问相册后重试',
        ViewerSaveStatus.outcomeUnknown => '保存结果尚未确定，请先查看相册',
        _ => '暂时无法保存，请重试',
      };
    });
  }

  Future<void> _expand() => showDialog<void>(
    context: context,
    builder: (dialog) => Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(title: Text(hhText(dialog, '支付宝收款码'))),
        body: Center(
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: Image.asset(
              asset,
              fit: BoxFit.contain,
              semanticLabel: hhText(dialog, '支付宝收款码'),
            ),
          ),
        ),
      ),
    ),
  );
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saver.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _SettingsPage(
    title: '支持我们',
    child: ListView(
      key: const ValueKey('settings-support-page'),
      padding: const EdgeInsets.all(22),
      children: [
        InkWell(
          key: const ValueKey('settings-support-code'),
          onTap: _expand,
          child: AspectRatio(
            aspectRatio: 2 / 3,
            child: Image.asset(
              asset,
              fit: BoxFit.contain,
              semanticLabel: hhText(context, '支付宝收款码'),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          hhText(context, '您的支持将全数用于开发与维护SpeechFUL项目'),
          key: const ValueKey('settings-support-purpose'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, height: 1.5),
        ),
        const SizedBox(height: 18),
        Text(
          hhText(context, '使用支付宝扫一扫，或保存收款码后从相册识别。'),
          style: const TextStyle(height: 1.5),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          key: const ValueKey('settings-support-save'),
          onPressed: _busy ? null : _save,
          icon: const Icon(Icons.save_alt_rounded),
          label: Text(hhText(context, _busy ? '保存中…' : '保存收款码')),
        ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Semantics(
              liveRegion: true,
              child: Text(hhText(context, _message!)),
            ),
          ),
      ],
    ),
  );
}
