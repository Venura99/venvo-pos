import 'package:shared_preferences/shared_preferences.dart';
import 'package:venvo_core/core/api/api_client.dart';

/// The few things this device remembers between runs.
///
/// Deliberately small. The business's data lives on the server; what is kept
/// here is only what this device needs in order to reach it — which server,
/// and the session token — plus the one preference that genuinely belongs to
/// the device rather than the business: light or dark.
///
/// The theme used to be a row in the settings table. With one shared database
/// that would have meant one person's click turning every till in the
/// business dark, so it moved here.
abstract class ClientPreferences implements ApiTokenStore {
  /// The server this device talks to, or null if none has been chosen yet.
  String? get serverUrl;

  Future<void> setServerUrl(String? url);

  /// `light`, `dark` or `system`.
  String? get themeMode;

  Future<void> setThemeMode(String mode);
}

/// Preferences kept by the platform: `SharedPreferences` on Android, browser
/// local storage on the web, the registry-backed store on Windows.
///
/// The session token is stored here in the clear. That is the ordinary trade
/// for a web client, where there is nowhere better to put it, and it is
/// bounded by the server: a token expires, idles out, and can be revoked from
/// another device. The password itself is never stored anywhere.
class SharedClientPreferences implements ClientPreferences {
  SharedClientPreferences._(this._store);

  static Future<SharedClientPreferences> load() async =>
      SharedClientPreferences._(await SharedPreferences.getInstance());

  final SharedPreferences _store;

  static const String _serverKey = 'venvo.server_url';
  static const String _tokenKey = 'venvo.session_token';
  static const String _themeKey = 'venvo.theme_mode';

  @override
  String? get serverUrl => _store.getString(_serverKey);

  @override
  Future<void> setServerUrl(String? url) async {
    if (url == null || url.trim().isEmpty) {
      await _store.remove(_serverKey);
    } else {
      await _store.setString(_serverKey, url.trim());
    }
  }

  @override
  String? get token => _store.getString(_tokenKey);

  @override
  Future<void> save(String token) => _store.setString(_tokenKey, token);

  @override
  Future<void> clear() => _store.remove(_tokenKey);

  @override
  String? get themeMode => _store.getString(_themeKey);

  @override
  Future<void> setThemeMode(String mode) => _store.setString(_themeKey, mode);
}

/// Preferences that forget everything when the process ends. Used by tests,
/// so no test can leave a token or a server address behind for the next.
class MemoryClientPreferences implements ClientPreferences {
  MemoryClientPreferences({this.serverUrl, this.token, this.themeMode});

  @override
  String? serverUrl;

  @override
  String? token;

  @override
  String? themeMode;

  @override
  Future<void> setServerUrl(String? url) async => serverUrl = url;

  @override
  Future<void> save(String value) async => token = value;

  @override
  Future<void> clear() async => token = null;

  @override
  Future<void> setThemeMode(String mode) async => themeMode = mode;
}
