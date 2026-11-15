import 'dart:io';

/// A problem with the server's configuration, reported before it starts
/// serving rather than on the first request that trips over it.
class ServerConfigError implements Exception {
  ServerConfigError(this.message);

  final String message;

  @override
  String toString() => 'Configuration error: $message';
}

/// Everything the server is told from outside.
///
/// **There is no secret in this file, and none is read from one.** The design
/// avoids having one: sessions are opaque random tokens stored (hashed) in the
/// database, so there is no signing key to configure, rotate, accidentally
/// commit, or leak into a client build. Passwords stay where they already are
/// — PBKDF2-HMAC-SHA256 hashes in the `users` table, salted per user.
///
/// The one thing the server refuses to guess is where the business's data
/// lives. Defaulting that to a temporary directory would produce a server that
/// starts cleanly, seeds an empty database, takes a day of real invoices and
/// then loses them on reboot. So `VENVO_DATA_DIR` is required and absent means
/// refuse to start.
class ServerConfig {
  ServerConfig({
    required this.address,
    required this.port,
    required this.dataRoot,
    required this.sessionTtl,
    required this.sessionIdleTimeout,
    required this.logStatements,
    this.webRoot,
  });

  /// Interface to bind. Defaults to loopback, because the intended deployment
  /// puts a reverse proxy (Caddy) in front to terminate TLS — binding the
  /// public interface by default would expose the API over plain HTTP the
  /// moment the server starts.
  final InternetAddress address;
  final int port;

  /// Root of the data directory: the SQLite file, attachments, backups and
  /// exports, exactly the layout `AppPaths` describes.
  final Directory dataRoot;

  /// How long a session lasts before the user must sign in again.
  final Duration sessionTtl;

  /// How long a session may sit unused before it stops working, independent of
  /// [sessionTtl]. A till left signed in overnight should not stay usable to
  /// whoever finds the tablet.
  final Duration sessionIdleTimeout;

  /// Logs every SQL statement. Useful when diagnosing a slow report; far too
  /// noisy, and too revealing, to leave on in production.
  final bool logStatements;

  /// The built web app (`flutter build web` output), served at `/` when set.
  /// A browser then needs only the server's address: the page and the API
  /// come from the same place, so there is nothing else to host and no
  /// cross-origin rules to configure.
  final Directory? webRoot;

  static const String _dataDirVar = 'VENVO_DATA_DIR';

  /// Reads the configuration from [env], validating as it goes.
  ///
  /// Every failure names the variable and what was wrong with it, because the
  /// person reading it is looking at a container that will not start.
  static ServerConfig fromEnvironment(Map<String, String> env) {
    final dataDir = env[_dataDirVar]?.trim();
    if (dataDir == null || dataDir.isEmpty) {
      throw ServerConfigError(
        '$_dataDirVar is required and names the directory holding the '
        'database, attachments, backups and exports. There is deliberately no '
        'default: a server that invented one would quietly serve an empty '
        'database and lose whatever was entered into it.',
      );
    }

    final root = Directory(dataDir);
    if (!root.existsSync()) {
      throw ServerConfigError(
        '$_dataDirVar points at "$dataDir", which does not exist. Create it '
        'and make it writable by the server, or point the variable at the '
        'directory that already holds venvo_pos.sqlite.',
      );
    }

    return ServerConfig(
      address: _address(env),
      port: _intInRange(env, 'VENVO_PORT', fallback: 8080, min: 1, max: 65535),
      dataRoot: root,
      sessionTtl: Duration(
        hours: _intInRange(
          env,
          'VENVO_SESSION_TTL_HOURS',
          fallback: 12,
          min: 1,
          max: 24 * 30,
        ),
      ),
      sessionIdleTimeout: Duration(
        minutes: _intInRange(
          env,
          'VENVO_SESSION_IDLE_MINUTES',
          fallback: 8 * 60,
          min: 5,
          max: 24 * 60,
        ),
      ),
      logStatements: _bool(env, 'VENVO_LOG_SQL', fallback: false),
      webRoot: _webRoot(env),
    );
  }

  static Directory? _webRoot(Map<String, String> env) {
    final raw = env['VENVO_WEB_DIR']?.trim();
    if (raw == null || raw.isEmpty) return null;
    final dir = Directory(raw);
    if (!File('$raw/index.html').existsSync()) {
      throw ServerConfigError(
        'VENVO_WEB_DIR is "$raw", which has no index.html. Point it at the '
        'output of `flutter build web` (build/web), or leave it unset to '
        'serve the API only.',
      );
    }
    return dir;
  }

  static InternetAddress _address(Map<String, String> env) {
    final raw = env['VENVO_BIND_ADDRESS']?.trim();
    if (raw == null || raw.isEmpty) return InternetAddress.loopbackIPv4;
    if (raw == 'any') return InternetAddress.anyIPv4;
    try {
      return InternetAddress(raw);
    } on ArgumentError {
      throw ServerConfigError(
        'VENVO_BIND_ADDRESS is "$raw", which is not an IP address. Use an '
        'address such as 127.0.0.1, or the word "any" to bind every '
        'interface. Binding every interface is only safe behind a reverse '
        'proxy that terminates TLS.',
      );
    }
  }

  static int _intInRange(
    Map<String, String> env,
    String name, {
    required int fallback,
    required int min,
    required int max,
  }) {
    final raw = env[name]?.trim();
    if (raw == null || raw.isEmpty) return fallback;
    final value = int.tryParse(raw);
    if (value == null) {
      throw ServerConfigError('$name is "$raw", which is not a whole number.');
    }
    if (value < min || value > max) {
      throw ServerConfigError(
        '$name is $value, outside the allowed range $min to $max.',
      );
    }
    return value;
  }

  static bool _bool(
    Map<String, String> env,
    String name, {
    required bool fallback,
  }) {
    final raw = env[name]?.trim().toLowerCase();
    if (raw == null || raw.isEmpty) return fallback;
    return switch (raw) {
      '1' || 'true' || 'yes' || 'on' => true,
      '0' || 'false' || 'no' || 'off' => false,
      _ => throw ServerConfigError('$name is "$raw". Use true or false.'),
    };
  }

  /// A one-line summary for the startup log. Contains nothing sensitive.
  String describe() =>
      'listening on ${address.address}:$port, data in ${dataRoot.path}, '
      'sessions last ${sessionTtl.inHours}h '
      '(idle ${sessionIdleTimeout.inMinutes}m)';
}
