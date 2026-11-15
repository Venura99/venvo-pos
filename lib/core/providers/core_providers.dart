import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:venvo_core/core/api/api_client.dart';
import 'package:venvo_core/core/api/settings_api.dart';
import 'package:venvo_core/core/services/clock.dart';

import '../bootstrap/client_bootstrap.dart';
import '../bootstrap/client_preferences.dart';

/// Root of the dependency graph.
///
/// Overridden in `main` with the [ClientBootstrap] built once the server has
/// been reached, and in tests with one wired to an in-process server. Reading
/// it without an override is a wiring mistake and fails loudly.
///
/// There is no database provider any more, and that absence is the design:
/// nothing in the client can read or write business data except through
/// [apiClientProvider], so there is no local copy to disagree with the
/// server's.
final clientBootstrapProvider = Provider<ClientBootstrap>((ref) {
  throw UnimplementedError(
    'clientBootstrapProvider must be overridden in ProviderScope with the '
    'ClientBootstrap created once the server has been reached.',
  );
});

/// The connection to the server. Every module's provider is built on this.
final apiClientProvider = Provider<ApiClient>(
  (ref) => ref.watch(clientBootstrapProvider).api,
);

final clockProvider = Provider<Clock>(
  (ref) => ref.watch(clientBootstrapProvider).clock,
);

/// Business settings, fetched from the server and cached.
///
/// Keeps the name it had when it was a local `SettingsService`, because the
/// screens that read it are unchanged: the accessors are the same, only where
/// the values come from is different.
final settingsServiceProvider = Provider<SettingsApi>(
  (ref) => ref.watch(clientBootstrapProvider).settings,
);

/// What this device remembers between runs: its server, its session token,
/// and light or dark.
final clientPreferencesProvider = Provider<ClientPreferences>(
  (ref) => ref.watch(clientBootstrapProvider).preferences,
);
