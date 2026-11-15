import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venvo_core/core/constants/app_constants.dart';
import 'package:venvo_core/core/database/app_database.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/agents/domain/agent_models.dart';
import 'package:venvo_core/features/categories/domain/category_models.dart';
import 'package:venvo_core/features/dashboard/data/dashboard_repository.dart';
import 'package:venvo_core/features/employees/domain/employee_models.dart';
import 'package:venvo_core/features/inventory/domain/stock_models.dart';
import 'package:venvo_core/features/invoices/domain/invoice_models.dart';
import 'package:venvo_core/features/petty_cash/domain/petty_cash_models.dart';
import 'package:venvo_core/features/products/domain/product_models.dart';
import 'package:venvo_core/features/returns/domain/return_models.dart';
import 'package:venvo_core/features/salaries/domain/salary_models.dart';
import 'package:venvo_core/features/shops/domain/shop_models.dart';

import '../helpers/master_data_fixtures.dart';
import '../helpers/test_harness.dart';

void main() {
  late TestHarness harness;
  late DashboardRepository dashboard;
  late int userId;

  setUp(() async {
    harness = await TestHarness.create(at: DateTime.utc(2026, 11, 15, 10));
    dashboard = DashboardRepository(harness.db, harness.clock);
    userId = await _insertUser(harness);
  });

  tearDown(() => harness.dispose());

  group('on an empty database', () {
    test('every figure is zero rather than null or an error', () async {
      final snapshot = await dashboard.load();

      expect(snapshot.todaysSales, Money.zero);
      expect(snapshot.todaysCollections, Money.zero);
      expect(snapshot.todaysExpenses, Money.zero);
      expect(snapshot.monthSales, Money.zero);
      expect(snapshot.monthExpenses, Money.zero);
      expect(snapshot.monthGrossProfit, Money.zero);
      expect(snapshot.totalReceivable, Money.zero);
      expect(snapshot.totalStockValue, Money.zero);
      expect(snapshot.pendingChequeTotal, Money.zero);
      expect(snapshot.pendingChequeCount, 0);
      expect(snapshot.lowStockCount, 0);
      expect(snapshot.unallocatedAdvances, Money.zero);
      expect(snapshot.isEmptyBusiness, isTrue);

      // The figures the later phases added read as true zeros too, rather
      // than as nulls dressed up for display.
      expect(snapshot.returnsAwaitingInspection, 0);
      expect(snapshot.returnsAwaitingInspectionUnits, 0);
      expect(snapshot.hasInspectionBacklog, isFalse);
      expect(snapshot.unappliedCreditNotes, Money.zero);
      expect(snapshot.pettyCashFloat, Money.zero);
      expect(snapshot.unpaidSalaries, Money.zero);
      expect(snapshot.outstandingEmployeeAdvances, Money.zero);
      expect(snapshot.monthNetProfit, Money.zero);
      expect(snapshot.monthRetailSales, Money.zero);
    });
  });

  group('sales and receivables', () {
    test('counts a posted invoice but not a draft one', () async {
      final shopId = await _insertShop(harness);

      await _insertInvoice(
        harness,
        userId: userId,
        shopId: shopId,
        number: 'SINV-2026-00001',
        netTotal: Money.fromMajor(20000),
        status: InvoiceStatus.posted,
      );
      await _insertInvoice(
        harness,
        userId: userId,
        shopId: shopId,
        number: 'SINV-2026-00002',
        netTotal: Money.fromMajor(50000),
        status: InvoiceStatus.draft,
      );

      final snapshot = await dashboard.load();
      expect(snapshot.todaysSales, Money.fromMajor(20000));
      expect(snapshot.receivableFromShops, Money.fromMajor(20000));
    });

    test('excludes a cancelled invoice from sales and receivables', () async {
      final shopId = await _insertShop(harness);
      await _insertInvoice(
        harness,
        userId: userId,
        shopId: shopId,
        number: 'SINV-2026-00001',
        netTotal: Money.fromMajor(20000),
        status: InvoiceStatus.cancelled,
      );

      final snapshot = await dashboard.load();
      expect(snapshot.todaysSales, Money.zero);
      expect(snapshot.receivableFromShops, Money.zero);
    });

    test(
      'a cash payment reduces the receivable and counts as collected',
      () async {
        // The brief's scenario 4: a Rs. 20,000 invoice part-paid with Rs. 10,000
        // leaves Rs. 10,000 outstanding.
        final shopId = await _insertShop(harness);
        final invoiceId = await _insertInvoice(
          harness,
          userId: userId,
          shopId: shopId,
          number: 'SINV-2026-00001',
          netTotal: Money.fromMajor(20000),
          status: InvoiceStatus.posted,
        );

        await _insertPayment(
          harness,
          userId: userId,
          shopId: shopId,
          number: 'PAY-2026-00001',
          amount: Money.fromMajor(10000),
          method: PaymentMethod.cash,
          status: PaymentStatus.cleared,
          allocateToInvoiceId: invoiceId,
        );

        var snapshot = await dashboard.load();
        expect(snapshot.receivableFromShops, Money.fromMajor(10000));
        expect(snapshot.todaysCollections, Money.fromMajor(10000));

        // Scenario 5: a further Rs. 5,000 leaves Rs. 5,000 outstanding.
        await _insertPayment(
          harness,
          userId: userId,
          shopId: shopId,
          number: 'PAY-2026-00002',
          amount: Money.fromMajor(5000),
          method: PaymentMethod.cash,
          status: PaymentStatus.cleared,
          allocateToInvoiceId: invoiceId,
        );

        snapshot = await dashboard.load();
        expect(snapshot.receivableFromShops, Money.fromMajor(5000));
        expect(snapshot.todaysCollections, Money.fromMajor(15000));
      },
    );

    test('includes an opening balance in the receivable', () async {
      await _insertShop(harness, openingBalance: Money.fromMajor(7500));
      final snapshot = await dashboard.load();
      expect(snapshot.receivableFromShops, Money.fromMajor(7500));
    });

    test('reports money received but not allocated as an advance', () async {
      final shopId = await _insertShop(harness);
      await _insertPayment(
        harness,
        userId: userId,
        shopId: shopId,
        number: 'PAY-2026-00001',
        amount: Money.fromMajor(3000),
        method: PaymentMethod.cash,
        status: PaymentStatus.cleared,
      );

      final snapshot = await dashboard.load();
      expect(snapshot.unallocatedAdvances, Money.fromMajor(3000));
    });

    test('separates agent receivables from shop receivables', () async {
      final agentId = await _insertAgent(harness);
      final shopId = await _insertShop(harness);

      await _insertInvoice(
        harness,
        userId: userId,
        agentId: agentId,
        partyType: PartyType.agent,
        number: 'AINV-2026-00001',
        netTotal: Money.fromMajor(150000),
        status: InvoiceStatus.posted,
      );
      await _insertInvoice(
        harness,
        userId: userId,
        shopId: shopId,
        number: 'SINV-2026-00001',
        netTotal: Money.fromMajor(20000),
        status: InvoiceStatus.posted,
      );

      final snapshot = await dashboard.load();
      expect(snapshot.receivableFromAgents, Money.fromMajor(150000));
      expect(snapshot.receivableFromShops, Money.fromMajor(20000));
      expect(snapshot.totalReceivable, Money.fromMajor(170000));
    });

    test('only counts sales dated today in the daily figure', () async {
      final shopId = await _insertShop(harness);
      await _insertInvoice(
        harness,
        userId: userId,
        shopId: shopId,
        number: 'SINV-2026-00001',
        netTotal: Money.fromMajor(20000),
        status: InvoiceStatus.posted,
        invoiceDate: DateTime.utc(2026, 11, 10, 10),
      );

      final snapshot = await dashboard.load();
      // Earlier this month, so it is in the month total but not today's.
      expect(snapshot.todaysSales, Money.zero);
      expect(snapshot.monthSales, Money.fromMajor(20000));
    });

    test('gross profit is net sales less the snapshotted cost', () async {
      final shopId = await _insertShop(harness);
      await _insertInvoice(
        harness,
        userId: userId,
        shopId: shopId,
        number: 'SINV-2026-00001',
        netTotal: Money.fromMajor(18000),
        costTotal: Money.fromMajor(12000),
        status: InvoiceStatus.posted,
      );

      final snapshot = await dashboard.load();
      expect(snapshot.monthGrossProfit, Money.fromMajor(6000));
    });
  });

  group('cheques are not cash until they clear', () {
    test(
      'a pending cheque is reported as pending, not as a collection',
      () async {
        // The brief's scenario 9.
        final shopId = await _insertShop(harness);
        final invoiceId = await _insertInvoice(
          harness,
          userId: userId,
          shopId: shopId,
          number: 'SINV-2026-00001',
          netTotal: Money.fromMajor(20000),
          status: InvoiceStatus.posted,
        );

        final paymentId = await _insertPayment(
          harness,
          userId: userId,
          shopId: shopId,
          number: 'PAY-2026-00001',
          amount: Money.fromMajor(10000),
          method: PaymentMethod.cheque,
          status: PaymentStatus.pending,
          allocateToInvoiceId: invoiceId,
        );
        await _insertCheque(harness, paymentId: paymentId, userId: userId);

        final snapshot = await dashboard.load();

        // It shows up as a pending cheque...
        expect(snapshot.pendingChequeTotal, Money.fromMajor(10000));
        expect(snapshot.pendingChequeCount, 1);
        // ...is not counted as collected cash...
        expect(snapshot.todaysCollections, Money.zero);
        // ...and has not reduced what the shop owes.
        expect(snapshot.receivableFromShops, Money.fromMajor(20000));
      },
    );

    test(
      'clearing the cheque turns it into a collection and settles the debt',
      () async {
        final shopId = await _insertShop(harness);
        final invoiceId = await _insertInvoice(
          harness,
          userId: userId,
          shopId: shopId,
          number: 'SINV-2026-00001',
          netTotal: Money.fromMajor(20000),
          status: InvoiceStatus.posted,
        );
        final paymentId = await _insertPayment(
          harness,
          userId: userId,
          shopId: shopId,
          number: 'PAY-2026-00001',
          amount: Money.fromMajor(10000),
          method: PaymentMethod.cheque,
          status: PaymentStatus.pending,
          allocateToInvoiceId: invoiceId,
        );
        final chequeId = await _insertCheque(
          harness,
          paymentId: paymentId,
          userId: userId,
        );

        await (harness.db.update(
          harness.db.payments,
        )..where((p) => p.id.equals(paymentId))).write(
          PaymentsCompanion(
            status: const Value(PaymentStatus.cleared),
            clearedAt: Value(harness.clock.nowUtc()),
          ),
        );
        await (harness.db.update(
          harness.db.cheques,
        )..where((c) => c.id.equals(chequeId))).write(
          ChequesCompanion(
            status: const Value(ChequeStatus.cleared),
            clearedAt: Value(harness.clock.nowUtc()),
            updatedAt: Value(harness.clock.nowUtc()),
          ),
        );

        final snapshot = await dashboard.load();
        expect(snapshot.pendingChequeTotal, Money.zero);
        expect(snapshot.pendingChequeCount, 0);
        expect(snapshot.todaysCollections, Money.fromMajor(10000));
        expect(snapshot.receivableFromShops, Money.fromMajor(10000));
      },
    );

    test(
      'a bounced cheque restores the receivable without deleting anything',
      () async {
        final shopId = await _insertShop(harness);
        final invoiceId = await _insertInvoice(
          harness,
          userId: userId,
          shopId: shopId,
          number: 'SINV-2026-00001',
          netTotal: Money.fromMajor(20000),
          status: InvoiceStatus.posted,
        );
        final paymentId = await _insertPayment(
          harness,
          userId: userId,
          shopId: shopId,
          number: 'PAY-2026-00001',
          amount: Money.fromMajor(10000),
          method: PaymentMethod.cheque,
          status: PaymentStatus.cleared,
          allocateToInvoiceId: invoiceId,
        );
        final chequeId = await _insertCheque(
          harness,
          paymentId: paymentId,
          userId: userId,
        );

        expect(
          (await dashboard.load()).receivableFromShops,
          Money.fromMajor(10000),
        );

        // The cheque bounces. The payment and its allocation stay on record.
        await (harness.db.update(
          harness.db.payments,
        )..where((p) => p.id.equals(paymentId))).write(
          PaymentsCompanion(
            status: const Value(PaymentStatus.bounced),
            bouncedAt: Value(harness.clock.nowUtc()),
          ),
        );
        await (harness.db.update(
          harness.db.cheques,
        )..where((c) => c.id.equals(chequeId))).write(
          ChequesCompanion(
            status: const Value(ChequeStatus.bounced),
            bouncedAt: Value(harness.clock.nowUtc()),
            bounceReason: const Value('Insufficient funds'),
            updatedAt: Value(harness.clock.nowUtc()),
          ),
        );

        final snapshot = await dashboard.load();
        expect(snapshot.receivableFromShops, Money.fromMajor(20000));
        expect(snapshot.todaysCollections, Money.zero);
        // A bounced cheque is not pending either: it needs a replacement, not
        // more waiting.
        expect(snapshot.pendingChequeCount, 0);

        // The original records are intact.
        final allocations = await harness.db
            .select(harness.db.paymentAllocations)
            .get();
        expect(allocations.length, 1);
        final payment = await harness.db
            .select(harness.db.payments)
            .getSingle();
        expect(payment.amountCents, Money.fromMajor(10000).cents);
      },
    );
  });

  group('stock valuation and low stock', () {
    test('values stock per location kind at weighted average cost', () async {
      final categoryId = await _insertCategory(harness);
      final productId = await _insertProduct(harness, categoryId);
      final agentId = await _insertAgent(harness);
      final shopId = await _insertShop(harness);

      final warehouse = await _locationByCode(
        harness,
        AppConstants.mainWarehouseCode,
      );
      final agentLocation = await _insertLocation(
        harness,
        'AG-1',
        LocationKind.agent,
        agentId: agentId,
      );
      final shopLocation = await _insertLocation(
        harness,
        'SH-1',
        LocationKind.shop,
        shopId: shopId,
      );

      // 50 in the warehouse, 30 with the agent, 20 in the shop, all at a cost
      // of Rs. 2,000 each.
      await _insertBalance(
        harness,
        warehouse,
        productId,
        50,
        Money.fromMajor(2000),
      );
      await _insertBalance(
        harness,
        agentLocation,
        productId,
        30,
        Money.fromMajor(2000),
      );
      await _insertBalance(
        harness,
        shopLocation,
        productId,
        20,
        Money.fromMajor(2000),
      );

      final snapshot = await dashboard.load();
      expect(snapshot.warehouseStockValue, Money.fromMajor(100000));
      expect(snapshot.agentStockValue, Money.fromMajor(60000));
      expect(snapshot.shopStockValue, Money.fromMajor(40000));
      expect(snapshot.totalStockValue, Money.fromMajor(200000));
    });

    test('damaged stock is valued separately, not as sellable stock', () async {
      final categoryId = await _insertCategory(harness);
      final productId = await _insertProduct(harness, categoryId);
      final damaged = await _locationByCode(
        harness,
        AppConstants.damagedLocationCode,
      );
      await _insertBalance(
        harness,
        damaged,
        productId,
        5,
        Money.fromMajor(2000),
      );

      final snapshot = await dashboard.load();
      expect(snapshot.damagedStockValue, Money.fromMajor(10000));
      expect(snapshot.totalStockValue, Money.zero);
    });

    test('counts a product with no stock row at all as low stock', () async {
      // A product that has never been stocked is below its reorder level.
      final categoryId = await _insertCategory(harness);
      await _insertProduct(harness, categoryId, reorderLevel: 10);

      final snapshot = await dashboard.load();
      expect(snapshot.lowStockCount, 1);
    });

    test('counts a product at or below its reorder level', () async {
      final categoryId = await _insertCategory(harness);
      final warehouse = await _locationByCode(
        harness,
        AppConstants.mainWarehouseCode,
      );

      final atLevel = await _insertProduct(
        harness,
        categoryId,
        sku: 'AT',
        reorderLevel: 10,
      );
      final below = await _insertProduct(
        harness,
        categoryId,
        sku: 'BELOW',
        reorderLevel: 10,
      );
      final above = await _insertProduct(
        harness,
        categoryId,
        sku: 'ABOVE',
        reorderLevel: 10,
      );

      await _insertBalance(harness, warehouse, atLevel, 10, Money.fromMajor(1));
      await _insertBalance(harness, warehouse, below, 9, Money.fromMajor(1));
      await _insertBalance(harness, warehouse, above, 11, Money.fromMajor(1));

      final snapshot = await dashboard.load();
      expect(snapshot.lowStockCount, 2);
    });

    test('ignores a product with no reorder level set', () async {
      final categoryId = await _insertCategory(harness);
      await _insertProduct(harness, categoryId, reorderLevel: 0);

      final snapshot = await dashboard.load();
      expect(snapshot.lowStockCount, 0);
    });

    test(
      'sums stock across locations before comparing to the reorder level',
      () async {
        // 6 in the warehouse plus 6 with an agent is 12, which is above a
        // reorder level of 10 even though neither location alone is.
        final categoryId = await _insertCategory(harness);
        final productId = await _insertProduct(
          harness,
          categoryId,
          reorderLevel: 10,
        );
        final agentId = await _insertAgent(harness);
        final warehouse = await _locationByCode(
          harness,
          AppConstants.mainWarehouseCode,
        );
        final agentLocation = await _insertLocation(
          harness,
          'AG-1',
          LocationKind.agent,
          agentId: agentId,
        );

        await _insertBalance(
          harness,
          warehouse,
          productId,
          6,
          Money.fromMajor(1),
        );
        await _insertBalance(
          harness,
          agentLocation,
          productId,
          6,
          Money.fromMajor(1),
        );

        final snapshot = await dashboard.load();
        expect(snapshot.lowStockCount, 0);
      },
    );
  });

  group('expenses', () {
    test('counts posted expenses for today and the month', () async {
      final category = await harness.db
          .select(harness.db.expenseCategories)
          .get();
      final transport = category.firstWhere((c) => c.code == 'TRANSPORT');

      await _insertExpense(
        harness,
        userId: userId,
        categoryId: transport.id,
        number: 'EXP-2026-00001',
        amount: Money.fromMajor(3000),
        status: InvoiceStatus.posted,
      );
      await _insertExpense(
        harness,
        userId: userId,
        categoryId: transport.id,
        number: 'EXP-2026-00002',
        amount: Money.fromMajor(5000),
        status: InvoiceStatus.posted,
        expenseDate: DateTime.utc(2026, 11, 2, 10),
      );
      // A draft expense must not be counted.
      await _insertExpense(
        harness,
        userId: userId,
        categoryId: transport.id,
        number: 'EXP-2026-00003',
        amount: Money.fromMajor(9000),
        status: InvoiceStatus.draft,
      );

      final snapshot = await dashboard.load();
      expect(snapshot.todaysExpenses, Money.fromMajor(3000));
      expect(snapshot.monthExpenses, Money.fromMajor(8000));
    });
  });

  // The figures the returns, finance and reporting phases added. These run
  // over the real services rather than over inserted rows, because what is
  // being checked is that the dashboard agrees with the modules.
  group('what the later phases added', () {
    late MasterDataFixture fixture;
    late DashboardRepository live;
    late int chargerId;
    late int warehouseId;
    late int agentId;
    late int agentLocationId;
    late int shopId;
    late int shopLocationId;

    setUp(() async {
      fixture = await MasterDataFixture.create(
        at: DateTime.utc(2026, 11, 15, 10),
      );
      live = fixture.dashboard;

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
          wholesalePrice: Money.fromMajor(3000),
          retailPrice: Money.fromMajor(3500),
        ),
      );
      warehouseId = (await fixture.locations.mainWarehouse()).id;
      agentId = await fixture.agents.create(
        fixture.admin,
        const AgentDraft(name: 'Agent A'),
      );
      agentLocationId = (await fixture.locations.forAgent(agentId))!.id;
      shopId = await fixture.shops.create(
        fixture.admin,
        ShopDraft(name: 'Shop A', assignedAgentId: agentId),
      );
      shopLocationId = (await fixture.locations.forShop(shopId))!.id;

      await fixture.postOpeningStock(
        locationId: warehouseId,
        productId: chargerId,
        quantity: 200,
        unitCost: Money.fromMajor(2000),
      );
      await fixture.stockLedger.postMovement(
        fixture.admin,
        StockMovementRequest(
          documentType: StockDocumentType.warehouseToAgent,
          sourceLocationId: warehouseId,
          destinationLocationId: agentLocationId,
          lines: [StockMovementLine(productId: chargerId, quantity: 100)],
        ),
      );
      await fixture.stockLedger.postMovement(
        fixture.admin,
        StockMovementRequest(
          documentType: StockDocumentType.agentToShop,
          sourceLocationId: agentLocationId,
          destinationLocationId: shopLocationId,
          agentId: agentId,
          shopId: shopId,
          lines: [StockMovementLine(productId: chargerId, quantity: 100)],
        ),
      );
    });

    tearDown(() => fixture.dispose());

    test('counts returns still waiting to be inspected', () async {
      await fixture.returns.postReturn(
        fixture.admin,
        ReturnDraft(
          route: ReturnRoute.shopToAgent,
          fromLocationId: shopLocationId,
          toLocationId: agentLocationId,
          agentId: agentId,
          shopId: shopId,
          reason: ReturnReason.defectiveItem,
          lines: [ReturnLineDraft(productId: chargerId, quantity: 7)],
        ),
      );

      final snapshot = await live.load();
      expect(snapshot.returnsAwaitingInspection, 1);
      expect(snapshot.returnsAwaitingInspectionUnits, 7);
      expect(snapshot.hasInspectionBacklog, isTrue);
    });

    test('a return drops out of the queue once it is inspected', () async {
      final posted = await fixture.returns.postReturn(
        fixture.admin,
        ReturnDraft(
          route: ReturnRoute.shopToAgent,
          fromLocationId: shopLocationId,
          toLocationId: agentLocationId,
          agentId: agentId,
          shopId: shopId,
          reason: ReturnReason.defectiveItem,
          lines: [
            ReturnLineDraft(
              productId: chargerId,
              quantity: 4,
              unitPrice: Money.fromMajor(3000),
            ),
          ],
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
            InspectionDecision(
              returnItemId: items.single.id,
              acceptedQuantity: 4,
            ),
          ],
        ),
      );

      var snapshot = await live.load();
      expect(snapshot.returnsAwaitingInspection, 0);
      expect(snapshot.unappliedCreditNotes, Money.zero);

      await fixture.returns.issueCreditNote(
        fixture.admin,
        returnId: posted.returnId,
      );

      // Credit raised but not applied is money the business owes back.
      snapshot = await live.load();
      expect(snapshot.unappliedCreditNotes, Money.fromMajor(12000));
    });

    test('reports the petty cash float', () async {
      await fixture.pettyCash.recordEntry(
        fixture.admin,
        PettyCashDraft(
          kind: PettyCashEntryKind.opening,
          amount: Money.fromMajor(15000),
          description: 'Opening float',
        ),
      );

      final snapshot = await live.load();
      expect(snapshot.pettyCashFloat, Money.fromMajor(15000));
      expect(snapshot.pettyCashFloat, await fixture.pettyCash.floatBalance());
    });

    test('reports unpaid salaries and employee advances', () async {
      final employeeId = await fixture.employees.create(
        fixture.admin,
        EmployeeDraft(
          name: 'Kamal Fernando',
          basicSalary: Money.fromMajor(45000),
        ),
      );
      await fixture.salaries.recordAdvance(
        fixture.admin,
        employeeId: employeeId,
        amount: Money.fromMajor(6000),
      );

      var snapshot = await live.load();
      expect(snapshot.outstandingEmployeeAdvances, Money.fromMajor(6000));
      // A draft salary is not a liability yet.
      expect(snapshot.unpaidSalaries, Money.zero);

      final salaryId = await fixture.salaries.createSalary(
        fixture.admin,
        SalaryDraft(
          employeeId: employeeId,
          periodYear: 2026,
          periodMonth: 11,
          basicSalary: Money.fromMajor(45000),
        ),
      );
      snapshot = await live.load();
      expect(snapshot.unpaidSalaries, Money.zero);

      await fixture.salaries.approveSalary(fixture.admin, salaryId: salaryId);

      snapshot = await live.load();
      // 45,000 earned less the 6,000 advance recovered by deduction.
      expect(snapshot.unpaidSalaries, Money.fromMajor(39000));
      expect(snapshot.outstandingEmployeeAdvances, Money.zero);
    });

    test('net profit comes from the journal and agrees with it', () async {
      await fixture.invoices.postInvoice(
        fixture.admin,
        InvoiceRequest(
          kind: InvoiceKind.shopInvoice,
          shopId: shopId,
          agentId: agentId,
          lines: [
            InvoiceLineRequest(
              productId: chargerId,
              quantity: 10,
              unitPrice: Money.fromMajor(3000),
            ),
          ],
        ),
      );

      final snapshot = await live.load();
      final report = await fixture.finance.profitAndLoss(
        from: DateTime(2026, 11).toUtc(),
        to: DateTime(
          2026,
          12,
        ).subtract(const Duration(milliseconds: 1)).toUtc(),
      );

      expect(snapshot.monthNetProfit, Money.fromMajor(10000));
      expect(snapshot.monthNetProfit, report.netProfit);
    });

    test('keeps a shop\'s counter sales out of the wholesale figure', () async {
      final customerLocationId = (await fixture.locations.byCode(
        AppConstants.customerLocationCode,
      )).id;

      await fixture.invoices.postInvoice(
        fixture.admin,
        InvoiceRequest(
          kind: InvoiceKind.shopInvoice,
          shopId: shopId,
          agentId: agentId,
          lines: [
            InvoiceLineRequest(
              productId: chargerId,
              quantity: 10,
              unitPrice: Money.fromMajor(3000),
            ),
          ],
        ),
      );
      await fixture.invoices.postInvoice(
        fixture.admin,
        InvoiceRequest(
          kind: InvoiceKind.retailSale,
          shopId: shopId,
          customerName: 'Walk-in',
          stockLinkage: MoveStockWithInvoice(
            documentType: StockDocumentType.retailSale,
            sourceLocationId: shopLocationId,
            destinationLocationId: customerLocationId,
          ),
          lines: [
            InvoiceLineRequest(
              productId: chargerId,
              quantity: 4,
              unitPrice: Money.fromMajor(3500),
            ),
          ],
        ),
      );

      final snapshot = await live.load();
      expect(snapshot.monthRetailSales, Money.fromMajor(14000));
      // Open question 7 in the business rules: retail is reported on its own
      // line so it can be excluded from company revenue if that is the
      // answer. It is not silently folded into the wholesale figure.
      expect(snapshot.monthRetailSales, isNot(equals(snapshot.monthSales)));
    });
  });
}

// --- Fixture helpers -------------------------------------------------------
// These insert rows directly, because the services that will create them
// properly are built in later phases. They exist to prove the *reporting*
// definitions are right, which is what this file is about.

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

Future<int> _insertCategory(TestHarness harness) {
  return harness.db
      .into(harness.db.categories)
      .insert(
        CategoriesCompanion.insert(
          name: 'Chargers',
          createdAt: harness.clock.nowUtc(),
          updatedAt: harness.clock.nowUtc(),
        ),
      );
}

Future<int> _insertProduct(
  TestHarness harness,
  int categoryId, {
  String sku = 'CHG-25W',
  int reorderLevel = 0,
}) {
  return harness.db
      .into(harness.db.products)
      .insert(
        ProductsCompanion.insert(
          sku: sku,
          name: '25W Charger',
          categoryId: categoryId,
          reorderLevel: Value(reorderLevel),
          createdAt: harness.clock.nowUtc(),
          updatedAt: harness.clock.nowUtc(),
        ),
      );
}

Future<int> _insertAgent(TestHarness harness, {Money? openingBalance}) {
  return harness.db
      .into(harness.db.agents)
      .insert(
        AgentsCompanion.insert(
          code: 'AG-001',
          name: 'Agent A',
          openingBalanceCents: Value((openingBalance ?? Money.zero).cents),
          createdAt: harness.clock.nowUtc(),
          updatedAt: harness.clock.nowUtc(),
        ),
      );
}

Future<int> _insertShop(TestHarness harness, {Money? openingBalance}) {
  return harness.db
      .into(harness.db.shops)
      .insert(
        ShopsCompanion.insert(
          code: 'SH-001',
          name: 'Shop A',
          openingBalanceCents: Value((openingBalance ?? Money.zero).cents),
          createdAt: harness.clock.nowUtc(),
          updatedAt: harness.clock.nowUtc(),
        ),
      );
}

Future<int> _locationByCode(TestHarness harness, String code) async {
  final row = await (harness.db.select(
    harness.db.inventoryLocations,
  )..where((l) => l.code.equals(code))).getSingle();
  return row.id;
}

Future<int> _insertLocation(
  TestHarness harness,
  String code,
  LocationKind kind, {
  int? agentId,
  int? shopId,
}) {
  return harness.db
      .into(harness.db.inventoryLocations)
      .insert(
        InventoryLocationsCompanion.insert(
          code: code,
          name: code,
          kind: kind,
          agentId: Value(agentId),
          shopId: Value(shopId),
          createdAt: harness.clock.nowUtc(),
        ),
      );
}

Future<void> _insertBalance(
  TestHarness harness,
  int locationId,
  int productId,
  int quantity,
  Money averageCost,
) async {
  await harness.db
      .into(harness.db.stockBalances)
      .insert(
        StockBalancesCompanion.insert(
          locationId: locationId,
          productId: productId,
          quantity: Value(quantity),
          averageCostCents: Value(averageCost.cents),
          updatedAt: harness.clock.nowUtc(),
        ),
      );
}

Future<int> _insertInvoice(
  TestHarness harness, {
  required int userId,
  required String number,
  required Money netTotal,
  required InvoiceStatus status,
  int? shopId,
  int? agentId,
  PartyType partyType = PartyType.shop,
  Money? costTotal,
  DateTime? invoiceDate,
}) {
  return harness.db
      .into(harness.db.invoices)
      .insert(
        InvoicesCompanion.insert(
          invoiceNumber: number,
          kind: partyType == PartyType.agent
              ? InvoiceKind.agentInvoice
              : InvoiceKind.shopInvoice,
          status: Value(status),
          invoiceDate: invoiceDate ?? harness.clock.nowUtc(),
          partyType: partyType,
          agentId: Value(agentId),
          shopId: Value(shopId),
          grossTotalCents: Value(netTotal.cents),
          netTotalCents: Value(netTotal.cents),
          costTotalCents: Value((costTotal ?? Money.zero).cents),
          createdByUserId: userId,
          createdAt: harness.clock.nowUtc(),
          postedAt: Value(
            status == InvoiceStatus.posted ? harness.clock.nowUtc() : null,
          ),
        ),
      );
}

Future<int> _insertPayment(
  TestHarness harness, {
  required int userId,
  required String number,
  required Money amount,
  required PaymentMethod method,
  required PaymentStatus status,
  int? shopId,
  int? agentId,
  int? allocateToInvoiceId,
}) async {
  final paymentId = await harness.db
      .into(harness.db.payments)
      .insert(
        PaymentsCompanion.insert(
          receiptNumber: number,
          direction: PaymentDirection.inbound,
          method: method,
          status: Value(status),
          paymentDate: harness.clock.nowUtc(),
          partyType: agentId != null ? PartyType.agent : PartyType.shop,
          agentId: Value(agentId),
          shopId: Value(shopId),
          amountCents: amount.cents,
          allocatedCents: Value(allocateToInvoiceId == null ? 0 : amount.cents),
          createdByUserId: userId,
          createdAt: harness.clock.nowUtc(),
          clearedAt: Value(
            status == PaymentStatus.cleared ? harness.clock.nowUtc() : null,
          ),
        ),
      );

  if (allocateToInvoiceId != null) {
    await harness.db
        .into(harness.db.paymentAllocations)
        .insert(
          PaymentAllocationsCompanion.insert(
            paymentId: paymentId,
            invoiceId: allocateToInvoiceId,
            amountCents: amount.cents,
            createdByUserId: userId,
            createdAt: harness.clock.nowUtc(),
          ),
        );
  }
  return paymentId;
}

Future<int> _insertCheque(
  TestHarness harness, {
  required int paymentId,
  required int userId,
}) {
  return harness.db
      .into(harness.db.cheques)
      .insert(
        ChequesCompanion.insert(
          paymentId: paymentId,
          chequeNumber: '123456',
          bankName: 'Commercial Bank',
          chequeDate: harness.clock.nowUtc(),
          updatedByUserId: Value(userId),
          createdAt: harness.clock.nowUtc(),
          updatedAt: harness.clock.nowUtc(),
        ),
      );
}

Future<int> _insertExpense(
  TestHarness harness, {
  required int userId,
  required int categoryId,
  required String number,
  required Money amount,
  required InvoiceStatus status,
  DateTime? expenseDate,
}) {
  return harness.db
      .into(harness.db.expenses)
      .insert(
        ExpensesCompanion.insert(
          voucherNumber: number,
          expenseDate: expenseDate ?? harness.clock.nowUtc(),
          categoryId: categoryId,
          description: 'Lorry hire',
          amountCents: amount.cents,
          paymentMethod: PaymentMethod.cash,
          status: Value(status),
          createdByUserId: userId,
          createdAt: harness.clock.nowUtc(),
        ),
      );
}
