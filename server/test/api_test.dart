import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_server/api_server.dart';
import 'package:venvo_server/config.dart';

/// Drives the API over real HTTP, against a real SQLite file in a temporary
/// directory. Nothing is stubbed: the server opens a database, seeds it, and
/// answers requests the way it will in production.
void main() {
  const adminPassword = 'Str0ngPass2026';

  late Directory dataDir;
  late VenvoApiServer server;
  late Uri base;
  final logs = <String>[];

  setUpAll(() {
    // Every test starts its own server over its own database, which is what
    // drift's multiple-instance warning exists to catch in application code.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() async {
    dataDir = await Directory.systemTemp.createTemp('venvo_api_');
    logs.clear();
    server = await VenvoApiServer.start(
      ServerConfig(
        address: InternetAddress.loopbackIPv4,
        // Port 0 asks the operating system for a free port, so tests never
        // collide with each other or with a real server on this machine.
        port: 0,
        dataRoot: dataDir,
        sessionTtl: const Duration(hours: 12),
        sessionIdleTimeout: const Duration(hours: 8),
        logStatements: false,
      ),
      log: logs.add,
    );
    base = server.url;
  });

  tearDown(() async {
    await server.stop();
    try {
      dataDir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows can hold the file briefly after close; the OS will reclaim it.
    }
  });

  Map<String, String> headers(String? token) => {
    'content-type': 'application/json',
    if (token != null) 'authorization': 'Bearer $token',
  };

  Future<http.Response> get(String path, {String? token}) =>
      http.get(base.resolve(path), headers: headers(token));

  Future<http.Response> send(
    String method,
    String path,
    Object? body, {
    String? token,
  }) async {
    final request = http.Request(method, base.resolve(path))
      ..headers.addAll(headers(token));
    if (body != null) request.body = jsonEncode(body);
    return http.Response.fromStream(await request.send());
  }

  Map<String, Object?> json(http.Response response) =>
      jsonDecode(response.body) as Map<String, Object?>;

  Map<String, Object?> errorOf(http.Response response) =>
      json(response)['error']! as Map<String, Object?>;

  /// Creates the administrator and returns the bearer token.
  Future<String> signUpAdministrator() async {
    final response = await send('POST', '/api/v1/auth/first-run', {
      'fullName': 'Venura Admin',
      'username': 'admin',
      'password': adminPassword,
      'deviceLabel': 'Test counter',
      'deviceKind': 'windows',
    });
    expect(response.statusCode, 201, reason: response.body);
    return json(response)['token']! as String;
  }

  /// Creates a user, signs them in, and clears the forced password change so
  /// the account can use the rest of the API.
  Future<String> createWorkingUser(
    String adminToken, {
    required String username,
    required List<String> roles,
  }) async {
    const initial = 'Initial1Pass';
    const chosen = 'Chosen2Pass9';

    final created = await send('POST', '/api/v1/users', {
      'fullName': username,
      'username': username,
      'password': initial,
      'roles': roles,
    }, token: adminToken);
    expect(created.statusCode, 201, reason: created.body);

    final signedIn = await send('POST', '/api/v1/auth/login', {
      'username': username,
      'password': initial,
    });
    expect(signedIn.statusCode, 200, reason: signedIn.body);
    final token = json(signedIn)['token']! as String;

    final changed = await send('POST', '/api/v1/auth/password', {
      'currentPassword': initial,
      'newPassword': chosen,
    }, token: token);
    expect(changed.statusCode, 200, reason: changed.body);
    return token;
  }

  group('open endpoints', () {
    test('health answers without a token', () async {
      final response = await get('/health');
      expect(response.statusCode, 200);
      expect(json(response)['status'], 'ok');
    });

    test('a fresh server reports that first-run setup is needed', () async {
      final response = await get('/api/v1/status');
      expect(response.statusCode, 200);
      expect(json(response)['needsFirstRunSetup'], isTrue);
      expect(json(response)['schemaVersion'], 4);
      expect(server.needsFirstRunSetup, isTrue);
    });

    test('no account exists until one is created', () async {
      // The server must never seed a usable login. Eight phases of the
      // desktop build held this and it matters far more now that the server
      // is reachable over a network.
      final response = await send('POST', '/api/v1/auth/login', {
        'username': 'admin',
        'password': 'admin',
      });
      expect(response.statusCode, 401);
    });
  });

  group('first-run', () {
    test('creates the administrator and issues a usable token', () async {
      final token = await signUpAdministrator();

      final me = await get('/api/v1/auth/me', token: token);
      expect(me.statusCode, 200, reason: me.body);
      final user = json(me)['user']! as Map<String, Object?>;
      expect(user['username'], 'admin');
      expect(user['roleCodes'], contains(RoleCodes.administrator));
      expect(user['mustChangePassword'], isFalse);
      // An administrator holds every permission there is.
      expect(
        (user['permissions']! as List).cast<String>().toSet(),
        Permissions.all.toSet(),
      );
    });

    test('refuses a second time', () async {
      await signUpAdministrator();
      final again = await send('POST', '/api/v1/auth/first-run', {
        'fullName': 'Someone Else',
        'username': 'intruder',
        'password': adminPassword,
      });
      // A business rule, not a validation problem: the request was fine, the
      // state of the database is what refuses it.
      expect(again.statusCode, 409, reason: again.body);
      expect(errorOf(again)['rule'], 'auth.first_run_once');
    });

    test('rejects a weak password without creating anything', () async {
      final weak = await send('POST', '/api/v1/auth/first-run', {
        'fullName': 'Venura Admin',
        'username': 'admin',
        'password': 'short',
      });
      expect(weak.statusCode, 422, reason: weak.body);
      expect(errorOf(weak)['field'], 'password');
      // And the server is still waiting for a first run.
      expect(json(await get('/api/v1/status'))['needsFirstRunSetup'], isTrue);
    });
  });

  group('authentication', () {
    test('a protected route without a token is refused', () async {
      await signUpAdministrator();
      final response = await get('/api/v1/users');
      expect(response.statusCode, 401);
    });

    test('a malformed authorization header is refused', () async {
      await signUpAdministrator();
      final response = await http.get(
        base.resolve('/api/v1/users'),
        headers: {'authorization': 'Basic abc123'},
      );
      expect(response.statusCode, 401);
    });

    test('a wrong password says no more than an unknown user', () async {
      await signUpAdministrator();
      final wrongPassword = await send('POST', '/api/v1/auth/login', {
        'username': 'admin',
        'password': 'Wr0ngPassword',
      });
      final unknownUser = await send('POST', '/api/v1/auth/login', {
        'username': 'nobody',
        'password': 'Wr0ngPassword',
      });

      expect(wrongPassword.statusCode, 401);
      expect(unknownUser.statusCode, 401);
      // Identical, so the endpoint cannot be used to discover usernames.
      expect(
        errorOf(wrongPassword)['message'],
        errorOf(unknownUser)['message'],
      );
    });

    test('repeated wrong passwords lock the account', () async {
      await signUpAdministrator();
      for (var attempt = 0; attempt < 5; attempt++) {
        final response = await send('POST', '/api/v1/auth/login', {
          'username': 'admin',
          'password': 'Wr0ngPassword',
        });
        expect(response.statusCode, 401);
      }

      // The correct password now fails too: the lockout written for the
      // offline build is what stands between a server on the internet and an
      // unlimited guessing rate.
      final correct = await send('POST', '/api/v1/auth/login', {
        'username': 'admin',
        'password': adminPassword,
      });
      expect(correct.statusCode, 401);
      expect(errorOf(correct)['message'], contains('Too many failed attempts'));
    });

    test('signing out stops the token working', () async {
      final token = await signUpAdministrator();
      expect((await get('/api/v1/auth/me', token: token)).statusCode, 200);

      final out = await send('POST', '/api/v1/auth/logout', null, token: token);
      expect(out.statusCode, 204);

      expect((await get('/api/v1/auth/me', token: token)).statusCode, 401);
    });
  });

  group('sessions', () {
    test('changing a password signs other devices out, not this one', () async {
      final first = await signUpAdministrator();
      final secondLogin = await send('POST', '/api/v1/auth/login', {
        'username': 'admin',
        'password': adminPassword,
        'deviceLabel': 'Back office',
      });
      final second = json(secondLogin)['token']! as String;
      expect((await get('/api/v1/auth/me', token: second)).statusCode, 200);

      final changed = await send('POST', '/api/v1/auth/password', {
        'currentPassword': adminPassword,
        'newPassword': 'Rotated9Pass',
      }, token: first);
      expect(changed.statusCode, 200, reason: changed.body);
      expect(json(changed)['otherDevicesSignedOut'], 1);

      // The other device is out; the one that made the change carries on.
      expect((await get('/api/v1/auth/me', token: second)).statusCode, 401);
      expect((await get('/api/v1/auth/me', token: first)).statusCode, 200);
    });

    test('a device can be signed out remotely', () async {
      final first = await signUpAdministrator();
      final secondLogin = await send('POST', '/api/v1/auth/login', {
        'username': 'admin',
        'password': adminPassword,
        'deviceLabel': 'Lost tablet',
      });
      final second = json(secondLogin)['token']! as String;
      final secondId = json(secondLogin)['sessionId']! as String;

      final devices = await get('/api/v1/auth/devices', token: first);
      expect((json(devices)['devices']! as List).length, 2);

      final revoked = await send(
        'DELETE',
        '/api/v1/auth/devices/$secondId',
        null,
        token: first,
      );
      expect(revoked.statusCode, 204);
      expect((await get('/api/v1/auth/me', token: second)).statusCode, 401);
    });

    test('a user cannot sign out another account\'s device', () async {
      final admin = await signUpAdministrator();
      final cashier = await createWorkingUser(
        admin,
        username: 'cashier1',
        roles: [RoleCodes.cashier],
      );

      final mine = await get('/api/v1/auth/devices', token: admin);
      final adminSessionId =
          ((json(mine)['devices']! as List).first as Map)['id'] as String;

      final attempt = await send(
        'DELETE',
        '/api/v1/auth/devices/$adminSessionId',
        null,
        token: cashier,
      );
      expect(attempt.statusCode, 404, reason: attempt.body);
      // The administrator's session is untouched.
      expect((await get('/api/v1/auth/me', token: admin)).statusCode, 200);
    });
  });

  group('users and roles', () {
    test('an administrator can read users, roles and permissions', () async {
      final token = await signUpAdministrator();

      final users = await get('/api/v1/users', token: token);
      expect(users.statusCode, 200, reason: users.body);
      expect((json(users)['users']! as List).length, 1);

      final roles = await get('/api/v1/roles', token: token);
      expect(roles.statusCode, 200);
      expect(
        (json(roles)['roles']! as List).map((r) => (r as Map)['code']).toSet(),
        containsAll(<String>[
          RoleCodes.administrator,
          RoleCodes.manager,
          RoleCodes.cashier,
          RoleCodes.accountant,
          RoleCodes.storeKeeper,
          RoleCodes.viewer,
        ]),
      );

      final permissions = await get('/api/v1/permissions', token: token);
      expect(permissions.statusCode, 200);
      expect(
        (json(permissions)['permissions']! as List).cast<String>(),
        Permissions.all,
      );
    });

    test('a new account must change its password first', () async {
      final admin = await signUpAdministrator();
      final created = await send('POST', '/api/v1/users', {
        'fullName': 'Nimal Perera',
        'username': 'nimal',
        'password': 'Initial1Pass',
        'roles': [RoleCodes.manager],
      }, token: admin);
      expect(created.statusCode, 201, reason: created.body);

      final login = await send('POST', '/api/v1/auth/login', {
        'username': 'nimal',
        'password': 'Initial1Pass',
      });
      final token = json(login)['token']! as String;
      expect((json(login)['user']! as Map)['mustChangePassword'], isTrue);

      // Business endpoints are closed until the password is replaced. The
      // desktop shell enforces this too, but a client is not a security
      // boundary — anyone can send an HTTP request.
      final blocked = await get('/api/v1/users', token: token);
      expect(blocked.statusCode, 401, reason: blocked.body);

      // The way out is open.
      expect((await get('/api/v1/auth/me', token: token)).statusCode, 200);
      final changed = await send('POST', '/api/v1/auth/password', {
        'currentPassword': 'Initial1Pass',
        'newPassword': 'Chosen2Pass9',
      }, token: token);
      expect(changed.statusCode, 200, reason: changed.body);

      // And now the account works, with a manager's permissions.
      final after = await get('/api/v1/auth/me', token: token);
      expect((json(after)['user']! as Map)['mustChangePassword'], isFalse);
    });

    test('a cashier may not administer users', () async {
      final admin = await signUpAdministrator();
      final cashier = await createWorkingUser(
        admin,
        username: 'cashier2',
        roles: [RoleCodes.cashier],
      );

      final refused = await get('/api/v1/users', token: cashier);
      expect(refused.statusCode, 403, reason: refused.body);
      expect(errorOf(refused)['permission'], Permissions.usersManage);
    });

    test('a role change takes effect without signing in again', () async {
      final admin = await signUpAdministrator();
      final cashier = await createWorkingUser(
        admin,
        username: 'cashier3',
        roles: [RoleCodes.cashier],
      );
      expect((await get('/api/v1/users', token: cashier)).statusCode, 403);

      final listed = await get('/api/v1/users', token: admin);
      final targetId =
          ((json(listed)['users']! as List)
                  .cast<Map<String, Object?>>()
                  .firstWhere((u) => u['username'] == 'cashier3'))['id']
              as int;

      final promoted = await send('PUT', '/api/v1/users/$targetId/roles', {
        'roles': [RoleCodes.manager, RoleCodes.administrator],
      }, token: admin);
      expect(promoted.statusCode, 204, reason: promoted.body);

      // Same token, no new sign-in. Permissions are resolved per request, so
      // a grant — or a revocation — applies to the very next call.
      expect((await get('/api/v1/users', token: cashier)).statusCode, 200);

      final demoted = await send('PUT', '/api/v1/users/$targetId/roles', {
        'roles': [RoleCodes.viewer],
      }, token: admin);
      expect(demoted.statusCode, 204);
      expect((await get('/api/v1/users', token: cashier)).statusCode, 403);
    });

    test('disabling an account ends its access at once', () async {
      final admin = await signUpAdministrator();
      final cashier = await createWorkingUser(
        admin,
        username: 'cashier4',
        roles: [RoleCodes.cashier],
      );
      expect((await get('/api/v1/auth/me', token: cashier)).statusCode, 200);

      final listed = await get('/api/v1/users', token: admin);
      final targetId =
          ((json(listed)['users']! as List)
                  .cast<Map<String, Object?>>()
                  .firstWhere((u) => u['username'] == 'cashier4'))['id']
              as int;

      final disabled = await send('PATCH', '/api/v1/users/$targetId/status', {
        'status': 'inactive',
      }, token: admin);
      expect(disabled.statusCode, 200, reason: disabled.body);
      expect(json(disabled)['signedOutDevices'], 1);

      expect((await get('/api/v1/auth/me', token: cashier)).statusCode, 401);
    });

    test('the last administrator cannot be disabled', () async {
      final admin = await signUpAdministrator();
      final listed = await get('/api/v1/users', token: admin);
      final id = ((json(listed)['users']! as List).first as Map)['id'] as int;

      final refused = await send('PATCH', '/api/v1/users/$id/status', {
        'status': 'inactive',
      }, token: admin);
      // Locking everybody out of the system is a business rule violation, and
      // the rule lives in the repository where it is already tested.
      expect(refused.statusCode, 409, reason: refused.body);
      expect((await get('/api/v1/auth/me', token: admin)).statusCode, 200);
    });
  });

  group('error reporting', () {
    test('a missing field is a 422 naming the field', () async {
      final token = await signUpAdministrator();
      final response = await send('POST', '/api/v1/users', {
        'username': 'nofullname',
        'password': 'Initial1Pass',
        'roles': [RoleCodes.cashier],
      }, token: token);
      expect(response.statusCode, 422, reason: response.body);
      expect(errorOf(response)['field'], 'fullName');
    });

    test('a body that is not JSON is a 422, not a 500', () async {
      final token = await signUpAdministrator();
      final response = await http.post(
        base.resolve('/api/v1/users'),
        headers: headers(token),
        body: 'this is not json',
      );
      expect(response.statusCode, 422, reason: response.body);
    });

    test('an unknown path with a valid token is a 404', () async {
      final token = await signUpAdministrator();
      final response = await get('/api/v1/nothing-here', token: token);
      expect(response.statusCode, 404);
    });

    test('nothing unexpected was logged during a clean run', () async {
      final token = await signUpAdministrator();
      await get('/api/v1/users', token: token);
      expect(
        logs.where((line) => line.contains('UNHANDLED')),
        isEmpty,
        reason: logs.join('\n'),
      );
    });
  });
}
