import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:venvo_core/core/api/api_client.dart';
import 'package:venvo_core/core/api/settings_api.dart';
import 'package:venvo_core/core/errors/failures.dart';
import 'package:venvo_core/core/services/clock.dart';
import 'package:venvo_core/features/authentication/api/auth_api.dart';
import 'package:venvo_core/features/authentication/domain/authenticated_user.dart';

import 'client_preferences.dart';

/// Everything the application is built from once it has reached its server.
///
/// There is no database in here. Every screen reads and writes through [api],
/// which is what makes two devices see the same data: there is one copy of
/// it, on the server, and nothing on the device to drift away from it.
class ClientBootstrap {
  ClientBootstrap({
    required this.api,
    required this.preferences,
    required this.needsFirstRunSetup,
    this.restoredUser,
    this.clock = const SystemClock(),
  }) : settings = SettingsApi(api),
       auth = AuthApi(api);

  /// The API version this build speaks. A server on a newer incompatible
  /// version is refused at connection time rather than half-working.
  static const int supportedApiVersion = 1;

  final ApiClient api;
  final ClientPreferences preferences;
  final SettingsApi settings;
  final AuthApi auth;
  final Clock clock;

  /// True when the server holds no user yet, so the first-run screen must
  /// create the administrator before anything else can happen.
  final bool needsFirstRunSetup;

  /// The user a stored session token still belongs to, if any. This is what
  /// lets a browser refresh, or reopening the app, carry on signed in.
  final AuthenticatedUser? restoredUser;

  /// Reaches the server at [serverUrl] and works out where the user stands.
  ///
  /// Throws a [StorageFailure] if the server cannot be reached or speaks a
  /// version this build does not — in both cases before any screen is shown,
  /// so nobody starts work against a server that will not accept it.
  static Future<ClientBootstrap> connect({
    required Uri serverUrl,
    required ClientPreferences preferences,
    http.Client? httpClient,
    Clock clock = const SystemClock(),
  }) async {
    final api = ApiClient(
      baseUrl: serverUrl,
      tokens: preferences,
      httpClient: httpClient,
    );
    final auth = AuthApi(api);

    final ServerStatus status;
    try {
      status = await auth.status();
    } catch (_) {
      await api.close();
      rethrow;
    }
    if (status.apiVersion != supportedApiVersion) {
      await api.close();
      throw StorageFailure(
        'This version of the application cannot talk to that server.',
        details:
            'The server speaks API version ${status.apiVersion}; this build '
            'speaks version $supportedApiVersion. Update whichever is older.',
      );
    }

    // A token kept from last time is tried once. If the server no longer
    // accepts it — expired, idled out, revoked from another device — it is
    // thrown away and the user simply signs in again.
    AuthenticatedUser? user;
    if (api.hasToken) {
      try {
        user = await auth.refresh(0);
      } on AuthFailure {
        await api.clearToken();
      }
    }

    final bootstrap = ClientBootstrap(
      api: api,
      preferences: preferences,
      needsFirstRunSetup: status.needsFirstRunSetup,
      restoredUser: user,
      clock: clock,
    );
    if (user != null) await bootstrap.loadSettingsFor(user);
    return bootstrap;
  }

  /// Loads the business settings once somebody is signed in and able to see
  /// them.
  ///
  /// Skipped while a password change is outstanding: the server keeps
  /// everything but the change-password endpoint closed until then, so asking
  /// would only produce a refusal. A failure here does not stop sign-in: the
  /// cache is left empty, so the next reader fetches again and the problem
  /// surfaces on the screen that actually needs the value.
  Future<void> loadSettingsFor(AuthenticatedUser user) async {
    if (user.mustChangePassword) return;
    try {
      await settings.load();
    } on AppFailure {
      settings.clear();
    }
  }

  Future<void> dispose() => api.close();
}

/// Works out which server this device should talk to, or null if it has to
/// ask.
///
/// In order: an address the user entered on this device; one compiled into
/// the build with `--dart-define=VENVO_API_URL=...`, which is how an Android
/// release is pointed at its server; and, in a browser, the place the page
/// itself was served from — the server serves the web app, so the two are the
/// same address and a web user never has to type one.
Uri? resolveServerUrl(ClientPreferences preferences) {
  final stored = normaliseServerUrl(preferences.serverUrl);
  if (stored != null) return stored;

  const compiled = String.fromEnvironment('VENVO_API_URL');
  final fromBuild = normaliseServerUrl(compiled);
  if (fromBuild != null) return fromBuild;

  if (kIsWeb) return normaliseServerUrl(Uri.base.origin);
  return null;
}

/// Turns what somebody typed into an address, or null if it is not one.
///
/// Adds `https://` when no scheme was given — never `http://`, because a
/// password and a session token travel to this address — and a trailing
/// slash, without which a server reached under a path would lose its last
/// path segment when request paths are resolved against it.
Uri? normaliseServerUrl(String? input) {
  var text = (input ?? '').trim();
  if (text.isEmpty) return null;
  if (!text.contains('://')) text = 'https://$text';
  final parsed = Uri.tryParse(text);
  if (parsed == null || parsed.host.isEmpty) return null;
  if (parsed.scheme != 'http' && parsed.scheme != 'https') return null;
  final path = parsed.path.endsWith('/') ? parsed.path : '${parsed.path}/';
  return parsed.replace(path: path, query: null, fragment: null);
}
