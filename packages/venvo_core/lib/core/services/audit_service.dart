import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../enums/app_enums.dart';
import 'clock.dart';

/// Writes the append-only audit trail.
///
/// Called from inside the same transaction as the operation being recorded, so
/// a rolled-back document leaves no audit row claiming it happened.
class AuditService {
  AuditService(this._db, this._clock);

  final AppDatabase _db;
  final Clock _clock;

  String? _hostName;

  String get hostName => _hostName ??= Platform.localHostname;

  Future<int> record({
    required AuditAction action,
    required String summary,
    int? userId,
    String? username,
    EntityKind? entityKind,
    int? entityId,
    Map<String, Object?>? before,
    Map<String, Object?>? after,
  }) {
    return _db
        .into(_db.auditLogs)
        .insert(
          AuditLogsCompanion.insert(
            occurredAt: _clock.nowUtc(),
            userId: Value(userId),
            username: Value(username),
            action: action,
            entityKind: Value(entityKind),
            entityId: Value(entityId),
            summary: summary.length > 500 ? summary.substring(0, 500) : summary,
            beforeJson: Value(_encode(before)),
            afterJson: Value(_encode(after)),
            hostName: Value(hostName),
          ),
        );
  }

  /// Convenience for the common "field X changed from A to B" case, keeping
  /// only the keys that actually differ so the trail stays readable.
  Future<int> recordUpdate({
    required EntityKind entityKind,
    required int entityId,
    required String summary,
    required Map<String, Object?> before,
    required Map<String, Object?> after,
    int? userId,
    String? username,
  }) {
    final changedBefore = <String, Object?>{};
    final changedAfter = <String, Object?>{};
    for (final key in {...before.keys, ...after.keys}) {
      if (before[key] != after[key]) {
        changedBefore[key] = before[key];
        changedAfter[key] = after[key];
      }
    }
    return record(
      action: AuditAction.update,
      summary: summary,
      userId: userId,
      username: username,
      entityKind: entityKind,
      entityId: entityId,
      before: changedBefore,
      after: changedAfter,
    );
  }

  static String? _encode(Map<String, Object?>? value) {
    if (value == null || value.isEmpty) return null;
    return jsonEncode(
      value,
      toEncodable: (object) {
        if (object is DateTime) return object.toUtc().toIso8601String();
        return object.toString();
      },
    );
  }
}
