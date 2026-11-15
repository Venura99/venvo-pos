import 'package:flutter_test/flutter_test.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/errors/failures.dart';
import 'package:venvo_core/core/services/password_hasher.dart';
import 'package:venvo_core/features/authentication/data/auth_repository.dart';
import 'package:venvo_core/features/authentication/data/user_admin_repository.dart';
import 'package:venvo_core/features/authentication/domain/authenticated_user.dart';

import '../helpers/test_harness.dart';

void main() {
  late TestHarness harness;
  late AuthRepository auth;
  late UserAdminRepository admin;

  setUp(() async {
    harness = await TestHarness.create();
    // A low PBKDF2 cost keeps the suite fast without changing behaviour.
    auth = AuthRepository(
      database: harness.db,
      clock: harness.clock,
      audit: harness.bootstrap.audit,
      hasher: const PasswordHasher(iterations: 1000),
    );
    admin = UserAdminRepository(
      database: harness.db,
      clock: harness.clock,
      audit: harness.bootstrap.audit,
    );
  });

  tearDown(() => harness.dispose());

  Future<AuthenticatedUser> createAdmin() => auth.createFirstAdministrator(
    fullName: 'Nimal Perera',
    username: 'nimal',
    password: 'Warehouse42',
  );

  group('first run', () {
    test('reports that no users exist', () async {
      expect(await auth.hasNoUsers(), isTrue);
    });

    test('creates an administrator holding every permission', () async {
      final user = await createAdmin();

      expect(user.username, 'nimal');
      expect(user.fullName, 'Nimal Perera');
      expect(user.isAdministrator, isTrue);
      expect(user.permissions.length, Permissions.all.length);
      expect(user.can(Permissions.stockNegativeOverride), isTrue);
      expect(user.mustChangePassword, isFalse);
      expect(await auth.hasNoUsers(), isFalse);
    });

    test('lower-cases the username', () async {
      final user = await auth.createFirstAdministrator(
        fullName: 'Nimal Perera',
        username: 'NiMaL',
        password: 'Warehouse42',
      );
      expect(user.username, 'nimal');
    });

    test('refuses to run once a user exists', () async {
      await createAdmin();
      await expectLater(
        auth.createFirstAdministrator(
          fullName: 'Intruder',
          username: 'intruder',
          password: 'Warehouse42',
        ),
        throwsA(isA<BusinessRuleFailure>()),
      );
    });

    test('rejects a weak password', () async {
      await expectLater(
        auth.createFirstAdministrator(
          fullName: 'Nimal Perera',
          username: 'nimal',
          password: 'short',
        ),
        throwsA(isA<ValidationFailure>()),
      );
      // Nothing was written, so first-run setup is still pending.
      expect(await auth.hasNoUsers(), isTrue);
    });

    test('rejects an invalid username', () async {
      for (final username in ['ab', 'has space', r'bad$char']) {
        await expectLater(
          auth.createFirstAdministrator(
            fullName: 'Nimal Perera',
            username: username,
            password: 'Warehouse42',
          ),
          throwsA(isA<ValidationFailure>()),
          reason: 'should reject "$username"',
        );
      }
    });

    test('stores no password in clear text', () async {
      await createAdmin();
      final row = await harness.db.select(harness.db.users).getSingle();
      expect(row.passwordHash, isNot(contains('Warehouse42')));
      expect(row.passwordSalt, isNotEmpty);
      expect(row.passwordIterations, 1000);
    });
  });

  group('sign in', () {
    test('succeeds with the correct credentials', () async {
      await createAdmin();
      final user = await auth.signIn(
        username: 'nimal',
        password: 'Warehouse42',
      );
      expect(user.username, 'nimal');
      expect(user.isAdministrator, isTrue);
    });

    test('accepts a username in any case', () async {
      await createAdmin();
      final user = await auth.signIn(
        username: 'NIMAL',
        password: 'Warehouse42',
      );
      expect(user.username, 'nimal');
    });

    test('records the sign-in time', () async {
      await createAdmin();
      await auth.signIn(username: 'nimal', password: 'Warehouse42');
      final row = await harness.db.select(harness.db.users).getSingle();
      expect(row.lastLoginAt, harness.clock.nowUtc());
    });

    test(
      'gives the same message for a wrong password and unknown user',
      () async {
        await createAdmin();

        AuthFailure? wrongPassword;
        try {
          await auth.signIn(username: 'nimal', password: 'WrongPass1');
        } on AuthFailure catch (failure) {
          wrongPassword = failure;
        }

        AuthFailure? unknownUser;
        try {
          await auth.signIn(username: 'ghost', password: 'WrongPass1');
        } on AuthFailure catch (failure) {
          unknownUser = failure;
        }

        expect(wrongPassword, isNotNull);
        expect(unknownUser, isNotNull);
        // Identical wording, so the screen cannot be used to discover which
        // usernames exist.
        expect(wrongPassword!.message, unknownUser!.message);
      },
    );

    test('locks the account after five failed attempts', () async {
      await createAdmin();

      for (var attempt = 1; attempt <= 5; attempt++) {
        await expectLater(
          auth.signIn(username: 'nimal', password: 'WrongPass1'),
          throwsA(isA<AuthFailure>()),
        );
      }

      // Even the correct password is refused while locked, and the message
      // says so rather than pretending the password is wrong.
      await expectLater(
        auth.signIn(username: 'nimal', password: 'Warehouse42'),
        throwsA(
          isA<AuthFailure>().having(
            (failure) => failure.message,
            'message',
            contains('Too many failed attempts'),
          ),
        ),
      );
    });

    test('the lockout expires', () async {
      await createAdmin();
      for (var attempt = 1; attempt <= 5; attempt++) {
        await expectLater(
          auth.signIn(username: 'nimal', password: 'WrongPass1'),
          throwsA(isA<AuthFailure>()),
        );
      }

      harness.clock.advance(const Duration(minutes: 6));
      final user = await auth.signIn(
        username: 'nimal',
        password: 'Warehouse42',
      );
      expect(user.username, 'nimal');

      // A successful sign-in clears the counters.
      final row = await harness.db.select(harness.db.users).getSingle();
      expect(row.failedLoginCount, 0);
      expect(row.lockedUntil, isNull);
    });

    test('a successful sign-in resets the failure count', () async {
      await createAdmin();
      await expectLater(
        auth.signIn(username: 'nimal', password: 'WrongPass1'),
        throwsA(isA<AuthFailure>()),
      );
      await auth.signIn(username: 'nimal', password: 'Warehouse42');

      final row = await harness.db.select(harness.db.users).getSingle();
      expect(row.failedLoginCount, 0);
    });

    test('refuses a disabled account with a distinct message', () async {
      final administrator = await createAdmin();
      final second = await auth.createUser(
        actor: administrator,
        fullName: 'Kamal Silva',
        username: 'kamal',
        password: 'Counter123',
        roleCodes: [RoleCodes.cashier],
      );
      await admin.setStatus(
        actor: administrator,
        targetUserId: second.id,
        status: EntityStatus.inactive,
      );

      await expectLater(
        auth.signIn(username: 'kamal', password: 'Counter123'),
        throwsA(
          isA<AuthFailure>().having(
            (failure) => failure.message,
            'message',
            contains('disabled'),
          ),
        ),
      );
    });

    test('re-hashes transparently when the cost has been raised', () async {
      await createAdmin();
      final before = await harness.db.select(harness.db.users).getSingle();
      expect(before.passwordIterations, 1000);

      final strongerAuth = AuthRepository(
        database: harness.db,
        clock: harness.clock,
        audit: harness.bootstrap.audit,
        hasher: const PasswordHasher(iterations: 5000),
      );
      await strongerAuth.signIn(username: 'nimal', password: 'Warehouse42');

      final after = await harness.db.select(harness.db.users).getSingle();
      expect(after.passwordIterations, 5000);
      expect(after.passwordHash, isNot(before.passwordHash));
      // And the password still works afterwards.
      await strongerAuth.signIn(username: 'nimal', password: 'Warehouse42');
    });
  });

  group('audit trail', () {
    test('records a successful sign-in', () async {
      await createAdmin();
      await auth.signIn(username: 'nimal', password: 'Warehouse42');

      final logs = await harness.db.select(harness.db.auditLogs).get();
      expect(logs.where((log) => log.action == AuditAction.login).length, 1);
    });

    test('records a failed attempt against an unknown username', () async {
      await expectLater(
        auth.signIn(username: 'ghost', password: 'WrongPass1'),
        throwsA(isA<AuthFailure>()),
      );

      final logs = await harness.db.select(harness.db.auditLogs).get();
      final failure = logs.singleWhere(
        (log) => log.action == AuditAction.loginFailed,
      );
      expect(failure.username, 'ghost');
      expect(failure.userId, isNull);
      expect(failure.summary, contains('unknown username'));
    });

    test('records the lockout', () async {
      await createAdmin();
      for (var attempt = 1; attempt <= 5; attempt++) {
        await expectLater(
          auth.signIn(username: 'nimal', password: 'WrongPass1'),
          throwsA(isA<AuthFailure>()),
        );
      }

      final logs = await harness.db.select(harness.db.auditLogs).get();
      expect(logs.any((log) => log.summary.contains('Account locked')), isTrue);
    });

    test('never writes a password into the audit trail', () async {
      await createAdmin();
      await auth.signIn(username: 'nimal', password: 'Warehouse42');
      await expectLater(
        auth.signIn(username: 'nimal', password: 'WrongPass1'),
        throwsA(isA<AuthFailure>()),
      );

      final logs = await harness.db.select(harness.db.auditLogs).get();
      for (final log in logs) {
        final text =
            '${log.summary}${log.beforeJson ?? ''}${log.afterJson ?? ''}';
        expect(text.contains('Warehouse42'), isFalse);
        expect(text.contains('WrongPass1'), isFalse);
      }
    });
  });

  group('permissions', () {
    test('a cashier gets only the cashier permissions', () async {
      final administrator = await createAdmin();
      final cashier = await auth.createUser(
        actor: administrator,
        fullName: 'Kamal Silva',
        username: 'kamal',
        password: 'Counter123',
        roleCodes: [RoleCodes.cashier],
      );

      expect(cashier.can(Permissions.invoiceCreate), isTrue);
      expect(cashier.can(Permissions.discountApplyItem), isTrue);
      // A cashier must not be able to adjust stock, exceed discount limits or
      // manage users.
      expect(cashier.can(Permissions.stockAdjust), isFalse);
      expect(cashier.can(Permissions.discountExceedLimit), isFalse);
      expect(cashier.can(Permissions.usersManage), isFalse);
      expect(cashier.isAdministrator, isFalse);
      expect(cashier.mustChangePassword, isTrue);
    });

    test('a user with two roles gets the union of their permissions', () async {
      final administrator = await createAdmin();
      final user = await auth.createUser(
        actor: administrator,
        fullName: 'Sunil Fernando',
        username: 'sunil',
        password: 'Counter123',
        roleCodes: [RoleCodes.cashier, RoleCodes.storeKeeper],
      );

      expect(user.can(Permissions.invoiceCreate), isTrue);
      expect(user.can(Permissions.stockTransfer), isTrue);
      expect(user.can(Permissions.usersManage), isFalse);
    });

    test(
      'require throws for a missing permission and passes for a held one',
      () async {
        final administrator = await createAdmin();
        final viewer = await auth.createUser(
          actor: administrator,
          fullName: 'Ravi Jayasuriya',
          username: 'ravi',
          password: 'Viewer123',
          roleCodes: [RoleCodes.viewer],
        );

        expect(() => viewer.require(Permissions.stockView), returnsNormally);
        expect(
          () => viewer.require(Permissions.stockAdjust, action: 'adjust stock'),
          throwsA(
            isA<PermissionFailure>()
                .having(
                  (f) => f.permission,
                  'permission',
                  Permissions.stockAdjust,
                )
                .having((f) => f.message, 'message', contains('adjust stock')),
          ),
        );
      },
    );

    test('a user without users.manage cannot create users', () async {
      final administrator = await createAdmin();
      final cashier = await auth.createUser(
        actor: administrator,
        fullName: 'Kamal Silva',
        username: 'kamal',
        password: 'Counter123',
        roleCodes: [RoleCodes.cashier],
      );

      await expectLater(
        auth.createUser(
          actor: cashier,
          fullName: 'Someone Else',
          username: 'someone',
          password: 'Counter123',
          roleCodes: [RoleCodes.viewer],
        ),
        throwsA(isA<PermissionFailure>()),
      );
    });

    test('refuses a duplicate username', () async {
      final administrator = await createAdmin();
      await expectLater(
        auth.createUser(
          actor: administrator,
          fullName: 'Another Nimal',
          username: 'nimal',
          password: 'Counter123',
          roleCodes: [RoleCodes.viewer],
        ),
        throwsA(isA<BusinessRuleFailure>()),
      );
    });

    test('refuses to create a user with no role', () async {
      final administrator = await createAdmin();
      await expectLater(
        auth.createUser(
          actor: administrator,
          fullName: 'Roleless',
          username: 'roleless',
          password: 'Counter123',
          roleCodes: const [],
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });
  });

  group('password changes', () {
    test('the owner can change their own password', () async {
      final user = await createAdmin();
      await auth.changeOwnPassword(
        user: user,
        currentPassword: 'Warehouse42',
        newPassword: 'Warehouse99',
      );

      await expectLater(
        auth.signIn(username: 'nimal', password: 'Warehouse42'),
        throwsA(isA<AuthFailure>()),
      );
      final signedIn = await auth.signIn(
        username: 'nimal',
        password: 'Warehouse99',
      );
      expect(signedIn.username, 'nimal');
    });

    test('changing a password requires the current one', () async {
      final user = await createAdmin();
      await expectLater(
        auth.changeOwnPassword(
          user: user,
          currentPassword: 'NotTheOne1',
          newPassword: 'Warehouse99',
        ),
        throwsA(isA<AuthFailure>()),
      );
    });

    test('the new password must differ and meet the policy', () async {
      final user = await createAdmin();
      await expectLater(
        auth.changeOwnPassword(
          user: user,
          currentPassword: 'Warehouse42',
          newPassword: 'Warehouse42',
        ),
        throwsA(isA<BusinessRuleFailure>()),
      );
      await expectLater(
        auth.changeOwnPassword(
          user: user,
          currentPassword: 'Warehouse42',
          newPassword: 'weak',
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('an administrator reset forces a change at next sign-in', () async {
      final administrator = await createAdmin();
      final cashier = await auth.createUser(
        actor: administrator,
        fullName: 'Kamal Silva',
        username: 'kamal',
        password: 'Counter123',
        roleCodes: [RoleCodes.cashier],
        mustChangePassword: false,
      );
      expect(cashier.mustChangePassword, isFalse);

      await auth.resetPassword(
        actor: administrator,
        targetUserId: cashier.id,
        temporaryPassword: 'Temporary1',
      );

      final signedIn = await auth.signIn(
        username: 'kamal',
        password: 'Temporary1',
      );
      expect(signedIn.mustChangePassword, isTrue);

      await auth.changeOwnPassword(
        user: signedIn,
        currentPassword: 'Temporary1',
        newPassword: 'ChosenByMe1',
      );
      final afterChange = await auth.signIn(
        username: 'kamal',
        password: 'ChosenByMe1',
      );
      expect(afterChange.mustChangePassword, isFalse);
    });

    test('a reset clears an existing lockout', () async {
      final administrator = await createAdmin();
      final cashier = await auth.createUser(
        actor: administrator,
        fullName: 'Kamal Silva',
        username: 'kamal',
        password: 'Counter123',
        roleCodes: [RoleCodes.cashier],
      );
      for (var attempt = 1; attempt <= 5; attempt++) {
        await expectLater(
          auth.signIn(username: 'kamal', password: 'WrongPass1'),
          throwsA(isA<AuthFailure>()),
        );
      }

      await auth.resetPassword(
        actor: administrator,
        targetUserId: cashier.id,
        temporaryPassword: 'Temporary1',
      );

      final signedIn = await auth.signIn(
        username: 'kamal',
        password: 'Temporary1',
      );
      expect(signedIn.username, 'kamal');
    });
  });

  group('account administration', () {
    test('lists users with their roles', () async {
      final administrator = await createAdmin();
      await auth.createUser(
        actor: administrator,
        fullName: 'Kamal Silva',
        username: 'kamal',
        password: 'Counter123',
        roleCodes: [RoleCodes.cashier],
      );

      final entries = await admin.listUsers();
      expect(entries.length, 2);
      final kamal = entries.firstWhere((entry) => entry.username == 'kamal');
      expect(kamal.roleCodes, [RoleCodes.cashier]);
      expect(kamal.mustChangePassword, isTrue);
      expect(kamal.lastLoginAt, isNull);
    });

    test('refuses to disable the last administrator', () async {
      final administrator = await createAdmin();
      final other = await auth.createUser(
        actor: administrator,
        fullName: 'Kamal Silva',
        username: 'kamal',
        password: 'Counter123',
        roleCodes: [RoleCodes.manager],
      );

      // Acting as a different administrator so the self-disable guard is not
      // what trips first.
      await admin.setRoles(
        actor: administrator,
        targetUserId: other.id,
        roleCodes: [RoleCodes.administrator],
      );
      final secondAdmin = await auth.refresh(other.id);

      // Disabling the first administrator is allowed while a second exists.
      await admin.setStatus(
        actor: secondAdmin,
        targetUserId: administrator.id,
        status: EntityStatus.inactive,
      );

      // Now only one administrator remains; disabling them must be refused.
      await expectLater(
        admin.setStatus(
          actor: await auth.refresh(administrator.id),
          targetUserId: secondAdmin.id,
          status: EntityStatus.inactive,
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'auth.keep_one_admin',
          ),
        ),
      );
    });

    test(
      'refuses to remove the administrator role from the last admin',
      () async {
        final administrator = await createAdmin();
        await expectLater(
          admin.setRoles(
            actor: administrator,
            targetUserId: administrator.id,
            roleCodes: [RoleCodes.viewer],
          ),
          throwsA(
            isA<BusinessRuleFailure>().having(
              (failure) => failure.rule,
              'rule',
              'auth.keep_one_admin',
            ),
          ),
        );
      },
    );

    test('refuses to disable your own account', () async {
      final administrator = await createAdmin();
      await expectLater(
        admin.setStatus(
          actor: administrator,
          targetUserId: administrator.id,
          status: EntityStatus.inactive,
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'auth.no_self_disable',
          ),
        ),
      );
    });

    test('changing roles takes effect on the next read', () async {
      final administrator = await createAdmin();
      final user = await auth.createUser(
        actor: administrator,
        fullName: 'Kamal Silva',
        username: 'kamal',
        password: 'Counter123',
        roleCodes: [RoleCodes.viewer],
      );
      expect(user.can(Permissions.invoiceCreate), isFalse);

      await admin.setRoles(
        actor: administrator,
        targetUserId: user.id,
        roleCodes: [RoleCodes.cashier],
      );

      final refreshed = await auth.refresh(user.id);
      expect(refreshed.can(Permissions.invoiceCreate), isTrue);
      expect(refreshed.can(Permissions.returnView), isFalse);
    });

    test('clearing a lockout lets the user straight back in', () async {
      final administrator = await createAdmin();
      final cashier = await auth.createUser(
        actor: administrator,
        fullName: 'Kamal Silva',
        username: 'kamal',
        password: 'Counter123',
        roleCodes: [RoleCodes.cashier],
      );
      for (var attempt = 1; attempt <= 5; attempt++) {
        await expectLater(
          auth.signIn(username: 'kamal', password: 'WrongPass1'),
          throwsA(isA<AuthFailure>()),
        );
      }

      await admin.clearLockout(actor: administrator, targetUserId: cashier.id);
      final signedIn = await auth.signIn(
        username: 'kamal',
        password: 'Counter123',
      );
      expect(signedIn.username, 'kamal');
    });
  });
}
