import 'dart:io';

import 'package:venvo_server/api_server.dart';
import 'package:venvo_server/config.dart';

/// Entry point for the Venvo POS API.
///
/// Configuration comes from the environment — see [ServerConfig]. A
/// configuration problem stops the process here with a message naming the
/// variable, rather than producing a server that starts and then misbehaves.
Future<void> main(List<String> arguments) async {
  // Container healthcheck. Handled before anything else and without touching
  // the database, so an unhealthy server cannot report itself healthy and a
  // healthy one is not disturbed by being asked.
  if (arguments.contains('--health-check')) {
    exitCode = await _healthCheck(Platform.environment);
    return;
  }

  final ServerConfig config;
  try {
    config = ServerConfig.fromEnvironment(Platform.environment);
  } on ServerConfigError catch (error) {
    stderr.writeln('Venvo POS API cannot start.');
    stderr.writeln();
    stderr.writeln(error.message);
    exitCode = 78; // EX_CONFIG, which an init system reports usefully.
    return;
  }

  final server = await VenvoApiServer.start(config);

  // Shut down on the signals a container runtime and an init system actually
  // send, so the database is closed cleanly and the write-ahead log is
  // checkpointed rather than left for recovery on the next start.
  //
  // SIGTERM is what `docker stop` and systemd send; SIGINT is Ctrl-C. SIGTERM
  // cannot be watched on Windows, so it is only registered where it exists.
  var shuttingDown = false;
  Future<void> shutdown(String signal) async {
    if (shuttingDown) return;
    shuttingDown = true;
    stdout.writeln('$signal received, shutting down');
    await server.stop();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen((_) => shutdown('SIGINT'));
  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen((_) => shutdown('SIGTERM'));
  }
}

/// Asks the running server whether it is answering requests.
///
/// Reads only the port from the environment: a healthcheck that validated the
/// whole configuration could fail for a reason that has nothing to do with
/// the server's health, and one that opened the database would compete with
/// the server for it.
Future<int> _healthCheck(Map<String, String> env) async {
  final port = int.tryParse(env['VENVO_PORT'] ?? '') ?? 8080;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final request = await client.get('127.0.0.1', port, '/health');
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode == 200 ? 0 : 1;
  } catch (_) {
    // Any failure to get a 200 from /health means unhealthy. There is nothing
    // useful to report to a caller that only reads the exit code.
    return 1;
  } finally {
    client.close(force: true);
  }
}
