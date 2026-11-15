import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_test/flutter_test.dart';
import 'package:venvo_core/core/constants/app_constants.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/errors/failures.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/agents/domain/agent_models.dart';
import 'package:venvo_core/features/categories/domain/category_models.dart';
import 'package:venvo_core/features/inventory/domain/stock_models.dart';
import 'package:venvo_core/features/products/domain/product_models.dart';
import 'package:venvo_core/features/returns/domain/return_models.dart';
import 'package:venvo_core/features/shops/domain/shop_models.dart';

import '../helpers/master_data_fixtures.dart';

/// The acceptance scenarios from the brief, plus the invariants the ledger
/// exists to guarantee.
void main() {
  late MasterDataFixture fixture;

  // The brief's running example: 25W chargers moving warehouse -> agent ->
  // shop -> customer.
  late int chargerId;
  late int warehouseId;
  late int agentAId;
  late int agentALocationId;
  late int shopAId;
  late int shopALocationId;
  late int supplierId;
  late int customerId;
  late int damagedId;
  late int adjustmentId;
  late int inTransitId;

  setUp(() async {
    fixture = await MasterDataFixture.create();

    final categoryId = await fixture.categories.create(
      fixture.admin,
      const CategoryDraft(name: 'Chargers'),
    );
    chargerId = await fixture.products.create(
      fixture.admin,
      ProductDraft(
        sku: 'CHG-25W',
        name: '25W Charger',
        categoryId: categoryId,
        costPrice: Money.fromMajor(2000),
        wholesalePrice: Money.fromMajor(3000),
        retailPrice: Money.fromMajor(3500),
      ),
    );

    warehouseId = (await fixture.locations.mainWarehouse()).id;
    supplierId = (await fixture.locations.byCode(
      AppConstants.supplierLocationCode,
    )).id;
    customerId = (await fixture.locations.byCode(
      AppConstants.customerLocationCode,
    )).id;
    damagedId = (await fixture.locations.byCode(
      AppConstants.damagedLocationCode,
    )).id;
    adjustmentId = (await fixture.locations.byCode(
      AppConstants.adjustmentLocationCode,
    )).id;
    inTransitId = (await fixture.locations.byCode(
      AppConstants.inTransitLocationCode,
    )).id;

    agentAId = await fixture.agents.create(
      fixture.admin,
      const AgentDraft(name: 'Agent A'),
    );
    agentALocationId = (await fixture.locations.forAgent(agentAId))!.id;

    shopAId = await fixture.shops.create(
      fixture.admin,
      ShopDraft(name: 'Shop A', assignedAgentId: agentAId),
    );
    shopALocationId = (await fixture.locations.forShop(shopAId))!.id;
  });

  tearDown(() => fixture.dispose());

  Future<int> balanceAt(int locationId, [int? productId]) {
    return fixture.stockLedger.balanceOf(
      locationId: locationId,
      productId: productId ?? chargerId,
    );
  }

  Future<StockMovementResult> move({
    required StockDocumentType type,
    required int from,
    required int to,
    int quantity = 1,
    int? productId,
    Money? unitCost,
    Money unitPrice = Money.zero,
    bool allowNegative = false,
    String? reason,
  }) {
    return fixture.stockLedger.postMovement(
      fixture.admin,
      StockMovementRequest(
        documentType: type,
        sourceLocationId: from,
        destinationLocationId: to,
        allowNegativeStock: allowNegative,
        negativeStockReason: reason,
        lines: [
          StockMovementLine(
            productId: productId ?? chargerId,
            quantity: quantity,
            unitCost: unitCost,
            unitPrice: unitPrice,
          ),
        ],
      ),
    );
  }

  /// Posts a return and accepts all of it, which is the two-leg path every
  /// return takes: out of the returning location into transit, then out of
  /// transit once somebody has inspected the goods.
  Future<void> returnAndAccept({
    required ReturnRoute route,
    required int from,
    required int to,
    required int quantity,
  }) async {
    final posted = await fixture.returns.postReturn(
      fixture.admin,
      ReturnDraft(
        route: route,
        fromLocationId: from,
        toLocationId: to,
        reason: ReturnReason.excessStock,
        lines: [ReturnLineDraft(productId: chargerId, quantity: quantity)],
      ),
    );

    final items = await (fixture.db.select(
      fixture.db.returnItems,
    )..where((row) => row.returnId.equals(posted.returnId))).get();

    await fixture.returns.recordInspection(
      fixture.admin,
      InspectionRequest(
        returnId: posted.returnId,
        decisions: [
          for (final item in items)
            InspectionDecision(
              returnItemId: item.id,
              acceptedQuantity: item.quantity,
            ),
        ],
      ),
    );
  }

  /// Puts 100 chargers in the warehouse, which is where every scenario starts.
  Future<void> stockTheWarehouse([int quantity = 100]) async {
    await fixture.postOpeningStock(
      locationId: warehouseId,
      productId: chargerId,
      quantity: quantity,
      unitCost: Money.fromMajor(2000),
    );
  }

  group('acceptance scenarios from the brief', () {
    test('Scenario 1: warehouse 100, transfer 50 to Agent A', () async {
      await stockTheWarehouse();
      expect(await balanceAt(warehouseId), 100);

      await move(
        type: StockDocumentType.warehouseToAgent,
        from: warehouseId,
        to: agentALocationId,
        quantity: 50,
      );

      expect(await balanceAt(warehouseId), 50);
      expect(await balanceAt(agentALocationId), 50);
    });

    test('Scenario 2: Agent A supplies 20 to Shop A', () async {
      await stockTheWarehouse();
      await move(
        type: StockDocumentType.warehouseToAgent,
        from: warehouseId,
        to: agentALocationId,
        quantity: 50,
      );

      await move(
        type: StockDocumentType.agentToShop,
        from: agentALocationId,
        to: shopALocationId,
        quantity: 20,
      );

      expect(await balanceAt(warehouseId), 50);
      expect(await balanceAt(agentALocationId), 30);
      expect(await balanceAt(shopALocationId), 20);
    });

    test('Scenario 3: Shop A sells 10 to customers', () async {
      await stockTheWarehouse();
      await move(
        type: StockDocumentType.warehouseToAgent,
        from: warehouseId,
        to: agentALocationId,
        quantity: 50,
      );
      await move(
        type: StockDocumentType.agentToShop,
        from: agentALocationId,
        to: shopALocationId,
        quantity: 20,
      );

      await move(
        type: StockDocumentType.retailSale,
        from: shopALocationId,
        to: customerId,
        quantity: 10,
      );

      expect(await balanceAt(shopALocationId), 10);
      // "Sold = 10". Goods flowed into the customer counterparty, so its
      // balance is what has been sold: a single read rather than a derived
      // guess. (A counterparty goods flow *out* of, such as suppliers, goes
      // negative instead.)
      expect(await balanceAt(customerId), 10);
    });

    test('Scenario 6: Shop A returns 5 good chargers to Agent A', () async {
      await stockTheWarehouse();
      await move(
        type: StockDocumentType.warehouseToAgent,
        from: warehouseId,
        to: agentALocationId,
        quantity: 50,
      );
      await move(
        type: StockDocumentType.agentToShop,
        from: agentALocationId,
        to: shopALocationId,
        quantity: 20,
      );

      // Through the real returns module, because that is the only way a
      // return can be posted: the ledger refuses a shop-to-agent document
      // that skips goods-in-transit, and therefore skips inspection.
      await returnAndAccept(
        route: ReturnRoute.shopToAgent,
        from: shopALocationId,
        to: agentALocationId,
        quantity: 5,
      );

      expect(await balanceAt(shopALocationId), 15);
      expect(await balanceAt(agentALocationId), 35);
      // Nothing is left parked in transit.
      expect(await balanceAt(inTransitId), 0);
    });

    test('Scenario 7: Agent A returns those 5 to the warehouse', () async {
      await stockTheWarehouse();
      await move(
        type: StockDocumentType.warehouseToAgent,
        from: warehouseId,
        to: agentALocationId,
        quantity: 50,
      );
      await move(
        type: StockDocumentType.agentToShop,
        from: agentALocationId,
        to: shopALocationId,
        quantity: 20,
      );
      await returnAndAccept(
        route: ReturnRoute.shopToAgent,
        from: shopALocationId,
        to: agentALocationId,
        quantity: 5,
      );

      await returnAndAccept(
        route: ReturnRoute.agentToWarehouse,
        from: agentALocationId,
        to: warehouseId,
        quantity: 5,
      );

      expect(await balanceAt(agentALocationId), 30);
      expect(await balanceAt(warehouseId), 55);
      expect(await balanceAt(inTransitId), 0);
    });

    test(
      'Scenario 10: a transfer that fails leaves neither side changed',
      () async {
        await stockTheWarehouse();

        // Two lines: the first is fine, the second asks for more than exists.
        // The first line's balance updates have already been written when the
        // second line fails, which is exactly the half-applied state the
        // transaction has to undo.
        final secondProduct = await fixture.products.create(
          fixture.admin,
          ProductDraft(
            sku: 'CBL-C',
            name: 'Type-C Cable',
            categoryId:
                (await fixture.categories.selectableCategories()).first.id,
          ),
        );
        await fixture.postOpeningStock(
          locationId: warehouseId,
          productId: secondProduct,
          quantity: 5,
        );

        await expectLater(
          fixture.stockLedger.postMovement(
            fixture.admin,
            StockMovementRequest(
              documentType: StockDocumentType.warehouseToAgent,
              sourceLocationId: warehouseId,
              destinationLocationId: agentALocationId,
              lines: [
                StockMovementLine(productId: chargerId, quantity: 10),
                // Only 5 cables exist.
                StockMovementLine(productId: secondProduct, quantity: 999),
              ],
            ),
          ),
          throwsA(
            isA<BusinessRuleFailure>().having(
              (failure) => failure.rule,
              'rule',
              'stock.no_negative_balance',
            ),
          ),
        );

        // Neither product moved, at either end.
        expect(await balanceAt(warehouseId, chargerId), 100);
        expect(await balanceAt(warehouseId, secondProduct), 5);
        expect(await balanceAt(agentALocationId, chargerId), 0);
        expect(await balanceAt(agentALocationId, secondProduct), 0);

        // No document, no lines and no ledger rows were left behind.
        final transfers =
            await (fixture.db.select(fixture.db.stockTransactions)..where(
                  (t) => t.documentType.equalsValue(
                    StockDocumentType.warehouseToAgent,
                  ),
                ))
                .get();
        expect(transfers, isEmpty);

        // And the ledger still balances to zero for every product.
        expect(await fixture.stockLedger.findUnbalancedProducts(), isEmpty);
      },
    );
  });

  group('the ledger is the authority', () {
    test('every movement writes a balanced pair of entries', () async {
      await stockTheWarehouse();
      await move(
        type: StockDocumentType.warehouseToAgent,
        from: warehouseId,
        to: agentALocationId,
        quantity: 50,
      );

      final entries = await fixture.db
          .select(fixture.db.stockLedgerEntries)
          .get();
      // Opening stock plus the transfer: two movements, two entries each.
      expect(entries.length, 4);

      final deltaSum = entries.fold(
        0,
        (total, entry) => total + entry.quantityDelta,
      );
      expect(deltaSum, 0);
      expect(await fixture.stockLedger.findUnbalancedProducts(), isEmpty);
    });

    test('cached balances agree with a replay of the ledger', () async {
      await stockTheWarehouse();
      await move(
        type: StockDocumentType.warehouseToAgent,
        from: warehouseId,
        to: agentALocationId,
        quantity: 50,
      );
      await move(
        type: StockDocumentType.agentToShop,
        from: agentALocationId,
        to: shopALocationId,
        quantity: 20,
      );
      await move(
        type: StockDocumentType.retailSale,
        from: shopALocationId,
        to: customerId,
        quantity: 10,
      );

      expect(await fixture.stockLedger.findBalanceDiscrepancies(), isEmpty);

      final check = await fixture.stockLedger.verifyBalance(
        locationId: agentALocationId,
        productId: chargerId,
      );
      expect(check.cached, 30);
      expect(check.fromLedger, 30);
      expect(check.matches, isTrue);
    });

    test('records the running balance on each entry', () async {
      await stockTheWarehouse();
      await move(
        type: StockDocumentType.warehouseToAgent,
        from: warehouseId,
        to: agentALocationId,
        quantity: 40,
      );

      final warehouseEntries =
          await (fixture.db.select(fixture.db.stockLedgerEntries)
                ..where((e) => e.locationId.equals(warehouseId))
                ..orderBy([(e) => OrderingTerm.asc(e.id)]))
              .get();

      expect(warehouseEntries.first.quantityDelta, 100);
      expect(warehouseEntries.first.balanceAfter, 100);
      expect(warehouseEntries.last.quantityDelta, -40);
      expect(warehouseEntries.last.balanceAfter, 60);
    });

    test(
      'a ledger entry snapshots the type of document that made it',
      () async {
        await stockTheWarehouse();
        await move(
          type: StockDocumentType.warehouseToAgent,
          from: warehouseId,
          to: agentALocationId,
          quantity: 10,
        );

        final entries = await (fixture.db.select(
          fixture.db.stockLedgerEntries,
        )..where((e) => e.locationId.equals(agentALocationId))).get();
        expect(entries.single.entryType, StockDocumentType.warehouseToAgent);
      },
    );
  });

  group('negative stock', () {
    test(
      'is refused by default, with a message naming the shortfall',
      () async {
        await stockTheWarehouse(30);

        await expectLater(
          move(
            type: StockDocumentType.warehouseToAgent,
            from: warehouseId,
            to: agentALocationId,
            quantity: 50,
          ),
          throwsA(
            isA<BusinessRuleFailure>()
                .having(
                  (failure) => failure.rule,
                  'rule',
                  'stock.no_negative_balance',
                )
                .having(
                  (failure) => failure.message,
                  'message',
                  allOf(contains('30 unit'), contains('needs 50')),
                ),
          ),
        );
        expect(await balanceAt(warehouseId), 30);
      },
    );

    test(
      'can be overridden by an authorised user, and is then recorded',
      () async {
        await stockTheWarehouse(30);

        final result = await move(
          type: StockDocumentType.warehouseToAgent,
          from: warehouseId,
          to: agentALocationId,
          quantity: 50,
          allowNegative: true,
          reason: 'Physical count pending, goods already dispatched',
        );

        expect(await balanceAt(warehouseId), -20);
        expect(await balanceAt(agentALocationId), 50);

        final document = await (fixture.db.select(
          fixture.db.stockTransactions,
        )..where((t) => t.id.equals(result.transactionId))).getSingle();
        expect(document.negativeStockOverride, isTrue);
        expect(document.overrideApprovedByUserId, fixture.admin.id);
        expect(document.overrideReason, contains('Physical count pending'));

        final entries = await fixture.auditEntries();
        expect(
          entries.any(
            (entry) => entry.action == AuditAction.permissionOverride,
          ),
          isTrue,
        );
      },
    );

    test('the override needs the override permission', () async {
      await stockTheWarehouse(30);
      final cashier = await fixture.auth.createUser(
        actor: fixture.admin,
        fullName: 'Kamal Silva',
        username: 'kamal',
        password: 'Counter123',
        roleCodes: const ['STORE_KEEPER'],
      );
      expect(cashier.can(Permissions.stockTransfer), isTrue);
      expect(cashier.can(Permissions.stockNegativeOverride), isFalse);

      await expectLater(
        fixture.stockLedger.postMovement(
          cashier,
          StockMovementRequest(
            documentType: StockDocumentType.warehouseToAgent,
            sourceLocationId: warehouseId,
            destinationLocationId: agentALocationId,
            allowNegativeStock: true,
            negativeStockReason: 'Trying it on',
            lines: [StockMovementLine(productId: chargerId, quantity: 50)],
          ),
        ),
        throwsA(isA<PermissionFailure>()),
      );
    });

    test('the override requires a reason', () async {
      await stockTheWarehouse(30);
      await expectLater(
        move(
          type: StockDocumentType.warehouseToAgent,
          from: warehouseId,
          to: agentALocationId,
          quantity: 50,
          allowNegative: true,
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('the setting can allow it without a per-document override', () async {
      await fixture.harness.bootstrap.settings.setBool(
        SettingKeys.allowNegativeStock,
        true,
      );
      await stockTheWarehouse(30);

      await move(
        type: StockDocumentType.warehouseToAgent,
        from: warehouseId,
        to: agentALocationId,
        quantity: 50,
      );
      expect(await balanceAt(warehouseId), -20);
    });

    test('virtual counterparties are expected to go negative', () async {
      // Opening stock drives the supplier counterparty negative, and that is
      // correct: it mirrors everything that has entered the business.
      await stockTheWarehouse();
      expect(await balanceAt(supplierId), -100);
    });
  });

  group('cost flow', () {
    test('cost is stated when goods enter from a counterparty', () async {
      await fixture.postOpeningStock(
        locationId: warehouseId,
        productId: chargerId,
        quantity: 100,
        unitCost: Money.fromMajor(1800),
      );

      final balance = await (fixture.db.select(
        fixture.db.stockBalances,
      )..where((b) => b.locationId.equals(warehouseId))).getSingle();
      expect(Money(balance.averageCostCents), Money.fromMajor(1800));
    });

    test('cost travels with the goods between real locations', () async {
      await fixture.postOpeningStock(
        locationId: warehouseId,
        productId: chargerId,
        quantity: 100,
        unitCost: Money.fromMajor(1800),
      );

      // The transfer states a different price; the *cost* must not follow it.
      await move(
        type: StockDocumentType.warehouseToAgent,
        from: warehouseId,
        to: agentALocationId,
        quantity: 50,
        unitCost: Money.fromMajor(9999),
        unitPrice: Money.fromMajor(3000),
      );

      final agentBalance = await (fixture.db.select(
        fixture.db.stockBalances,
      )..where((b) => b.locationId.equals(agentALocationId))).getSingle();
      expect(Money(agentBalance.averageCostCents), Money.fromMajor(1800));
    });

    test('blends the cost of two receipts at different prices', () async {
      // 100 at 1,800 then 100 at 2,200 averages to 2,000.
      await fixture.postOpeningStock(
        locationId: warehouseId,
        productId: chargerId,
        quantity: 100,
        unitCost: Money.fromMajor(1800),
      );
      await fixture.postOpeningStock(
        locationId: warehouseId,
        productId: chargerId,
        quantity: 100,
        unitCost: Money.fromMajor(2200),
      );

      final balance = await (fixture.db.select(
        fixture.db.stockBalances,
      )..where((b) => b.locationId.equals(warehouseId))).getSingle();
      expect(balance.quantity, 200);
      expect(Money(balance.averageCostCents), Money.fromMajor(2000));
    });

    test('taking stock out does not change the cost of what is left', () async {
      await fixture.postOpeningStock(
        locationId: warehouseId,
        productId: chargerId,
        quantity: 100,
        unitCost: Money.fromMajor(1800),
      );
      await move(
        type: StockDocumentType.warehouseToAgent,
        from: warehouseId,
        to: agentALocationId,
        quantity: 60,
      );

      final balance = await (fixture.db.select(
        fixture.db.stockBalances,
      )..where((b) => b.locationId.equals(warehouseId))).getSingle();
      expect(balance.quantity, 40);
      expect(Money(balance.averageCostCents), Money.fromMajor(1800));
    });

    test('falls back to the product cost when nothing else is known', () async {
      // No cost stated and the source is a counterparty, so the product's own
      // cost price is used.
      final supplier = await fixture.locations.byCode(
        AppConstants.supplierLocationCode,
      );
      await fixture.stockLedger.postMovement(
        fixture.admin,
        StockMovementRequest(
          documentType: StockDocumentType.openingStock,
          sourceLocationId: supplier.id,
          destinationLocationId: warehouseId,
          lines: [StockMovementLine(productId: chargerId, quantity: 10)],
        ),
      );

      final balance = await (fixture.db.select(
        fixture.db.stockBalances,
      )..where((b) => b.locationId.equals(warehouseId))).getSingle();
      expect(Money(balance.averageCostCents), Money.fromMajor(2000));
    });
  });

  group('document validation', () {
    test('refuses an empty document', () async {
      await expectLater(
        fixture.stockLedger.postMovement(
          fixture.admin,
          StockMovementRequest(
            documentType: StockDocumentType.warehouseToAgent,
            sourceLocationId: warehouseId,
            destinationLocationId: agentALocationId,
            lines: const [],
          ),
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('refuses the same location at both ends', () async {
      await expectLater(
        move(
          type: StockDocumentType.interLocationTransfer,
          from: warehouseId,
          to: warehouseId,
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('refuses a duplicated product', () async {
      await stockTheWarehouse();
      await expectLater(
        fixture.stockLedger.postMovement(
          fixture.admin,
          StockMovementRequest(
            documentType: StockDocumentType.warehouseToAgent,
            sourceLocationId: warehouseId,
            destinationLocationId: agentALocationId,
            lines: [
              StockMovementLine(productId: chargerId, quantity: 5),
              StockMovementLine(productId: chargerId, quantity: 3),
            ],
          ),
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'stock.no_duplicate_products',
          ),
        ),
      );
    });

    test('refuses a zero or negative quantity', () async {
      await expectLater(
        move(
          type: StockDocumentType.warehouseToAgent,
          from: warehouseId,
          to: agentALocationId,
          quantity: 0,
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('refuses an archived product', () async {
      final categoryId =
          (await fixture.categories.selectableCategories()).first.id;
      final retiredId = await fixture.products.create(
        fixture.admin,
        ProductDraft(
          sku: 'OLD-1',
          name: 'Discontinued thing',
          categoryId: categoryId,
        ),
      );
      await fixture.products.archive(fixture.admin, retiredId);

      await expectLater(
        move(
          type: StockDocumentType.openingStock,
          from: supplierId,
          to: warehouseId,
          productId: retiredId,
          quantity: 5,
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'stock.product_not_archived',
          ),
        ),
      );
    });

    test('refuses an inactive location', () async {
      // Deactivating the agent deactivates its stock location.
      await fixture.agents.update(
        fixture.admin,
        const AgentDraft(id: 1, name: 'Agent A', status: EntityStatus.inactive),
      );
      await stockTheWarehouse();

      await expectLater(
        move(
          type: StockDocumentType.warehouseToAgent,
          from: warehouseId,
          to: agentALocationId,
          quantity: 5,
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'stock.location_active',
          ),
        ),
      );
    });

    test('refuses a line discount larger than the line', () async {
      await stockTheWarehouse();
      await expectLater(
        fixture.stockLedger.postMovement(
          fixture.admin,
          StockMovementRequest(
            documentType: StockDocumentType.warehouseToAgent,
            sourceLocationId: warehouseId,
            destinationLocationId: agentALocationId,
            lines: [
              StockMovementLine(
                productId: chargerId,
                quantity: 2,
                unitPrice: Money.fromMajor(3000),
                discountType: DiscountType.fixedAmount,
                discountValue: Money.fromMajor(7000).cents,
              ),
            ],
          ),
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });
  });

  group('route validation', () {
    test(
      'a warehouse-to-agent document must actually go to an agent',
      () async {
        await stockTheWarehouse();
        await expectLater(
          move(
            type: StockDocumentType.warehouseToAgent,
            from: warehouseId,
            to: shopALocationId,
            quantity: 5,
          ),
          throwsA(
            isA<BusinessRuleFailure>().having(
              (failure) => failure.rule,
              'rule',
              'stock.route_destination_kind',
            ),
          ),
        );
      },
    );

    test('an agent-to-shop document must come from an agent', () async {
      await stockTheWarehouse();
      await expectLater(
        move(
          type: StockDocumentType.agentToShop,
          from: warehouseId,
          to: shopALocationId,
          quantity: 5,
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'stock.route_source_kind',
          ),
        ),
      );
    });

    test('a retail sale must come from a shop and go to customers', () async {
      await stockTheWarehouse();
      await expectLater(
        move(
          type: StockDocumentType.retailSale,
          from: warehouseId,
          to: customerId,
          quantity: 5,
        ),
        throwsA(isA<BusinessRuleFailure>()),
      );
    });

    test('a damage write-off must go to the damaged store', () async {
      await stockTheWarehouse();
      await expectLater(
        move(
          type: StockDocumentType.damageWriteOff,
          from: warehouseId,
          to: agentALocationId,
          quantity: 5,
        ),
        throwsA(isA<BusinessRuleFailure>()),
      );

      // The correct route works.
      await move(
        type: StockDocumentType.damageWriteOff,
        from: warehouseId,
        to: damagedId,
        quantity: 5,
      );
      expect(await balanceAt(damagedId), 5);
      expect(await balanceAt(warehouseId), 95);
    });

    test('adjustments go through the adjustment counterparty', () async {
      await move(
        type: StockDocumentType.adjustmentIncrease,
        from: adjustmentId,
        to: warehouseId,
        quantity: 7,
        unitCost: Money.fromMajor(2000),
      );
      expect(await balanceAt(warehouseId), 7);
      expect(await balanceAt(adjustmentId), -7);

      await move(
        type: StockDocumentType.adjustmentDecrease,
        from: warehouseId,
        to: adjustmentId,
        quantity: 3,
      );
      expect(await balanceAt(warehouseId), 4);
      expect(await balanceAt(adjustmentId), -4);
    });
  });

  group('document numbering', () {
    test('uses a different prefix per kind of movement', () async {
      await stockTheWarehouse();
      final transfer = await move(
        type: StockDocumentType.warehouseToAgent,
        from: warehouseId,
        to: agentALocationId,
        quantity: 10,
      );
      final supply = await move(
        type: StockDocumentType.agentToShop,
        from: agentALocationId,
        to: shopALocationId,
        quantity: 5,
      );
      final adjustment = await move(
        type: StockDocumentType.adjustmentIncrease,
        from: adjustmentId,
        to: warehouseId,
        quantity: 1,
      );

      expect(transfer.documentNumber, startsWith('TRF-'));
      expect(supply.documentNumber, startsWith('SUP-'));
      expect(adjustment.documentNumber, startsWith('ADJ-'));
    });

    test('numbers are sequential within a kind', () async {
      await stockTheWarehouse();
      final first = await move(
        type: StockDocumentType.warehouseToAgent,
        from: warehouseId,
        to: agentALocationId,
        quantity: 1,
      );
      final second = await move(
        type: StockDocumentType.warehouseToAgent,
        from: warehouseId,
        to: agentALocationId,
        quantity: 1,
      );

      expect(first.documentNumber, 'TRF-2026-00001');
      expect(second.documentNumber, 'TRF-2026-00002');
    });
  });

  group('cancelling a document', () {
    test('posts a reversal and leaves the original ledger intact', () async {
      await stockTheWarehouse();
      final transfer = await move(
        type: StockDocumentType.warehouseToAgent,
        from: warehouseId,
        to: agentALocationId,
        quantity: 50,
      );
      expect(await balanceAt(warehouseId), 50);

      final entriesBefore =
          (await fixture.db.select(fixture.db.stockLedgerEntries).get()).length;

      final reversal = await fixture.stockLedger.cancelMovement(
        fixture.admin,
        transactionId: transfer.transactionId,
        reason: 'Wrong agent',
      );

      // The goods are back.
      expect(await balanceAt(warehouseId), 100);
      expect(await balanceAt(agentALocationId), 0);

      // The original's entries were not deleted; the reversal added its own.
      final entriesAfter = await fixture.db
          .select(fixture.db.stockLedgerEntries)
          .get();
      expect(entriesAfter.length, entriesBefore + 2);

      final original = await (fixture.db.select(
        fixture.db.stockTransactions,
      )..where((t) => t.id.equals(transfer.transactionId))).getSingle();
      expect(original.status, StockDocumentStatus.cancelled);
      expect(original.cancelReason, 'Wrong agent');
      expect(original.cancelledByUserId, fixture.admin.id);

      final reversalDocument = await (fixture.db.select(
        fixture.db.stockTransactions,
      )..where((t) => t.id.equals(reversal.transactionId))).getSingle();
      expect(reversalDocument.reversesTransactionId, transfer.transactionId);
      expect(reversalDocument.sourceLocationId, agentALocationId);
      expect(reversalDocument.destinationLocationId, warehouseId);

      expect(await fixture.stockLedger.findUnbalancedProducts(), isEmpty);
      expect(await fixture.stockLedger.findBalanceDiscrepancies(), isEmpty);
    });

    test('refuses to cancel the same document twice', () async {
      await stockTheWarehouse();
      final transfer = await move(
        type: StockDocumentType.warehouseToAgent,
        from: warehouseId,
        to: agentALocationId,
        quantity: 10,
      );
      await fixture.stockLedger.cancelMovement(
        fixture.admin,
        transactionId: transfer.transactionId,
        reason: 'First cancellation',
      );

      await expectLater(
        fixture.stockLedger.cancelMovement(
          fixture.admin,
          transactionId: transfer.transactionId,
          reason: 'Again',
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'stock.cancel_posted_only',
          ),
        ),
      );
    });

    test('refuses a cancellation when the goods have moved on', () async {
      await stockTheWarehouse();
      final transfer = await move(
        type: StockDocumentType.warehouseToAgent,
        from: warehouseId,
        to: agentALocationId,
        quantity: 20,
      );
      // The agent has already passed all of them to the shop.
      await move(
        type: StockDocumentType.agentToShop,
        from: agentALocationId,
        to: shopALocationId,
        quantity: 20,
      );

      await expectLater(
        fixture.stockLedger.cancelMovement(
          fixture.admin,
          transactionId: transfer.transactionId,
          reason: 'Too late',
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'stock.no_negative_balance',
          ),
        ),
      );

      // Nothing changed, and the original is still posted.
      expect(await balanceAt(shopALocationId), 20);
      final original = await (fixture.db.select(
        fixture.db.stockTransactions,
      )..where((t) => t.id.equals(transfer.transactionId))).getSingle();
      expect(original.status, StockDocumentStatus.posted);
    });

    test('requires a reason', () async {
      await stockTheWarehouse();
      final transfer = await move(
        type: StockDocumentType.warehouseToAgent,
        from: warehouseId,
        to: agentALocationId,
        quantity: 10,
      );

      await expectLater(
        fixture.stockLedger.cancelMovement(
          fixture.admin,
          transactionId: transfer.transactionId,
          reason: '   ',
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('records the cancellation and the reversal number', () async {
      await stockTheWarehouse();
      final transfer = await move(
        type: StockDocumentType.warehouseToAgent,
        from: warehouseId,
        to: agentALocationId,
        quantity: 10,
      );
      final reversal = await fixture.stockLedger.cancelMovement(
        fixture.admin,
        transactionId: transfer.transactionId,
        reason: 'Wrong agent',
      );

      final entries = await fixture.auditEntries();
      final cancellation = entries.firstWhere(
        (entry) => entry.action == AuditAction.cancel,
      );
      expect(cancellation.summary, contains(transfer.documentNumber));
      expect(cancellation.summary, contains(reversal.documentNumber));
      expect(cancellation.summary, contains('Wrong agent'));
    });
  });

  group('permissions', () {
    test('a store keeper can transfer but not adjust', () async {
      final keeper = await fixture.auth.createUser(
        actor: fixture.admin,
        fullName: 'Sunil Fernando',
        username: 'sunil',
        password: 'Keeper123',
        roleCodes: const ['STORE_KEEPER'],
      );
      await stockTheWarehouse();

      await fixture.stockLedger.postMovement(
        keeper,
        StockMovementRequest(
          documentType: StockDocumentType.warehouseToAgent,
          sourceLocationId: warehouseId,
          destinationLocationId: agentALocationId,
          lines: [StockMovementLine(productId: chargerId, quantity: 5)],
        ),
      );
      expect(await balanceAt(agentALocationId), 5);

      await expectLater(
        fixture.stockLedger.postMovement(
          keeper,
          StockMovementRequest(
            documentType: StockDocumentType.adjustmentIncrease,
            sourceLocationId: adjustmentId,
            destinationLocationId: warehouseId,
            lines: [StockMovementLine(productId: chargerId, quantity: 5)],
          ),
        ),
        throwsA(
          isA<PermissionFailure>().having(
            (failure) => failure.permission,
            'permission',
            Permissions.stockAdjust,
          ),
        ),
      );
    });

    test('a viewer cannot move stock at all', () async {
      final viewer = await fixture.createViewer();
      await stockTheWarehouse();

      await expectLater(
        fixture.stockLedger.postMovement(
          viewer,
          StockMovementRequest(
            documentType: StockDocumentType.warehouseToAgent,
            sourceLocationId: warehouseId,
            destinationLocationId: agentALocationId,
            lines: [StockMovementLine(productId: chargerId, quantity: 5)],
          ),
        ),
        throwsA(isA<PermissionFailure>()),
      );
    });
  });

  group('document contents', () {
    test('snapshots the product name and SKU on each line', () async {
      await stockTheWarehouse();
      final transfer = await move(
        type: StockDocumentType.warehouseToAgent,
        from: warehouseId,
        to: agentALocationId,
        quantity: 10,
        unitPrice: Money.fromMajor(3000),
      );

      final items = await (fixture.db.select(
        fixture.db.stockTransactionItems,
      )..where((i) => i.transactionId.equals(transfer.transactionId))).get();
      expect(items.single.productNameSnapshot, '25W Charger');
      expect(items.single.skuSnapshot, 'CHG-25W');
      expect(items.single.unitPriceCents, Money.fromMajor(3000).cents);
      expect(items.single.lineTotalCents, Money.fromMajor(30000).cents);

      // Renaming the product afterwards must not rewrite the document.
      await fixture.products.update(
        fixture.admin,
        ProductDraft(
          id: chargerId,
          sku: 'CHG-25W-V2',
          name: '25W Charger (new)',
          categoryId:
              (await fixture.categories.selectableCategories()).first.id,
        ),
      );

      final itemsAfter = await (fixture.db.select(
        fixture.db.stockTransactionItems,
      )..where((i) => i.transactionId.equals(transfer.transactionId))).get();
      expect(itemsAfter.single.productNameSnapshot, '25W Charger');
      expect(itemsAfter.single.skuSnapshot, 'CHG-25W');
    });

    test('carries the delivery-note totals without creating revenue', () async {
      // The brief's example: 50 units at Rs. 3,000 is Rs. 150,000 on the
      // delivery note. No invoice exists, so nothing is receivable.
      await stockTheWarehouse();
      final transfer = await move(
        type: StockDocumentType.warehouseToAgent,
        from: warehouseId,
        to: agentALocationId,
        quantity: 50,
        unitPrice: Money.fromMajor(3000),
      );

      final document = await (fixture.db.select(
        fixture.db.stockTransactions,
      )..where((t) => t.id.equals(transfer.transactionId))).getSingle();
      expect(document.totalQuantity, 50);
      expect(Money(document.totalCents), Money.fromMajor(150000));

      // No invoice was created by the transfer.
      final invoices = await fixture.db.select(fixture.db.invoices).get();
      expect(invoices, isEmpty);

      final agents = await fixture.agents
          .watchAgents(const AgentFilter())
          .first;
      expect(agents.single.billedTotal, Money.zero);
      expect(agents.single.outstandingBalance, Money.zero);
    });

    test('records which party the movement concerned', () async {
      await stockTheWarehouse();
      final transfer = await move(
        type: StockDocumentType.warehouseToAgent,
        from: warehouseId,
        to: agentALocationId,
        quantity: 10,
      );

      final document = await (fixture.db.select(
        fixture.db.stockTransactions,
      )..where((t) => t.id.equals(transfer.transactionId))).getSingle();
      expect(document.agentId, agentAId);
    });
  });
}
