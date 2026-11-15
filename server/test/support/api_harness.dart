import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:venvo_core/features/payments/data/cheque_reminders.dart';
import 'package:venvo_server/api_server.dart';
import 'package:venvo_server/config.dart';

/// A running API over a real SQLite file in a temporary directory.
///
/// Nothing is stubbed: the server opens a database, seeds it, and answers over
/// real HTTP. Tests that go through here therefore exercise the status codes,
/// headers and JSON a client will actually receive.
class ApiHarness {
  ApiHarness._(this._server, this._dataDir, this.logs);

  final VenvoApiServer _server;
  final Directory _dataDir;

  /// Everything the server logged. Tests assert on this to prove that a clean
  /// run produced no unhandled errors.
  final List<String> logs;

  static const String adminPassword = 'Str0ngPass2026';

  Uri get base => _server.url;

  bool get needsFirstRunSetup => _server.needsFirstRunSetup;

  static Future<ApiHarness> start({ReminderSender? reminderSender}) async {
    // Each test starts its own server over its own database, which is what
    // drift's multiple-instance warning exists to catch in application code.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

    final dataDir = await Directory.systemTemp.createTemp('venvo_api_');
    final logs = <String>[];
    final server = await VenvoApiServer.start(
      ServerConfig(
        address: InternetAddress.loopbackIPv4,
        // Port 0 asks the operating system for a free one, so tests never
        // collide with each other or with a real server on this machine.
        port: 0,
        dataRoot: dataDir,
        sessionTtl: const Duration(hours: 12),
        sessionIdleTimeout: const Duration(hours: 8),
        logStatements: false,
      ),
      log: logs.add,
      reminderSender: reminderSender,
    );
    return ApiHarness._(server, dataDir, logs);
  }

  Future<void> stop() async {
    await _server.stop();
    try {
      _dataDir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows can hold the file briefly after close; the OS reclaims it.
    }
  }

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

  /// The list under [key], as maps.
  List<Map<String, Object?>> list(http.Response response, String key) =>
      (json(response)[key]! as List).cast<Map<String, Object?>>();

  Map<String, Object?> errorOf(http.Response response) =>
      json(response)['error']! as Map<String, Object?>;

  /// Creates the administrator and returns a bearer token.
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

  /// Creates a user with [roles], signs them in and clears the forced password
  /// change, so the returned token can be used against the business endpoints.
  Future<String> createWorkingUser({
    required String adminToken,
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

  /// Creates a category and returns its id. Products need one.
  Future<int> createCategory(String token, {String name = 'Chargers'}) async {
    final response = await send('POST', '/api/v1/categories', {
      'name': name,
    }, token: token);
    expect(response.statusCode, 201, reason: response.body);
    return json(response)['id']! as int;
  }
}
