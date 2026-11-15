import 'package:drift/drift.dart';

import '../../../core/constants/permissions.dart';
import '../../../core/database/app_database.dart';
import '../../../core/enums/app_enums.dart';
import '../../../core/errors/guards.dart';
import '../../../core/services/audit_service.dart';
import '../../../core/services/clock.dart';
import '../domain/authenticated_user.dart';

/// A user row together with the roles assigned to it, for the admin list.
class UserListEntry {
  const UserListEntry({
    required this.id,
    required this.username,
    required this.fullName,
    required this.status,
    required this.roleCodes,
    required this.roleNames,
    required this.mustChangePassword,
    required this.lastLoginAt,
    required this.isLockedOut,
  });

  final int id;
  final String username;
  final String fullName;
  final EntityStatus status;
  final List<String> roleCodes;
  final List<String> roleNames;
  final bool mustChangePassword;
  final DateTime? lastLoginAt;
  final bool isLockedOut;
}

/// Reads and maintains user accounts and their role assignments.
class UserAdminRepository {
  const UserAdminRepository({
    required AppDatabase database,
    required Clock clock,
    required AuditService audit,
  }) : _db = database,
       _clock = clock,
       _audit = audit;

  final AppDatabase _db;
  final Clock _clock;
  final AuditService _audit;

  Future<List<UserListEntry>> listUsers() async {
    final users = await (_db.select(
      _db.users,
    )..orderBy([(u) => OrderingTerm.asc(u.username)])).get();

    final roleRows = await _db.select(_db.userRoles).join([
      innerJoin(_db.roles, _db.roles.id.equalsExp(_db.userRoles.roleId)),
    ]).get();

    final rolesByUser = <int, List<Role>>{};
    for (final row in roleRows) {
      final link = row.readTable(_db.userRoles);
      rolesByUser
          .putIfAbsent(link.userId, () => [])
          .add(row.readTable(_db.roles));
    }

    final now = _clock.nowUtc();
    return users.map((user) {
      final roles = rolesByUser[user.id] ?? const <Role>[];
      return UserListEntry(
        id: user.id,
        username: user.username,
        fullName: user.fullName,
        status: user.status,
        roleCodes: roles.map((r) => r.code).toList(),
        roleNames: roles.map((r) => r.name).toList(),
        mustChangePassword: user.mustChangePassword,
        lastLoginAt: user.lastLoginAt,
        isLockedOut: user.lockedUntil != null && user.lockedUntil!.isAfter(now),
      );
    }).toList();
  }

  Future<List<Role>> listRoles() =>
      (_db.select(_db.roles)..orderBy([(r) => OrderingTerm.asc(r.code)])).get();

  /// Enables or disables an account.
  ///
  /// Refuses to disable the last active administrator, which would otherwise
  /// lock everybody out of an offline database with no recovery path.
  Future<void> setStatus({
    required AuthenticatedUser actor,
    required int targetUserId,
    required EntityStatus status,
  }) async {
    actor.require(Permissions.usersManage, action: 'enable or disable users');

    await _db.transaction(() async {
      final target = requireFound(
        await (_db.select(
          _db.users,
        )..where((u) => u.id.equals(targetUserId))).getSingleOrNull(),
        'That user no longer exists.',
      );

      if (status != EntityStatus.active) {
        requireRule(
          targetUserId != actor.id,
          'You cannot disable your own account.',
          rule: 'auth.no_self_disable',
        );
        requireRule(
          await _activeAdministratorCount(excludingUserId: targetUserId) > 0,
          'This is the last active administrator. Create or enable another '
          'administrator first.',
          rule: 'auth.keep_one_admin',
        );
      }

      await (_db.update(
        _db.users,
      )..where((u) => u.id.equals(targetUserId))).write(
        UsersCompanion(
          status: Value(status),
          failedLoginCount: const Value(0),
          lockedUntil: const Value(null),
          updatedAt: Value(_clock.nowUtc()),
        ),
      );

      await _audit.record(
        action: status == EntityStatus.active
            ? AuditAction.update
            : AuditAction.archive,
        summary: status == EntityStatus.active
            ? 'Enabled the account "${target.username}".'
            : 'Disabled the account "${target.username}".',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.user,
        entityId: targetUserId,
      );
    });
  }

  /// Replaces a user's role assignments.
  Future<void> setRoles({
    required AuthenticatedUser actor,
    required int targetUserId,
    required List<String> roleCodes,
  }) async {
    actor.require(Permissions.usersManage, action: 'change user roles');
    require(roleCodes.isNotEmpty, 'Assign at least one role.', field: 'roles');

    await _db.transaction(() async {
      final roles = await (_db.select(
        _db.roles,
      )..where((r) => r.code.isIn(roleCodes))).get();
      requireRule(
        roles.length == roleCodes.length,
        'One or more of the selected roles no longer exists.',
        rule: 'auth.roles_exist',
      );

      if (!roleCodes.contains(RoleCodes.administrator)) {
        requireRule(
          await _activeAdministratorCount(excludingUserId: targetUserId) > 0,
          'This is the last administrator. Give another user the '
          'Administrator role first.',
          rule: 'auth.keep_one_admin',
        );
      }

      await (_db.delete(
        _db.userRoles,
      )..where((ur) => ur.userId.equals(targetUserId))).go();
      for (final role in roles) {
        await _db
            .into(_db.userRoles)
            .insert(
              UserRolesCompanion.insert(userId: targetUserId, roleId: role.id),
            );
      }

      await _audit.record(
        action: AuditAction.update,
        summary:
            'Set roles for user #$targetUserId to '
            '${roles.map((r) => r.code).join(', ')}.',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.user,
        entityId: targetUserId,
      );
    });
  }

  /// Clears a lockout imposed by repeated failed sign-in attempts.
  Future<void> clearLockout({
    required AuthenticatedUser actor,
    required int targetUserId,
  }) async {
    actor.require(Permissions.usersManage, action: 'unlock accounts');
    await (_db.update(
      _db.users,
    )..where((u) => u.id.equals(targetUserId))).write(
      UsersCompanion(
        failedLoginCount: const Value(0),
        lockedUntil: const Value(null),
        updatedAt: Value(_clock.nowUtc()),
      ),
    );
    await _audit.record(
      action: AuditAction.update,
      summary: 'Cleared the sign-in lockout on user #$targetUserId.',
      userId: actor.id,
      username: actor.username,
      entityKind: EntityKind.user,
      entityId: targetUserId,
    );
  }

  Future<int> _activeAdministratorCount({int? excludingUserId}) async {
    final query =
        _db.select(_db.userRoles).join([
          innerJoin(_db.roles, _db.roles.id.equalsExp(_db.userRoles.roleId)),
          innerJoin(_db.users, _db.users.id.equalsExp(_db.userRoles.userId)),
        ])..where(
          _db.roles.code.equals(RoleCodes.administrator) &
              _db.users.status.equalsValue(EntityStatus.active),
        );
    final rows = await query.get();
    return rows
        .where((row) => row.readTable(_db.users).id != excludingUserId)
        .length;
  }
}
