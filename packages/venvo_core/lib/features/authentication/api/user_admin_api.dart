import '../../../core/api/api_client.dart';
import '../../../core/api/api_decode.dart';
import '../../../core/api/revision_bus.dart';
import '../../../core/database/app_database.dart';
import '../../../core/enums/app_enums.dart';
import '../../../core/errors/failures.dart';
import '../data/user_admin_repository.dart';
import '../domain/authenticated_user.dart';

/// User accounts and their roles, over HTTP. Mirrors `UserAdminRepository`.
///
/// Every call here needs `users.manage`, and the check is made on the server
/// against the caller's session — not against the `actor` argument, which is
/// accepted only so the users screen compiles unchanged.
class UserAdminApi {
  const UserAdminApi(this._client);

  final ApiClient _client;

  Future<List<UserListEntry>> listUsers() async {
    final json = await _client.get('/api/v1/users');
    return decodeList(json, 'users', _entry);
  }

  Future<List<Role>> listRoles() async {
    final json = await _client.get('/api/v1/roles');
    return decodeList(json, 'roles', Role.fromJson);
  }

  /// Enables or disables an account. Disabling one signs every device it is
  /// using out at once; the server refuses to disable the last administrator.
  Future<void> setStatus({
    required AuthenticatedUser actor,
    required int targetUserId,
    required EntityStatus status,
  }) async {
    await _client.patch(
      '/api/v1/users/$targetUserId/status',
      body: {'status': status.name},
      bumps: {ApiTopic.users},
    );
  }

  /// Replaces a user's roles. Takes effect on their very next request, with
  /// no need for them to sign in again.
  Future<void> setRoles({
    required AuthenticatedUser actor,
    required int targetUserId,
    required List<String> roleCodes,
  }) async {
    await _client.put(
      '/api/v1/users/$targetUserId/roles',
      body: {'roles': roleCodes},
      bumps: {ApiTopic.users},
    );
  }

  Future<void> clearLockout({
    required AuthenticatedUser actor,
    required int targetUserId,
  }) async {
    await _client.post(
      '/api/v1/users/$targetUserId/unlock',
      bumps: {ApiTopic.users},
    );
  }

  static UserListEntry _entry(Map<String, dynamic> json) {
    final statusName = json['status'];
    final status = EntityStatus.values
        .where((s) => s.name == statusName)
        .firstOrNull;
    if (status == null) {
      throw StorageFailure(
        'The server sent a reply this version cannot read.',
        details: 'Unknown account status "$statusName".',
      );
    }
    final lastLogin = json['lastLoginAt'];
    return UserListEntry(
      id: json['id'] as int,
      username: json['username'] as String,
      fullName: json['fullName'] as String,
      status: status,
      roleCodes: (json['roleCodes'] as List).cast<String>(),
      roleNames: (json['roleNames'] as List).cast<String>(),
      mustChangePassword: json['mustChangePassword'] as bool,
      lastLoginAt: lastLogin is String ? DateTime.parse(lastLogin) : null,
      isLockedOut: json['isLockedOut'] as bool,
    );
  }
}
