import 'package:drift/drift.dart';

import '../constants/app_constants.dart';
import '../database/app_database.dart';
import 'clock.dart';

/// Typed access to the key/value `settings` table, with an in-memory cache so
/// that rules consulted on every transaction (the negative-stock policy, the
/// discount ceilings) do not hit the database on each check.
class SettingsService {
  SettingsService(this._db, this._clock);

  final AppDatabase _db;
  final Clock _clock;
  final Map<String, String?> _cache = {};
  bool _loaded = false;

  Future<void> load() async {
    final rows = await _db.select(_db.settings).get();
    _cache
      ..clear()
      ..addEntries(rows.map((row) => MapEntry(row.key, row.value)));
    _loaded = true;
  }

  Future<void> _ensureLoaded() async {
    if (!_loaded) await load();
  }

  Future<String?> getString(String key, {String? fallback}) async {
    await _ensureLoaded();
    return _cache[key] ?? fallback;
  }

  Future<int> getInt(String key, {int fallback = 0}) async {
    final raw = await getString(key);
    return raw == null ? fallback : (int.tryParse(raw) ?? fallback);
  }

  Future<bool> getBool(String key, {bool fallback = false}) async {
    final raw = await getString(key);
    if (raw == null) return fallback;
    return raw == 'true' || raw == '1';
  }

  Future<DateTime?> getDateTime(String key) async {
    final raw = await getString(key);
    return raw == null ? null : DateTime.tryParse(raw)?.toUtc();
  }

  /// Reads a setting from the cache without awaiting. Returns [fallback] when
  /// the cache has not been loaded yet, so callers on a synchronous path (a
  /// widget build) always get a usable value.
  bool getBoolSync(String key, {bool fallback = false}) {
    final raw = _cache[key];
    if (raw == null) return fallback;
    return raw == 'true' || raw == '1';
  }

  int getIntSync(String key, {int fallback = 0}) {
    final raw = _cache[key];
    return raw == null ? fallback : (int.tryParse(raw) ?? fallback);
  }

  String? getStringSync(String key) => _cache[key];

  Future<void> setString(
    String key,
    String? value, {
    int? updatedByUserId,
    String valueType = 'string',
    String? description,
  }) async {
    final now = _clock.nowUtc();
    await _db
        .into(_db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: key,
            value: Value(value),
            valueType: Value(valueType),
            description: Value(description),
            updatedAt: now,
            updatedByUserId: Value(updatedByUserId),
          ),
        );
    _cache[key] = value;
  }

  Future<void> setInt(String key, int value, {int? updatedByUserId}) =>
      setString(
        key,
        value.toString(),
        valueType: 'int',
        updatedByUserId: updatedByUserId,
      );

  Future<void> setBool(String key, bool value, {int? updatedByUserId}) =>
      setString(
        key,
        value ? 'true' : 'false',
        valueType: 'bool',
        updatedByUserId: updatedByUserId,
      );

  Future<void> setDateTime(
    String key,
    DateTime value, {
    int? updatedByUserId,
  }) => setString(
    key,
    value.toUtc().toIso8601String(),
    valueType: 'datetime',
    updatedByUserId: updatedByUserId,
  );

  // --- Frequently consulted business policies -----------------------------

  /// When false (the default), no operation may drive a real location's stock
  /// below zero. An authorised user can still override a single document.
  Future<bool> get allowNegativeStock =>
      getBool(SettingKeys.allowNegativeStock);

  /// Largest invoice-level discount an ordinary user may grant, in basis
  /// points. 1000 means 10%.
  Future<int> get maxInvoiceDiscountBps =>
      getInt(SettingKeys.maxInvoiceDiscountBps, fallback: 1000);

  Future<int> get maxItemDiscountBps =>
      getInt(SettingKeys.maxItemDiscountBps, fallback: 1500);

  Future<String> get businessName async =>
      await getString(SettingKeys.businessName) ?? AppConstants.companyName;
}
