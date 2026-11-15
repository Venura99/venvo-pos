import 'package:flutter_test/flutter_test.dart';
import 'package:venvo_core/core/constants/app_constants.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/errors/failures.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/categories/domain/category_models.dart';
import 'package:venvo_core/features/inventory/data/stock_count_repository.dart';
import 'package:venvo_core/features/products/domain/product_models.dart';

import '../helpers/master_data_fixtures.dart';

void main() {
  late MasterDataFixture fixture;
  late StockCountRepository counts;
  late int warehouseId;
  late int chargerId;
  late int cableId;

  setUp(() async {
    fixture = await MasterDataFixture.create();
    counts = StockCountRepository(
      database: fixture.db,
      clock: fixture.harness.clock,
      audit: fixture.harness.bootstrap.audit,
      sequences: fixture.harness.bootstrap.sequences,
      ledger: fixture.stockLedger,
    );

    final categoryId = await fixture.categories.create(
      fixture.admin,
      const CategoryDraft(name: 'Accessories'),
    );
    chargerId = await fixture.products.create(
      fixture.admin,
      ProductDraft(
        sku: 'CHG-25W',
        name: '25W Charger',
        categoryId: categoryId,
        costPrice: Money.fromMajor(2000),
      ),
    );
    cableId = await fixture.products.create(
      fixture.admin,
      ProductDraft(
        sku: 'CBL-C',
        name: 'Type-C Cable',
        categoryId: categoryId,
        costPrice: Money.fromMajor(400),
      ),
    );

    warehouseId = (await fixture.locations.mainWarehouse()).id;
    await fixture.postOpeningStock(
      locationId: warehouseId,
      productId: chargerId,
      quantity: 100,
      unitCost: Money.fromMajor(2000),
    );
    await fixture.postOpeningStock(
      locationId: warehouseId,
      productId: cableId,
      quantity: 50,
      unitCost: Money.fromMajor(400),
    );
  });

  tearDown(() => fixture.dispose());

  Future<int> balanceAt(int productId) => fixture.stockLedger.balanceOf(
    locationId: warehouseId,
    productId: productId,
  );

  group('opening a count', () {
    test('captures the system quantities as they are now', () async {
      final countId = await counts.createCount(
        fixture.admin,
        locationId: warehouseId,
      );
      final sheet = await counts.loadCount(countId);

      expect(sheet.documentNumber, startsWith('REC-'));
      expect(sheet.status, StockDocumentStatus.draft);
      expect(sheet.lines.length, 2);
      expect(
        sheet.lines
            .firstWhere((line) => line.productId == chargerId)
            .systemQuantity,
        100,
      );
      expect(sheet.countedLineCount, 0);
      expect(sheet.hasVariances, isFalse);
    });

    test(
      'a movement after the sheet opens does not change the variance',
      () async {
        // This is why the quantities are snapshotted: a transfer posted while
        // the counter is walking the shelves must not silently alter what the
        // count is compared against.
        final countId = await counts.createCount(
          fixture.admin,
          locationId: warehouseId,
        );

        await fixture.postOpeningStock(
          locationId: warehouseId,
          productId: chargerId,
          quantity: 20,
        );

        final sheet = await counts.loadCount(countId);
        expect(
          sheet.lines
              .firstWhere((line) => line.productId == chargerId)
              .systemQuantity,
          100,
        );
        expect(await balanceAt(chargerId), 120);
      },
    );

    test('excludes products with no stock unless asked', () async {
      final emptyProduct = await fixture.products.create(
        fixture.admin,
        ProductDraft(
          sku: 'PWB-10K',
          name: 'Power Bank',
          categoryId:
              (await fixture.categories.selectableCategories()).first.id,
        ),
      );

      final lean = await counts.createCount(
        fixture.admin,
        locationId: warehouseId,
      );
      expect(
        (await counts.loadCount(lean)).lines.map((line) => line.productId),
        isNot(contains(emptyProduct)),
      );
      await counts.discardCount(fixture.admin, lean);

      final full = await counts.createCount(
        fixture.admin,
        locationId: warehouseId,
        includeZeroStock: true,
      );
      expect(
        (await counts.loadCount(full)).lines.map((line) => line.productId),
        contains(emptyProduct),
      );
    });

    test('refuses a second open count for the same location', () async {
      await counts.createCount(fixture.admin, locationId: warehouseId);
      await expectLater(
        counts.createCount(fixture.admin, locationId: warehouseId),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'count.one_open_per_location',
          ),
        ),
      );
    });

    test('refuses to count a virtual counterparty', () async {
      final supplier = await fixture.locations.byCode(
        AppConstants.supplierLocationCode,
      );
      await expectLater(
        counts.createCount(fixture.admin, locationId: supplier.id),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'count.real_location_only',
          ),
        ),
      );
    });

    test('requires the reconcile permission', () async {
      final viewer = await fixture.createViewer();
      await expectLater(
        counts.createCount(viewer, locationId: warehouseId),
        throwsA(isA<PermissionFailure>()),
      );
    });
  });

  group('recording what was found', () {
    test('saves counted quantities and computes variances', () async {
      final countId = await counts.createCount(
        fixture.admin,
        locationId: warehouseId,
      );

      await counts.saveCountedQuantities(
        fixture.admin,
        countId: countId,
        countedByProductId: {chargerId: 97, cableId: 53},
      );

      final sheet = await counts.loadCount(countId);
      expect(sheet.countedLineCount, 2);

      final charger = sheet.lines.firstWhere(
        (line) => line.productId == chargerId,
      );
      expect(charger.countedQuantity, 97);
      expect(charger.variance, -3);
      expect(charger.hasVariance, isTrue);

      final cable = sheet.lines.firstWhere((line) => line.productId == cableId);
      expect(cable.variance, 3);

      expect(sheet.shortageUnits, 3);
      expect(sheet.surplusUnits, 3);
    });

    test('a count matching the system is not a variance', () async {
      final countId = await counts.createCount(
        fixture.admin,
        locationId: warehouseId,
      );
      await counts.saveCountedQuantities(
        fixture.admin,
        countId: countId,
        countedByProductId: {chargerId: 100},
      );

      final sheet = await counts.loadCount(countId);
      expect(sheet.countedLineCount, 1);
      expect(sheet.hasVariances, isFalse);
    });

    test('a blank count clears it again', () async {
      final countId = await counts.createCount(
        fixture.admin,
        locationId: warehouseId,
      );
      await counts.saveCountedQuantities(
        fixture.admin,
        countId: countId,
        countedByProductId: {chargerId: 97},
      );
      await counts.saveCountedQuantities(
        fixture.admin,
        countId: countId,
        countedByProductId: {chargerId: null},
      );

      final sheet = await counts.loadCount(countId);
      expect(sheet.countedLineCount, 0);
    });

    test('refuses a negative counted quantity', () async {
      final countId = await counts.createCount(
        fixture.admin,
        locationId: warehouseId,
      );
      await expectLater(
        counts.saveCountedQuantities(
          fixture.admin,
          countId: countId,
          countedByProductId: {chargerId: -1},
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('values the variance at the carrying cost', () async {
      final countId = await counts.createCount(
        fixture.admin,
        locationId: warehouseId,
      );
      await counts.saveCountedQuantities(
        fixture.admin,
        countId: countId,
        // 3 chargers short at 2,000 and 5 cables over at 400:
        // -6,000 + 2,000 = -4,000
        countedByProductId: {chargerId: 97, cableId: 55},
      );

      expect(await counts.varianceValue(countId), Money.fromMajor(-4000));
    });
  });

  group('posting a count', () {
    test(
      'posts a surplus as an increase and a shortage as a decrease',
      () async {
        final countId = await counts.createCount(
          fixture.admin,
          locationId: warehouseId,
        );
        await counts.saveCountedQuantities(
          fixture.admin,
          countId: countId,
          countedByProductId: {chargerId: 97, cableId: 53},
        );

        final results = await counts.postCount(
          fixture.admin,
          countId: countId,
          reason: 'Monthly stock-take',
        );

        expect(results.length, 2);
        // Stock now matches what was counted.
        expect(await balanceAt(chargerId), 97);
        expect(await balanceAt(cableId), 53);

        final sheet = await counts.loadCount(countId);
        expect(sheet.status, StockDocumentStatus.posted);
        expect(sheet.increaseTransactionId, isNotNull);
        expect(sheet.decreaseTransactionId, isNotNull);

        // The ledger still balances, and the cache still agrees with it.
        expect(await fixture.stockLedger.findUnbalancedProducts(), isEmpty);
        expect(await fixture.stockLedger.findBalanceDiscrepancies(), isEmpty);
      },
    );

    test('posts only one document when the variance is one-way', () async {
      final countId = await counts.createCount(
        fixture.admin,
        locationId: warehouseId,
      );
      await counts.saveCountedQuantities(
        fixture.admin,
        countId: countId,
        countedByProductId: {chargerId: 95},
      );

      final results = await counts.postCount(fixture.admin, countId: countId);
      expect(results.length, 1);
      expect(await balanceAt(chargerId), 95);

      final sheet = await counts.loadCount(countId);
      expect(sheet.increaseTransactionId, isNull);
      expect(sheet.decreaseTransactionId, isNotNull);
    });

    test('a count with no variance posts nothing and closes', () async {
      final countId = await counts.createCount(
        fixture.admin,
        locationId: warehouseId,
      );
      await counts.saveCountedQuantities(
        fixture.admin,
        countId: countId,
        countedByProductId: {chargerId: 100, cableId: 50},
      );

      final results = await counts.postCount(fixture.admin, countId: countId);
      expect(results, isEmpty);

      final sheet = await counts.loadCount(countId);
      expect(sheet.status, StockDocumentStatus.posted);
      expect(sheet.increaseTransactionId, isNull);
      expect(sheet.decreaseTransactionId, isNull);
      // Nothing moved.
      expect(await balanceAt(chargerId), 100);
    });

    test('an uncounted line is left alone', () async {
      final countId = await counts.createCount(
        fixture.admin,
        locationId: warehouseId,
      );
      // Only the chargers were counted.
      await counts.saveCountedQuantities(
        fixture.admin,
        countId: countId,
        countedByProductId: {chargerId: 90},
      );
      await counts.postCount(fixture.admin, countId: countId);

      expect(await balanceAt(chargerId), 90);
      // The cables were never counted, so their balance is untouched rather
      // than being written down to zero.
      expect(await balanceAt(cableId), 50);
    });

    test('refuses to post a count with nothing entered', () async {
      final countId = await counts.createCount(
        fixture.admin,
        locationId: warehouseId,
      );
      await expectLater(
        counts.postCount(fixture.admin, countId: countId),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'count.needs_counts',
          ),
        ),
      );
    });

    test('refuses to post the same count twice', () async {
      final countId = await counts.createCount(
        fixture.admin,
        locationId: warehouseId,
      );
      await counts.saveCountedQuantities(
        fixture.admin,
        countId: countId,
        countedByProductId: {chargerId: 99},
      );
      await counts.postCount(fixture.admin, countId: countId);

      await expectLater(
        counts.postCount(fixture.admin, countId: countId),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'count.draft_only',
          ),
        ),
      );
    });

    test('a posted sheet can no longer be edited', () async {
      final countId = await counts.createCount(
        fixture.admin,
        locationId: warehouseId,
      );
      await counts.saveCountedQuantities(
        fixture.admin,
        countId: countId,
        countedByProductId: {chargerId: 99},
      );
      await counts.postCount(fixture.admin, countId: countId);

      await expectLater(
        counts.saveCountedQuantities(
          fixture.admin,
          countId: countId,
          countedByProductId: {chargerId: 50},
        ),
        throwsA(isA<BusinessRuleFailure>()),
      );
    });

    test('the adjustment documents reference the count', () async {
      final countId = await counts.createCount(
        fixture.admin,
        locationId: warehouseId,
      );
      final sheet = await counts.loadCount(countId);
      await counts.saveCountedQuantities(
        fixture.admin,
        countId: countId,
        countedByProductId: {chargerId: 95},
      );
      final results = await counts.postCount(fixture.admin, countId: countId);

      final document = await (fixture.db.select(
        fixture.db.stockTransactions,
      )..where((t) => t.id.equals(results.single.transactionId))).getSingle();
      expect(document.referenceNote, sheet.documentNumber);
      expect(document.documentType, StockDocumentType.adjustmentDecrease);
    });

    test('records the outcome in the audit log', () async {
      final countId = await counts.createCount(
        fixture.admin,
        locationId: warehouseId,
      );
      await counts.saveCountedQuantities(
        fixture.admin,
        countId: countId,
        countedByProductId: {chargerId: 97, cableId: 53},
      );
      await counts.postCount(
        fixture.admin,
        countId: countId,
        reason: 'Monthly stock-take',
      );

      final entries = await fixture.auditEntries();
      final posted = entries.firstWhere(
        (entry) =>
            entry.action == AuditAction.post &&
            entry.summary.contains('stock count'),
      );
      expect(posted.summary, contains('1 surplus'));
      expect(posted.summary, contains('1 shortage'));
      expect(posted.afterJson, contains('Monthly stock-take'));
    });

    test('requires the reconcile permission', () async {
      final countId = await counts.createCount(
        fixture.admin,
        locationId: warehouseId,
      );
      await counts.saveCountedQuantities(
        fixture.admin,
        countId: countId,
        countedByProductId: {chargerId: 99},
      );

      final viewer = await fixture.createViewer();
      await expectLater(
        counts.postCount(viewer, countId: countId),
        throwsA(isA<PermissionFailure>()),
      );
    });
  });

  group('discarding a count', () {
    test('removes an unposted sheet', () async {
      final countId = await counts.createCount(
        fixture.admin,
        locationId: warehouseId,
      );
      await counts.discardCount(fixture.admin, countId);

      expect(await counts.watchCounts().first, isEmpty);
      // Nothing it recorded ever touched stock.
      expect(await balanceAt(chargerId), 100);
    });

    test('refuses to discard a posted sheet', () async {
      final countId = await counts.createCount(
        fixture.admin,
        locationId: warehouseId,
      );
      await counts.saveCountedQuantities(
        fixture.admin,
        countId: countId,
        countedByProductId: {chargerId: 99},
      );
      await counts.postCount(fixture.admin, countId: countId);

      await expectLater(
        counts.discardCount(fixture.admin, countId),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'count.draft_only',
          ),
        ),
      );
    });
  });
}
