import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../localization/app_localizations.dart';
import 'post_api.dart';
import 'post_controller.dart';

typedef PostShareSender = Future<void> Function(String text);

class PostSharingScope extends InheritedWidget {
  const PostSharingScope({super.key, required this.send, required super.child});
  final PostShareSender send;
  static const channel = MethodChannel('speechful/post-sharing');
  static Future<void> nativeShare(String text) =>
      channel.invokeMethod<void>('shareText', text);
  static PostShareSender sender(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PostSharingScope>()?.send ??
      nativeShare;
  @override
  bool updateShouldNotify(PostSharingScope oldWidget) => send != oldWidget.send;
}

/// One visible action owns the in-flight request. A late authorized response
/// cannot open a share sheet after logout, route removal or account replacement.
class PostShareAction extends StatefulWidget {
  const PostShareAction({
    super.key,
    required this.controller,
    required this.postId,
    required this.builder,
  });
  final PostController controller;
  final String postId;
  final Widget Function(VoidCallback? onPressed, bool busy) builder;
  @override
  State<PostShareAction> createState() => _PostShareActionState();
}

class _PostShareActionState extends State<PostShareAction> {
  late final _version = widget.controller.authorityVersion;
  bool get _current =>
      mounted &&
      widget.controller.available &&
      widget.controller.authorityVersion == _version;

  Future<void> _share() async {
    if (!_current ||
        !widget.controller.beginSharingPost(widget.postId, _version)) {
      return;
    }
    final send = PostSharingScope.sender(context);
    try {
      final link = await widget.controller.loadShareLink(widget.postId);
      if (!mounted || !_current || ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      await send(link.text);
      // Presenting or dismissing a system sheet does not mean a post was sent.
    } catch (error) {
      if (!mounted || !_current) return;
      final message = error is PostFailure && error.code == 'POST_NOT_FOUND'
          ? '原帖已不可用'
          : '暂时无法分享，请重试。';
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(hhText(context, message))));
    } finally {
      widget.controller.endSharingPost(widget.postId, _version);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final busy = widget.controller.sharingPost(widget.postId);
      return widget.builder(
        _current && !busy && widget.controller.supportsPostSharing
            ? _share
            : null,
        busy,
      );
    },
  );
}
