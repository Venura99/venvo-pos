import 'package:flutter_test/flutter_test.dart';
import 'package:venvo_core/core/constants/app_constants.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/services/app_paths.dart';
import 'package:venvo_core/core/services/document_pdf_service.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/agents/domain/agent_models.dart';
import 'package:venvo_core/features/categories/domain/category_models.dart';
import 'package:venvo_core/features/employees/domain/employee_models.dart';
import 'package:venvo_core/features/expenses/domain/expense_models.dart';
import 'package:venvo_core/features/inventory/domain/stock_models.dart';
import 'package:venvo_core/features/invoices/data/invoice_service.dart';
import 'package:venvo_core/features/invoices/domain/invoice_models.dart';
import 'package:venvo_core/features/payments/domain/payment_models.dart';
import 'package:venvo_core/features/petty_cash/domain/petty_cash_models.dart';
import 'package:venvo_core/features/products/domain/product_models.dart';
import 'package:venvo_core/features/reports/data/report_export_service.dart';
import 'package:venvo_core/features/reports/domain/report_catalogue.dart';
import 'package:venvo_core/features/reports/domain/report_models.dart';
import 'package:venvo_core/features/returns/domain/return_models.dart';
import 'package:venvo_core/features/salaries/domain/salary_models.dart';
import 'package:venvo_core/features/shops/domain/shop_models.dart';

import '../helpers/master_data_fixtures.dart';
import '../helpers/test_harness.dart';

/// The eighteen reports.
///
/// The thing being proved throughout: a report agrees with the screen it
/// corresponds to. A report is what gets printed and taken to a meeting, so a
/// "collections" total that counted pending cheques, or an "outstanding"
/// figure that ignored credit notes, would be worse than no report at all.
void main() {
  late MasterDataFixture fixture;
  late int chargerId;
  late int cableId;
  late int categoryId;
  late int warehouseId;
  late int agentId;
  late int agentLocationId;
  late int shopId;
  late int shopLocationId;
  late int customerLocationId;

  setUp(() async {
    fixture = await MasterDataFixture.create(
      at: DateTime.utc(2026, 11, 15, 10),
    );

    categoryId = await fixture.categories.create(
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
        reorderLevel: 20,
      ),
    );
    cableId = await fixture.products.create(
      fixture.admin,
      ProductDraft(
        sku: 'CBL-C',
        name: 'Type-C Cable',
        categoryId: categoryId,
        costPrice: Money.fromMajor(300),
        wholesalePrice: Money.fromMajor(500),
        retailPrice: Money.fromMajor(650),
      ),
    );

    warehouseId = (await fixture.locations.mainWarehouse()).id;
    customerLocationId = (await fixture.locations.byCode(
      AppConstants.customerLocationCode,
    )).id;

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
  });

  tearDown(() => fixture.dispose());

  Future<ReportResult> run(String id, [ReportFilter? filter]) {
    final definition = reportById(id)!;
    return fixture.reports.run(definition, filter ?? const ReportFilter());
  }

  /// The value in a named column of a row, found by the column's label so the
  /// assertions do not break every time a column is inserted.
  ReportValue cell(ReportResult report, int rowIndex, String columnLabel) {
    final index = report.columns.indexWhere(
      (column) => column.label == columnLabel,
    );
    expect(index, isNot(-1), reason: 'no column called "$columnLabel"');
    return report.rows[rowIndex].values[index];
  }

  ReportValue total(ReportResult report, String columnLabel) {
    final index = report.columns.indexWhere(
      (column) => column.label == columnLabel,
    );
    expect(index, isNot(-1), reason: 'no column called "$columnLabel"');
    return report.totals![index];
  }

  Future<void> stockTheWarehouse({int quantity = 500}) {
    return fixture.postOpeningStock(
      locationId: warehouseId,
      productId: chargerId,
      quantity: quantity,
      unitCost: Money.fromMajor(2000),
    );
  }

  Future<void> supplyTheShop({int quantity = 100}) async {
    await fixture.stockLedger.postMovement(
      fixture.admin,
      StockMovementRequest(
        documentType: StockDocumentType.warehouseToAgent,
        sourceLocationId: warehouseId,
        destinationLocationId: agentLocationId,
        lines: [StockMovementLine(productId: chargerId, quantity: quantity)],
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
        lines: [StockMovementLine(productId: chargerId, quantity: quantity)],
      ),
    );
  }

  Future<InvoicePostResult> raiseShopInvoice({
    int quantity = 10,
    Money? unitPrice,
    DiscountType invoiceDiscountType = DiscountType.none,
    int invoiceDiscountValue = 0,
  }) {
    return fixture.invoices.postInvoice(
      fixture.admin,
      InvoiceRequest(
        kind: InvoiceKind.shopInvoice,
        shopId: shopId,
        agentId: agentId,
        invoiceDiscountType: invoiceDiscountType,
        invoiceDiscountValue: invoiceDiscountValue,
        discountReason: invoiceDiscountType == DiscountType.none
            ? null
            : 'Volume deal',
        lines: [
          InvoiceLineRequest(
            productId: chargerId,
            quantity: quantity,
            unitPrice: unitPrice ?? Money.fromMajor(3000),
          ),
        ],
      ),
    );
  }

  group('the catalogue', () {
    test('has the eighteen reports the brief asks for', () {
      expect(kReports, hasLength(18));

      expect(kReports.where((r) => r.group == ReportGroup.sales), hasLength(5));
      expect(kReports.where((r) => r.group == ReportGroup.stock), hasLength(5));
      expect(kReports.where((r) => r.group == ReportGroup.money), hasLength(4));
      expect(
        kReports.where((r) => r.group == ReportGroup.finance),
        hasLength(4),
      );

      // Every id is unique and resolvable, which is what the screen and the
      // export filenames rely on.
      expect(kReports.map((r) => r.id).toSet(), hasLength(18));
      for (final report in kReports) {
        expect(reportById(report.id), same(report));
      }
    });

    test('every report runs on an empty database without throwing', () async {
      for (final definition in kReports) {
        final result = await fixture.reports.run(
          definition,
          const ReportFilter(),
        );
        expect(
          result.title,
          definition.title,
          reason: '${definition.id} returned the wrong title',
        );
        // A report with no data still has its columns and its caveats, so the
        // page explains itself rather than being blank.
        expect(result.columns, isNotEmpty, reason: definition.id);
      }
    });

    test('a report needs the same permission as the module it reads', () {
      expect(
        reportById(ReportIds.salaries)!.permission,
        Permissions.salaryView,
      );
      expect(
        reportById(ReportIds.profitAndLoss)!.permission,
        Permissions.financialLedgerView,
      );
      expect(
        reportById(ReportIds.warehouseStock)!.permission,
        Permissions.stockView,
      );
      expect(
        reportById(ReportIds.collections)!.permission,
        Permissions.paymentView,
      );
    });
  });

  group('sales reports', () {
    test('daily sales shows gross, discount, net, cost and margin', () async {
      await stockTheWarehouse();
      await supplyTheShop();
      // 10 at Rs. 3,000 with 10% off: Rs. 30,000 gross, Rs. 27,000 net, on
      // goods that cost Rs. 20,000.
      await raiseShopInvoice(
        quantity: 10,
        invoiceDiscountType: DiscountType.percentage,
        invoiceDiscountValue: 1000,
      );

      final report = await run(ReportIds.dailySales);

      expect(report.rows, hasLength(1));
      expect(cell(report, 0, 'Invoices').number, 1);
      expect(cell(report, 0, 'Gross').money, Money.fromMajor(30000));
      expect(cell(report, 0, 'Discount').money, Money.fromMajor(3000));
      expect(cell(report, 0, 'Net').money, Money.fromMajor(27000));
      expect(cell(report, 0, 'Cost').money, Money.fromMajor(20000));
      expect(cell(report, 0, 'Gross profit').money, Money.fromMajor(7000));
      // 7,000 of 27,000 is 25.93%.
      expect(cell(report, 0, 'Margin').bps, 2593);

      expect(total(report, 'Net').money, Money.fromMajor(27000));
      expect(total(report, 'Gross profit').money, Money.fromMajor(7000));
      // The totals row recomputes the margin rather than summing margins,
      // which would be meaningless.
      expect(total(report, 'Margin').bps, 2593);
    });

    test('leaves retail sales out of the wholesale figures', () async {
      await stockTheWarehouse();
      await supplyTheShop();
      await raiseShopInvoice(quantity: 10);

      // The shop sells 5 of those over its own counter.
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
              quantity: 5,
              unitPrice: Money.fromMajor(3500),
            ),
          ],
        ),
      );

      final report = await run(ReportIds.dailySales);

      // The wholesale supply only. Adding the shop's counter sales would
      // count the same goods as revenue twice.
      expect(cell(report, 0, 'Net').money, Money.fromMajor(30000));
      expect(cell(report, 0, 'Invoices').number, 1);
      expect(
        report.notes.any(
          (note) => note.text.contains('counted as revenue twice'),
        ),
        isTrue,
      );
    });

    test('excludes a cancelled invoice', () async {
      await stockTheWarehouse();
      await supplyTheShop();
      final invoice = await raiseShopInvoice(quantity: 10);
      await raiseShopInvoice(quantity: 4);
      await fixture.invoices.cancelInvoice(
        fixture.admin,
        invoiceId: invoice.invoiceId,
        reason: 'Duplicate',
      );

      final report = await run(ReportIds.dailySales);
      expect(cell(report, 0, 'Invoices').number, 1);
      expect(cell(report, 0, 'Net').money, Money.fromMajor(12000));
    });

    test('monthly sales rolls the days up', () async {
      await stockTheWarehouse();
      await supplyTheShop();
      await raiseShopInvoice(quantity: 10);
      await raiseShopInvoice(quantity: 5);

      final report = await run(ReportIds.monthlySales);

      expect(report.rows, hasLength(1));
      expect(cell(report, 0, 'Invoices').number, 2);
      expect(cell(report, 0, 'Net').money, Money.fromMajor(45000));
      expect(cell(report, 0, 'Month').kind, ReportValueKind.month);
    });

    test('agent-wise sales reports the balance as it stands now', () async {
      await stockTheWarehouse();
      await fixture.stockLedger.postMovement(
        fixture.admin,
        StockMovementRequest(
          documentType: StockDocumentType.warehouseToAgent,
          sourceLocationId: warehouseId,
          destinationLocationId: agentLocationId,
          lines: [StockMovementLine(productId: chargerId, quantity: 50)],
        ),
      );
      final invoice = await fixture.invoices.postInvoice(
        fixture.admin,
        InvoiceRequest(
          kind: InvoiceKind.agentInvoice,
          agentId: agentId,
          lines: [
            InvoiceLineRequest(
              productId: chargerId,
              quantity: 20,
              unitPrice: Money.fromMajor(2500),
            ),
          ],
        ),
      );
      // Half of it paid in cash.
      await fixture.payments.recordPayment(
        fixture.admin,
        PaymentRequest(
          direction: PaymentDirection.inbound,
          method: PaymentMethod.cash,
          amount: Money.fromMajor(25000),
          agentId: agentId,
          allocations: [
            PaymentAllocationRequest(
              invoiceId: invoice.invoiceId,
              amount: Money.fromMajor(25000),
            ),
          ],
        ),
      );

      final report = await run(ReportIds.agentSales);

      expect(report.rows, hasLength(1));
      expect(cell(report, 0, 'Agent').text, 'Agent A');
      expect(cell(report, 0, 'Net billed').money, Money.fromMajor(50000));
      expect(cell(report, 0, 'Outstanding now').money, Money.fromMajor(25000));
      // And it agrees with the invoice register.
      expect(
        cell(report, 0, 'Outstanding now').money,
        await fixture.payments.outstandingOf(invoice.invoiceId),
      );
    });

    test('shop-wise sales covers only the wholesale supply', () async {
      await stockTheWarehouse();
      await supplyTheShop();
      await raiseShopInvoice(quantity: 10);

      final report = await run(ReportIds.shopSales);

      expect(report.rows, hasLength(1));
      expect(cell(report, 0, 'Shop').text, 'Shop A');
      expect(cell(report, 0, 'Net billed').money, Money.fromMajor(30000));
      expect(cell(report, 0, 'Gross profit').money, Money.fromMajor(10000));
    });

    test(
      'product-wise sales prices at what was billed, not at today\'s price',
      () async {
        await stockTheWarehouse();
        await supplyTheShop();
        await raiseShopInvoice(quantity: 10);

        // Somebody raises the catalogue price afterwards.
        await fixture.products.update(
          fixture.admin,
          ProductDraft(
            id: chargerId,
            sku: 'CHG-25W',
            name: '25W Charger',
            categoryId: categoryId,
            costPrice: Money.fromMajor(9000),
            wholesalePrice: Money.fromMajor(9500),
            retailPrice: Money.fromMajor(9900),
          ),
        );

        final report = await run(ReportIds.productSales);

        expect(report.rows, hasLength(1));
        expect(cell(report, 0, 'Units sold').number, 10);
        expect(cell(report, 0, 'Net revenue').money, Money.fromMajor(30000));
        // The cost as snapshotted on the invoice line, not the new catalogue
        // cost - a later re-pricing cannot rewrite what was earned.
        expect(cell(report, 0, 'Cost').money, Money.fromMajor(20000));
        expect(cell(report, 0, 'Gross profit').money, Money.fromMajor(10000));
      },
    );

    test('narrows by period, agent and category', () async {
      await stockTheWarehouse();
      await supplyTheShop();
      await raiseShopInvoice(quantity: 10);

      final future = await run(
        ReportIds.dailySales,
        ReportFilter(from: DateTime.utc(2030)),
      );
      expect(future.rows, isEmpty);

      final covering = await run(
        ReportIds.dailySales,
        ReportFilter(from: DateTime.utc(2026), to: DateTime.utc(2027)),
      );
      expect(covering.rows, hasLength(1));

      final otherAgent = await fixture.agents.create(
        fixture.admin,
        const AgentDraft(name: 'Agent B'),
      );
      expect(
        (await run(
          ReportIds.agentSales,
          ReportFilter(agentId: otherAgent),
        )).rows,
        isEmpty,
      );

      final otherCategory = await fixture.categories.create(
        fixture.admin,
        const CategoryDraft(name: 'Batteries'),
      );
      expect(
        (await run(
          ReportIds.productSales,
          ReportFilter(categoryId: otherCategory),
        )).rows,
        isEmpty,
      );
    });
  });

  group('stock reports', () {
    test('warehouse stock values what is there at average cost', () async {
      await stockTheWarehouse(quantity: 100);

      final report = await run(ReportIds.warehouseStock);

      expect(report.rows, hasLength(1));
      expect(cell(report, 0, 'Units').number, 100);
      expect(cell(report, 0, 'Average cost').money, Money.fromMajor(2000));
      expect(cell(report, 0, 'Value').money, Money.fromMajor(200000));
      expect(cell(report, 0, 'Reorder at').number, 20);
      expect(total(report, 'Value').money, Money.fromMajor(200000));
    });

    test('agent-wise and shop-wise stock agree with the ledger', () async {
      await stockTheWarehouse();
      await supplyTheShop(quantity: 100);
      // The agent keeps 40 back.
      await fixture.stockLedger.postMovement(
        fixture.admin,
        StockMovementRequest(
          documentType: StockDocumentType.warehouseToAgent,
          sourceLocationId: warehouseId,
          destinationLocationId: agentLocationId,
          lines: [StockMovementLine(productId: chargerId, quantity: 40)],
        ),
      );

      final agents = await run(ReportIds.agentStock);
      expect(agents.rows, hasLength(1));
      expect(cell(agents, 0, 'Units held').number, 40);
      expect(
        cell(agents, 0, 'Units held').number,
        await fixture.stockLedger.balanceOf(
          locationId: agentLocationId,
          productId: chargerId,
        ),
      );

      final shops = await run(ReportIds.shopStock);
      expect(cell(shops, 0, 'Units held').number, 100);
      expect(cell(shops, 0, 'Value at cost').money, Money.fromMajor(200000));
    });

    test(
      'stock movement reads the ledger and leaves counterparties out',
      () async {
        await stockTheWarehouse(quantity: 100);
        await supplyTheShop(quantity: 30);

        final report = await run(ReportIds.stockMovement);

        // Opening stock into the warehouse, out to the agent, in to the agent,
        // out to the shop, in to the shop: five rows at the business's own
        // locations. The supplier counterparty leg is not one of them.
        expect(report.rows, hasLength(5));
        expect(
          report.rows.every(
            (row) => !row.values[3].text!.toLowerCase().contains('supplier'),
          ),
          isTrue,
        );
        expect(total(report, 'In').number, 160);
        expect(total(report, 'Out').number, 60);
        // The balance column is a running figure, so it is not totalled.
        expect(total(report, 'Balance after').isEmpty, isTrue);
      },
    );

    test('stock valuation splits sellable from damaged', () async {
      await stockTheWarehouse(quantity: 100);
      final damaged = (await fixture.locations.byCode(
        AppConstants.damagedLocationCode,
      )).id;
      await fixture.stockLedger.postMovement(
        fixture.admin,
        StockMovementRequest(
          documentType: StockDocumentType.damageWriteOff,
          sourceLocationId: warehouseId,
          destinationLocationId: damaged,
          lines: [StockMovementLine(productId: chargerId, quantity: 10)],
        ),
      );

      final report = await run(ReportIds.stockValuation);

      expect(report.rows, hasLength(1));
      expect(cell(report, 0, 'Warehouse').number, 90);
      expect(cell(report, 0, 'Damaged').number, 10);
      expect(cell(report, 0, 'Sellable value').money, Money.fromMajor(180000));
      expect(cell(report, 0, 'Damaged value').money, Money.fromMajor(20000));
    });

    test('a product with nothing anywhere is left out', () async {
      await stockTheWarehouse();

      final report = await run(ReportIds.stockValuation);
      // The cable exists but has never been stocked.
      expect(report.rows, hasLength(1));
      expect(cell(report, 0, 'SKU').text, 'CHG-25W');
      expect(cableId, isNotNull);
    });
  });

  group('money reports', () {
    test(
      'collections counts cleared money and lists pending separately',
      () async {
        await stockTheWarehouse();
        await supplyTheShop();
        final invoice = await raiseShopInvoice(quantity: 10);

        await fixture.payments.recordPayment(
          fixture.admin,
          PaymentRequest(
            direction: PaymentDirection.inbound,
            method: PaymentMethod.cash,
            amount: Money.fromMajor(10000),
            shopId: shopId,
            allocations: [
              PaymentAllocationRequest(
                invoiceId: invoice.invoiceId,
                amount: Money.fromMajor(10000),
              ),
            ],
          ),
        );
        await fixture.payments.recordPayment(
          fixture.admin,
          PaymentRequest(
            direction: PaymentDirection.inbound,
            method: PaymentMethod.cheque,
            amount: Money.fromMajor(20000),
            shopId: shopId,
            cheque: ChequeDetails(
              chequeNumber: 'CHQ-1',
              bankName: 'Commercial Bank',
              chequeDate: DateTime.utc(2026, 11, 15),
            ),
          ),
        );

        final report = await run(ReportIds.collections);

        expect(report.rows, hasLength(2));
        // Rule M5: the cheque is not a collection until it clears.
        expect(total(report, 'Collected').money, Money.fromMajor(10000));
        expect(
          total(report, 'Awaiting clearance').money,
          Money.fromMajor(20000),
        );
        expect(
          report.notes.any(
            (note) => note.text.contains('cleared money counts'),
          ),
          isTrue,
        );
      },
    );

    test('an unapplied receipt is shown as the party\'s advance', () async {
      await fixture.payments.recordPayment(
        fixture.admin,
        PaymentRequest(
          direction: PaymentDirection.inbound,
          method: PaymentMethod.cash,
          amount: Money.fromMajor(5000),
          shopId: shopId,
        ),
      );

      final report = await run(ReportIds.collections);
      expect(total(report, 'Collected').money, Money.fromMajor(5000));
      expect(total(report, 'Unapplied').money, Money.fromMajor(5000));
    });

    test('outstanding balances agree with the party screens', () async {
      await stockTheWarehouse();
      await supplyTheShop();
      final invoice = await raiseShopInvoice(quantity: 10);
      await fixture.payments.recordPayment(
        fixture.admin,
        PaymentRequest(
          direction: PaymentDirection.inbound,
          method: PaymentMethod.cash,
          amount: Money.fromMajor(12000),
          shopId: shopId,
          allocations: [
            PaymentAllocationRequest(
              invoiceId: invoice.invoiceId,
              amount: Money.fromMajor(12000),
            ),
          ],
        ),
      );

      final report = await run(ReportIds.outstanding);
      final shopRow = report.rows.indexWhere(
        (row) => row.values[1].text == 'Shop A',
      );
      expect(shopRow, isNot(-1));

      expect(cell(report, shopRow, 'Billed').money, Money.fromMajor(30000));
      expect(cell(report, shopRow, 'Settled').money, Money.fromMajor(12000));
      expect(
        cell(report, shopRow, 'Outstanding').money,
        Money.fromMajor(18000),
      );

      // The same number the shop screen shows.
      final shops = await fixture.shops.watchShops(const ShopFilter()).first;
      expect(
        cell(report, shopRow, 'Outstanding').money,
        shops.single.outstandingBalance,
      );
    });

    test('a credit note reduces the outstanding figure', () async {
      await stockTheWarehouse();
      await supplyTheShop();
      final invoice = await raiseShopInvoice(quantity: 10);
      final itemId = (await fixture.returns.returnableLines(
        invoice.invoiceId,
      )).single.invoiceItemId;

      final returned = await fixture.returns.postReturn(
        fixture.admin,
        ReturnDraft(
          route: ReturnRoute.shopToAgent,
          fromLocationId: shopLocationId,
          toLocationId: agentLocationId,
          agentId: agentId,
          shopId: shopId,
          reason: ReturnReason.excessStock,
          originInvoiceId: invoice.invoiceId,
          lines: [
            ReturnLineDraft(
              productId: chargerId,
              quantity: 2,
              originInvoiceItemId: itemId,
            ),
          ],
        ),
      );
      final items = await (fixture.db.select(
        fixture.db.returnItems,
      )..where((row) => row.returnId.equals(returned.returnId))).get();
      await fixture.returns.recordInspection(
        fixture.admin,
        InspectionRequest(
          returnId: returned.returnId,
          decisions: [
            InspectionDecision(
              returnItemId: items.single.id,
              acceptedQuantity: 2,
            ),
          ],
        ),
      );
      final creditNoteId = await fixture.returns.issueCreditNote(
        fixture.admin,
        returnId: returned.returnId,
      );
      await fixture.returns.applyToInvoice(
        fixture.admin,
        creditNoteId: creditNoteId,
        invoiceId: invoice.invoiceId,
        amount: Money.fromMajor(6000),
      );

      final report = await run(ReportIds.outstanding);
      final shopRow = report.rows.indexWhere(
        (row) => row.values[1].text == 'Shop A',
      );
      expect(
        cell(report, shopRow, 'Credit notes').money,
        Money.fromMajor(6000),
      );
      expect(
        cell(report, shopRow, 'Outstanding').money,
        Money.fromMajor(24000),
      );
    });

    test('discounts report keeps the input beside the cash amount', () async {
      await stockTheWarehouse();
      await supplyTheShop();
      await raiseShopInvoice(
        quantity: 10,
        invoiceDiscountType: DiscountType.percentage,
        invoiceDiscountValue: 1000,
      );

      final report = await run(ReportIds.discounts);

      expect(report.rows, hasLength(1));
      expect(cell(report, 0, 'On').text, 'The whole invoice');
      // "10%" is preserved, not just the Rs. 3,000 it came to.
      expect(cell(report, 0, 'As entered').text, '10%');
      expect(cell(report, 0, 'Applied to').money, Money.fromMajor(30000));
      expect(cell(report, 0, 'Discount').money, Money.fromMajor(3000));
      expect(cell(report, 0, 'Effective').bps, 1000);
      expect(cell(report, 0, 'Given by').text, 'Nimal Perera');
      expect(cell(report, 0, 'Past ceiling').text, 'No');
    });

    test('returns report shows the inspection split and the credit', () async {
      await stockTheWarehouse();
      await supplyTheShop();
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
              quantity: 10,
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
              acceptedQuantity: 6,
              damagedQuantity: 3,
              scrappedQuantity: 1,
            ),
          ],
        ),
      );

      final report = await run(ReportIds.returns);

      expect(report.rows, hasLength(1));
      expect(cell(report, 0, 'Units back').number, 10);
      expect(cell(report, 0, 'Accepted').number, 6);
      expect(cell(report, 0, 'Damaged').number, 3);
      expect(cell(report, 0, 'Scrapped').number, 1);
      expect(cell(report, 0, 'Value').money, Money.fromMajor(30000));
      expect(cell(report, 0, 'Invoice').text, 'not traced');
      expect(cell(report, 0, 'Status').text, 'Inspected');
    });

    test('a cancelled return is listed but counts nothing', () async {
      await stockTheWarehouse();
      await supplyTheShop();
      final posted = await fixture.returns.postReturn(
        fixture.admin,
        ReturnDraft(
          route: ReturnRoute.shopToAgent,
          fromLocationId: shopLocationId,
          toLocationId: agentLocationId,
          agentId: agentId,
          shopId: shopId,
          reason: ReturnReason.excessStock,
          lines: [
            ReturnLineDraft(
              productId: chargerId,
              quantity: 5,
              unitPrice: Money.fromMajor(3000),
            ),
          ],
        ),
      );
      await fixture.returns.cancelReturn(
        fixture.admin,
        returnId: posted.returnId,
        reason: 'Never arrived',
      );

      final report = await run(ReportIds.returns);
      expect(report.rows, hasLength(1));
      expect(cell(report, 0, 'Status').text, 'Cancelled');
      expect(total(report, 'Units back').number, 0);
      expect(total(report, 'Value').money, Money.zero);
    });
  });

  group('finance reports', () {
    Future<void> openFloat([Money amount = const Money(2000000)]) {
      return fixture.pettyCash.recordEntry(
        fixture.admin,
        PettyCashDraft(
          kind: PettyCashEntryKind.opening,
          amount: amount,
          description: 'Opening float',
        ),
      );
    }

    Future<int> transportCategory() async {
      final categories = await fixture.expenseQueries.watchCategories().first;
      return categories
          .firstWhere((c) => c.name.toLowerCase().contains('transport'))
          .id;
    }

    test('expenses report breaks the period down by category', () async {
      final transport = await transportCategory();
      await openFloat();
      await fixture.expenses.postExpense(
        fixture.admin,
        ExpenseDraft(
          categoryId: transport,
          description: 'Lorry hire',
          amount: Money.fromMajor(5000),
          paymentMethod: PaymentMethod.cash,
        ),
      );
      await fixture.expenses.postExpense(
        fixture.admin,
        ExpenseDraft(
          categoryId: transport,
          description: 'Tea',
          amount: Money.fromMajor(1000),
          paymentMethod: PaymentMethod.cash,
          fromPettyCash: true,
        ),
      );

      final report = await run(ReportIds.expenses);

      expect(report.rows, hasLength(1));
      expect(cell(report, 0, 'Vouchers').number, 2);
      expect(cell(report, 0, 'Spent').money, Money.fromMajor(6000));
      expect(
        cell(report, 0, 'Of which petty cash').money,
        Money.fromMajor(1000),
      );
      // One category, so it is all of the spend.
      expect(cell(report, 0, 'Share').bps, Money.bpsScale);
    });

    test('petty cash report reads as a cash book', () async {
      await openFloat(Money.fromMajor(20000));
      final transport = await transportCategory();
      await fixture.expenses.postExpense(
        fixture.admin,
        ExpenseDraft(
          categoryId: transport,
          description: 'Parking',
          amount: Money.fromMajor(500),
          paymentMethod: PaymentMethod.cash,
          fromPettyCash: true,
        ),
      );

      final report = await run(ReportIds.pettyCash);

      expect(report.rows, hasLength(2));
      // Newest first, so the expense is the top row.
      expect(cell(report, 0, 'Out').money, Money.fromMajor(500));
      expect(cell(report, 0, 'Balance').money, Money.fromMajor(19500));
      expect(cell(report, 1, 'In').money, Money.fromMajor(20000));
      // The totals row shows where the float stands, not a sum of balances.
      expect(total(report, 'Balance').money, Money.fromMajor(19500));
      expect(
        total(report, 'Balance').money,
        await fixture.pettyCash.floatBalance(),
      );
    });

    test(
      'salaries report shows the wage bill and what is still owed',
      () async {
        final employeeId = await fixture.employees.create(
          fixture.admin,
          EmployeeDraft(
            name: 'Kamal Fernando',
            designation: 'Driver',
            basicSalary: Money.fromMajor(45000),
          ),
        );
        await fixture.salaries.recordAdvance(
          fixture.admin,
          employeeId: employeeId,
          amount: Money.fromMajor(10000),
        );
        final salaryId = await fixture.salaries.createSalary(
          fixture.admin,
          SalaryDraft(
            employeeId: employeeId,
            periodYear: 2026,
            periodMonth: 11,
            basicSalary: Money.fromMajor(45000),
          ),
        );
        await fixture.salaries.approveSalary(fixture.admin, salaryId: salaryId);
        await fixture.salaries.paySalary(
          fixture.admin,
          salaryId: salaryId,
          amount: Money.fromMajor(20000),
        );

        final report = await run(ReportIds.salaries);

        expect(report.rows, hasLength(1));
        expect(cell(report, 0, 'Basic').money, Money.fromMajor(45000));
        expect(
          cell(report, 0, 'Advance recovered').money,
          Money.fromMajor(10000),
        );
        expect(cell(report, 0, 'Net').money, Money.fromMajor(35000));
        expect(cell(report, 0, 'Paid').money, Money.fromMajor(20000));
        expect(cell(report, 0, 'Still owed').money, Money.fromMajor(15000));
        expect(cell(report, 0, 'Status').text, 'Part paid');

        // And it agrees with the salary register.
        final totals = await fixture.salaryQueries.totals(const SalaryFilter());
        expect(total(report, 'Still owed').money, totals.outstanding);
      },
    );

    test('the salary period filter compares months, not timestamps', () async {
      final employeeId = await fixture.employees.create(
        fixture.admin,
        EmployeeDraft(name: 'Kamal', basicSalary: Money.fromMajor(45000)),
      );
      await fixture.salaries.createSalary(
        fixture.admin,
        SalaryDraft(
          employeeId: employeeId,
          periodYear: 2026,
          periodMonth: 9,
          basicSalary: Money.fromMajor(45000),
        ),
      );
      await fixture.salaries.createSalary(
        fixture.admin,
        SalaryDraft(
          employeeId: employeeId,
          periodYear: 2026,
          periodMonth: 11,
          basicSalary: Money.fromMajor(45000),
        ),
      );

      final october = await run(
        ReportIds.salaries,
        ReportFilter(from: DateTime(2026, 10), to: DateTime(2026, 12, 31)),
      );
      expect(october.rows, hasLength(1));
      expect(october.rows.single.values[1].date!.month, 11);
    });

    test(
      'profit and loss is read from the journal and says if it balances',
      () async {
        await stockTheWarehouse();
        await supplyTheShop();
        await raiseShopInvoice(quantity: 10);
        final transport = await transportCategory();
        await fixture.expenses.postExpense(
          fixture.admin,
          ExpenseDraft(
            categoryId: transport,
            description: 'Lorry hire',
            amount: Money.fromMajor(5000),
            paymentMethod: PaymentMethod.cash,
          ),
        );

        final report = await run(ReportIds.profitAndLoss);

        Money line(String label) => report.rows
            .firstWhere((row) => row.values[0].text == label)
            .values[1]
            .money!;

        expect(line('Revenue'), Money.fromMajor(30000));
        expect(line('Cost of goods sold'), Money.fromMajor(-20000));
        expect(line('Gross profit'), Money.fromMajor(10000));
        expect(line('Operating expenses'), Money.fromMajor(-5000));
        expect(line('Net profit'), Money.fromMajor(5000));

        // The same figure the ledger service gives, because it is the same
        // query behind both.
        final direct = await fixture.finance.profitAndLoss();
        expect(line('Net profit'), direct.netProfit);

        expect(
          report.notes.any((note) => note.text.contains('balances')),
          isTrue,
        );
      },
    );
  });

  group('export', () {
    late ReportExportService service;

    setUp(() async {
      final harness = await TestHarness.create(withDataDirectory: true);
      addTearDown(harness.dispose);
      service = ReportExportService(
        paths: await AppPaths.at(harness.bootstrap.requirePaths.root),
        business: const BusinessIdentity(
          name: 'Venvo Global (Pvt) Ltd',
          address: '12 Main Street, Colombo',
          phone: '011 2345678',
        ),
      );
    });

    test('a PDF is produced for every report, empty or not', () async {
      for (final definition in kReports) {
        final result = await fixture.reports.run(
          definition,
          const ReportFilter(),
        );
        final bytes = await service.buildPdf(result);
        expect(
          String.fromCharCodes(bytes.take(5)),
          '%PDF-',
          reason: '${definition.id} did not produce a PDF',
        );
        expect(bytes.length, greaterThan(800), reason: definition.id);
      }
    });

    test('the CSV holds numbers a spreadsheet can add up', () async {
      await stockTheWarehouse();
      await supplyTheShop();
      await raiseShopInvoice(
        quantity: 10,
        invoiceDiscountType: DiscountType.percentage,
        invoiceDiscountValue: 1000,
      );

      final result = await run(ReportIds.dailySales);
      final csv = service.buildCsv(result);

      expect(csv, contains('Venvo Global (Pvt) Ltd'));
      expect(csv, contains('Daily sales'));
      // Bare numbers, not "Rs. 27,000.00", so a spreadsheet reads them back
      // as numbers rather than as text.
      expect(csv, contains('27000.00'));
      expect(csv, isNot(contains('Rs.')));
      // The caveats travel with the figures.
      expect(csv, contains('How to read this report'));
      expect(csv, contains('Total'));
    });

    test('the period and the caveats are on the page', () async {
      final result = await run(
        ReportIds.dailySales,
        ReportFilter(
          from: DateTime.utc(2026, 11),
          to: DateTime.utc(2026, 11, 30),
        ),
      );
      final csv = service.buildCsv(result);

      expect(csv, contains('1 Nov 2026 to 30 Nov 2026'));
      expect(csv, contains('counted as revenue twice'));
    });

    test('an all-time report says so rather than leaving it blank', () async {
      final result = await run(ReportIds.dailySales);
      expect(service.buildCsv(result), contains('All time'));
    });

    test('files are written under the exports folder, stamped', () async {
      await stockTheWarehouse();
      final result = await run(ReportIds.warehouseStock);

      final pdf = await service.savePdf(
        result,
        reportId: ReportIds.warehouseStock,
      );
      final csv = await service.saveCsv(
        result,
        reportId: ReportIds.warehouseStock,
      );

      expect(pdf.existsSync(), isTrue);
      expect(csv.existsSync(), isTrue);
      expect(pdf.path, contains('reports'));
      expect(pdf.uri.pathSegments.last, startsWith('stock-warehouse-'));
      expect(pdf.uri.pathSegments.last, endsWith('.pdf'));
      expect(csv.uri.pathSegments.last, endsWith('.csv'));
      // A UTF-8 byte-order mark, so Excel on Windows reads the separators
      // rather than mangling them.
      expect(csv.readAsBytesSync().take(3), [0xEF, 0xBB, 0xBF]);
    });
  });
}
