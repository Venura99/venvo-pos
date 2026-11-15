import 'package:drift/drift.dart';

import '../constants/app_constants.dart';
import '../constants/permissions.dart';
import '../enums/app_enums.dart';
import '../services/clock.dart';
import 'app_database.dart';

/// Populates the system data a fresh database cannot work without:
/// permissions, roles, the inventory locations that make the ledger balance,
/// the chart of accounts, default expense categories and default settings.
///
/// Deliberately does **not** create a user. No password is hardcoded anywhere;
/// the first administrator is created by whoever installs the application,
/// through the first-run screen.
///
/// Every step is idempotent and the whole seed runs in one transaction, so it
/// is safe to call on every launch and safe to interrupt.
class DatabaseSeeder {
  const DatabaseSeeder(this._db, this._clock);

  final AppDatabase _db;
  final Clock _clock;

  Future<void> run() async {
    await _db.transaction(() async {
      await _seedPermissions();
      await _seedRoles();
      await _seedLocations();
      await _seedAccounts();
      await _seedExpenseCategories();
      await _seedDefaultSettings();
    });
  }

  /// True when no user exists yet, which is what the first-run screen keys on.
  Future<bool> needsFirstRunSetup() async {
    final count = await (_db.selectOnly(
      _db.users,
    )..addColumns([_db.users.id.count()])).getSingle();
    return (count.read(_db.users.id.count()) ?? 0) == 0;
  }

  // --- Permissions and roles ---------------------------------------------

  Future<void> _seedPermissions() async {
    final existing = await _db.select(_db.permissionDefs).get();
    final known = existing.map((row) => row.key).toSet();

    for (final key in Permissions.all) {
      if (known.contains(key)) continue;
      await _db
          .into(_db.permissionDefs)
          .insert(
            PermissionDefsCompanion.insert(
              key: key,
              module: key.split('.').first,
              description: Value(_describePermission(key)),
            ),
          );
    }
  }

  Future<void> _seedRoles() async {
    final roleNames = <String, String>{
      RoleCodes.administrator: 'Administrator',
      RoleCodes.manager: 'Manager',
      RoleCodes.storeKeeper: 'Store Keeper',
      RoleCodes.cashier: 'Cashier',
      RoleCodes.accountant: 'Accountant',
      RoleCodes.viewer: 'Viewer',
      RoleCodes.agent: 'Agent',
    };

    final permissionIds = <String, int>{
      for (final row in await _db.select(_db.permissionDefs).get())
        row.key: row.id,
    };

    for (final entry in roleNames.entries) {
      final code = entry.key;
      var role = await (_db.select(
        _db.roles,
      )..where((r) => r.code.equals(code))).getSingleOrNull();

      if (role == null) {
        final id = await _db
            .into(_db.roles)
            .insert(
              RolesCompanion.insert(
                code: code,
                name: entry.value,
                description: Value(_describeRole(code)),
                isSystem: const Value(true),
                createdAt: _clock.nowUtc(),
              ),
            );
        role = await (_db.select(
          _db.roles,
        )..where((r) => r.id.equals(id))).getSingle();
      }

      // The administrator always holds every permission, including ones added
      // by a later version of the application.
      final grants = code == RoleCodes.administrator
          ? Permissions.all
          : (RoleCodes.defaultGrants[code] ?? const <String>[]);

      final alreadyGranted =
          (await (_db.select(
                _db.rolePermissions,
              )..where((rp) => rp.roleId.equals(role!.id))).get())
              .map((rp) => rp.permissionId)
              .toSet();

      for (final key in grants) {
        final permissionId = permissionIds[key];
        if (permissionId == null || alreadyGranted.contains(permissionId)) {
          continue;
        }
        await _db
            .into(_db.rolePermissions)
            .insert(
              RolePermissionsCompanion.insert(
                roleId: role.id,
                permissionId: permissionId,
              ),
            );
      }
    }
  }

  // --- Inventory locations ------------------------------------------------

  /// Creates the main warehouse, the damaged/quarantine store and the four
  /// virtual counterparty locations. The virtual ones are what let every
  /// movement be a balanced pair of ledger entries.
  Future<void> _seedLocations() async {
    const seeds = <(String, String, LocationKind)>[
      (
        AppConstants.mainWarehouseCode,
        'Main Warehouse',
        LocationKind.warehouse,
      ),
      (
        AppConstants.damagedLocationCode,
        'Damaged / Quarantine Store',
        LocationKind.damaged,
      ),
      (AppConstants.supplierLocationCode, 'Suppliers', LocationKind.supplier),
      (
        AppConstants.customerLocationCode,
        'Retail Customers',
        LocationKind.customer,
      ),
      (
        AppConstants.adjustmentLocationCode,
        'Stock Adjustments',
        LocationKind.adjustment,
      ),
      (
        AppConstants.inTransitLocationCode,
        'Goods In Transit',
        LocationKind.inTransit,
      ),
    ];

    for (final (code, name, kind) in seeds) {
      final existing = await (_db.select(
        _db.inventoryLocations,
      )..where((l) => l.code.equals(code))).getSingleOrNull();
      if (existing != null) continue;

      await _db
          .into(_db.inventoryLocations)
          .insert(
            InventoryLocationsCompanion.insert(
              code: code,
              name: name,
              kind: kind,
              createdAt: _clock.nowUtc(),
            ),
          );
    }
  }

  // --- Chart of accounts --------------------------------------------------

  Future<void> _seedAccounts() async {
    const seeds = <(String, String, AccountType)>[
      (AccountCodes.cashOnHand, 'Cash on Hand', AccountType.asset),
      (AccountCodes.pettyCash, 'Petty Cash', AccountType.asset),
      (AccountCodes.bank, 'Bank', AccountType.asset),
      (
        AccountCodes.chequesInClearing,
        'Cheques in Clearing',
        AccountType.asset,
      ),
      (AccountCodes.receivableAgents, 'Receivable - Agents', AccountType.asset),
      (AccountCodes.receivableShops, 'Receivable - Shops', AccountType.asset),
      (
        AccountCodes.receivableRetail,
        'Receivable - Retail Customers',
        AccountType.asset,
      ),
      (
        AccountCodes.receivableEmployees,
        'Receivable - Employee Advances',
        AccountType.asset,
      ),
      (AccountCodes.inventory, 'Inventory', AccountType.asset),
      (
        AccountCodes.customerAdvances,
        'Customer Advances',
        AccountType.liability,
      ),
      (AccountCodes.salariesPayable, 'Salaries Payable', AccountType.liability),
      (
        AccountCodes.payableSuppliers,
        'Payable - Suppliers',
        AccountType.liability,
      ),
      (AccountCodes.ownersEquity, "Owner's Equity", AccountType.equity),
      (AccountCodes.salesRevenue, 'Sales Revenue', AccountType.income),
      (AccountCodes.salesDiscounts, 'Sales Discounts', AccountType.income),
      (AccountCodes.salesReturns, 'Sales Returns', AccountType.income),
      (AccountCodes.costOfGoodsSold, 'Cost of Goods Sold', AccountType.expense),
      (
        AccountCodes.operatingExpenses,
        'Operating Expenses',
        AccountType.expense,
      ),
      (AccountCodes.salaryExpense, 'Salary Expense', AccountType.expense),
      (AccountCodes.stockWriteOff, 'Stock Write-Off', AccountType.expense),
      (
        AccountCodes.chequeBounceCharges,
        'Cheque Bounce Charges',
        AccountType.expense,
      ),
    ];

    for (final (code, name, type) in seeds) {
      final existing = await (_db.select(
        _db.accounts,
      )..where((a) => a.code.equals(code))).getSingleOrNull();
      if (existing != null) continue;

      await _db
          .into(_db.accounts)
          .insert(
            AccountsCompanion.insert(
              code: code,
              name: name,
              type: type,
              isSystem: const Value(true),
              createdAt: _clock.nowUtc(),
            ),
          );
    }
  }

  Future<void> _seedExpenseCategories() async {
    final operating =
        await (_db.select(_db.accounts)
              ..where((a) => a.code.equals(AccountCodes.operatingExpenses)))
            .getSingleOrNull();

    const seeds = <(String, String)>[
      ('TRANSPORT', 'Transport'),
      ('FUEL', 'Fuel'),
      ('RENT', 'Warehouse Rent'),
      ('ELECTRICITY', 'Electricity'),
      ('INTERNET', 'Internet'),
      ('PACKAGING', 'Packaging'),
      ('MAINTENANCE', 'Maintenance'),
      ('OFFICE', 'Office Expenses'),
      ('OTHER', 'Other'),
    ];

    for (final (code, name) in seeds) {
      final existing = await (_db.select(
        _db.expenseCategories,
      )..where((c) => c.code.equals(code))).getSingleOrNull();
      if (existing != null) continue;

      await _db
          .into(_db.expenseCategories)
          .insert(
            ExpenseCategoriesCompanion.insert(
              code: code,
              name: name,
              accountId: Value(operating?.id),
              // "Other" cannot be removed: it is the fallback category.
              isSystem: Value(code == 'OTHER'),
              createdAt: _clock.nowUtc(),
            ),
          );
    }
  }

  // --- Default settings ---------------------------------------------------

  Future<void> _seedDefaultSettings() async {
    final defaults = <String, (String, String)>{
      SettingKeys.businessName: (AppConstants.companyName, 'string'),
      SettingKeys.businessAddress: ('', 'string'),
      SettingKeys.businessPhone: ('', 'string'),
      SettingKeys.businessEmail: ('', 'string'),
      SettingKeys.businessTaxId: ('', 'string'),
      SettingKeys.invoiceFooterNote: (
        'Goods once sold are only returnable under the agreed return policy.',
        'string',
      ),
      SettingKeys.themeMode: ('system', 'string'),
      // Negative stock is refused by default; an authorised user can still
      // override a single document and the override is recorded on it.
      SettingKeys.allowNegativeStock: ('false', 'bool'),
      SettingKeys.lowStockOnlyActive: ('true', 'bool'),
      // 10% and 15% ceilings, in basis points.
      SettingKeys.maxInvoiceDiscountBps: ('1000', 'int'),
      SettingKeys.maxItemDiscountBps: ('1500', 'int'),
      SettingKeys.autoBackupEnabled: ('true', 'bool'),
      SettingKeys.autoBackupRetentionCount: ('14', 'int'),
      SettingKeys.seededVersion: (AppConstants.appVersion, 'string'),
    };

    final existing = (await _db.select(_db.settings).get())
        .map((row) => row.key)
        .toSet();

    for (final entry in defaults.entries) {
      if (existing.contains(entry.key)) continue;
      final (value, valueType) = entry.value;
      await _db
          .into(_db.settings)
          .insert(
            SettingsCompanion.insert(
              key: entry.key,
              value: Value(value),
              valueType: Value(valueType),
              updatedAt: _clock.nowUtc(),
            ),
          );
    }
  }

  static String _describeRole(String code) => switch (code) {
    RoleCodes.administrator =>
      'Full access, including users, settings, backups and restores.',
    RoleCodes.manager =>
      'Day-to-day running of stock, billing, collections and reports.',
    RoleCodes.storeKeeper => 'Stock movements, transfers and goods inspection.',
    RoleCodes.cashier => 'Billing, retail sales and recording collections.',
    RoleCodes.accountant =>
      'Payments, cheques, expenses, salaries and financial reports.',
    RoleCodes.viewer => 'Read-only access to operational data and reports.',
    RoleCodes.agent =>
      'A sales agent in the field: sees shops and invoices, records '
          'collections and cheques with a photo of the cheque.',
    _ => '',
  };

  static String _describePermission(String key) {
    final parts = key.split('.');
    final module = parts.first.replaceAll('_', ' ');
    final action = parts.length > 1 ? parts[1].replaceAll('_', ' ') : '';
    return '${action.isEmpty ? 'Access' : _capitalise(action)} $module';
  }

  static String _capitalise(String value) =>
      value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);
}
