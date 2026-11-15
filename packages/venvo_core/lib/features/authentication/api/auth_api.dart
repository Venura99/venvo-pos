import '../../../core/api/api_client.dart';
import '../../../core/api/revision_bus.dart';
import '../../../core/errors/failures.dart';
import '../domain/authenticated_user.dart';

/// What a client needs to know before it can show its first screen.
class ServerStatus {
  const ServerStatus({
    required this.needsFirstRunSetup,
    required this.schemaVersion,
    required this.apiVersion,
  });

  final bool needsFirstRunSetup;
  final int schemaVersion;
  final int apiVersion;
}

/// Authentication over HTTP. Mirrors `AuthRepository`, so
/// `auth_controller.dart` works against either.
///
/// The one behaviour this adds is token handling: a successful sign-in stores
/// the bearer token on the [ApiClient] and signing out clears it. The token is
/// the session, so nothing else in the client needs to know it exists.
class AuthApi {
  const AuthApi(this._client);

  final ApiClient _client;

  Future<ServerStatus> status() async {
    final json = await _client.get('/api/v1/status');
    return ServerStatus(
      needsFirstRunSetup: json['needsFirstRunSetup'] as bool? ?? false,
      schemaVersion: json['schemaVersion'] as int? ?? 0,
      apiVersion: json['apiVersion'] as int? ?? 0,
    );
  }

  /// True when the server holds no user yet, so first-run setup must happen.
  Future<bool> hasNoUsers() async => (await status()).needsFirstRunSetup;

  Future<AuthenticatedUser> signIn({
    required String username,
    required String password,
    String? deviceLabel,
    String? deviceKind,
  }) async {
    final json = await _client.post(
      '/api/v1/auth/login',
      body: {
        'username': username,
        'password': password,
        if (deviceLabel != null) 'deviceLabel': deviceLabel,
        if (deviceKind != null) 'deviceKind': deviceKind,
      },
    );
    return _acceptSession(json);
  }

  Future<AuthenticatedUser> createFirstAdministrator({
    required String fullName,
    required String username,
    required String password,
    String? deviceLabel,
    String? deviceKind,
  }) async {
    final json = await _client.post(
      '/api/v1/auth/first-run',
      body: {
        'fullName': fullName,
        'username': username,
        'password': password,
        if (deviceLabel != null) 'deviceLabel': deviceLabel,
        if (deviceKind != null) 'deviceKind': deviceKind,
      },
      bumps: {ApiTopic.users},
    );
    return _acceptSession(json);
  }

  Future<void> signOut(AuthenticatedUser user) async {
    try {
      await _client.post('/api/v1/auth/logout');
    } on AppFailure {
      // The token is being thrown away either way. A server that cannot be
      // reached, or a session it has already forgotten, must not leave
      // someone stuck signed in on this device.
    } finally {
      await _client.clearToken();
    }
  }

  /// Re-reads the signed-in user, e.g. after their roles changed.
  ///
  /// [userId] is ignored: the server resolves the user from the token, so this
  /// cannot be used to read somebody else's account.
  Future<AuthenticatedUser> refresh(int userId) async {
    final json = await _client.get('/api/v1/auth/me');
    return _user(json);
  }

  Future<void> changeOwnPassword({
    required AuthenticatedUser user,
    required String currentPassword,
    required String newPassword,
  }) async {
    await _client.post(
      '/api/v1/auth/password',
      body: {'currentPassword': currentPassword, 'newPassword': newPassword},
    );
  }

  Future<AuthenticatedUser> createUser({
    required AuthenticatedUser actor,
    required String fullName,
    required String username,
    required String password,
    required List<String> roleCodes,
    bool mustChangePassword = true,
  }) async {
    final json = await _client.post(
      '/api/v1/users',
      body: {
        'fullName': fullName,
        'username': username,
        'password': password,
        'roles': roleCodes,
      },
      bumps: {ApiTopic.users},
    );
    return _user(json);
  }

  Future<void> resetPassword({
    required AuthenticatedUser actor,
    required int targetUserId,
    required String temporaryPassword,
  }) async {
    await _client.post(
      '/api/v1/users/$targetUserId/password-reset',
      body: {'temporaryPassword': temporaryPassword},
      bumps: {ApiTopic.users},
    );
  }

  /// Stores the token from a sign-in reply and returns the user it belongs to.
  Future<AuthenticatedUser> _acceptSession(Map<String, Object?> json) async {
    final token = json['token'];
    if (token is! String || token.isEmpty) {
      throw const StorageFailure(
        'The server did not return a session.',
        details: 'No token in the sign-in reply.',
      );
    }
    await _client.saveToken(token);
    return _user(json);
  }

  AuthenticatedUser _user(Map<String, Object?> json) {
    final user = json['user'];
    if (user is! Map<String, Object?>) {
      throw StorageFailure(
        'The server sent a reply this version cannot read.',
        details: 'Expected a "user" object, got ${user.runtimeType}.',
      );
    }
    return AuthenticatedUser.fromJson(user);
  }
}
