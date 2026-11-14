import '../storage/post_store.dart';
import 'post_api.dart';
import 'post_models.dart';

/// An operation whose captured account window is no longer usable.
class StalePostPublication implements Exception {
  const StalePostPublication();
}

/// A captured account/storage window and its integration ports. Feature owners
/// borrow the store; the session owner still validates and persists metadata.
/// Projection and media effects are delivered back to their existing owners.
abstract interface class PostPublicationContext {
  String get accountId;
  int get epoch;
  String get token;
  PostStore get store;
  bool get isCurrent;
  Future<T> accept<T>(PostResponse<T> response);
  void reportFailure(Object error, {String? commandId});
  Future<void> refreshLocal();
  void submissionRecorded(String id);
  void setCommandMessage(String message);
  Future<void> preserveCancelledImages(StoredPostEntry entry);
  Future<void> resumeImageUpload(String id);
  Future<void> resultRecorded(PostResultUpdate update);
}

/// A receipt/task fact emitted only after its durable state transition.
class PostResultUpdate {
  const PostResultUpdate({
    required this.previous,
    required this.state,
    required this.data,
    required this.task,
    required this.announcePublication,
    this.commandState,
    this.fromTask = false,
  });
  final StoredPostEntry previous;
  final String state;
  final Map<String, dynamic> data;
  final PostTask? task;
  final PostCommandState? commandState;
  final bool announcePublication, fromTask;
}
