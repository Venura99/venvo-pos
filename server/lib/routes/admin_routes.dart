import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/errors/failures.dart';
import 'package:venvo_core/features/authentication/data/auth_repository.dart';
import 'package:venvo_core/features/authentication/data/user_admin_repository.dart';

import '../auth/auth_middleware.dart';
import '../auth/session_store.dart';
import '../http/json_body.dart';
import '../http/responses.dart';

/// User accounts, roles and permissions.
///
/// Note what is *not* here: any permission logic. Every mutating call goes
/// through [UserAdminRepository] or [AuthRepository], which take the actor and
/// call `actor.require(Permissions.usersManage)` themselves. That check cannot
/// be bypassed by reaching the operation another way, and it is the same check
/// the desktop build has been making for eight phases. The routes only add
/// what is genuinely new over a network: ending the sessions of an account
/// whose access has just been taken away.
Router adminRoutes({
  required UserAdminRepository users,
  required AuthRepository auth,
  required SessionStore sessions,
}) {
  final router = Router();

  router.get('/users', (Request request) async {
    // listUsers is a plain read and does no checking of its own, so the
    // permission is required here. There is no separate "view users"
    // permission: seeing who has access is itself administrative.
    requirePermission(request, Permissions.usersManage, action: 'view users');
    final entries = await users.listUsers();
    return Api.ok({'users': entries.map(_userEntry).toList()});
  });

  router.get('/roles', (Request request) async {
    requirePermission(request, Permissions.usersManage, action: 'view roles');
    final roles = await users.listRoles();
    // The row's own JSON, so the client rebuilds the same `Role` class the
    // screens already use rather than a look-alike.
    return Api.ok({'roles': roles.map((role) => role.toJson()).toList()});
  });

  /// The permission catalogue, so a client can render a role editor without
  /// hardcoding a list that would drift out of step with the server.
  router.get('/permissions', (Request request) async {
    requirePermission(
      request,
      Permissions.usersManage,
      action: 'view permissions',
    );
    return Api.ok({
      'permissions': Permissions.all,
      'defaultGrants': RoleCodes.defaultGrants,
    });
  });

  router.post('/users', (Request request) async {
    final body = await JsonBody.read(request);
    final created = await auth.createUser(
      actor: request.session.user,
      fullName: body.requireString('fullName', maxLength: 180),
      username: body.requireString('username', maxLength: 48),
      password: body.requireSecret('password'),
      roleCodes: _roleCodes(body),
      // Defaults to true in the repository, and left that way: an account
      // created by an administrator starts with a password that
      // administrator knows, so the holder must replace it before working.
      mustChangePassword: true,
    );
    return Api.created({'user': created.toJson()});
  });

  router.patch('/users/<id>/status', (Request request, String id) async {
    final targetId = _parseId(id);
    final body = await JsonBody.read(request);
    final status = _parseStatus(body.requireString('status'));

    // Refuses to disable the last active administrator — that rule lives in
    // the repository, where it is already tested.
    await users.setStatus(
      actor: request.session.user,
      targetUserId: targetId,
      status: status,
    );

    // A disabled account would stop working on its next request anyway,
    // because the session lookup re-checks the account status. Revoking here
    // as well makes it immediate rather than "whenever they next ask for
    // something", and leaves a reason on the row.
    final signedOut = status == EntityStatus.active
        ? 0
        : await sessions.revokeAllForUser(
            targetId,
            reason: 'Account disabled.',
          );
    return Api.ok({'signedOutDevices': signedOut});
  });

  router.put('/users/<id>/roles', (Request request, String id) async {
    final body = await JsonBody.read(request);
    await users.setRoles(
      actor: request.session.user,
      targetUserId: _parseId(id),
      roleCodes: _roleCodes(body),
    );
    // No sessions are revoked, and none need to be: permissions are resolved
    // from the database on every request, so a role change takes effect on
    // the target's very next call. That is the whole reason they are not
    // cached in the session row.
    return Api.noContent();
  });

  router.post('/users/<id>/password-reset', (Request request, String id) async {
    final targetId = _parseId(id);
    final body = await JsonBody.read(request);
    await auth.resetPassword(
      actor: request.session.user,
      targetUserId: targetId,
      temporaryPassword: body.requireSecret('temporaryPassword'),
    );
    // Whoever was signed in as that account must now sign in again with the
    // temporary password, which is the point of resetting it.
    final signedOut = await sessions.revokeAllForUser(
      targetId,
      reason: 'Password reset by an administrator.',
    );
    return Api.ok({'signedOutDevices': signedOut});
  });

  router.post('/users/<id>/unlock', (Request request, String id) async {
    await users.clearLockout(
      actor: request.session.user,
      targetUserId: _parseId(id),
    );
    return Api.noContent();
  });

  return router;
}

Map<String, Object?> _userEntry(UserListEntry entry) => {
  'id': entry.id,
  'username': entry.username,
  'fullName': entry.fullName,
  'status': entry.status.name,
  'roleCodes': entry.roleCodes,
  'roleNames': entry.roleNames,
  'mustChangePassword': entry.mustChangePassword,
  'lastLoginAt': entry.lastLoginAt?.toIso8601String(),
  'isLockedOut': entry.isLockedOut,
};

int _parseId(String raw) {
  final value = int.tryParse(raw);
  if (value == null || value <= 0) {
    throw ValidationFailure('"$raw" is not a user id.', field: 'id');
  }
  return value;
}

EntityStatus _parseStatus(String raw) {
  for (final status in EntityStatus.values) {
    if (status.name == raw) return status;
  }
  throw ValidationFailure(
    'status must be one of '
    '${EntityStatus.values.map((s) => s.name).join(', ')}.',
    field: 'status',
  );
}

List<String> _roleCodes(JsonBody body) {
  final raw = body.requireList('roles');
  final codes = <String>[];
  for (final entry in raw) {
    if (entry is! String || entry.trim().isEmpty) {
      throw const ValidationFailure(
        'roles must be a list of role codes.',
        field: 'roles',
      );
    }
    codes.add(entry.trim());
  }
  // Left to the repository to reject an empty list, so the message matches
  // the one the desktop build already gives.
  return codes;
}
