import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:venvo_server/api_server.dart';
import 'package:venvo_server/config.dart';

/// The server serving the built web app beside the API, on one address.
void main() {
  late Directory dataDir;
  late Directory webDir;
  late VenvoApiServer server;
  late Uri base;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    dataDir = await Directory.systemTemp.createTemp('venvo_web_data_');
    webDir = await Directory.systemTemp.createTemp('venvo_web_app_');
    File(
      '${webDir.path}/index.html',
    ).writeAsStringSync('<html><body>venvo web app</body></html>');
    File('${webDir.path}/main.dart.js').writeAsStringSync('// app');
    Directory('${webDir.path}/assets').createSync();
    File('${webDir.path}/assets/logo.txt').writeAsStringSync('logo');

    server = await VenvoApiServer.start(
      ServerConfig(
        address: InternetAddress.loopbackIPv4,
        port: 0,
        dataRoot: dataDir,
        sessionTtl: const Duration(hours: 12),
        sessionIdleTimeout: const Duration(hours: 8),
        logStatements: false,
        webRoot: webDir,
      ),
      log: (_) {},
    );
    base = server.url;
  });

  tearDown(() async {
    await server.stop();
    for (final dir in [dataDir, webDir]) {
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows can hold a file briefly after close.
      }
    }
  });

  test('the address itself serves the app', () async {
    final response = await http.get(base);
    expect(response.statusCode, 200);
    expect(response.body, contains('venvo web app'));
    // An entry point must be re-checked, or a browser keeps old code.
    expect(response.headers['cache-control'], 'no-cache');
  });

  test('the app\'s own files are served', () async {
    final response = await http.get(base.resolve('assets/logo.txt'));
    expect(response.statusCode, 200);
    expect(response.body, 'logo');
  });

  test('the API is still the API on the same address', () async {
    final response = await http.get(base.resolve('api/v1/status'));
    expect(response.statusCode, 200);
    expect(
      (jsonDecode(response.body) as Map<String, Object?>)['apiVersion'],
      1,
    );
    expect((await http.get(base.resolve('health'))).statusCode, 200);
  });

  test('an unknown API path is never answered with the web page', () async {
    // A protected API path with no token must still be refused by the API,
    // not quietly served index.html with a 200.
    final response = await http.get(base.resolve('api/v1/products'));
    expect(response.statusCode, 401);
  });

  test('a reload deep inside the app gets the app back', () async {
    final response = await http.get(base.resolve('invoices/42'));
    expect(response.statusCode, 200);
    expect(response.body, contains('venvo web app'));
  });
}
