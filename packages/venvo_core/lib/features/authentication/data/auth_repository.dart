import 'package:drift/drift.dart';

import '../../../core/constants/permissions.dart';
import '../../../core/database/app_database.dart';
import '../../../core/enums/app_enums.dart';
import '../../../core/errors/failures.dart';
import '../../../core/errors/guards.dart';
import '../../../core/services/audit_service.dart';
import '../../../core/services/clock.dart';
import '../../../core/services/password_hasher.dart';
import '../domain/authenticated_user.dart';

/// Sign-in, account creation and password changes.
///
/// Failed attempts are counted and the account is locked for a short period
/// after [_maxFailedAttempts], which makes offline brute forcing impractical
/// without ever locking a legitimate user out for long. Every outcome,
/// including failures against unknown usernames, is written to the audit log.
class AuthRepository {
  AuthRepository({
    required AppDatabase database,
    required Clock clock,
    required AuditService audit,
    PasswordHasher hasher = const PasswordHasher(),
  }) : _db = database,
       _clock = clock,
       _audit = audit,
       _hasher = hasher;

  final AppDatabase _db;
  final Clock _clock;
  final AuditService _audit;
  final PasswordHasher _hasher;

  static const int _maxFailedAttempts = 5;
  static const Duration _lockoutDuration = Duration(minutes: 5);

  /// True when no user exists, so the application must run first-run setup.
  Future<bool> hasNoUsers() async {
    final row = await (_db.selectOnly(
      _db.users,
    )..addColumns([_db.users.id.count()])).getSingle();
    return (row.read(_db.users.id.count()) ?? 0) == 0;
  }

  /// Creates the first administrator. Refuses to run once any user exists, so
  /// it cannot be used to grant oneself access to an established database.
  Future<AuthenticatedUser> createFirstAdministrator({
    required String fullName,
    required String username,
    required String password,
  }) async {
    final cleanName = requireText(fullName, 'Full name');
    final cleanUsername = _normaliseUsername(username);
    final strengthProblem = validatePasswordStrength(password);
    if (strengthProblem != null) {
      throw ValidationFailure(strengthProblem, field: 'password');
    }

    return _db.transaction(() async {
      requireRule(
        await hasNoUsers(),
        'An administrator account already exists. Sign in instead.',
        rule: 'auth.first_run_once',
      );

      final adminRole = requireFound(
        await (_db.select(_db.roles)
              ..where((r) => r.code.equals(RoleCodes.administrator)))
            .getSingleOrNull(),
        'The Administrator role is missing from this database.',
      );

      final userId = await _insertUser(
        fullName: cleanName,
        username: cleanUsername,
        password: password,
        mustChangePassword: false,
      );

      await _db
          .into(_db.userRoles)
          .insert(
            UserRolesCompanion.insert(userId: userId, roleId: adminRole.id),
          );

      await _audit.record(
        action: AuditAction.create,
        summary: 'Created the first administrator account "$cleanUsername".',
        userId: userId,
        username: cleanUsername,
        entityKind: EntityKind.user,
        entityId: userId,
      );

      return _loadUser(userId);
    });
  }

  /// Creates an additional user. Requires `users.manage`.
  Future<AuthenticatedUser> createUser({
    required AuthenticatedUser actor,
    required String fullName,
    required String username,
    required String password,
    required List<String> roleCodes,
    bool mustChangePassword = true,
  }) async {
    actor.require(Permissions.usersManage, action: 'create users');
    final cleanName = requireText(fullName, 'Full name');
    final cleanUsername = _normaliseUsername(username);
    final strengthProblem = validatePasswordStrength(password);
    if (strengthProblem != null) {
      throw ValidationFailure(strengthProblem, field: 'password');
    }
    require(roleCodes.isNotEmpty, 'Assign at least one role.', field: 'roles');

    return _db.transaction(() async {
      final taken = await (_db.select(
        _db.users,
      )..where((u) => u.username.equals(cleanUsername))).getSingleOrNull();
      requireRule(
        taken == null,
        'The username "$cleanUsername" is already in use.',
        rule: 'auth.username_unique',
      );

      final roles = await (_db.select(
        _db.roles,
      )..where((r) => r.code.isIn(roleCodes))).get();
      requireRule(
        roles.length == roleCodes.length,
        'One or more of the selected roles no longer exists.',
        rule: 'auth.roles_exist',
      );

      final userId = await _insertUser(
        fullName: cleanName,
        username: cleanUsername,
        password: password,
        mustChangePassword: mustChangePassword,
      );

      for (final role in roles) {
        await _db
            .into(_db.userRoles)
            .insert(UserRolesCompanion.insert(userId: userId, roleId: role.id));
      }

      await _audit.record(
        action: AuditAction.create,
        summary:
            'Created user "$cleanUsername" with roles '
            '${roles.map((r) => r.code).join(', ')}.',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.user,
        entityId: userId,
      );

      return _loadUser(userId);
    });
  }

  /// Verifies credentials and returns the resolved user.
  ///
  /// The same message is returned for an unknown username and a wrong
  /// password, so the screen cannot be used to discover valid usernames.
  Future<AuthenticatedUser> signIn({
    required String username,
    required String password,
  }) async {
    final cleanUsername = _normaliseUsername(username);
    require(password.isNotEmpty, 'Enter your password.', field: 'password');

    const genericFailure = AuthFailure('Incorrect username or password.');

    final row = await (_db.select(
      _db.users,
    )..where((u) => u.username.equals(cleanUsername))).getSingleOrNull();

    if (row == null) {
      await _audit.record(
        action: AuditAction.loginFailed,
        summary: 'Sign-in attempt for unknown username "$cleanUsername".',
        username: cleanUsername,
      );
      throw genericFailure;
    }

    if (row.status != EntityStatus.active) {
      await _audit.record(
        action: AuditAction.loginFailed,
        summary: 'Sign-in attempt on a disabled account.',
        userId: row.id,
        username: row.username,
        entityKind: EntityKind.user,
        entityId: row.id,
      );
      throw const AuthFailure(
        'This account has been disabled. Ask an administrator to re-enable it.',
      );
    }

    final now = _clock.nowUtc();
    final lockedUntil = row.lockedUntil;
    if (lockedUntil != null && lockedUntil.isAfter(now)) {
      final minutes = lockedUntil.difference(now).inMinutes + 1;
      throw AuthFailure(
        'Too many failed attempts. Try again in $minutes minute(s).',
      );
    }

    final matches = _hasher.verify(
      password: password,
      hashBase64: row.passwordHash,
      saltBase64: row.passwordSalt,
      iterations: row.passwordIterations,
    );

    if (!matches) {
      final attempts = row.failedLoginCount + 1;
      final shouldLock = attempts >= _maxFailedAttempts;
      await (_db.update(_db.users)..where((u) => u.id.equals(row.id))).write(
        UsersCompanion(
          failedLoginCount: Value(shouldLock ? 0 : attempts),
          lockedUntil: Value(shouldLock ? now.add(_lockoutDuration) : null),
          updatedAt: Value(now),
        ),
      );
      await _audit.record(
        action: AuditAction.loginFailed,
        summary: shouldLock
            ? 'Account locked after $_maxFailedAttempts failed sign-in attempts.'
            : 'Failed sign-in attempt ($attempts of $_maxFailedAttempts).',
        userId: row.id,
        username: row.username,
        entityKind: EntityKind.user,
        entityId: row.id,
      );
      throw genericFailure;
    }

    // Success: clear the counters and transparently upgrade a hash that was
    // derived with a weaker cost than the current setting.
    final rehash = _hasher.needsRehash(row.passwordIterations)
        ? _hasher.hash(password)
        : null;

    await (_db.update(_db.users)..where((u) => u.id.equals(row.id))).write(
      UsersCompanion(
        failedLoginCount: const Value(0),
        lockedUntil: const Value(null),
        lastLoginAt: Value(now),
        updatedAt: Value(now),
        passwordHash: rehash == null
            ? const Value.absent()
            : Value(rehash.hashBase64),
        passwordSalt: rehash == null
            ? const Value.absent()
            : Value(rehash.saltBase64),
        passwordIterations: rehash == null
            ? const Value.absent()
            : Value(rehash.iterations),
      ),
    );

    await _audit.record(
      action: AuditAction.login,
      summary: 'Signed in.',
      userId: row.id,
      username: row.username,
      entityKind: EntityKind.user,
      entityId: row.id,
    );

    return _loadUser(row.id);
  }

  Future<void> signOut(AuthenticatedUser user) async {
    await _audit.record(
      action: AuditAction.logout,
      summary: 'Signed out.',
      userId: user.id,
      username: user.username,
      entityKind: EntityKind.user,
      entityId: user.id,
    );
  }

  /// Changes the signed-in user's own password after re-verifying the current
  /// one.
  Future<void> changeOwnPassword({
    required AuthenticatedUser user,
    required String currentPassword,
    required String newPassword,
  }) async {
    final strengthProblem = validatePasswordStrength(newPassword);
    if (strengthProblem != null) {
      throw ValidationFailure(strengthProblem, field: 'newPassword');
    }
    requireRule(
      currentPassword != newPassword,
      'The new password must be different from the current one.',
      rule: 'auth.password_changed',
    );

    final row = requireFound(
      await (_db.select(
        _db.users,
      )..where((u) => u.id.equals(user.id))).getSingleOrNull(),
      'Your account no longer exists.',
    );

    final matches = _hasher.verify(
      password: currentPassword,
      hashBase64: row.passwordHash,
      saltBase64: row.passwordSalt,
      iterations: row.passwordIterations,
    );
    if (!matches) {
      throw const AuthFailure('Your current password is incorrect.');
    }

    final hash = _hasher.hash(newPassword);
    final now = _clock.nowUtc();
    await (_db.update(_db.users)..where((u) => u.id.equals(user.id))).write(
      UsersCompanion(
        passwordHash: Value(hash.hashBase64),
        passwordSalt: Value(hash.saltBase64),
        passwordIterations: Value(hash.iterations),
        mustChangePassword: const Value(false),
        updatedAt: Value(now),
      ),
    );

    await _audit.record(
      action: AuditAction.update,
      summary: 'Changed own password.',
      userId: user.id,
      username: user.username,
      entityKind: EntityKind.user,
      entityId: user.id,
    );
  }

  /// Administrator reset. The target must choose a new password on next
  /// sign-in.
  Future<void> resetPassword({
    required AuthenticatedUser actor,
    required int targetUserId,
    required String temporaryPassword,
  }) async {
    actor.require(Permissions.usersManage, action: 'reset passwords');
    final strengthProblem = validatePasswordStrength(temporaryPassword);
    if (strengthProblem != null) {
      throw ValidationFailure(strengthProblem, field: 'password');
    }

    final target = requireFound(
      await (_db.select(
        _db.users,
      )..where((u) => u.id.equals(targetUserId))).getSingleOrNull(),
      'That user no longer exists.',
    );

    final hash = _hasher.hash(temporaryPassword);
    await (_db.update(
      _db.users,
    )..where((u) => u.id.equals(targetUserId))).write(
      UsersCompanion(
        passwordHash: Value(hash.hashBase64),
        passwordSalt: Value(hash.saltBase64),
        passwordIterations: Value(hash.iterations),
        mustChangePassword: const Value(true),
        failedLoginCount: const Value(0),
        lockedUntil: const Value(null),
        updatedAt: Value(_clock.nowUtc()),
      ),
    );

    await _audit.record(
      action: AuditAction.update,
      summary: 'Reset the password for "${target.username}".',
      userId: actor.id,
      username: actor.username,
      entityKind: EntityKind.user,
      entityId: targetUserId,
    );
  }

  /// Re-reads a user and their permissions, e.g. after their roles changed.
  Future<AuthenticatedUser> refresh(int userId) => _loadUser(userId);

  Future<int> _insertUser({
    required String fullName,
    required String username,
    required String password,
    required bool mustChangePassword,
  }) async {
    final hash = _hasher.hash(password);
    final now = _clock.nowUtc();
    return _db
        .into(_db.users)
        .insert(
          UsersCompanion.insert(
            username: username,
            fullName: fullName,
            passwordHash: hash.hashBase64,
            passwordSalt: hash.saltBase64,
            passwordIterations: hash.iterations,
            mustChangePassword: Value(mustChangePassword),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  /// Resolves a user plus the union of the permissions granted by their roles.
  Future<AuthenticatedUser> _loadUser(int userId) async {
    final user = requireFound(
      await (_db.select(
        _db.users,
      )..where((u) => u.id.equals(userId))).getSingleOrNull(),
      'That user no longer exists.',
    );

    final roleQuery = _db.select(_db.userRoles).join([
      innerJoin(_db.roles, _db.roles.id.equalsExp(_db.userRoles.roleId)),
    ])..where(_db.userRoles.userId.equals(userId));
    final roles = (await roleQuery.get()).map(
      (row) => row.readTable(_db.roles),
    );
    final roleIds = roles.map((role) => role.id).toList();
    final roleCodes = roles.map((role) => role.code).toSet();

    final permissions = <String>{};
    if (roleIds.isNotEmpty) {
      final permissionQuery = _db.select(_db.rolePermissions).join([
        innerJoin(
          _db.permissionDefs,
          _db.permissionDefs.id.equalsExp(_db.rolePermissions.permissionId),
        ),
      ])..where(_db.rolePermissions.roleId.isIn(roleIds));
      for (final row in await permissionQuery.get()) {
        permissions.add(row.readTable(_db.permissionDefs).key);
      }
    }

    return AuthenticatedUser(
      id: user.id,
      username: user.username,
      fullName: user.fullName,
      roleCodes: roleCodes,
      permissions: permissions,
      mustChangePassword: user.mustChangePassword,
    );
  }

  static String _normaliseUsername(String value) {
    final clean = requireText(value, 'Username', maxLength: 48).toLowerCase();
    require(
      clean.length >= 3,
      'Username must be at least 3 characters.',
      field: 'username',
    );
    require(
      RegExp(r'^[a-z0-9._-]+$').hasMatch(clean),
      'Username may contain only letters, numbers, dots, underscores and hyphens.',
      field: 'username',
    );
    return clean;
  }
}
