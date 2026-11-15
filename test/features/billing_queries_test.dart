import 'package:flutter_test/flutter_test.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/agents/domain/agent_models.dart';
import 'package:venvo_core/features/categories/domain/category_models.dart';
import 'package:venvo_core/features/inventory/domain/stock_models.dart';
import 'package:venvo_core/features/invoices/data/invoice_query_repository.dart';
import 'package:venvo_core/features/invoices/domain/invoice_models.dart';
import 'package:venvo_core/features/payments/data/payment_query_repository.dart';
import 'package:venvo_core/features/payments/domain/payment_models.dart';
import 'package:venvo_core/features/products/domain/product_models.dart';
import 'package:venvo_core/features/shops/domain/shop_models.dart';

import '../helpers/master_data_fixtures.dart';

/// Exercises the hand-written reporting SQL behind the registers.
void main() {
  late MasterDataFixture fixture;
  late InvoiceQueryRepository invoiceQueries;
  late PaymentQueryRepository paymentQueries;
  late int chargerId;
  late int agentId;
  late int agentLocationId;
  late int shopId;
  late int warehouseId;

  setUp(() async {
    fixture = await MasterDataFixture.create();
    invoiceQueries = InvoiceQueryRepository(fixture.db);
    paymentQueries = PaymentQueryRepository(fixture.db);

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

    await fixture.postOpeningStock(
      locationId: warehouseId,
      productId: chargerId,
      quantity: 200,
      unitCost: Money.fromMajor(2000),
    );
  });

  tearDown(() => fixture.dispose());

  Future<InvoicePostResultLike> raiseShopInvoice({
    int quantity = 10,
    Money? unitPrice,
  }) async {
    final result = await fixture.invoices.postInvoice(
      fixture.admin,
      InvoiceRequest(
        kind: InvoiceKind.shopInvoice,
        shopId: shopId,
        agentId: agentId,
        lines: [
          InvoiceLineRequest(
            productId: chargerId,
            quantity: quantity,
            unitPrice: unitPrice ?? Money.fromMajor(2000),
          ),
        ],
      ),
    );
    return InvoicePostResultLike(result.invoiceId, result.invoiceNumber);
  }

  group('invoice register', () {
    test('lists an invoice with its settlement worked out', () async {
      final invoice = await raiseShopInvoice();
      await fixture.payments.recordPayment(
        fixture.admin,
        PaymentRequest(
          direction: PaymentDirection.inbound,
          method: PaymentMethod.cash,
          amount: Money.fromMajor(8000),
          shopId: shopId,
          allocations: [
            PaymentAllocationRequest(
              invoiceId: invoice.id,
              amount: Money.fromMajor(8000),
            ),
          ],
        ),
      );

      final rows = await invoiceQueries
          .watchInvoices(const InvoiceFilter())
          .first;
      expect(rows.length, 1);

      final row = rows.single;
      expect(row.invoiceNumber, invoice.number);
      expect(row.kind, InvoiceKind.shopInvoice);
      expect(row.partyName, 'Shop A');
      expect(row.agentName, 'Agent A');
      expect(row.net, Money.fromMajor(20000));
      expect(row.settled, Money.fromMajor(8000));
      expect(row.outstanding, Money.fromMajor(12000));
      expect(row.settlementStatus, PaymentSettlementStatus.partiallyPaid);
      expect(row.lineCount, 1);
      expect(row.createdBy, 'Nimal Perera');
      expect(row.cost, Money.fromMajor(20000));
    });

    test('keeps a pending cheque out of settlement but reports it', () async {
      final invoice = await raiseShopInvoice();
      await fixture.payments.recordPayment(
        fixture.admin,
        PaymentRequest(
          direction: PaymentDirection.inbound,
          method: PaymentMethod.cheque,
          amount: Money.fromMajor(20000),
          shopId: shopId,
          cheque: ChequeDetails(
            chequeNumber: '123',
            bankName: 'Commercial Bank',
            chequeDate: fixture.harness.clock.nowUtc(),
          ),
          allocations: [
            PaymentAllocationRequest(
              invoiceId: invoice.id,
              amount: Money.fromMajor(20000),
            ),
          ],
        ),
      );

      final row =
          (await invoiceQueries.watchInvoices(const InvoiceFilter()).first)
              .single;
      expect(row.settled, Money.zero);
      expect(row.pendingCheques, Money.fromMajor(20000));
      expect(row.outstanding, Money.fromMajor(20000));
      expect(row.outstandingIfChequesClear, Money.zero);
      expect(row.hasPendingCheques, isTrue);
      expect(row.settlementStatus, PaymentSettlementStatus.unpaid);
    });

    test('filters by settlement state', () async {
      final paid = await raiseShopInvoice(quantity: 1);
      await raiseShopInvoice(quantity: 2);

      await fixture.payments.recordPayment(
        fixture.admin,
        PaymentRequest(
          direction: PaymentDirection.inbound,
          method: PaymentMethod.cash,
          amount: Money.fromMajor(2000),
          shopId: shopId,
          allocations: [
            PaymentAllocationRequest(
              invoiceId: paid.id,
              amount: Money.fromMajor(2000),
            ),
          ],
        ),
      );

      final unpaid = await invoiceQueries
          .watchInvoices(
            const InvoiceFilter(settlement: PaymentSettlementStatus.unpaid),
          )
          .first;
      expect(unpaid.length, 1);
      expect(unpaid.single.net, Money.fromMajor(4000));

      final settled = await invoiceQueries
          .watchInvoices(
            const InvoiceFilter(settlement: PaymentSettlementStatus.paid),
          )
          .first;
      expect(settled.single.invoiceNumber, paid.number);
    });

    test('filters by kind, party, search and unpaid', () async {
      await raiseShopInvoice();

      expect(
        (await invoiceQueries
                .watchInvoices(
                  const InvoiceFilter(kinds: {InvoiceKind.retailSale}),
                )
                .first)
            .length,
        0,
      );
      expect(
        (await invoiceQueries
                .watchInvoices(InvoiceFilter(shopId: shopId))
                .first)
            .length,
        1,
      );
      expect(
        (await invoiceQueries
                .watchInvoices(const InvoiceFilter(search: 'shop a'))
                .first)
            .length,
        1,
      );
      expect(
        (await invoiceQueries
                .watchInvoices(const InvoiceFilter(unpaidOnly: true))
                .first)
            .length,
        1,
      );
    });

    test('excludes a cancelled invoice from the unpaid filter', () async {
      final invoice = await raiseShopInvoice();
      await fixture.invoices.cancelInvoice(
        fixture.admin,
        invoiceId: invoice.id,
        reason: 'Raised in error',
      );

      final unpaid = await invoiceQueries
          .watchInvoices(const InvoiceFilter(unpaidOnly: true))
          .first;
      expect(unpaid, isEmpty);

      final all = await invoiceQueries
          .watchInvoices(const InvoiceFilter())
          .first;
      expect(all.single.isCancelled, isTrue);
      expect(all.single.outstanding, Money.zero);
    });

    test('totals aggregate the filtered set', () async {
      await raiseShopInvoice(quantity: 5);
      await raiseShopInvoice(quantity: 5);

      final totals = await invoiceQueries.totals(const InvoiceFilter());
      expect(totals.count, 2);
      expect(totals.net, Money.fromMajor(20000));
      expect(totals.cost, Money.fromMajor(20000));
      expect(totals.grossProfit, Money.zero);
      expect(totals.outstanding, Money.fromMajor(20000));
    });
  });

  group('invoice detail', () {
    test('returns the lines, the payments and the party details', () async {
      final invoice = await raiseShopInvoice();
      await fixture.payments.recordPayment(
        fixture.admin,
        PaymentRequest(
          direction: PaymentDirection.inbound,
          method: PaymentMethod.cheque,
          amount: Money.fromMajor(5000),
          shopId: shopId,
          cheque: ChequeDetails(
            chequeNumber: '555',
            bankName: 'Sampath Bank',
            chequeDate: fixture.harness.clock.nowUtc(),
          ),
          allocations: [
            PaymentAllocationRequest(
              invoiceId: invoice.id,
              amount: Money.fromMajor(5000),
            ),
          ],
        ),
      );

      final detail = await invoiceQueries.invoiceDetail(invoice.id);
      expect(detail.summary.invoiceNumber, invoice.number);
      expect(detail.lines.length, 1);
      expect(detail.lines.single.productName, '25W Charger');
      expect(detail.lines.single.quantity, 10);
      expect(detail.totalQuantity, 10);

      expect(detail.payments.length, 1);
      final payment = detail.payments.single;
      expect(payment.allocated, Money.fromMajor(5000));
      expect(payment.chequeNumber, '555');
      expect(payment.chequeStatus, ChequeStatus.pending);
      // A pending cheque is on the invoice but is not effective.
      expect(payment.isEffective, isFalse);
    });

    test('shows a withdrawn allocation as no longer on the invoice', () async {
      final invoice = await raiseShopInvoice();
      final payment = await fixture.payments.recordPayment(
        fixture.admin,
        PaymentRequest(
          direction: PaymentDirection.inbound,
          method: PaymentMethod.cash,
          amount: Money.fromMajor(5000),
          shopId: shopId,
          allocations: [
            PaymentAllocationRequest(
              invoiceId: invoice.id,
              amount: Money.fromMajor(5000),
            ),
          ],
        ),
      );
      await fixture.payments.releaseAllocation(
        fixture.admin,
        paymentId: payment.paymentId,
        invoiceId: invoice.id,
        reason: 'Wrong invoice',
      );

      final detail = await invoiceQueries.invoiceDetail(invoice.id);
      // The two allocation rows net to zero, so the payment drops off.
      expect(detail.payments, isEmpty);
      expect(detail.summary.outstanding, Money.fromMajor(20000));
    });
  });

  group('unbilled deliveries', () {
    test('lists a posted transfer with no invoice against it', () async {
      final transfer = await fixture.stockLedger.postMovement(
        fixture.admin,
        StockMovementRequest(
          documentType: StockDocumentType.warehouseToAgent,
          sourceLocationId: warehouseId,
          destinationLocationId: agentLocationId,
          lines: [
            StockMovementLine(
              productId: chargerId,
              quantity: 50,
              unitPrice: Money.fromMajor(3000),
            ),
          ],
        ),
      );

      final unbilled = await invoiceQueries.watchUnbilledDeliveries().first;
      expect(unbilled.length, 1);
      expect(unbilled.single.documentNumber, transfer.documentNumber);
      expect(unbilled.single.documentValue, Money.fromMajor(150000));
      expect(unbilled.single.partyName, 'Agent A');
      expect(unbilled.single.needsPrices, isFalse);
    });

    test('drops off once it is billed', () async {
      final transfer = await fixture.stockLedger.postMovement(
        fixture.admin,
        StockMovementRequest(
          documentType: StockDocumentType.warehouseToAgent,
          sourceLocationId: warehouseId,
          destinationLocationId: agentLocationId,
          lines: [
            StockMovementLine(
              productId: chargerId,
              quantity: 50,
              unitPrice: Money.fromMajor(3000),
            ),
          ],
        ),
      );
      await fixture.invoices.billDelivery(
        fixture.admin,
        stockTransactionId: transfer.transactionId,
      );

      expect(await invoiceQueries.watchUnbilledDeliveries().first, isEmpty);
    });

    test(
      'reappears if the invoice is cancelled, so it can be rebilled',
      () async {
        final transfer = await fixture.stockLedger.postMovement(
          fixture.admin,
          StockMovementRequest(
            documentType: StockDocumentType.warehouseToAgent,
            sourceLocationId: warehouseId,
            destinationLocationId: agentLocationId,
            lines: [
              StockMovementLine(
                productId: chargerId,
                quantity: 50,
                unitPrice: Money.fromMajor(3000),
              ),
            ],
          ),
        );
        final invoice = await fixture.invoices.billDelivery(
          fixture.admin,
          stockTransactionId: transfer.transactionId,
        );
        await fixture.invoices.cancelInvoice(
          fixture.admin,
          invoiceId: invoice.invoiceId,
          reason: 'Wrong price',
        );

        final unbilled = await invoiceQueries.watchUnbilledDeliveries().first;
        expect(unbilled.single.documentNumber, transfer.documentNumber);
      },
    );

    test('ignores a document type that is not billable', () async {
      await fixture.postOpeningStock(
        locationId: warehouseId,
        productId: chargerId,
        quantity: 10,
      );
      expect(await invoiceQueries.watchUnbilledDeliveries().first, isEmpty);
    });
  });

  group('payment register', () {
    test('lists a payment with the invoices it was applied to', () async {
      final invoice = await raiseShopInvoice();
      await fixture.payments.recordPayment(
        fixture.admin,
        PaymentRequest(
          direction: PaymentDirection.inbound,
          method: PaymentMethod.cash,
          amount: Money.fromMajor(6000),
          shopId: shopId,
          referenceNumber: 'CASH-001',
          allocations: [
            PaymentAllocationRequest(
              invoiceId: invoice.id,
              amount: Money.fromMajor(6000),
            ),
          ],
        ),
      );

      final rows = await paymentQueries
          .watchPayments(const PaymentFilter())
          .first;
      expect(rows.length, 1);
      final row = rows.single;
      expect(row.partyName, 'Shop A');
      expect(row.method, PaymentMethod.cash);
      expect(row.status, PaymentStatus.cleared);
      expect(row.amount, Money.fromMajor(6000));
      expect(row.allocated, Money.fromMajor(6000));
      expect(row.unallocated, Money.zero);
      expect(row.invoiceNumbers, [invoice.number]);
      expect(row.isAdvance, isFalse);
    });

    test('identifies an advance', () async {
      await fixture.payments.recordPayment(
        fixture.admin,
        PaymentRequest(
          direction: PaymentDirection.inbound,
          method: PaymentMethod.cash,
          amount: Money.fromMajor(4000),
          shopId: shopId,
        ),
      );

      final advances = await paymentQueries
          .watchPayments(const PaymentFilter(advancesOnly: true))
          .first;
      expect(advances.length, 1);
      expect(advances.single.isAdvance, isTrue);
      expect(advances.single.unallocated, Money.fromMajor(4000));
      expect(advances.single.invoiceNumbers, isEmpty);
    });

    test('filters by method and status', () async {
      await fixture.payments.recordPayment(
        fixture.admin,
        PaymentRequest(
          direction: PaymentDirection.inbound,
          method: PaymentMethod.cheque,
          amount: Money.fromMajor(3000),
          shopId: shopId,
          cheque: ChequeDetails(
            chequeNumber: '321',
            bankName: 'HNB',
            chequeDate: fixture.harness.clock.nowUtc(),
          ),
        ),
      );

      expect(
        (await paymentQueries
                .watchPayments(
                  const PaymentFilter(method: PaymentMethod.cheque),
                )
                .first)
            .length,
        1,
      );
      expect(
        (await paymentQueries
                .watchPayments(
                  const PaymentFilter(status: PaymentStatus.cleared),
                )
                .first)
            .length,
        0,
      );
      expect(
        (await paymentQueries
                .watchPayments(const PaymentFilter(search: '321'))
                .first)
            .length,
        1,
      );
    });

    test('totals separate cleared money from promises', () async {
      await fixture.payments.recordPayment(
        fixture.admin,
        PaymentRequest(
          direction: PaymentDirection.inbound,
          method: PaymentMethod.cash,
          amount: Money.fromMajor(5000),
          shopId: shopId,
        ),
      );
      await fixture.payments.recordPayment(
        fixture.admin,
        PaymentRequest(
          direction: PaymentDirection.inbound,
          method: PaymentMethod.cheque,
          amount: Money.fromMajor(7000),
          shopId: shopId,
          cheque: ChequeDetails(
            chequeNumber: '999',
            bankName: 'HNB',
            chequeDate: fixture.harness.clock.nowUtc(),
          ),
        ),
      );

      final totals = await paymentQueries.paymentTotals(const PaymentFilter());
      expect(totals.count, 2);
      expect(totals.clearedIn, Money.fromMajor(5000));
      expect(totals.pending, Money.fromMajor(7000));
      expect(totals.advances, Money.fromMajor(5000));
    });
  });

  group('cheque register', () {
    Future<int> giveCheque({
      DateTime? chequeDate,
      String number = '777',
    }) async {
      final payment = await fixture.payments.recordPayment(
        fixture.admin,
        PaymentRequest(
          direction: PaymentDirection.inbound,
          method: PaymentMethod.cheque,
          amount: Money.fromMajor(10000),
          shopId: shopId,
          cheque: ChequeDetails(
            chequeNumber: number,
            bankName: 'Commercial Bank',
            branchName: 'Nugegoda',
            chequeDate: chequeDate ?? fixture.harness.clock.nowUtc(),
          ),
        ),
      );
      return payment.chequeId!;
    }

    test('lists a cheque with its party and bank', () async {
      await giveCheque();

      final rows = await paymentQueries
          .watchCheques(const ChequeFilter())
          .first;
      expect(rows.length, 1);
      final row = rows.single;
      expect(row.chequeNumber, '777');
      expect(row.bankName, 'Commercial Bank');
      expect(row.branchName, 'Nugegoda');
      expect(row.partyName, 'Shop A');
      expect(row.amount, Money.fromMajor(10000));
      expect(row.status, ChequeStatus.pending);
      expect(row.isOutstanding, isTrue);
    });

    test('marks a post-dated cheque as not bankable', () async {
      final now = fixture.harness.clock.nowUtc();
      await giveCheque(chequeDate: now.add(const Duration(days: 20)));

      final row =
          (await paymentQueries.watchCheques(const ChequeFilter()).first)
              .single;
      expect(row.isPostDated(now), isTrue);
      expect(row.isBankable(now), isFalse);
    });

    test(
      'the bankable filter finds only cheques that can be banked today',
      () async {
        final now = fixture.harness.clock.nowUtc();
        await giveCheque(number: '111');
        await giveCheque(
          number: '222',
          chequeDate: now.add(const Duration(days: 20)),
        );

        final bankable = await paymentQueries
            .watchCheques(const ChequeFilter(bankableOnly: true))
            .first;
        expect(bankable.length, 1);
        expect(bankable.single.chequeNumber, '111');
      },
    );

    test('follows the cheque through banking, clearing and bouncing', () async {
      final chequeId = await giveCheque();

      await fixture.payments.depositCheque(fixture.admin, chequeId: chequeId);
      var row = (await paymentQueries.watchCheques(const ChequeFilter()).first)
          .single;
      expect(row.status, ChequeStatus.deposited);
      expect(row.depositedAt, isNotNull);
      expect(row.isOutstanding, isTrue);

      await fixture.payments.clearCheque(fixture.admin, chequeId: chequeId);
      row = (await paymentQueries.watchCheques(const ChequeFilter()).first)
          .single;
      expect(row.status, ChequeStatus.cleared);
      expect(row.isCleared, isTrue);
      expect(row.isOutstanding, isFalse);

      await fixture.payments.bounceCheque(
        fixture.admin,
        chequeId: chequeId,
        reason: 'Returned unpaid',
        bounceCharge: Money.fromMajor(350),
      );
      row = (await paymentQueries.watchCheques(const ChequeFilter()).first)
          .single;
      expect(row.status, ChequeStatus.bounced);
      expect(row.bounceReason, 'Returned unpaid');
      expect(row.bounceCharge, Money.fromMajor(350));
    });

    test('totals split outstanding, cleared and bounced', () async {
      final first = await giveCheque(number: '111');
      await giveCheque(number: '222');
      await fixture.payments.clearCheque(fixture.admin, chequeId: first);

      final totals = await paymentQueries.chequeTotals(const ChequeFilter());
      expect(totals.count, 2);
      expect(totals.cleared, Money.fromMajor(10000));
      expect(totals.outstanding, Money.fromMajor(10000));
      expect(totals.bounced, Money.zero);
    });

    test('filters by status', () async {
      await giveCheque();
      expect(
        (await paymentQueries
                .watchCheques(
                  const ChequeFilter(statuses: {ChequeStatus.cleared}),
                )
                .first)
            .length,
        0,
      );
      expect(
        (await paymentQueries
                .watchCheques(
                  const ChequeFilter(statuses: {ChequeStatus.pending}),
                )
                .first)
            .length,
        1,
      );
    });
  });
}

/// Minimal holder so the helper does not depend on the service's result type.
class InvoicePostResultLike {
  const InvoicePostResultLike(this.id, this.number);

  final int id;
  final String number;
}
