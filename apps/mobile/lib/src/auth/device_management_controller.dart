import 'package:flutter/foundation.dart';

import 'auth_models.dart';
import 'auth_session_controller.dart';
import 'auth_store.dart';
import 'credential_management_api.dart';

enum DeviceManagementStatus {
  idle,
  loading,
  ready,
  signedOut,
  unavailable,
  storageFailure,
  failed,
}

/// Reads only the current session projection. Credential operations and recent
/// replacement history never enter this controller's published state.
class DeviceManagementController extends ChangeNotifier {
  DeviceManagementController({
    required this.api,
    required this.store,
    required this.sessions,
  }) {
    store.addListener(_authorityChanged);
    sessions.addListener(_authorityChanged);
    _authorityChanged();
  }
  final CredentialManagementApi api;
  final AuthStore store;
  final AuthSessionController sessions;
  DeviceManagementStatus _status = DeviceManagementStatus.idle;
  DeviceDirectory? _device;
  String? _error;
  Object? _owner = Object();
  int _epoch = 0;
  bool _busy = false, _disposed = false;
  DeviceManagementStatus get status => _status;
  DeviceDirectory? get device => _device;
  String? get errorMessage => _error;
  bool get busy => _busy;

  Object? _window() {
    final record = store.current?.session;
    return record != null && sessions.isCurrentToken(record.token)
        ? (record.accountId, record.token, sessions.authorityVersion)
        : null;
  }

  void _authorityChanged() {
    final owner = _window();
    if (_disposed || owner == _owner && store.current != null) return;
    _epoch++;
    _owner = owner;
    _device = null;
    _error = null;
    _busy = false;
    _status = store.current == null
        ? DeviceManagementStatus.storageFailure
        : owner != null
        ? DeviceManagementStatus.idle
        : sessions.status == AuthStatus.unavailable
        ? DeviceManagementStatus.unavailable
        : DeviceManagementStatus.signedOut;
    notifyListeners();
  }

  bool _current(int epoch, Object owner) =>
      !_disposed && epoch == _epoch && owner == _window();

  Future<void> load() async {
    if (_disposed || _busy) return;
    final owner = _window();
    final record = store.current?.session;
    if (owner == null || record == null) {
      _authorityChanged();
      return;
    }
    final epoch = ++_epoch;
    _owner = owner;
    _busy = true;
    _device = null;
    _error = null;
    _status = DeviceManagementStatus.loading;
    notifyListeners();
    try {
      final response = await api.devices(record.token);
      if (!_current(epoch, owner)) return;
      if (!response.sessionExpiresAt.isUtc ||
          !response.currentSignedInAt.isUtc) {
        throw const AuthFailure(kind: AuthFailureKind.invalidResponse);
      }
      if (!await sessions.persistSessionMetadata(
            record.token,
            response.sessionExpiresAt,
            () => _current(epoch, owner),
          ) ||
          !_current(epoch, owner)) {
        return;
      }
      _device = DeviceDirectory(
        currentSignedInAt: response.currentSignedInAt,
        sessionExpiresAt: store.current!.session!.expiresAt,
      );
      _status = DeviceManagementStatus.ready;
    } on AuthStorageFailure {
      if (!_disposed && store.current == null) {
        _device = null;
        _status = DeviceManagementStatus.storageFailure;
        _error = '安全存储暂时不可用，请恢复后重试。';
      }
    } on AuthFailure catch (failure) {
      if (!_current(epoch, owner)) return;
      _device = null;
      if (failure.unauthorized) {
        sessions.sessionUnauthorized(record.token, failure.code);
      } else if (failure.kind == AuthFailureKind.unavailable) {
        sessions.sessionUnavailable(record.token);
      } else {
        _status = DeviceManagementStatus.failed;
        _error = '设备与会话读取失败，请重试。';
      }
    } on Object {
      if (_current(epoch, owner)) {
        _device = null;
        _status = DeviceManagementStatus.failed;
        _error = '设备与会话读取失败，请重试。';
      }
    } finally {
      if (!_disposed && epoch == _epoch) _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    store.removeListener(_authorityChanged);
    sessions.removeListener(_authorityChanged);
    super.dispose();
  }
}
