import 'package:drift/drift.dart';

import '../constants/app_constants.dart';
import '../enums/app_enums.dart';
import 'tables/finance_tables.dart';
import 'tables/inventory_tables.dart';
import 'tables/master_tables.dart';
import 'tables/payment_tables.dart';
import 'tables/returns_tables.dart';
import 'tables/sales_tables.dart';
import 'tables/system_tables.dart';

export 'tables/finance_tables.dart';
export 'tables/inventory_tables.dart';
export 'tables/master_tables.dart';
export 'tables/payment_tables.dart';
export 'tables/returns_tables.dart';
export 'tables/sales_tables.dart';
export 'tables/system_tables.dart';

part 'app_database.g.dart';

/// The single Drift database for the application.
///
/// Tables are listed in dependency order so that `createAll` and any future
/// schema dump are readable top to bottom.
///
/// Two invariants are enforced at the connection level in [migration]:
/// foreign keys are switched on for every connection, and the schema version
/// is bumped only through an explicit, tested step in [_upgrade].
@DriftDatabase(
  tables: [
    // System and security
    Users,
    Roles,
    PermissionDefs,
    RolePermissions,
    UserRoles,
    Settings,
    DocumentSequences,
    AuditLogs,
    Attachments,
    BackupRecords,
    UserSessions,
    // Master data
    Categories,
    Agents,
    Shops,
    Employees,
    Products,
    InventoryLocations,
    // Inventory
    StockTransactions,
    StockTransactionItems,
    StockLedgerEntries,
    StockBalances,
    StockCounts,
    StockCountItems,
    // Billing
    Invoices,
    InvoiceItems,
    DiscountRecords,
    // Payments
    Payments,
    PaymentAllocations,
    Cheques,
    ChequeReminders,
    // Returns
    ReturnDocuments,
    ReturnItems,
    CreditNotes,
    CreditNoteApplications,
    // Finance
    Accounts,
    FinancialLedgerEntries,
    ExpenseCategories,
    Expenses,
    PettyCashEntries,
    EmployeeAdvances,
    Salaries,
    SalaryPayments,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// Bump this for every shipped schema change and add the matching branch to
  /// [_upgrade]. Never edit an existing branch once it has shipped.
  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
    },
    onUpgrade: _upgrade,
    beforeOpen: (details) async {
      // Per-connection and therefore not part of the file's pragmas.
      await customStatement('PRAGMA foreign_keys = ON');

      // Drift migrates forward but does not refuse a file written by a newer
      // release, which would then be read with the wrong column
      // expectations - silently, and against live business data. Refuse it.
      final previousVersion = details.versionBefore;
      if (previousVersion != null && previousVersion > details.versionNow) {
        throw StateError(
          'This database was created by a newer version of ${AppConstants.appName} '
          '(database schema v$previousVersion, this build supports '
          'v${details.versionNow}). Install the newer version, or restore a '
          'backup taken with this one. The file has not been modified.',
        );
      }

      if (details.wasCreated || details.hadUpgrade) {
        // A fresh or just-migrated file is checked before any business data
        // is written to it.
        await _assertIntegrity();
      }
    },
  );

  /// Applies schema changes one version at a time.
  ///
  /// Every shipped schema change adds a branch here and bumps
  /// [schemaVersion]. Branches are append-only: editing one that has already
  /// shipped would leave existing installations in a state no code expects.
  ///
  /// Foreign keys are switched off for the duration because SQLite rejects the
  /// intermediate states of a table rebuild, and switched back on before the
  /// database is handed to the application.
  Future<void> _upgrade(Migrator migrator, int from, int to) async {
    await customStatement('PRAGMA foreign_keys = OFF');
    try {
      for (var version = from; version < to; version++) {
        await _upgradeStep(migrator, version);
      }
    } finally {
      await customStatement('PRAGMA foreign_keys = ON');
    }
  }

  Future<void> _upgradeStep(Migrator migrator, int fromVersion) async {
    // v1 -> v2: three composite indexes.
    //
    // The stock movement history and the invoice register both read "this
    // one thing, newest first". With separate indexes on the key and on the
    // date, SQLite used one for the filter and then sorted the result in a
    // temporary B-tree - fine on a demonstration database, a full sort of
    // the table on a real one. These are walked in order instead.
    //
    // Found by the query-plan checks in `test/core/performance_test.dart`,
    // which is what they are for.
    if (fromVersion == 1) {
      await migrator.createIndex(idxLedgerProductOccurred);
      await migrator.createIndex(idxInvoicesShopDate);
      await migrator.createIndex(idxInvoicesAgentDate);
      return;
    }

    // v2 -> v3: user_sessions, for the cloud build's bearer tokens.
    //
    // Additive and safe on a database in use: a brand new table that nothing
    // existing references, so there is no table rebuild and no risk to a
    // single row of business data. A desktop install that never talks to a
    // server simply leaves it empty.
    if (fromVersion == 2) {
      await migrator.createTable(userSessions);
      // Indexes are separate schema objects in drift and are *not* created
      // by createTable, so they are created here explicitly. The unique one
      // on token_hash is not an optimisation: it is what makes a token
      // lookup a single index probe, and what stops two sessions ever
      // sharing a token hash.
      await migrator.createIndex(idxSessionsToken);
      await migrator.createIndex(idxSessionsUser);
      await migrator.createIndex(idxSessionsExpires);
      return;
    }

    // v3 -> v4: cheque_reminders, the log of WhatsApp reminders sent about
    // cheques coming due. Additive: a new table nothing existing refers to.
    if (fromVersion == 3) {
      await migrator.createTable(chequeReminders);
      await migrator.createIndex(idxChequeRemindersCheque);
      return;
    }

    throw StateError(
      'No migration registered from schema version $fromVersion to '
      '${fromVersion + 1}. Add a step to AppDatabase._upgradeStep before '
      'shipping this schema change.',
    );
  }

  /// Runs SQLite's own consistency checks. Used after creation, after a
  /// migration and when validating a backup archive.
  Future<void> _assertIntegrity() async {
    final integrity = await customSelect('PRAGMA integrity_check').get();
    final firstRow = integrity.first.data.values.first;
    if (firstRow != 'ok') {
      throw StateError('SQLite integrity check failed: $firstRow');
    }
    final violations = await customSelect('PRAGMA foreign_key_check').get();
    if (violations.isNotEmpty) {
      throw StateError(
        'Foreign key violations found in database: ${violations.length} row(s)',
      );
    }
  }

  /// Public wrapper used by the backup module to validate a restored file.
  Future<void> verifyIntegrity() => _assertIntegrity();

  /// Runs [action] inside a single database transaction.
  ///
  /// Every multi-step stock or financial operation goes through here, which is
  /// what guarantees that a failure part way through leaves neither side of a
  /// transfer updated.
  Future<T> transactional<T>(Future<T> Function() action) =>
      transaction(action);
}

/// Drift type converter used where an enum list has to live in one column.
/// Declared here so table files stay free of converter boilerplate.
class EntityStatusConverter extends TypeConverter<EntityStatus, String> {
  const EntityStatusConverter();

  @override
  EntityStatus fromSql(String fromDb) => EntityStatus.values.byName(fromDb);

  @override
  String toSql(EntityStatus value) => value.name;
}
