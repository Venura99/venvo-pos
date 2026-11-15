import '../constants/app_constants.dart';
import '../errors/failures.dart';
import '../services/document_pdf_service.dart';
import 'api_client.dart';
import 'revision_bus.dart';

/// Application settings over HTTP, with the same typed accessors
/// `SettingsService` exposes.
///
/// **Cached on purpose.** The discount ceilings are consulted on a hot path —
/// every keystroke in a discount field asks whether the value is still
/// allowed — and a network round trip per keystroke would make billing feel
/// broken, which the brief forbids. So the whole set is fetched once by
/// [load] and held, exactly as `SettingsService` holds it locally, and
/// re-fetched when something changes it.
///
/// The consequence to be honest about: a ceiling changed on another device is
/// not seen here until this client reloads. For a setting that changes a few
/// times a year that is the right trade; the server enforces the real ceiling
/// on every write regardless, so a stale client can annoy a cashier but
/// cannot let a discount through.
class SettingsApi {
  SettingsApi(this._client);

  final ApiClient _client;
  Map<String, Object?> _values = const {};
  Set<String> _writable = const {};
  var _loaded = false;

  /// Fetches every setting and caches it. Call once at start-up, and again
  /// after changing one.
  Future<void> load() async {
    final json = await _client.get('/api/v1/settings');
    final values = json['settings'];
    if (values is! Map<String, Object?>) {
      throw StorageFailure(
        'The server sent a reply this version cannot read.',
        details: 'Expected an object under "settings".',
      );
    }
    _values = values;
    final writable = json['writable'];
    _writable = writable is List
        ? writable.cast<String>().toSet()
        : const <String>{};
    _loaded = true;
  }

  /// Settings this user's server will accept changes to.
  Set<String> get writableKeys => _writable;

  Future<void> _ensureLoaded() async {
    if (!_loaded) await load();
  }

  Future<String?> getString(String key, {String? fallback}) async {
    await _ensureLoaded();
    final value = _values[key];
    return value is String && value.isNotEmpty ? value : fallback;
  }

  Future<int> getInt(String key, {int fallback = 0}) async {
    await _ensureLoaded();
    final value = _values[key];
    return value is int ? value : fallback;
  }

  Future<bool> getBool(String key, {bool fallback = false}) async {
    await _ensureLoaded();
    final value = _values[key];
    return value is bool ? value : fallback;
  }

  /// Writes settings and refreshes the cache.
  ///
  /// Takes a map so several can change together: the business details on the
  /// settings screen are edited as one form and should be saved as one.
  Future<List<String>> update(Map<String, Object?> changes) async {
    final json = await _client.put(
      '/api/v1/settings',
      body: {'settings': changes},
      bumps: {ApiTopic.settings},
    );
    await load();
    final changed = json['changed'];
    return changed is List ? changed.cast<String>() : const <String>[];
  }

  /// A cached value, read without waiting. Null until [load] has run or when
  /// the setting is unset. For the places that need a value while building a
  /// widget and cannot await one — the business name in the top bar, the
  /// initial contents of the settings form.
  String? getStringSync(String key) {
    final value = _values[key];
    return value is String && value.isNotEmpty ? value : null;
  }

  /// As [getStringSync], for a whole number.
  int getIntSync(String key, {int fallback = 0}) {
    final value = _values[key];
    return value is int ? value : fallback;
  }

  /// As [getStringSync], for a flag.
  bool getBoolSync(String key, {bool fallback = false}) {
    final value = _values[key];
    return value is bool ? value : fallback;
  }

  /// Forgets everything cached, so the next reader fetches afresh. Called on
  /// sign-out: the next person at this device may be allowed to see different
  /// things, and must not inherit what the last one loaded.
  void clear() {
    _values = const {};
    _writable = const {};
    _loaded = false;
  }

  /// The business's details as they print on a document, from the cache.
  Future<BusinessIdentity> businessIdentity() async {
    String? clean(String? value) {
      final text = (value ?? '').trim();
      return text.isEmpty ? null : text;
    }

    return BusinessIdentity(
      name: await businessName,
      address: clean(await getString(SettingKeys.businessAddress)),
      phone: clean(await getString(SettingKeys.businessPhone)),
      email: clean(await getString(SettingKeys.businessEmail)),
      taxId: clean(await getString(SettingKeys.businessTaxId)),
      footerNote: clean(await getString(SettingKeys.invoiceFooterNote)),
    );
  }

  // The named accessors `SettingsService` provides, so client code reads the
  // same way against either.

  Future<bool> get allowNegativeStock =>
      getBool(SettingKeys.allowNegativeStock);

  Future<int> get maxInvoiceDiscountBps =>
      getInt(SettingKeys.maxInvoiceDiscountBps, fallback: 1000);

  Future<int> get maxItemDiscountBps =>
      getInt(SettingKeys.maxItemDiscountBps, fallback: 1500);

  Future<String> get businessName async =>
      await getString(SettingKeys.businessName) ?? AppConstants.companyName;
}
