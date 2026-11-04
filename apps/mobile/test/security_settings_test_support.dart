import 'dart:async';

import 'package:hnuhole_mobile/hnuhole_mobile.dart';

const securityTestAccount = '00000000-0000-4000-8000-000000000001';
final securityTestExpiry = DateTime.utc(2031, 1, 1);

class SecuritySettingsVault implements AuthVault {
  String? value;
  bool failNext = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async {
    if (failNext) {
      failNext = false;
      throw const AuthStorageFailure();
    }
    value = next;
  }
}

class SecuritySettingsApi implements AuthApi, CredentialManagementApi {
  String account = securityTestAccount;
  int deviceReads = 0, credentialReads = 0, revocations = 0;
  final closureRequests = <({String id, String digest, String password})>[];
  int closureQueries = 0;
  AuthFailure? deviceFailure, closureFailure;
  Completer<DeviceDirectory>? deviceWait;
  Completer<RecoveryCredentialSummary>? credentialWait;
  ClosureState closureState = ClosureState.pending;
  @override
  Future<CurrentSession> currentSession(String token) async => CurrentSession(
    accountId: account,
    username: 'private_name',
    expiresAt: securityTestExpiry,
  );
  @override
  Future<AuthSession> login({
    required String username,
    required String password,
    required String installationId,
    required String idempotencyKey,
  }) async => AuthSession(
    accountId: account,
    sessionToken: AuthCrypto.randomEncoded(32),
    expiresAt: securityTestExpiry,
  );
  @override
  Future<void> revokeSession(String secret) async {
    revocations++;
  }

  @override
  Future<DeviceDirectory> devices(String token) async {
    deviceReads++;
    if (deviceFailure != null) throw deviceFailure!;
    return deviceWait != null
        ? deviceWait!.future
        : DeviceDirectory(
            currentSignedInAt: DateTime.utc(2026, 10, 1),
            sessionExpiresAt: securityTestExpiry,
            lastReplacedSignedInAt: DateTime.utc(2026, 9, 1),
            lastReplacedAt: DateTime.utc(2026, 10, 1),
          );
  }

  @override
  Future<RecoveryCredentialSummary> recoveryCredentials(String token) async {
    credentialReads++;
    if (credentialWait != null) return credentialWait!.future;
    throw const AuthFailure(kind: AuthFailureKind.unavailable);
  }

  @override
  Future<ClosureAccepted> requestClosure({
    required String sessionToken,
    required String password,
    required String closureId,
    required String statusDigest,
  }) async {
    closureRequests.add((
      id: closureId,
      digest: statusDigest,
      password: password,
    ));
    if (closureFailure != null) throw closureFailure!;
    return ClosureAccepted(
      closureId: closureId,
      dueAt: DateTime.utc(2030, 11, 6),
    );
  }

  @override
  Future<ClosureStatus> closureStatus({
    required String closureId,
    required String statusSecret,
  }) async {
    closureQueries++;
    return ClosureStatus(
      state: closureState,
      dueAt: closureState == ClosureState.pending
          ? DateTime.utc(2030, 11, 6)
          : null,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Channels implements ChannelRepository {
  @override
  Future<ChannelDirectoryResult> loadChannels({
    required String sessionToken,
  }) async => ChannelDirectoryResult(
    expiresAt: securityTestExpiry,
    channels: [
      for (var i = 0; i < ChannelDirectory.requiredCodes.length; i++)
        Channel(
          id: 'channel-$i',
          code: ChannelDirectory.requiredCodes[i],
          name: ChannelDirectory.requiredCodes[i],
          initiallyVisible: i < 5,
          displayOrder: i,
        ),
    ],
  );
}

class SecuritySettingsFixture {
  final vault = SecuritySettingsVault();
  final api = SecuritySettingsApi();
  late final store = AuthStore(vault);
  late final directory = ChannelDirectoryController(repository: _Channels());
  late final sessions = AuthSessionController(
    api: api,
    store: store,
    directory: directory,
  );
  late final flows = AuthFlows(
    api: api,
    store: store,
    acceptRegistrationSession: sessions.acceptSession,
    clearCommunityAccess: sessions.clearCommunityAccess,
  );
  Future<void> start() async {
    await store.update(
      (s) => s.copyWith(
        session: SessionRecord(
          token: AuthCrypto.randomEncoded(32),
          accountId: securityTestAccount,
          expiresAt: securityTestExpiry,
        ),
      ),
    );
    await sessions.start();
  }

  void dispose() {
    flows.dispose();
    sessions.dispose();
    directory.dispose();
    store.dispose();
  }
}
