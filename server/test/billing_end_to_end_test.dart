import 'package:test/test.dart';
import 'package:venvo_core/core/api/api_client.dart';
import 'package:venvo_core/core/constants/app_constants.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/errors/failures.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/agents/api/agent_api.dart';
import 'package:venvo_core/features/agents/domain/agent_models.dart';
import 'package:venvo_core/features/authentication/api/auth_api.dart';
import 'package:venvo_core/features/authentication/domain/authenticated_user.dart';
import 'package:venvo_core/features/categories/api/category_api.dart';
import 'package:venvo_core/features/categories/domain/category_models.dart';
import 'package:venvo_core/features/finance/api/finance_api.dart';
import 'package:venvo_core/features/inventory/api/location_api.dart';
import 'package:venvo_core/features/inventory/api/stock_api.dart';
import 'package:venvo_core/features/inventory/domain/stock_models.dart';
import 'package:venvo_core/features/invoices/api/invoice_api.dart';
import 'package:venvo_core/features/invoices/data/invoice_service.dart';
import 'package:venvo_core/features/invoices/domain/invoice_models.dart';
import 'package:venvo_core/features/payments/api/payment_api.dart';
import 'package:venvo_core/features/payments/domain/payment_models.dart';
import 'package:venvo_core/features/products/api/product_api.dart';
import 'package:venvo_core/features/products/domain/product_models.dart';
import 'package:venvo_core/features/shops/api/shop_api.dart';
import 'package:venvo_core/features/shops/domain/shop_models.dart';

import 'support/api_harness.dart';

/// Billing and settlement, driven through the real client.
///
/// The questions being asked are the ones a wholesale business would be ruined
/// by getting wrong: does the journal still balance, does cancelling a bill
/// un-ship the goods, and does a cheque count as money before it has cleared.
void main() {
  late ApiHarness api;
  late ApiClient client;
  late AuthApi auth;
  late AuthenticatedUser admin;
  late InvoiceApi invoices;
  late InvoiceQueryApi invoiceQueries;
  late PaymentApi payments;
  late StockLedgerApi ledger;
  late FinanceApi finance;

  late int warehouseId;
  late int shopLocationId;
  late int shopId;
  late int productId;

  const unitPrice = Money(130000); // Rs 1,300.00

  setUp(() async {
    api = await ApiHarness.start();
    client = ApiClient(baseUrl: api.base, tokens: InMemoryTokenStore());
    auth = AuthApi(client);
    invoices = InvoiceApi(client);
    invoiceQueries = InvoiceQueryApi(client);
    payments = PaymentApi(client);
    ledger = StockLedgerApi(client);
    finance = FinanceApi(client);

    admin = await auth.createFirstAdministrator(
      fullName: 'Venura Admin',
      username: 'admin',
      password: ApiHarness.adminPassword,
    );

    final locations = LocationApi(client);
    final virtual = await locations.watchLocations(includeVirtual: true).first;
    warehouseId = virtual
        .firstWhere((l) => l.code == AppConstants.mainWarehouseCode)
        .id;
    final supplierId = virtual
        .firstWhere((l) => l.code == AppConstants.supplierLocationCode)
        .id;

    final categoryId = await CategoryApi(
      client,
    ).create(admin, const CategoryDraft(name: 'Chargers'));
    productId = await ProductApi(client).create(
      admin,
      ProductDraft(
        sku: 'CHG-25W',
        name: 'Fast charger 25W',
        categoryId: categoryId,
        costPrice: const Money(100000),
        wholesalePrice: unitPrice,
      ),
    );

    final agentId = await AgentApi(
      client,
    ).create(admin, const AgentDraft(name: 'Kandy route'));
    shopId = await ShopApi(client).create(
      admin,
      ShopDraft(name: 'Sea Street Mobiles', assignedAgentId: agentId),
    );
    shopLocationId = (await locations.watchLocations().first)
        .firstWhere((l) => l.shopId == shopId)
        .id;

    // 200 units in the warehouse to sell from.
    await ledger.postMovement(
      admin,
      StockMovementRequest(
        documentType: StockDocumentType.openingStock,
        sourceLocationId: supplierId,
        destinationLocationId: warehouseId,
        lines: [
          StockMovementLine(
            productId: productId,
            quantity: 200,
            unitCost: const Money(100000),
          ),
        ],
      ),
    );
  });

  tearDown(() async {
    await client.close();
    await api.stop();
  });

  Future<int> balanceAt(int locationId) =>
      ledger.balanceOf(locationId: locationId, productId: productId);

  /// Raises a shop invoice that moves the goods at the same time.
  Future<InvoicePostResult> invoiceWithStock(int quantity) =>
      invoices.postInvoice(
        admin,
        InvoiceRequest(
          kind: InvoiceKind.shopInvoice,
          shopId: shopId,
          lines: [
            InvoiceLineRequest(
              productId: productId,
              quantity: quantity,
              unitPrice: unitPrice,
            ),
          ],
          stockLinkage: MoveStockWithInvoice(
            documentType: StockDocumentType.warehouseToShop,
            sourceLocationId: warehouseId,
            destinationLocationId: shopLocationId,
          ),
        ),
      );

  /// Posts the goods first, then bills them as a separate decision.
  Future<(StockMovementResult, InvoicePostResult)> deliverThenBill(
    int quantity,
  ) async {
    final delivery = await ledger.postMovement(
      admin,
      StockMovementRequest(
        documentType: StockDocumentType.warehouseToShop,
        sourceLocationId: warehouseId,
        destinationLocationId: shopLocationId,
        shopId: shopId,
        lines: [
          StockMovementLine(
            productId: productId,
            quantity: quantity,
            unitPrice: unitPrice,
          ),
        ],
      ),
    );
    final invoice = await invoices.billDelivery(
      admin,
      stockTransactionId: delivery.transactionId,
    );
    return (delivery, invoice);
  }

  /// The invariant that has to hold after every single operation here.
  Future<void> expectBooksBalanced() async {
    expect(
      await finance.findUnbalancedBatches(),
      isEmpty,
      reason: 'a journal batch does not balance',
    );
    final trial = await finance.trialBalance();
    expect(
      trial.isBalanced,
      isTrue,
      reason:
          'trial balance: debits ${trial.totalDebits.cents} '
          'against credits ${trial.totalCredits.cents}',
    );
  }

  group('raising an invoice', () {
    test('goods and money are posted together', () async {
      final result = await invoiceWithStock(10);

      expect(result.invoiceNumber, isNotEmpty);
      expect(result.totals.net, const Money(1300000));
      expect(result.stockTransactionId, isNotNull);
      expect(result.stockDocumentNumber, isNotEmpty);

      // The goods moved.
      expect(await balanceAt(warehouseId), 190);
      expect(await balanceAt(shopLocationId), 10);
      expect(await ledger.findUnbalancedProducts(), isEmpty);

      // And the money is owed, in the accounts.
      expect(
        await finance.balanceOf(AccountCodes.receivableShops),
        const Money(1300000),
      );
      await expectBooksBalanced();
    });

    test('billing a delivery leaves the goods where they are', () async {
      final (delivery, invoice) = await deliverThenBill(15);
      expect(invoice.invoiceNumber, isNotEmpty);

      // The movement happened once, when the lorry left — not again at
      // billing time.
      expect(await balanceAt(warehouseId), 185);
      expect(await balanceAt(shopLocationId), 15);
      expect(delivery.totalQuantity, 15);
      await expectBooksBalanced();

      // And it is no longer waiting to be billed.
      final unbilled = await invoiceQueries.watchUnbilledDeliveries().first;
      expect(
        unbilled.map((d) => d.stockTransactionId),
        isNot(contains(delivery.transactionId)),
      );
    });

    test('an invoice for more than the stock on hand is refused', () async {
      await expectLater(
        invoiceWithStock(201),
        throwsA(isA<BusinessRuleFailure>()),
      );
      // Nothing moved and nothing is owed.
      expect(await balanceAt(warehouseId), 200);
      expect(await finance.balanceOf(AccountCodes.receivableShops), Money.zero);
      await expectBooksBalanced();
    });
  });

  group('cancelling', () {
    test('by default the goods stay where they were sent', () async {
      // The default is deliberate and worth pinning: cancelling a bill is not
      // un-shipping. If this flipped to reversing by default, cancelling the
      // paperwork for goods a shop already has would invent 20 units in a
      // warehouse that does not have them.
      final invoice = await invoiceWithStock(20);
      expect(await balanceAt(shopLocationId), 20);

      final cancellation = await invoices.cancelInvoice(
        admin,
        invoiceId: invoice.invoiceId,
        reason: 'Re-billing with the right price',
      );

      expect(await balanceAt(warehouseId), 180);
      expect(await balanceAt(shopLocationId), 20);
      expect(cancellation.stockReversalDocumentNumber, isNull);
      // The money is released even though the goods are not.
      expect(await finance.balanceOf(AccountCodes.receivableShops), Money.zero);
      await expectBooksBalanced();
    });

    test('asking for it reverses the movement too', () async {
      final invoice = await invoiceWithStock(20);
      expect(await balanceAt(shopLocationId), 20);

      final cancellation = await invoices.cancelInvoice(
        admin,
        invoiceId: invoice.invoiceId,
        reason: 'Ordered in error, lorry turned back',
        reverseStockMovement: true,
      );

      expect(await balanceAt(warehouseId), 200);
      expect(await balanceAt(shopLocationId), 0);
      expect(cancellation.stockReversalDocumentNumber, isNotNull);
      expect(await finance.balanceOf(AccountCodes.receivableShops), Money.zero);
      expect(await ledger.findUnbalancedProducts(), isEmpty);
      await expectBooksBalanced();
    });

    test('cancelling the bill for a delivery leaves the goods out', () async {
      // The case the default exists for. The lorry has been; the bill was
      // wrong. Cancelling it releases the money and leaves the 25 units with
      // the shop, which is where they actually are.
      final (_, invoice) = await deliverThenBill(25);
      expect(await balanceAt(shopLocationId), 25);

      final cancellation = await invoices.cancelInvoice(
        admin,
        invoiceId: invoice.invoiceId,
        reason: 'Will re-bill with the right discount',
      );

      expect(await balanceAt(shopLocationId), 25);
      expect(await balanceAt(warehouseId), 175);
      expect(cancellation.stockReversalDocumentNumber, isNull);
      expect(await finance.balanceOf(AccountCodes.receivableShops), Money.zero);
      await expectBooksBalanced();
    });

    test('asking for the reversal sends a billed delivery back too', () async {
      // Worth pinning because it is not the obvious reading of the flag: the
      // reversal applies to whatever document the invoice is linked to, with
      // no distinction between a movement the invoice posted and one it only
      // billed. Setting the flag on a billed delivery therefore does send the
      // goods back — a real operation, and a surprising one, which is why the
      // default is false.
      final (delivery, invoice) = await deliverThenBill(25);
      expect(await balanceAt(shopLocationId), 25);

      final cancellation = await invoices.cancelInvoice(
        admin,
        invoiceId: invoice.invoiceId,
        reason: 'Goods returned and the bill withdrawn',
        reverseStockMovement: true,
      );

      expect(cancellation.stockReversalDocumentNumber, isNotNull);
      expect(await balanceAt(shopLocationId), 0);
      expect(await balanceAt(warehouseId), 200);
      expect(delivery.totalQuantity, 25);
      expect(await ledger.findUnbalancedProducts(), isEmpty);
      await expectBooksBalanced();
    });

    test('cancelling needs a reason', () async {
      final invoice = await invoiceWithStock(5);
      await expectLater(
        invoices.cancelInvoice(
          admin,
          invoiceId: invoice.invoiceId,
          reason: '  ',
        ),
        throwsA(isA<ValidationFailure>()),
      );
      expect(await balanceAt(shopLocationId), 5);
    });
  });

  group('settlement', () {
    test('a cash collection clears the invoice at once', () async {
      final invoice = await invoiceWithStock(10);
      final owed = invoice.totals.net;
      expect(await payments.outstandingOf(invoice.invoiceId), owed);

      await payments.recordPayment(
        admin,
        PaymentRequest(
          direction: PaymentDirection.inbound,
          method: PaymentMethod.cash,
          amount: owed,
          partyType: PartyType.shop,
          shopId: shopId,
          allocations: [
            PaymentAllocationRequest(
              invoiceId: invoice.invoiceId,
              amount: owed,
            ),
          ],
        ),
      );

      expect(await payments.outstandingOf(invoice.invoiceId), Money.zero);
      expect(await finance.balanceOf(AccountCodes.cashOnHand), owed);
      await expectBooksBalanced();
    });

    test('a cheque is not money until it clears', () async {
      // The timing rule. A cheque in the drawer is a promise; posting it to
      // the bank account on the day it was taken would overstate cash and
      // understate what the business is owed.
      final invoice = await invoiceWithStock(10);
      final owed = invoice.totals.net;

      final payment = await payments.recordPayment(
        admin,
        PaymentRequest(
          direction: PaymentDirection.inbound,
          method: PaymentMethod.cheque,
          amount: owed,
          partyType: PartyType.shop,
          shopId: shopId,
          cheque: ChequeDetails(
            chequeNumber: '123456',
            bankName: 'Commercial Bank',
            chequeDate: DateTime.utc(2026, 11, 20),
          ),
          allocations: [
            PaymentAllocationRequest(
              invoiceId: invoice.invoiceId,
              amount: owed,
            ),
          ],
        ),
      );

      // Nothing has reached the bank account.
      expect(await finance.balanceOf(AccountCodes.bank), Money.zero);
      // And the debt is still outstanding, because outstanding counts cleared
      // money only.
      expect(await payments.outstandingOf(invoice.invoiceId), owed);
      // But it cannot be allocated against twice: the pending cheque has
      // already claimed it. This gap between the two figures is the whole
      // reason they are separate questions.
      expect(
        await payments.allocatableRemaining(invoice.invoiceId),
        Money.zero,
      );
      await expectBooksBalanced();

      // Now the money actually arrives.
      final chequeId = payment.chequeId;
      expect(chequeId, isNotNull, reason: 'a cheque payment creates a cheque');
      await payments.clearCheque(admin, chequeId: chequeId!);

      expect(await finance.balanceOf(AccountCodes.bank), owed);
      expect(await payments.outstandingOf(invoice.invoiceId), Money.zero);
      await expectBooksBalanced();
    });

    test(
      'a bounced cheque undoes the clearance and charges the shop',
      () async {
        final invoice = await invoiceWithStock(10);
        final owed = invoice.totals.net;
        final payment = await payments.recordPayment(
          admin,
          PaymentRequest(
            direction: PaymentDirection.inbound,
            method: PaymentMethod.cheque,
            amount: owed,
            partyType: PartyType.shop,
            shopId: shopId,
            cheque: ChequeDetails(
              chequeNumber: '654321',
              bankName: 'Commercial Bank',
              chequeDate: DateTime.utc(2026, 11, 20),
            ),
            allocations: [
              PaymentAllocationRequest(
                invoiceId: invoice.invoiceId,
                amount: owed,
              ),
            ],
          ),
        );
        final chequeId = payment.chequeId!;

        await payments.clearCheque(admin, chequeId: chequeId);
        expect(await finance.balanceOf(AccountCodes.bank), owed);

        await payments.bounceCheque(
          admin,
          chequeId: chequeId,
          reason: 'Insufficient funds',
          bounceCharge: const Money(50000),
        );

        // The money came in and went out again, less the charge the bank took.
        expect(await finance.balanceOf(AccountCodes.bank), const Money(-50000));
        // And the invoice is owed again.
        expect(await payments.outstandingOf(invoice.invoiceId), owed);
        await expectBooksBalanced();
      },
    );

    test('an advance with no allocation is held, not applied', () async {
      await payments.recordPayment(
        admin,
        PaymentRequest(
          direction: PaymentDirection.inbound,
          method: PaymentMethod.cash,
          amount: const Money(500000),
          partyType: PartyType.shop,
          shopId: shopId,
        ),
      );
      expect(
        await payments.advanceBalance(shopId: shopId),
        const Money(500000),
      );
      await expectBooksBalanced();
    });

    test('allocatable invoices are listed for the shop', () async {
      final invoice = await invoiceWithStock(10);
      final list = await payments.allocatableInvoices(shopId: shopId);
      expect(list.map((i) => i.invoiceId), contains(invoice.invoiceId));
    });
  });

  group('permissions', () {
    test('a cashier may bill but may not cancel', () async {
      final cashierClient = ApiClient(
        baseUrl: api.base,
        tokens: InMemoryTokenStore(),
      );
      addTearDown(cashierClient.close);
      final cashierAuth = AuthApi(cashierClient);
      await auth.createUser(
        actor: admin,
        fullName: 'Cashier',
        username: 'cashier',
        password: 'Initial1Pass',
        roleCodes: [RoleCodes.cashier],
      );
      final cashier = await cashierAuth.signIn(
        username: 'cashier',
        password: 'Initial1Pass',
      );
      await cashierAuth.changeOwnPassword(
        user: cashier,
        currentPassword: 'Initial1Pass',
        newPassword: 'Chosen2Pass9',
      );
      expect(cashier.can(Permissions.invoicePost), isTrue);
      expect(cashier.can(Permissions.invoiceCancel), isFalse);
      // And not stock: a cashier bills, a storekeeper moves goods.
      expect(cashier.can(Permissions.stockTransfer), isFalse);

      // So the cashier bills a delivery somebody else posted, rather than an
      // invoice that moves the stock itself — which is refused, correctly.
      final delivery = await ledger.postMovement(
        admin,
        StockMovementRequest(
          documentType: StockDocumentType.warehouseToShop,
          sourceLocationId: warehouseId,
          destinationLocationId: shopLocationId,
          shopId: shopId,
          lines: [
            StockMovementLine(
              productId: productId,
              quantity: 2,
              unitPrice: unitPrice,
            ),
          ],
        ),
      );

      final cashierInvoices = InvoiceApi(cashierClient);
      await expectLater(
        cashierInvoices.postInvoice(
          cashier,
          InvoiceRequest(
            kind: InvoiceKind.shopInvoice,
            shopId: shopId,
            lines: [
              InvoiceLineRequest(
                productId: productId,
                quantity: 2,
                unitPrice: unitPrice,
              ),
            ],
            stockLinkage: MoveStockWithInvoice(
              documentType: StockDocumentType.warehouseToShop,
              sourceLocationId: warehouseId,
              destinationLocationId: shopLocationId,
            ),
          ),
        ),
        throwsA(
          isA<PermissionFailure>().having(
            (f) => f.permission,
            'permission',
            Permissions.stockTransfer,
          ),
        ),
      );

      final raised = await cashierInvoices.billDelivery(
        cashier,
        stockTransactionId: delivery.transactionId,
      );
      expect(raised.invoiceNumber, isNotEmpty);

      await expectLater(
        cashierInvoices.cancelInvoice(
          cashier,
          invoiceId: raised.invoiceId,
          reason: 'Changed my mind',
        ),
        throwsA(
          isA<PermissionFailure>().having(
            (f) => f.permission,
            'permission',
            Permissions.invoiceCancel,
          ),
        ),
      );
      await expectBooksBalanced();
    });
  });
}
