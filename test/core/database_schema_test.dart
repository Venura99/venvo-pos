import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;
import 'package:venvo_core/core/constants/app_constants.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/database/app_database.dart';
import 'package:venvo_core/core/database/database_seeder.dart';
import 'package:venvo_core/core/enums/app_enums.dart';

import '../helpers/test_harness.dart';

void main() {
  late TestHarness harness;

  setUp(() async {
    harness = await TestHarness.create();
  });

  tearDown(() => harness.dispose());

  group('schema', () {
    test(
      'creates at the declared version and passes integrity checks',
      () async {
        expect(harness.db.schemaVersion, 4);
        // Throws if either PRAGMA reports a problem.
        await harness.db.verifyIntegrity();
      },
    );

    test('enforces foreign keys on the connection', () async {
      final pragma = await harness.db
          .customSelect('PRAGMA foreign_keys')
          .getSingle();
      expect(pragma.data.values.first, 1);
    });

    test('every declared foreign key survives code generation', () async {
      // This exists because the schema once lost all of them at once.
      //
      // drift_dev cannot resolve the table class in
      // `integer().references(Users, #id)` when it runs against an analyzer
      // newer than it supports. It does not fail the build — it emits a
      // warning and generates the column with no foreign key. Regenerating
      // after moving the code into its own package took every constraint out
      // of the database, and the only thing that noticed was one insert test
      // further down this file.
      //
      // So this counts what SQLite is actually enforcing. It reads
      // `foreign_key_list`, not the Dart source, because the source was
      // correct the whole time — it was the generated schema that was wrong.
      final tables = await harness.db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name NOT LIKE 'sqlite_%'",
          )
          .get();

      var total = 0;
      final withNone = <String>[];
      for (final row in tables) {
        final table = row.read<String>('name');
        final keys = await harness.db
            .customSelect('PRAGMA foreign_key_list("$table")')
            .get();
        if (keys.isEmpty) withNone.add(table);
        total += keys.length;
      }

      // 108 is the number of `.references()` declarations in
      // lib/core/database/tables/, which is the number SQLite should be
      // enforcing. The seven tables that declare none are root entities.
      expect(
        total,
        108,
        reason:
            'Found $total foreign keys across ${tables.length} tables. '
            'Tables declaring none: ${withNone.join(', ')}. '
            'If this is 0, code generation dropped them: check the analyzer '
            'version pinned in packages/venvo_core/pubspec.yaml. If it is '
            'merely different, a table was added or changed and this number '
            'should be updated deliberately.',
      );
    });

    test('refuses a row whose foreign key does not resolve', () async {
      // A product must belong to a category that exists.
      await expectLater(
        harness.db
            .into(harness.db.products)
            .insert(
              ProductsCompanion.insert(
                sku: 'ORPHAN-1',
                name: 'Orphan product',
                categoryId: 9999,
                createdAt: harness.clock.nowUtc(),
                updatedAt: harness.clock.nowUtc(),
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('enforces the unique constraint on product SKU', () async {
      final categoryId = await _insertCategory(harness);
      await _insertProduct(harness, categoryId, 'CHG-25W');

      await expectLater(
        _insertProduct(harness, categoryId, 'CHG-25W'),
        throwsA(isA<SqliteException>()),
      );
    });

    test(
      'allows many products without a barcode despite the unique index',
      () async {
        // A nullable unique column must not force the first null to be the only
        // one, or every product without a barcode would collide.
        final categoryId = await _insertCategory(harness);
        await _insertProduct(harness, categoryId, 'CHG-25W');
        await _insertProduct(harness, categoryId, 'CHG-66W');
        await _insertProduct(harness, categoryId, 'CBL-TYPEC');

        final count = await harness.db
            .customSelect('SELECT COUNT(*) AS c FROM products')
            .getSingle();
        expect(count.data['c'], 3);
      },
    );

    test('rejects a zero quantity on a stock ledger entry', () async {
      // The ledger is a double-entry record; a zero delta would be a row that
      // claims a movement happened without moving anything.
      final categoryId = await _insertCategory(harness);
      final productId = await _insertProduct(harness, categoryId, 'CHG-25W');
      final userId = await _insertUser(harness);
      final locations = await harness.db
          .select(harness.db.inventoryLocations)
          .get();
      final warehouse = locations.firstWhere(
        (l) => l.code == AppConstants.mainWarehouseCode,
      );
      final transactionId = await _insertStockTransaction(
        harness,
        userId: userId,
        sourceLocationId: locations
            .firstWhere((l) => l.kind == LocationKind.supplier)
            .id,
        destinationLocationId: warehouse.id,
      );

      await expectLater(
        harness.db
            .into(harness.db.stockLedgerEntries)
            .insert(
              StockLedgerEntriesCompanion.insert(
                transactionId: transactionId,
                locationId: warehouse.id,
                productId: productId,
                quantityDelta: 0,
                balanceAfter: 0,
                entryType: StockDocumentType.purchaseIn,
                occurredAt: harness.clock.nowUtc(),
                recordedAt: harness.clock.nowUtc(),
                recordedByUserId: userId,
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('rejects a non-positive quantity on a document line', () async {
      final categoryId = await _insertCategory(harness);
      final productId = await _insertProduct(harness, categoryId, 'CHG-25W');
      final userId = await _insertUser(harness);
      final locations = await harness.db
          .select(harness.db.inventoryLocations)
          .get();
      final transactionId = await _insertStockTransaction(
        harness,
        userId: userId,
        sourceLocationId: locations
            .firstWhere((l) => l.kind == LocationKind.supplier)
            .id,
        destinationLocationId: locations
            .firstWhere((l) => l.code == AppConstants.mainWarehouseCode)
            .id,
      );

      await expectLater(
        harness.db
            .into(harness.db.stockTransactionItems)
            .insert(
              StockTransactionItemsCompanion.insert(
                transactionId: transactionId,
                lineNumber: 1,
                productId: productId,
                productNameSnapshot: '25W Charger',
                skuSnapshot: 'CHG-25W',
                quantity: 0,
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('stores enums by name, so reordering a Dart enum is safe', () async {
      final row = await harness.db
          .customSelect(
            'SELECT kind FROM inventory_locations WHERE code = ?',
            variables: const [Variable<String>(AppConstants.mainWarehouseCode)],
          )
          .getSingle();
      expect(row.data['kind'], 'warehouse');
    });

    test('stores dates as ISO-8601 UTC text', () async {
      final row = await harness.db
          .customSelect('SELECT updated_at FROM settings LIMIT 1')
          .getSingle();
      final value = row.data['updated_at'] as String;
      expect(value, endsWith('Z'));
      expect(DateTime.parse(value).isUtc, isTrue);
    });
  });

  group('seed', () {
    test('creates every permission exactly once', () async {
      final permissions = await harness.db
          .select(harness.db.permissionDefs)
          .get();
      expect(permissions.length, Permissions.all.length);
      expect(permissions.map((p) => p.key).toSet(), Permissions.all.toSet());
    });

    test('gives the administrator role every permission', () async {
      final adminRole = await (harness.db.select(
        harness.db.roles,
      )..where((r) => r.code.equals(RoleCodes.administrator))).getSingle();
      final grants = await (harness.db.select(
        harness.db.rolePermissions,
      )..where((rp) => rp.roleId.equals(adminRole.id))).get();
      expect(grants.length, Permissions.all.length);
    });

    test(
      'grants each non-admin role only its documented permissions',
      () async {
        for (final entry in RoleCodes.defaultGrants.entries) {
          final role = await (harness.db.select(
            harness.db.roles,
          )..where((r) => r.code.equals(entry.key))).getSingle();
          final grantRows = await (harness.db.select(
            harness.db.rolePermissions,
          )..where((rp) => rp.roleId.equals(role.id))).get();
          expect(
            grantRows.length,
            entry.value.length,
            reason:
                'role ${entry.key} should hold ${entry.value.length} grants',
          );
        }
      },
    );

    test('never grants a dangerous permission to a non-admin role', () async {
      // Overriding negative stock, exceeding discount limits and restoring a
      // backup are administrator-only by design.
      const restricted = [
        Permissions.stockNegativeOverride,
        Permissions.discountExceedLimit,
        Permissions.backupRestore,
        Permissions.usersManage,
      ];
      for (final grants in RoleCodes.defaultGrants.values) {
        for (final permission in restricted) {
          expect(grants.contains(permission), isFalse);
        }
      }
    });

    test(
      'creates the warehouse and all virtual counterparty locations',
      () async {
        final locations = await harness.db
            .select(harness.db.inventoryLocations)
            .get();
        final kinds = locations.map((l) => l.kind).toSet();

        expect(
          kinds,
          containsAll(<LocationKind>[
            LocationKind.warehouse,
            LocationKind.damaged,
            LocationKind.supplier,
            LocationKind.customer,
            LocationKind.adjustment,
            LocationKind.inTransit,
          ]),
        );
        expect(
          locations
              .where((l) => l.code == AppConstants.mainWarehouseCode)
              .length,
          1,
        );
      },
    );

    test('creates the chart of accounts and expense categories', () async {
      final accounts = await harness.db.select(harness.db.accounts).get();
      expect(accounts.length, greaterThanOrEqualTo(19));
      expect(accounts.every((a) => a.isSystem), isTrue);
      expect(
        accounts.map((a) => a.code),
        contains(AccountCodes.chequesInClearing),
      );

      final categories = await harness.db
          .select(harness.db.expenseCategories)
          .get();
      expect(categories.length, 9);
      // "Other" is the fallback and must not be removable.
      expect(categories.firstWhere((c) => c.code == 'OTHER').isSystem, isTrue);
    });

    test('sets the safe defaults for the operating policies', () async {
      final settings = harness.bootstrap.settings;
      // Negative stock must be refused unless explicitly turned on.
      expect(await settings.allowNegativeStock, isFalse);
      expect(await settings.maxInvoiceDiscountBps, 1000);
      expect(await settings.maxItemDiscountBps, 1500);
    });

    test('creates no user, so there is no default password anywhere', () async {
      final users = await harness.db.select(harness.db.users).get();
      expect(users, isEmpty);
      expect(harness.bootstrap.needsFirstRunSetup, isTrue);
    });

    test('is idempotent: running it again changes nothing', () async {
      Future<Map<String, int>> counts() async {
        Future<int> count(String table) async {
          final row = await harness.db
              .customSelect('SELECT COUNT(*) AS c FROM $table')
              .getSingle();
          return row.data['c'] as int;
        }

        return {
          'permissions': await count('permissions'),
          'roles': await count('roles'),
          'role_permissions': await count('role_permissions'),
          'inventory_locations': await count('inventory_locations'),
          'accounts': await count('accounts'),
          'expense_categories': await count('expense_categories'),
          'settings': await count('settings'),
        };
      }

      final before = await counts();
      await DatabaseSeeder(harness.db, harness.clock).run();
      await DatabaseSeeder(harness.db, harness.clock).run();
      expect(await counts(), before);
    });
  });
}

Future<int> _insertCategory(TestHarness harness, [String name = 'Chargers']) {
  return harness.db
      .into(harness.db.categories)
      .insert(
        CategoriesCompanion.insert(
          name: name,
          createdAt: harness.clock.nowUtc(),
          updatedAt: harness.clock.nowUtc(),
        ),
      );
}

Future<int> _insertProduct(TestHarness harness, int categoryId, String sku) {
  return harness.db
      .into(harness.db.products)
      .insert(
        ProductsCompanion.insert(
          sku: sku,
          name: sku,
          categoryId: categoryId,
          createdAt: harness.clock.nowUtc(),
          updatedAt: harness.clock.nowUtc(),
        ),
      );
}

Future<int> _insertUser(TestHarness harness) {
  return harness.db
      .into(harness.db.users)
      .insert(
        UsersCompanion.insert(
          username: 'tester',
          fullName: 'Test User',
          passwordHash: 'x',
          passwordSalt: 'y',
          passwordIterations: 1,
          createdAt: harness.clock.nowUtc(),
          updatedAt: harness.clock.nowUtc(),
        ),
      );
}

Future<int> _insertStockTransaction(
  TestHarness harness, {
  required int userId,
  required int sourceLocationId,
  required int destinationLocationId,
}) {
  return harness.db
      .into(harness.db.stockTransactions)
      .insert(
        StockTransactionsCompanion.insert(
          documentNumber: 'TEST-00001',
          documentType: StockDocumentType.purchaseIn,
          documentDate: harness.clock.nowUtc(),
          sourceLocationId: sourceLocationId,
          destinationLocationId: destinationLocationId,
          createdByUserId: userId,
          createdAt: harness.clock.nowUtc(),
        ),
      );
}
