import 'package:flutter_test/flutter_test.dart';
import 'package:venvo_core/core/constants/app_constants.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/errors/failures.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/agents/domain/agent_models.dart';
import 'package:venvo_core/features/categories/domain/category_models.dart';
import 'package:venvo_core/features/finance/domain/finance_models.dart';
import 'package:venvo_core/features/inventory/domain/stock_models.dart';
import 'package:venvo_core/features/invoices/data/invoice_service.dart';
import 'package:venvo_core/features/invoices/domain/invoice_models.dart';
import 'package:venvo_core/features/payments/domain/payment_models.dart';
import 'package:venvo_core/features/products/domain/product_models.dart';
import 'package:venvo_core/features/returns/domain/return_models.dart';
import 'package:venvo_core/features/shops/domain/shop_models.dart';

import '../helpers/master_data_fixtures.dart';

/// The double-entry journal behind every figure.
///
/// The test that matters most is the last one in each group: after a run of
/// real business events, the trial balance still balances and no batch is
/// lopsided. If a posting anywhere in the application is wrong, that is where
/// it shows up.
void main() {
  late MasterDataFixture fixture;
  late int chargerId;
  late int warehouseId;
  late int agentId;
  late int agentLocationId;
  late int shopId;
  late int shopLocationId;
  late int customerLocationId;

  setUp(() async {
    fixture = await MasterDataFixture.create();

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
    customerLocationId = (await fixture.locations.byCode(
      AppConstants.customerLocationCode,
    )).id;
  });

  tearDown(() => fixture.dispose());

  Future<Money> account(String code) => fixture.finance.balanceOf(code);

  /// The invariant that every other assertion rests on.
  Future<void> expectJournalSound() async {
    expect(
      await fixture.finance.findUnbalancedBatches(),
      isEmpty,
      reason: 'every batch must have equal debits and credits',
    );
    final balance = await fixture.finance.trialBalance();
    expect(
      balance.totalDebits,
      balance.totalCredits,
      reason: 'the trial balance must balance',
    );
  }

  Future<void> stockTheWarehouse({
    int quantity = 100,
    Money unitCost = const Money(200000),
  }) {
    return fixture.postOpeningStock(
      locationId: warehouseId,
      productId: chargerId,
      quantity: quantity,
      unitCost: unitCost,
    );
  }

  Future<void> supplyTheShop({int quantity = 50}) async {
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
    ImmediatePayment? payment,
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
        payment: payment,
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

  group('the posting primitive', () {
    test('refuses a batch whose two sides disagree', () async {
      await expectLater(
        fixture.finance.post(
          actor: fixture.admin,
          sourceKind: EntityKind.setting,
          entryDate: DateTime.utc(2026, 11, 1),
          description: 'A deliberately lopsided posting',
          lines: [
            JournalLine.debit(AccountCodes.cashOnHand, Money.fromMajor(100)),
            JournalLine.credit(AccountCodes.bank, Money.fromMajor(90)),
          ],
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'finance.batch_must_balance',
          ),
        ),
      );
      // Nothing was written, so there is no lopsided batch to find.
      expect(await fixture.finance.findUnbalancedBatches(), isEmpty);
    });

    test('drops zero lines rather than making the caller check', () async {
      final batchId = await fixture.finance.post(
        actor: fixture.admin,
        sourceKind: EntityKind.setting,
        entryDate: DateTime.utc(2026, 11, 1),
        description: 'With a nil discount line',
        lines: const [
          JournalLine.debit(AccountCodes.cashOnHand, Money(10000)),
          JournalLine.debit(AccountCodes.salesDiscounts, Money.zero),
          JournalLine.credit(AccountCodes.ownersEquity, Money(10000)),
        ],
      );

      expect(batchId, startsWith('JRN-'));
      final rows = await fixture.finance
          .watchEntries(const FinancialLedgerFilter())
          .first;
      expect(rows.where((row) => row.batchId == batchId), hasLength(2));
      await expectJournalSound();
    });

    test('refuses a negative line, because a side is not a sign', () async {
      await expectLater(
        fixture.finance.post(
          actor: fixture.admin,
          sourceKind: EntityKind.setting,
          entryDate: DateTime.utc(2026, 11, 1),
          description: 'Negative debit',
          lines: [
            JournalLine.debit(AccountCodes.cashOnHand, Money.fromMajor(-100)),
            JournalLine.credit(
              AccountCodes.ownersEquity,
              Money.fromMajor(-100),
            ),
          ],
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('reverses a batch by mirroring it, and only once', () async {
      final batchId = await fixture.finance.post(
        actor: fixture.admin,
        sourceKind: EntityKind.setting,
        entryDate: DateTime.utc(2026, 11, 1),
        description: 'To be undone',
        lines: [
          JournalLine.debit(AccountCodes.cashOnHand, Money.fromMajor(500)),
          JournalLine.credit(AccountCodes.ownersEquity, Money.fromMajor(500)),
        ],
      );
      expect(await account(AccountCodes.cashOnHand), Money.fromMajor(500));

      await fixture.finance.reverse(
        actor: fixture.admin,
        batchId: batchId,
        reason: 'Entered in error',
      );

      expect(await account(AccountCodes.cashOnHand), Money.zero);
      await expectJournalSound();

      await expectLater(
        fixture.finance.reverse(
          actor: fixture.admin,
          batchId: batchId,
          reason: 'Again',
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'finance.reverse_once',
          ),
        ),
      );
    });
  });

  group('stock', () {
    test(
      'opening stock is the owner putting goods in, not a purchase',
      () async {
        await stockTheWarehouse(quantity: 100, unitCost: Money.fromMajor(2000));

        expect(await account(AccountCodes.inventory), Money.fromMajor(200000));
        // Credit balances read negative in the debits-positive convention.
        expect(
          await account(AccountCodes.ownersEquity),
          Money.fromMajor(-200000),
        );
        await expectJournalSound();
      },
    );

    test('moving goods between your own locations posts nothing', () async {
      await stockTheWarehouse();
      final before = await fixture.finance
          .watchEntries(const FinancialLedgerFilter())
          .first;

      await supplyTheShop();

      final after = await fixture.finance
          .watchEntries(const FinancialLedgerFilter())
          .first;
      // Nothing the business owns has changed, so the accounts do not move.
      expect(after.length, before.length);
      expect(await account(AccountCodes.inventory), Money.fromMajor(200000));
    });

    test('a write-off is a loss against inventory', () async {
      await stockTheWarehouse();
      final damaged = (await fixture.locations.byCode(
        AppConstants.damagedLocationCode,
      )).id;

      await fixture.stockLedger.postMovement(
        fixture.admin,
        StockMovementRequest(
          documentType: StockDocumentType.damageWriteOff,
          sourceLocationId: warehouseId,
          destinationLocationId: damaged,
          lines: [StockMovementLine(productId: chargerId, quantity: 5)],
        ),
      );

      expect(await account(AccountCodes.stockWriteOff), Money.fromMajor(10000));
      expect(await account(AccountCodes.inventory), Money.fromMajor(190000));
      await expectJournalSound();
    });

    test('cancelling a write-off mirrors it rather than guessing', () async {
      await stockTheWarehouse();
      final damaged = (await fixture.locations.byCode(
        AppConstants.damagedLocationCode,
      )).id;
      final posted = await fixture.stockLedger.postMovement(
        fixture.admin,
        StockMovementRequest(
          documentType: StockDocumentType.damageWriteOff,
          sourceLocationId: warehouseId,
          destinationLocationId: damaged,
          lines: [StockMovementLine(productId: chargerId, quantity: 5)],
        ),
      );

      await fixture.stockLedger.cancelMovement(
        fixture.admin,
        transactionId: posted.transactionId,
        reason: 'Goods were not damaged after all',
      );

      expect(await account(AccountCodes.stockWriteOff), Money.zero);
      expect(await account(AccountCodes.inventory), Money.fromMajor(200000));
      await expectJournalSound();
    });

    test(
      'cancelling opening stock returns it to equity, not to a loss',
      () async {
        final posted = await fixture.postOpeningStock(
          locationId: warehouseId,
          productId: chargerId,
          quantity: 10,
          unitCost: Money.fromMajor(2000),
        );

        await fixture.stockLedger.cancelMovement(
          fixture.admin,
          transactionId: posted.transactionId,
          reason: 'Entered twice',
        );

        expect(await account(AccountCodes.inventory), Money.zero);
        expect(await account(AccountCodes.ownersEquity), Money.zero);
        // The point of mirroring the original batch: nothing was booked as a
        // loss, which is what a document-type guess would have done.
        expect(await account(AccountCodes.stockWriteOff), Money.zero);
        await expectJournalSound();
      },
    );
  });

  group('invoices', () {
    test(
      'posts revenue at the full price with the discount beside it',
      () async {
        await stockTheWarehouse();
        await supplyTheShop();

        // 10 at Rs. 3,000 is Rs. 30,000 gross, 10% off is Rs. 27,000 net.
        await raiseShopInvoice(
          quantity: 10,
          invoiceDiscountType: DiscountType.percentage,
          invoiceDiscountValue: 1000,
        );

        expect(
          await account(AccountCodes.salesRevenue),
          Money.fromMajor(-30000),
          reason: 'revenue is recognised at the price before discount',
        );
        expect(
          await account(AccountCodes.salesDiscounts),
          Money.fromMajor(3000),
        );
        expect(
          await account(AccountCodes.receivableShops),
          Money.fromMajor(27000),
          reason: 'the shop owes the discounted amount',
        );
        // Cost of the 10 chargers at Rs. 2,000 each.
        expect(
          await account(AccountCodes.costOfGoodsSold),
          Money.fromMajor(20000),
        );
        expect(await account(AccountCodes.inventory), Money.fromMajor(180000));
        await expectJournalSound();
      },
    );

    test('the receivable agrees with what the invoice says is owed', () async {
      await stockTheWarehouse();
      await supplyTheShop();
      final invoice = await raiseShopInvoice(quantity: 10);

      expect(
        await account(AccountCodes.receivableShops),
        await fixture.payments.outstandingOf(invoice.invoiceId),
      );
    });

    test('a retail sale lands on its own receivable', () async {
      await stockTheWarehouse();
      await supplyTheShop();

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
              quantity: 2,
              unitPrice: Money.fromMajor(3500),
            ),
          ],
        ),
      );

      // Kept apart from the shop's wholesale debt, which is the same
      // separation the sales reports keep.
      expect(
        await account(AccountCodes.receivableRetail),
        Money.fromMajor(7000),
      );
      expect(await account(AccountCodes.receivableShops), Money.zero);
      await expectJournalSound();
    });

    test('cancelling takes the revenue and the cost back out', () async {
      await stockTheWarehouse();
      await supplyTheShop();
      final invoice = await raiseShopInvoice(quantity: 10);

      await fixture.invoices.cancelInvoice(
        fixture.admin,
        invoiceId: invoice.invoiceId,
        reason: 'Raised on the wrong shop',
      );

      expect(await account(AccountCodes.salesRevenue), Money.zero);
      expect(await account(AccountCodes.costOfGoodsSold), Money.zero);
      expect(await account(AccountCodes.receivableShops), Money.zero);
      expect(await account(AccountCodes.inventory), Money.fromMajor(200000));
      await expectJournalSound();
    });
  });

  group('money in', () {
    test('cash settles the receivable and shows up as cash', () async {
      await stockTheWarehouse();
      await supplyTheShop();
      final invoice = await raiseShopInvoice(quantity: 10);

      await fixture.payments.recordPayment(
        fixture.admin,
        PaymentRequest(
          direction: PaymentDirection.inbound,
          method: PaymentMethod.cash,
          amount: Money.fromMajor(30000),
          shopId: shopId,
          allocations: [
            PaymentAllocationRequest(
              invoiceId: invoice.invoiceId,
              amount: Money.fromMajor(30000),
            ),
          ],
        ),
      );

      expect(await account(AccountCodes.cashOnHand), Money.fromMajor(30000));
      expect(await account(AccountCodes.receivableShops), Money.zero);
      // The advance was raised and released again in the same breath.
      expect(await account(AccountCodes.customerAdvances), Money.zero);
      await expectJournalSound();
    });

    test('unapplied money is a liability, not income', () async {
      await fixture.payments.recordPayment(
        fixture.admin,
        PaymentRequest(
          direction: PaymentDirection.inbound,
          method: PaymentMethod.cash,
          amount: Money.fromMajor(5000),
          shopId: shopId,
        ),
      );

      expect(await account(AccountCodes.cashOnHand), Money.fromMajor(5000));
      expect(
        await account(AccountCodes.customerAdvances),
        Money.fromMajor(-5000),
        reason: 'the business owes the shop goods or a refund',
      );
      expect(await account(AccountCodes.salesRevenue), Money.zero);
      await expectJournalSound();
    });

    test('a pending cheque is in clearing and settles nothing', () async {
      await stockTheWarehouse();
      await supplyTheShop();
      final invoice = await raiseShopInvoice(quantity: 10);

      await fixture.payments.recordPayment(
        fixture.admin,
        PaymentRequest(
          direction: PaymentDirection.inbound,
          method: PaymentMethod.cheque,
          amount: Money.fromMajor(30000),
          shopId: shopId,
          cheque: ChequeDetails(
            chequeNumber: 'CHQ-1',
            bankName: 'Commercial Bank',
            chequeDate: DateTime.utc(2026, 11, 1),
          ),
          allocations: [
            PaymentAllocationRequest(
              invoiceId: invoice.invoiceId,
              amount: Money.fromMajor(30000),
            ),
          ],
        ),
      );

      expect(
        await account(AccountCodes.chequesInClearing),
        Money.fromMajor(30000),
      );
      expect(await account(AccountCodes.cashOnHand), Money.zero);
      expect(await account(AccountCodes.bank), Money.zero);
      // The crux: the journal and the invoice register agree that nothing is
      // settled yet.
      expect(
        await account(AccountCodes.receivableShops),
        Money.fromMajor(30000),
      );
      expect(
        await fixture.payments.outstandingOf(invoice.invoiceId),
        Money.fromMajor(30000),
      );
      await expectJournalSound();
    });

    test(
      'clearing it moves the money to the bank and settles the debt',
      () async {
        await stockTheWarehouse();
        await supplyTheShop();
        final invoice = await raiseShopInvoice(quantity: 10);
        final payment = await fixture.payments.recordPayment(
          fixture.admin,
          PaymentRequest(
            direction: PaymentDirection.inbound,
            method: PaymentMethod.cheque,
            amount: Money.fromMajor(30000),
            shopId: shopId,
            cheque: ChequeDetails(
              chequeNumber: 'CHQ-1',
              bankName: 'Commercial Bank',
              chequeDate: DateTime.utc(2026, 11, 1),
            ),
            allocations: [
              PaymentAllocationRequest(
                invoiceId: invoice.invoiceId,
                amount: Money.fromMajor(30000),
              ),
            ],
          ),
        );

        await fixture.payments.clearCheque(
          fixture.admin,
          chequeId: payment.chequeId!,
        );

        expect(await account(AccountCodes.chequesInClearing), Money.zero);
        expect(await account(AccountCodes.bank), Money.fromMajor(30000));
        expect(await account(AccountCodes.receivableShops), Money.zero);
        expect(
          await fixture.payments.outstandingOf(invoice.invoiceId),
          Money.zero,
        );
        await expectJournalSound();
      },
    );

    test('bouncing after clearance takes it out of the bank again', () async {
      await stockTheWarehouse();
      await supplyTheShop();
      final invoice = await raiseShopInvoice(quantity: 10);
      final payment = await fixture.payments.recordPayment(
        fixture.admin,
        PaymentRequest(
          direction: PaymentDirection.inbound,
          method: PaymentMethod.cheque,
          amount: Money.fromMajor(30000),
          shopId: shopId,
          cheque: ChequeDetails(
            chequeNumber: 'CHQ-1',
            bankName: 'Commercial Bank',
            chequeDate: DateTime.utc(2026, 11, 1),
          ),
          allocations: [
            PaymentAllocationRequest(
              invoiceId: invoice.invoiceId,
              amount: Money.fromMajor(30000),
            ),
          ],
        ),
      );
      await fixture.payments.clearCheque(
        fixture.admin,
        chequeId: payment.chequeId!,
      );

      await fixture.payments.bounceCheque(
        fixture.admin,
        chequeId: payment.chequeId!,
        reason: 'Insufficient funds',
        bounceCharge: Money.fromMajor(500),
      );

      // The Rs. 30,000 really did arrive in the bank when the cheque cleared
      // and really did leave again when it bounced, so the two cancel. What
      // the business is left down is the bank's charge - and it came out of
      // the bank, not out of clearing, which is the thing a flat "credit
      // clearing" posting would have got wrong.
      expect(
        await account(AccountCodes.bank),
        Money.fromMajor(-500),
        reason: 'in and out again, less the bounce charge',
      );
      expect(await account(AccountCodes.chequesInClearing), Money.zero);
      expect(
        await account(AccountCodes.chequeBounceCharges),
        Money.fromMajor(500),
      );
      // The debt is owed again, in the journal and in the register alike.
      expect(
        await account(AccountCodes.receivableShops),
        Money.fromMajor(30000),
      );
      expect(
        await fixture.payments.outstandingOf(invoice.invoiceId),
        Money.fromMajor(30000),
      );
      await expectJournalSound();
    });

    test('bouncing before clearance takes it out of clearing', () async {
      final payment = await fixture.payments.recordPayment(
        fixture.admin,
        PaymentRequest(
          direction: PaymentDirection.inbound,
          method: PaymentMethod.cheque,
          amount: Money.fromMajor(10000),
          shopId: shopId,
          cheque: ChequeDetails(
            chequeNumber: 'CHQ-2',
            bankName: 'Commercial Bank',
            chequeDate: DateTime.utc(2026, 11, 1),
          ),
        ),
      );

      await fixture.payments.bounceCheque(
        fixture.admin,
        chequeId: payment.chequeId!,
        reason: 'Signature mismatch',
      );

      expect(await account(AccountCodes.chequesInClearing), Money.zero);
      expect(await account(AccountCodes.bank), Money.zero);
      expect(await account(AccountCodes.customerAdvances), Money.zero);
      await expectJournalSound();
    });
  });

  group('credit notes', () {
    test('a credit note is a sales return held to the party', () async {
      await stockTheWarehouse();
      await supplyTheShop();
      final invoice = await raiseShopInvoice(quantity: 10);
      final invoiceItemId = (await fixture.returns.returnableLines(
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
              quantity: 4,
              originInvoiceItemId: invoiceItemId,
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
              acceptedQuantity: 4,
            ),
          ],
        ),
      );

      final creditNoteId = await fixture.returns.issueCreditNote(
        fixture.admin,
        returnId: returned.returnId,
      );

      // Revenue is reduced now; the debt is not, until it is applied.
      expect(await account(AccountCodes.salesReturns), Money.fromMajor(12000));
      expect(
        await account(AccountCodes.receivableShops),
        Money.fromMajor(30000),
      );
      await expectJournalSound();

      await fixture.returns.applyToInvoice(
        fixture.admin,
        creditNoteId: creditNoteId,
        invoiceId: invoice.invoiceId,
        amount: Money.fromMajor(12000),
      );

      expect(
        await account(AccountCodes.receivableShops),
        Money.fromMajor(18000),
      );
      expect(
        await fixture.payments.outstandingOf(invoice.invoiceId),
        Money.fromMajor(18000),
      );
      await expectJournalSound();
    });
  });

  group('profit and loss', () {
    test('agrees with the figures the operational records give', () async {
      await stockTheWarehouse(quantity: 100, unitCost: Money.fromMajor(2000));
      await supplyTheShop(quantity: 50);

      // Sell 10 at Rs. 3,000 with 10% off the invoice: Rs. 27,000 net on
      // goods that cost Rs. 20,000.
      await raiseShopInvoice(
        quantity: 10,
        invoiceDiscountType: DiscountType.percentage,
        invoiceDiscountValue: 1000,
      );

      final report = await fixture.finance.profitAndLoss();

      expect(report.grossSales, Money.fromMajor(30000));
      expect(report.discounts, Money.fromMajor(3000));
      expect(report.returns, Money.zero);
      expect(report.revenue, Money.fromMajor(27000));
      expect(report.costOfGoodsSold, Money.fromMajor(20000));
      expect(report.grossProfit, Money.fromMajor(7000));
      expect(report.netProfit, Money.fromMajor(7000));
      expect(report.isProfitable, isTrue);
      await expectJournalSound();
    });

    test('a write-off eats into the profit', () async {
      await stockTheWarehouse();
      await supplyTheShop();
      await raiseShopInvoice(quantity: 10);

      final before = await fixture.finance.profitAndLoss();
      expect(before.netProfit, Money.fromMajor(10000));

      final damaged = (await fixture.locations.byCode(
        AppConstants.damagedLocationCode,
      )).id;
      await fixture.stockLedger.postMovement(
        fixture.admin,
        StockMovementRequest(
          documentType: StockDocumentType.damageWriteOff,
          sourceLocationId: warehouseId,
          destinationLocationId: damaged,
          lines: [StockMovementLine(productId: chargerId, quantity: 2)],
        ),
      );

      final after = await fixture.finance.profitAndLoss();
      expect(after.stockWriteOff, Money.fromMajor(4000));
      expect(after.netProfit, Money.fromMajor(6000));
      await expectJournalSound();
    });

    test('is narrowed by the period asked for', () async {
      await stockTheWarehouse();
      await supplyTheShop();
      await raiseShopInvoice(quantity: 10);

      final future = await fixture.finance.profitAndLoss(
        from: DateTime.utc(2030),
      );
      expect(future.revenue, Money.zero);
      expect(future.netProfit, Money.zero);

      final covering = await fixture.finance.profitAndLoss(
        from: DateTime.utc(2026),
        to: DateTime.utc(2027),
      );
      expect(covering.revenue, Money.fromMajor(30000));
    });
  });

  group('after a full round of business', () {
    test('the trial balance still balances and nothing is lopsided', () async {
      await stockTheWarehouse(quantity: 200, unitCost: Money.fromMajor(2000));
      await supplyTheShop(quantity: 100);

      // An invoice, part paid in cash, part by a cheque that clears.
      final first = await raiseShopInvoice(quantity: 20);
      await fixture.payments.recordPayment(
        fixture.admin,
        PaymentRequest(
          direction: PaymentDirection.inbound,
          method: PaymentMethod.cash,
          amount: Money.fromMajor(20000),
          shopId: shopId,
          allocations: [
            PaymentAllocationRequest(
              invoiceId: first.invoiceId,
              amount: Money.fromMajor(20000),
            ),
          ],
        ),
      );
      final cheque = await fixture.payments.recordPayment(
        fixture.admin,
        PaymentRequest(
          direction: PaymentDirection.inbound,
          method: PaymentMethod.cheque,
          amount: Money.fromMajor(40000),
          shopId: shopId,
          cheque: ChequeDetails(
            chequeNumber: 'CHQ-9',
            bankName: 'Commercial Bank',
            chequeDate: DateTime.utc(2026, 11, 1),
          ),
          allocations: [
            PaymentAllocationRequest(
              invoiceId: first.invoiceId,
              amount: Money.fromMajor(40000),
            ),
          ],
        ),
      );
      await fixture.payments.clearCheque(
        fixture.admin,
        chequeId: cheque.chequeId!,
      );

      // A second invoice, cancelled.
      final second = await raiseShopInvoice(quantity: 5);
      await fixture.invoices.cancelInvoice(
        fixture.admin,
        invoiceId: second.invoiceId,
        reason: 'Duplicate',
      );

      // A write-off and an advance left unapplied.
      final damaged = (await fixture.locations.byCode(
        AppConstants.damagedLocationCode,
      )).id;
      await fixture.stockLedger.postMovement(
        fixture.admin,
        StockMovementRequest(
          documentType: StockDocumentType.damageWriteOff,
          sourceLocationId: warehouseId,
          destinationLocationId: damaged,
          lines: [StockMovementLine(productId: chargerId, quantity: 3)],
        ),
      );
      await fixture.payments.recordPayment(
        fixture.admin,
        PaymentRequest(
          direction: PaymentDirection.inbound,
          method: PaymentMethod.cash,
          amount: Money.fromMajor(1000),
          shopId: shopId,
        ),
      );

      await expectJournalSound();

      // The invoice is fully settled, so the shop's receivable is clear and
      // only the unapplied advance is left owing to it.
      expect(await account(AccountCodes.receivableShops), Money.zero);
      expect(
        await account(AccountCodes.customerAdvances),
        Money.fromMajor(-1000),
      );
      expect(await account(AccountCodes.cashOnHand), Money.fromMajor(21000));
      expect(await account(AccountCodes.bank), Money.fromMajor(40000));

      final report = await fixture.finance.profitAndLoss();
      expect(report.revenue, Money.fromMajor(60000));
      expect(report.costOfGoodsSold, Money.fromMajor(40000));
      expect(report.stockWriteOff, Money.fromMajor(6000));
      expect(report.netProfit, Money.fromMajor(14000));
    });

    test('every journal row can be traced back to what caused it', () async {
      await stockTheWarehouse();
      await supplyTheShop();
      final invoice = await raiseShopInvoice(quantity: 10);

      final rows = await fixture.finance.entriesForSource(
        sourceKind: EntityKind.invoice,
        sourceId: invoice.invoiceId,
      );

      expect(rows, isNotEmpty);
      expect(
        rows.every((row) => row.description.contains(invoice.invoiceNumber)),
        isTrue,
      );
      expect(rows.map((row) => row.batchId).toSet(), hasLength(1));
    });
  });
}
