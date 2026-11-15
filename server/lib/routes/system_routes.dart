// The full drift import, not a `show`: the audit search uses the `lower()`
// extension on a column expression, which a narrowed import does not bring in.
import 'package:drift/drift.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:venvo_core/core/constants/app_constants.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/database/app_database.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/errors/failures.dart';
import 'package:venvo_core/core/services/audit_service.dart';
import 'package:venvo_core/core/services/settings_service.dart';
import 'package:venvo_core/features/dashboard/data/dashboard_repository.dart';
import 'package:venvo_core/features/finance/data/financial_ledger_service.dart';
import 'package:venvo_core/features/finance/domain/finance_models.dart';

import '../auth/auth_middleware.dart';
import '../http/json_body.dart';
import '../http/query_params.dart';
import '../http/responses.dart';

/// How a setting is stored, so a value can be read back as the type the
/// business logic expects rather than as text.
enum _SettingType { text, integer, flag }

/// The settings a client may change, and nothing else.
///
/// An allow-list rather than a generic key/value door. `backup.last_auto_at`
/// and `system.seeded_version` are written by the machinery that owns them —
/// a client able to set the seeded version could convince the seeder it had
/// already run, on a database where it had not.
const Map<String, _SettingType> _writableSettings = {
  SettingKeys.businessName: _SettingType.text,
  SettingKeys.businessAddress: _SettingType.text,
  SettingKeys.businessPhone: _SettingType.text,
  SettingKeys.businessEmail: _SettingType.text,
  SettingKeys.businessTaxId: _SettingType.text,
  SettingKeys.invoiceFooterNote: _SettingType.text,
  SettingKeys.themeMode: _SettingType.text,
  SettingKeys.allowNegativeStock: _SettingType.flag,
  SettingKeys.lowStockOnlyActive: _SettingType.flag,
  SettingKeys.maxInvoiceDiscountBps: _SettingType.integer,
  SettingKeys.maxItemDiscountBps: _SettingType.integer,
  SettingKeys.autoBackupEnabled: _SettingType.flag,
  SettingKeys.autoBackupRetentionCount: _SettingType.integer,
  SettingKeys.whatsappAdminNumbers: _SettingType.text,
  SettingKeys.chequeReminderDaysBefore: _SettingType.integer,
};

/// Settings that can be read but not written here.
const Map<String, _SettingType> _readOnlySettings = {
  SettingKeys.lastAutoBackupAt: _SettingType.text,
  SettingKeys.seededVersion: _SettingType.text,
};

/// The dashboard, the journal listing, settings and the audit trail.
Router systemRoutes({
  required DashboardRepository dashboard,
  required FinancialLedgerService finance,
  required SettingsService settings,
  required AppDatabase database,
  required AuditService audit,
}) {
  final router = Router();

  /// The figures across the top of the dashboard.
  ///
  /// Every one is computed from the ledgers on this request. None of them is a
  /// stored total that somebody has to remember to update, which is why they
  /// cannot drift from the transactions underneath.
  router.get('/dashboard', (Request request) async {
    requirePermission(
      request,
      Permissions.reportsView,
      action: 'view the dashboard',
    );
    final snapshot = await dashboard.load();
    return Api.ok({'dashboard': snapshot.toJson()});
  });

  /// Journal entries, newest first.
  router.get('/finance/entries', (Request request) async {
    requirePermission(
      request,
      Permissions.financialLedgerView,
      action: 'view the financial ledger',
    );
    final query = QueryParams.of(request);
    final rows = await finance
        .watchEntries(
          FinancialLedgerFilter(
            search: query.string('search'),
            accountCode: query.optionalString('account'),
            sourceKind: query.has('sourceKind')
                ? query.enumValue(
                    'sourceKind',
                    EntityKind.values,
                    fallback: EntityKind.values.first,
                  )
                : null,
            from: query.optionalUtcDate('from'),
            to: query.optionalUtcDate('to'),
            limit: query.optionalInt('limit') ?? 300,
          ),
        )
        .first;
    return Api.ok({'entries': rows.map((r) => r.toJson()).toList()});
  });

  // ---- settings ----------------------------------------------------------

  /// Readable by any signed-in user: the business name and the discount
  /// ceilings are needed to render a screen, not just to administer one.
  router.get('/settings', (Request request) async {
    final values = <String, Object?>{};
    for (final entry in {..._writableSettings, ..._readOnlySettings}.entries) {
      values[entry.key] = switch (entry.value) {
        _SettingType.text => await settings.getString(entry.key),
        _SettingType.integer => await settings.getInt(entry.key),
        _SettingType.flag => await settings.getBool(entry.key),
      };
    }
    return Api.ok({
      'settings': values,
      'writable': _writableSettings.keys.toList(),
    });
  });

  router.put('/settings', (Request request) async {
    final user = request.session.user;
    user.require(Permissions.settingsManage, action: 'change settings');

    final body = await JsonBody.read(request);
    final changes = body.requireMap('settings');
    if (changes.isEmpty) {
      throw const ValidationFailure(
        'No settings were given to change.',
        field: 'settings',
      );
    }

    final applied = <String>[];
    for (final key in changes.keys) {
      final type = _writableSettings[key];
      if (type == null) {
        // Named explicitly rather than ignored: a client that thinks it
        // changed a setting and did not is worse than one told it cannot.
        throw ValidationFailure(
          _readOnlySettings.containsKey(key)
              ? '"$key" is maintained by the system and cannot be set here.'
              : '"$key" is not a setting that can be changed.',
          field: 'settings',
        );
      }
      final value = changes[key];
      switch (type) {
        case _SettingType.text:
          if (value is! String) {
            throw ValidationFailure('"$key" must be text.', field: key);
          }
          await settings.setString(key, value, updatedByUserId: user.id);
        case _SettingType.integer:
          if (value is! int) {
            throw ValidationFailure(
              '"$key" must be a whole number.',
              field: key,
            );
          }
          if (key == SettingKeys.chequeReminderDaysBefore &&
              (value < 0 || value > 30)) {
            throw ValidationFailure(
              'Remind between 0 and 30 days before the cheque date.',
              field: key,
            );
          }
          await settings.setInt(key, value, updatedByUserId: user.id);
        case _SettingType.flag:
          if (value is! bool) {
            throw ValidationFailure(
              '"$key" must be true or false.',
              field: key,
            );
          }
          await settings.setBool(key, value, updatedByUserId: user.id);
      }
      applied.add(key);
    }

    // The desktop build's settings screen wrote this audit entry itself. A
    // client cannot be relied on to, so it is written here, where the change
    // actually happens, and names what changed.
    await audit.record(
      action: AuditAction.update,
      summary: 'Updated application settings: ${applied.join(', ')}.',
      userId: user.id,
      username: user.username,
      entityKind: EntityKind.setting,
    );

    // The cached values are reloaded so the next read — and the next business
    // rule that consults a ceiling — sees what was just written.
    await settings.load();
    return Api.ok({'changed': applied});
  });

  // ---- audit trail -------------------------------------------------------

  /// The audit trail, newest first.
  ///
  /// Read-only by design, and there is deliberately no endpoint that writes or
  /// deletes an entry: the trail is written as a side effect of the operations
  /// being recorded, and a trail somebody can edit is not a trail.
  router.get('/audit', (Request request) async {
    requirePermission(
      request,
      Permissions.auditView,
      action: 'view the audit trail',
    );
    final query = QueryParams.of(request);
    final search = query.optionalString('search');
    final action = query.has('action')
        ? query.enumValue(
            'action',
            AuditAction.values,
            fallback: AuditAction.values.first,
          )
        : null;

    final statement = database.select(database.auditLogs)
      ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)])
      ..limit(query.optionalInt('limit') ?? 200);
    if (action != null) {
      statement.where((t) => t.action.equalsValue(action));
    }
    if (search != null) {
      final pattern = '%${search.toLowerCase()}%';
      statement.where(
        (t) =>
            t.summary.lower().like(pattern) | t.username.lower().like(pattern),
      );
    }
    final rows = await statement.get();
    return Api.ok({'entries': rows.map((r) => r.toJson()).toList()});
  });

  return router;
}
