import 'package:flutter/widgets.dart';

import 'post_sharing_api.dart';

class PendingPostLink {
  const PendingPostLink(this.target, this.sequence);
  final PostLinkTarget target;
  final int sequence;
}

/// Registered before either MaterialApp, so a platform link never becomes an
/// unguarded Navigator route. Only the target survives the authentication UI.
class PostLinkInbox extends ChangeNotifier with WidgetsBindingObserver {
  PostLinkInbox(this.communityBaseUri);
  final Uri communityBaseUri;
  PendingPostLink? pending;
  bool invalidLink = false;
  int _sequence = 0;
  bool _started = false;

  void start({String? initialRoute}) {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    final route =
        initialRoute ??
        WidgetsBinding.instance.platformDispatcher.defaultRouteName;
    if (route != '/') receive(route);
  }

  void receive(String raw) {
    final target = PostLinkTarget.parse(raw, communityBaseUri);
    if (target == null) {
      invalidLink = true;
    } else {
      invalidLink = false;
      // Even the same URL is a new click, allowing a cancelled login to retry.
      pending = PendingPostLink(target, ++_sequence);
    }
    notifyListeners();
  }

  void complete(int sequence) {
    if (pending?.sequence != sequence) return;
    pending = null;
    notifyListeners();
  }

  void clear() {
    pending = null;
    invalidLink = false;
    notifyListeners();
  }

  @override
  Future<bool> didPushRouteInformation(
    RouteInformation routeInformation,
  ) async {
    // Flutter's default implementation strips the origin. Validate the whole
    // platform URL here instead, before any Navigator gets to interpret it.
    receive(routeInformation.uri.toString());
    return true;
  }

  @override
  void dispose() {
    if (_started) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
