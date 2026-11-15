import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart' as shelf;
import 'package:venvo_core/core/bootstrap/app_bootstrap.dart';
import 'package:venvo_core/core/database/app_database.dart';
import 'package:venvo_core/core/database/database_connection.dart';
import 'package:venvo_core/core/services/clock.dart';
import 'package:venvo_pos/core/bootstrap/client_bootstrap.dart';
import 'package:venvo_pos/core/bootstrap/client_preferences.dart';
import 'package:venvo_server/api_server.dart';
import 'package:venvo_server/config.dart';

import 'test_harness.dart';

/// An `http.Client` that hands each request straight to a shelf handler.
///
/// The client application is tested against the **real** server — the same
/// routes, authentication and business services that run in production —
/// without opening a socket. That matters inside a widget test, whose fake
/// clock cannot drive real network I/O; a request here is just a chain of
/// futures, which the test's frames run.
class ShelfHttpClient extends http.BaseClient {
  ShelfHttpClient(this._handler);

  final shelf.Handler _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await request.finalize().toBytes();
    final response = await _handler(
      shelf.Request(
        request.method,
        request.url,
        headers: request.headers,
        body: body,
      ),
    );
    return http.StreamedResponse(
      response.read(),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

/// A real server over an in-memory database, and a client connected to it.
class InProcessServer {
  InProcessServer._(this.serverBootstrap, this.client, this._dataDir);

  final AppBootstrap serverBootstrap;
  final ClientBootstrap client;
  final Directory _dataDir;

  static Future<InProcessServer> start({Clock? clock}) async {
    configureSqliteForTests();
    final serverClock = clock ?? FixedClock(DateTime.utc(2026, 11, 1, 9, 30));
    final dataDir = await Directory.systemTemp.createTemp('venvo_client_');
    final serverBootstrap = await AppBootstrap.forTesting(
      clock: serverClock,
      database: AppDatabase(DatabaseConnections.memory()),
      dataRoot: dataDir,
    );
    final composed = VenvoApiServer.compose(
      bootstrap: serverBootstrap,
      clock: serverClock,
      log: (_) {},
      config: ServerConfig(
        address: InternetAddress.loopbackIPv4,
        port: 0,
        dataRoot: dataDir,
        sessionTtl: const Duration(hours: 12),
        sessionIdleTimeout: const Duration(hours: 8),
        logStatements: false,
      ),
    );
    final client = await ClientBootstrap.connect(
      serverUrl: Uri.parse('http://venvo.test/'),
      preferences: MemoryClientPreferences(),
      httpClient: ShelfHttpClient(composed.handler),
      clock: serverClock,
    );
    return InProcessServer._(serverBootstrap, client, dataDir);
  }

  Future<void> stop() async {
    await client.dispose();
    await serverBootstrap.dispose();
    try {
      if (_dataDir.existsSync()) await _dataDir.delete(recursive: true);
    } on FileSystemException {
      // The operating system reclaims it.
    }
  }
}
