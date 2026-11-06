part of 'post_controller.dart';

extension PostSharingController on PostController {
  bool sharingPost(String id) =>
      supportsPostSharing && _sharingPosts[id] == authorityVersion;
  bool beginSharingPost(String id, int version) {
    if (!available || authorityVersion != version || sharingPost(id)) {
      return false;
    }
    _sharingPosts[id] = version;
    _notify();
    return true;
  }

  void endSharingPost(String id, int version) {
    if (_sharingPosts[id] != version) return;
    _sharingPosts.remove(id);
    _notify();
  }

  Future<PostShareLink> loadShareLink(String postId) => _withDiscoveryAuthority(
    (token) =>
        (_api as PostSharingApi).shareLink(sessionToken: token, postId: postId),
  );

  Future<PostDetail> resolvePostLink(String url) => _withDiscoveryAuthority(
    (token) =>
        (_api as PostSharingApi).resolvePostLink(sessionToken: token, url: url),
  );
}
