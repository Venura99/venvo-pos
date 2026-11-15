import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_test/flutter_test.dart';
import 'package:venvo_core/core/constants/app_constants.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/errors/failures.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/agents/domain/agent_models.dart';
import 'package:venvo_core/features/authentication/domain/authenticated_user.dart';
import 'package:venvo_core/features/categories/domain/category_models.dart';
import 'package:venvo_core/features/inventory/domain/stock_models.dart';
import 'package:venvo_core/features/invoices/data/invoice_service.dart';
import 'package:venvo_core/features/invoices/domain/invoice_models.dart';
import 'package:venvo_core/features/payments/domain/payment_models.dart';
import 'package:venvo_core/features/products/domain/product_models.dart';
import 'package:venvo_core/features/shops/domain/shop_models.dart';

import '../helpers/master_data_fixtures.dart';

void main() {
  late MasterDataFixture fixture;
  late int chargerId;
  late int cableId;
  late int agentId;
  late int agentLocationId;
  late int shopId;
  late int shopLocationId;
  late int warehouseId;
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

    await fixture.postOpeningStock(
      locationId: warehouseId,
      productId: chargerId,
      quantity: 500,
      unitCost: Money.fromMajor(2000),
    );
  });

  tearDown(() => fixture.dispose());

  /// A shop invoice for one charger line, defaulting to the brief's figures.
  Future<InvoicePostResult> raiseShopInvoice({
    int quantity = 10,
    Money? unitPrice,
    DiscountType invoiceDiscountType = DiscountType.none,
    int invoiceDiscountValue = 0,
    DiscountType lineDiscountType = DiscountType.none,
    int lineDiscountValue = 0,
    ImmediatePayment? payment,
    String? discountReason,
    AuthenticatedUser? actor,
  }) {
    return fixture.invoices.postInvoice(
      actor ?? fixture.admin,
      InvoiceRequest(
        kind: InvoiceKind.shopInvoice,
        shopId: shopId,
        agentId: agentId,
        invoiceDiscountType: invoiceDiscountType,
        invoiceDiscountValue: invoiceDiscountValue,
        discountReason: discountReason,
        payment: payment,
        lines: [
          InvoiceLineRequest(
            productId: chargerId,
            quantity: quantity,
            unitPrice: unitPrice ?? Money.fromMajor(2000),
            discountType: lineDiscountType,
            discountValue: lineDiscountValue,
          ),
        ],
      ),
    );
  }

  Future<Money> outstanding(int invoiceId) =>
      fixture.payments.outstandingOf(invoiceId);

  group('acceptance scenarios from the brief', () {
    test('Scenario 4: a Rs. 20,000 invoice part-paid by Rs. 10,000 leaves '
        'Rs. 10,000 outstanding', () async {
      final invoice = await raiseShopInvoice();
      expect(invoice.totals.net, Money.fromMajor(20000));
      expect(await outstanding(invoice.invoiceId), Money.fromMajor(20000));

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

      expect(await outstanding(invoice.invoiceId), Money.fromMajor(10000));
    });

    test(
      'Scenario 5: a further Rs. 5,000 leaves Rs. 5,000 outstanding',
      () async {
        final invoice = await raiseShopInvoice();

        for (final amount in [Money.fromMajor(10000), Money.fromMajor(5000)]) {
          await fixture.payments.recordPayment(
            fixture.admin,
            PaymentRequest(
              direction: PaymentDirection.inbound,
              method: PaymentMethod.cash,
              amount: amount,
              shopId: shopId,
              allocations: [
                PaymentAllocationRequest(
                  invoiceId: invoice.invoiceId,
                  amount: amount,
                ),
              ],
            ),
          );
        }

        expect(await outstanding(invoice.invoiceId), Money.fromMajor(5000));
      },
    );

    test('Scenario 8: Rs. 20,000 less 10% is Rs. 18,000, and a Rs. 9,000 '
        'payment leaves Rs. 9,000 outstanding', () async {
      final invoice = await raiseShopInvoice(
        invoiceDiscountType: DiscountType.percentage,
        invoiceDiscountValue: 1000,
      );

      expect(invoice.totals.gross, Money.fromMajor(20000));
      expect(invoice.totals.invoiceDiscount, Money.fromMajor(2000));
      expect(invoice.totals.net, Money.fromMajor(18000));

      await fixture.payments.recordPayment(
        fixture.admin,
        PaymentRequest(
          direction: PaymentDirection.inbound,
          method: PaymentMethod.cash,
          amount: Money.fromMajor(9000),
          shopId: shopId,
          allocations: [
            PaymentAllocationRequest(
              invoiceId: invoice.invoiceId,
              amount: Money.fromMajor(9000),
            ),
          ],
        ),
      );

      expect(await outstanding(invoice.invoiceId), Money.fromMajor(9000));
    });

    test('Scenario 9: a Rs. 10,000 cheque that has not cleared is a pending '
        'cheque, not cleared cash', () async {
      final invoice = await raiseShopInvoice();

      final payment = await fixture.payments.recordPayment(
        fixture.admin,
        PaymentRequest(
          direction: PaymentDirection.inbound,
          method: PaymentMethod.cheque,
          amount: Money.fromMajor(10000),
          shopId: shopId,
          cheque: ChequeDetails(
            chequeNumber: '456789',
            bankName: 'Commercial Bank',
            chequeDate: fixture.harness.clock.nowUtc(),
          ),
          allocations: [
            PaymentAllocationRequest(
              invoiceId: invoice.invoiceId,
              amount: Money.fromMajor(10000),
            ),
          ],
        ),
      );

      // Recorded as pending, not cleared.
      expect(payment.status, PaymentStatus.pending);
      expect(payment.isPending, isTrue);

      // The debt has not been reduced.
      expect(await outstanding(invoice.invoiceId), Money.fromMajor(20000));

      // But the invoice cannot be allocated twice for the same money.
      expect(
        await fixture.payments.allocatableRemaining(invoice.invoiceId),
        Money.fromMajor(10000),
      );

      // It shows up as a pending cheque on the shop's balance.
      final shops = await fixture.shops.watchShops(const ShopFilter()).first;
      expect(shops.single.pendingChequeTotal, Money.fromMajor(10000));
      expect(shops.single.outstandingBalance, Money.fromMajor(20000));
    });
  });

  group('discount arithmetic', () {
    test('line discounts come off before the invoice discount', () async {
      // 10 x 2,000 = 20,000 gross. 5% on the line = 1,000, leaving 19,000.
      // 10% invoice discount on 19,000 = 1,900, leaving 17,100.
      final invoice = await raiseShopInvoice(
        lineDiscountType: DiscountType.percentage,
        lineDiscountValue: 500,
        invoiceDiscountType: DiscountType.percentage,
        invoiceDiscountValue: 1000,
      );

      expect(invoice.totals.gross, Money.fromMajor(20000));
      expect(invoice.totals.itemDiscount, Money.fromMajor(1000));
      expect(invoice.totals.afterItemDiscounts, Money.fromMajor(19000));
      expect(invoice.totals.invoiceDiscount, Money.fromMajor(1900));
      expect(invoice.totals.net, Money.fromMajor(17100));
    });

    test('a fixed-amount invoice discount is exact', () async {
      // Rs. 2,500 off Rs. 20,000 is 12.5%, which is above the 10% ceiling, so
      // it needs a reason as well as the authority to grant it.
      final invoice = await raiseShopInvoice(
        invoiceDiscountType: DiscountType.fixedAmount,
        invoiceDiscountValue: Money.fromMajor(2500).cents,
        discountReason: 'Agreed with the owner',
      );
      expect(invoice.totals.invoiceDiscount, Money.fromMajor(2500));
      expect(invoice.totals.net, Money.fromMajor(17500));
    });

    test('a fixed amount at the ceiling needs no authorisation', () async {
      final invoice = await raiseShopInvoice(
        invoiceDiscountType: DiscountType.fixedAmount,
        invoiceDiscountValue: Money.fromMajor(2000).cents,
      );
      expect(invoice.totals.net, Money.fromMajor(18000));
    });

    test(
      'a fixed discount larger than the invoice is capped, not negative',
      () async {
        final invoice = await raiseShopInvoice(
          invoiceDiscountType: DiscountType.fixedAmount,
          invoiceDiscountValue: Money.fromMajor(99999).cents,
          discountReason: 'Written off entirely',
        );
        expect(invoice.totals.net, Money.zero);
        expect(invoice.totals.invoiceDiscount, Money.fromMajor(20000));
      },
    );

    test('a fractional percentage stays exact', () async {
      // 12.5% of 20,000 is 2,500 exactly.
      final invoice = await raiseShopInvoice(
        invoiceDiscountType: DiscountType.percentage,
        invoiceDiscountValue: 1250,
        discountReason: 'Negotiated rate',
      );
      expect(invoice.totals.invoiceDiscount, Money.fromMajor(2500));
      expect(invoice.totals.net, Money.fromMajor(17500));
    });

    test('stores how the discount was entered, not only its amount', () async {
      final invoice = await raiseShopInvoice(
        invoiceDiscountType: DiscountType.percentage,
        invoiceDiscountValue: 1000,
      );

      final stored = await (fixture.db.select(
        fixture.db.invoices,
      )..where((i) => i.id.equals(invoice.invoiceId))).getSingle();
      expect(stored.invoiceDiscountType, DiscountType.percentage);
      expect(stored.invoiceDiscountValue, 1000);
      expect(stored.invoiceDiscountCents, Money.fromMajor(2000).cents);
    });

    test('records every discount in the discount history', () async {
      final invoice = await raiseShopInvoice(
        lineDiscountType: DiscountType.percentage,
        lineDiscountValue: 500,
        invoiceDiscountType: DiscountType.percentage,
        invoiceDiscountValue: 1000,
      );

      final records =
          await (fixture.db.select(fixture.db.discountRecords)
                ..where((d) => d.invoiceId.equals(invoice.invoiceId))
                ..orderBy([(d) => OrderingTerm.asc(d.id)]))
              .get();

      expect(records.length, 2);
      expect(records.first.scope, DiscountScope.item);
      expect(records.first.discountCents, Money.fromMajor(1000).cents);
      expect(records.first.baseAmountCents, Money.fromMajor(20000).cents);
      expect(records.last.scope, DiscountScope.invoice);
      expect(records.last.discountCents, Money.fromMajor(1900).cents);
      // The invoice-level discount was applied to the post-line-discount base.
      expect(records.last.baseAmountCents, Money.fromMajor(19000).cents);
    });

    test('an invoice with no discount records none', () async {
      final invoice = await raiseShopInvoice();
      final records = await (fixture.db.select(
        fixture.db.discountRecords,
      )..where((d) => d.invoiceId.equals(invoice.invoiceId))).get();
      expect(records, isEmpty);
    });
  });

  group('discount ceilings', () {
    Future<AuthenticatedUser> makeCashier() => fixture.auth.createUser(
      actor: fixture.admin,
      fullName: 'Kamal Silva',
      username: 'kamal',
      password: 'Counter123',
      roleCodes: const ['CASHIER'],
    );

    Future<AuthenticatedUser> makeManager() => fixture.auth.createUser(
      actor: fixture.admin,
      fullName: 'Nimali Rajapaksa',
      username: 'nimali',
      password: 'Manager123',
      roleCodes: const ['MANAGER'],
    );

    test('a cashier may discount a line up to the ceiling', () async {
      final cashier = await makeCashier();
      expect(cashier.can(Permissions.discountApplyItem), isTrue);
      expect(cashier.can(Permissions.discountExceedLimit), isFalse);

      // The seeded line ceiling is 15%.
      final invoice = await raiseShopInvoice(
        actor: cashier,
        lineDiscountType: DiscountType.percentage,
        lineDiscountValue: 1500,
      );
      expect(invoice.totals.itemDiscount, Money.fromMajor(3000));
      expect(invoice.totals.net, Money.fromMajor(17000));
    });

    test('a cashier cannot discount a whole invoice at all', () async {
      // Deliberate: a line discount is a counter decision, a whole-invoice
      // discount is a manager's.
      final cashier = await makeCashier();
      expect(cashier.can(Permissions.discountApplyInvoice), isFalse);

      await expectLater(
        raiseShopInvoice(
          actor: cashier,
          invoiceDiscountType: DiscountType.percentage,
          invoiceDiscountValue: 500,
        ),
        throwsA(
          isA<PermissionFailure>().having(
            (failure) => failure.permission,
            'permission',
            Permissions.discountApplyInvoice,
          ),
        ),
      );
    });

    test('a manager may discount an invoice up to the ceiling', () async {
      final manager = await makeManager();
      expect(manager.can(Permissions.discountApplyInvoice), isTrue);
      expect(manager.can(Permissions.discountExceedLimit), isFalse);

      // The seeded invoice ceiling is 10%.
      final invoice = await raiseShopInvoice(
        actor: manager,
        invoiceDiscountType: DiscountType.percentage,
        invoiceDiscountValue: 1000,
      );
      expect(invoice.totals.net, Money.fromMajor(18000));
    });

    test('a manager cannot exceed the invoice ceiling', () async {
      final manager = await makeManager();
      await expectLater(
        raiseShopInvoice(
          actor: manager,
          invoiceDiscountType: DiscountType.percentage,
          invoiceDiscountValue: 1500,
          discountReason: 'Trying it on',
        ),
        throwsA(
          isA<PermissionFailure>().having(
            (failure) => failure.permission,
            'permission',
            Permissions.discountExceedLimit,
          ),
        ),
      );
    });

    test(
      'an administrator may exceed it, with a reason, and it is recorded',
      () async {
        final invoice = await raiseShopInvoice(
          invoiceDiscountType: DiscountType.percentage,
          invoiceDiscountValue: 2000,
          discountReason: 'Clearing old stock',
        );
        expect(invoice.totals.net, Money.fromMajor(16000));

        final stored = await (fixture.db.select(
          fixture.db.invoices,
        )..where((i) => i.id.equals(invoice.invoiceId))).getSingle();
        expect(stored.discountApprovedByUserId, fixture.admin.id);
        expect(stored.discountReason, 'Clearing old stock');

        final record = await (fixture.db.select(
          fixture.db.discountRecords,
        )..where((d) => d.invoiceId.equals(invoice.invoiceId))).getSingle();
        expect(record.exceededLimit, isTrue);
        expect(record.approvedByUserId, fixture.admin.id);

        final entries = await fixture.auditEntries();
        expect(
          entries.any(
            (entry) =>
                entry.action == AuditAction.permissionOverride &&
                entry.summary.contains('above the configured ceiling'),
          ),
          isTrue,
        );
      },
    );

    test(
      'exceeding the ceiling requires a reason even for an administrator',
      () async {
        await expectLater(
          raiseShopInvoice(
            invoiceDiscountType: DiscountType.percentage,
            invoiceDiscountValue: 2000,
          ),
          throwsA(isA<ValidationFailure>()),
        );
      },
    );

    test('the line ceiling is checked separately', () async {
      final cashier = await makeCashier();
      // The seeded line ceiling is 15%.
      await raiseShopInvoice(
        actor: cashier,
        lineDiscountType: DiscountType.percentage,
        lineDiscountValue: 1500,
      );

      await expectLater(
        raiseShopInvoice(
          actor: cashier,
          lineDiscountType: DiscountType.percentage,
          lineDiscountValue: 1600,
          discountReason: 'Too much',
        ),
        throwsA(isA<PermissionFailure>()),
      );
    });

    test(
      'a fixed-amount discount is measured against the same ceiling',
      () async {
        final manager = await makeManager();
        // Rs. 4,000 off Rs. 20,000 is 20%, over the 10% invoice ceiling. How it
        // was entered makes no difference to whether it is allowed.
        await expectLater(
          raiseShopInvoice(
            actor: manager,
            invoiceDiscountType: DiscountType.fixedAmount,
            invoiceDiscountValue: Money.fromMajor(4000).cents,
            discountReason: 'Over the line',
          ),
          throwsA(
            isA<PermissionFailure>().having(
              (failure) => failure.permission,
              'permission',
              Permissions.discountExceedLimit,
            ),
          ),
        );
      },
    );

    test(
      'a user without the discount permission cannot discount at all',
      () async {
        final keeper = await fixture.auth.createUser(
          actor: fixture.admin,
          fullName: 'Sunil Fernando',
          username: 'sunil',
          password: 'Keeper123',
          roleCodes: const ['STORE_KEEPER'],
        );

        await expectLater(
          raiseShopInvoice(
            actor: keeper,
            invoiceDiscountType: DiscountType.percentage,
            invoiceDiscountValue: 100,
          ),
          throwsA(isA<PermissionFailure>()),
        );
      },
    );
  });

  group('allocation rules', () {
    test('refuses to allocate more than the payment', () async {
      final invoice = await raiseShopInvoice();
      await expectLater(
        fixture.payments.recordPayment(
          fixture.admin,
          PaymentRequest(
            direction: PaymentDirection.inbound,
            method: PaymentMethod.cash,
            amount: Money.fromMajor(5000),
            shopId: shopId,
            allocations: [
              PaymentAllocationRequest(
                invoiceId: invoice.invoiceId,
                amount: Money.fromMajor(6000),
              ),
            ],
          ),
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('refuses to over-allocate an invoice', () async {
      final invoice = await raiseShopInvoice();
      await expectLater(
        fixture.payments.recordPayment(
          fixture.admin,
          PaymentRequest(
            direction: PaymentDirection.inbound,
            method: PaymentMethod.cash,
            amount: Money.fromMajor(25000),
            shopId: shopId,
            allocations: [
              PaymentAllocationRequest(
                invoiceId: invoice.invoiceId,
                amount: Money.fromMajor(25000),
              ),
            ],
          ),
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'payment.no_over_allocation',
          ),
        ),
      );
    });

    test(
      'a pending cheque stops the same invoice being allocated twice',
      () async {
        final invoice = await raiseShopInvoice();
        await fixture.payments.recordPayment(
          fixture.admin,
          PaymentRequest(
            direction: PaymentDirection.inbound,
            method: PaymentMethod.cheque,
            amount: Money.fromMajor(20000),
            shopId: shopId,
            cheque: ChequeDetails(
              chequeNumber: '111',
              bankName: 'Commercial Bank',
              chequeDate: fixture.harness.clock.nowUtc(),
            ),
            allocations: [
              PaymentAllocationRequest(
                invoiceId: invoice.invoiceId,
                amount: Money.fromMajor(20000),
              ),
            ],
          ),
        );

        // Still fully owed, because the cheque has not cleared...
        expect(await outstanding(invoice.invoiceId), Money.fromMajor(20000));
        // ...but nothing more may be promised against it.
        expect(
          await fixture.payments.allocatableRemaining(invoice.invoiceId),
          Money.zero,
        );

        await expectLater(
          fixture.payments.recordPayment(
            fixture.admin,
            PaymentRequest(
              direction: PaymentDirection.inbound,
              method: PaymentMethod.cash,
              amount: Money.fromMajor(5000),
              shopId: shopId,
              allocations: [
                PaymentAllocationRequest(
                  invoiceId: invoice.invoiceId,
                  amount: Money.fromMajor(5000),
                ),
              ],
            ),
          ),
          throwsA(isA<BusinessRuleFailure>()),
        );
      },
    );

    test('money received with nothing applied is an advance', () async {
      final payment = await fixture.payments.recordPayment(
        fixture.admin,
        PaymentRequest(
          direction: PaymentDirection.inbound,
          method: PaymentMethod.cash,
          amount: Money.fromMajor(7000),
          shopId: shopId,
        ),
      );

      expect(payment.allocated, Money.zero);
      expect(payment.unallocated, Money.fromMajor(7000));
      expect(
        await fixture.payments.advanceBalance(shopId: shopId),
        Money.fromMajor(7000),
      );
    });

    test('an advance can be applied to an invoice later', () async {
      final payment = await fixture.payments.recordPayment(
        fixture.admin,
        PaymentRequest(
          direction: PaymentDirection.inbound,
          method: PaymentMethod.cash,
          amount: Money.fromMajor(7000),
          shopId: shopId,
        ),
      );
      final invoice = await raiseShopInvoice();

      await fixture.payments.allocate(
        fixture.admin,
        paymentId: payment.paymentId,
        allocations: [
          PaymentAllocationRequest(
            invoiceId: invoice.invoiceId,
            amount: Money.fromMajor(7000),
          ),
        ],
      );

      expect(await outstanding(invoice.invoiceId), Money.fromMajor(13000));
      expect(await fixture.payments.advanceBalance(shopId: shopId), Money.zero);
    });

    test('one payment can settle several invoices', () async {
      final first = await raiseShopInvoice(quantity: 5);
      final second = await raiseShopInvoice(quantity: 3);

      await fixture.payments.recordPayment(
        fixture.admin,
        PaymentRequest(
          direction: PaymentDirection.inbound,
          method: PaymentMethod.cash,
          amount: Money.fromMajor(16000),
          shopId: shopId,
          allocations: [
            PaymentAllocationRequest(
              invoiceId: first.invoiceId,
              amount: Money.fromMajor(10000),
            ),
            PaymentAllocationRequest(
              invoiceId: second.invoiceId,
              amount: Money.fromMajor(6000),
            ),
          ],
        ),
      );

      expect(await outstanding(first.invoiceId), Money.zero);
      expect(await outstanding(second.invoiceId), Money.zero);
    });

    test('an allocation can be withdrawn, leaving the trail intact', () async {
      final invoice = await raiseShopInvoice();
      final payment = await fixture.payments.recordPayment(
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

      await fixture.payments.releaseAllocation(
        fixture.admin,
        paymentId: payment.paymentId,
        invoiceId: invoice.invoiceId,
        reason: 'Applied to the wrong invoice',
      );

      expect(await outstanding(invoice.invoiceId), Money.fromMajor(20000));
      expect(
        await fixture.payments.advanceBalance(shopId: shopId),
        Money.fromMajor(10000),
      );

      // Both the original allocation and its withdrawal are on record.
      final allocations = await (fixture.db.select(
        fixture.db.paymentAllocations,
      )..where((a) => a.invoiceId.equals(invoice.invoiceId))).get();
      expect(allocations.length, 2);
      expect(allocations.map((a) => a.amountCents).reduce((a, b) => a + b), 0);
    });

    test('refuses to allocate to an unposted invoice', () async {
      final invoice = await raiseShopInvoice();
      await fixture.invoices.cancelInvoice(
        fixture.admin,
        invoiceId: invoice.invoiceId,
        reason: 'Raised in error',
      );

      await expectLater(
        fixture.payments.recordPayment(
          fixture.admin,
          PaymentRequest(
            direction: PaymentDirection.inbound,
            method: PaymentMethod.cash,
            amount: Money.fromMajor(1000),
            shopId: shopId,
            allocations: [
              PaymentAllocationRequest(
                invoiceId: invoice.invoiceId,
                amount: Money.fromMajor(1000),
              ),
            ],
          ),
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'payment.invoice_posted_only',
          ),
        ),
      );
    });
  });

  group('cheque lifecycle', () {
    Future<({int invoiceId, int chequeId, int paymentId})> giveCheque({
      Money? amount,
      DateTime? chequeDate,
    }) async {
      final invoice = await raiseShopInvoice();
      final payment = await fixture.payments.recordPayment(
        fixture.admin,
        PaymentRequest(
          direction: PaymentDirection.inbound,
          method: PaymentMethod.cheque,
          amount: amount ?? Money.fromMajor(10000),
          shopId: shopId,
          cheque: ChequeDetails(
            chequeNumber: '777',
            bankName: 'Commercial Bank',
            chequeDate: chequeDate ?? fixture.harness.clock.nowUtc(),
          ),
          allocations: [
            PaymentAllocationRequest(
              invoiceId: invoice.invoiceId,
              amount: amount ?? Money.fromMajor(10000),
            ),
          ],
        ),
      );
      return (
        invoiceId: invoice.invoiceId,
        chequeId: payment.chequeId!,
        paymentId: payment.paymentId,
      );
    }

    test('clearing a cheque turns it into settlement', () async {
      final given = await giveCheque();
      expect(await outstanding(given.invoiceId), Money.fromMajor(20000));

      await fixture.payments.clearCheque(
        fixture.admin,
        chequeId: given.chequeId,
      );

      expect(await outstanding(given.invoiceId), Money.fromMajor(10000));

      final payment = await (fixture.db.select(
        fixture.db.payments,
      )..where((p) => p.id.equals(given.paymentId))).getSingle();
      expect(payment.status, PaymentStatus.cleared);
      expect(payment.clearedAt, isNotNull);
    });

    test('a bounce brings the debt back without rewriting anything', () async {
      final given = await giveCheque();
      await fixture.payments.clearCheque(
        fixture.admin,
        chequeId: given.chequeId,
      );
      expect(await outstanding(given.invoiceId), Money.fromMajor(10000));

      await fixture.payments.bounceCheque(
        fixture.admin,
        chequeId: given.chequeId,
        reason: 'Insufficient funds',
        bounceCharge: Money.fromMajor(500),
      );

      // The debt is owed again.
      expect(await outstanding(given.invoiceId), Money.fromMajor(20000));

      // The payment and its allocation are still there.
      final allocations = await (fixture.db.select(
        fixture.db.paymentAllocations,
      )..where((a) => a.paymentId.equals(given.paymentId))).get();
      expect(allocations.length, 1);
      expect(allocations.single.amountCents, Money.fromMajor(10000).cents);

      final cheque = await (fixture.db.select(
        fixture.db.cheques,
      )..where((c) => c.id.equals(given.chequeId))).getSingle();
      expect(cheque.status, ChequeStatus.bounced);
      expect(cheque.bounceReason, 'Insufficient funds');
      expect(cheque.bounceChargeCents, Money.fromMajor(500).cents);
      expect(cheque.clearedAt, isNull);
    });

    test(
      'a bounced cheque frees the invoice for a replacement payment',
      () async {
        final given = await giveCheque();
        await fixture.payments.bounceCheque(
          fixture.admin,
          chequeId: given.chequeId,
          reason: 'Signature mismatch',
        );

        // The promise is gone, so money may be applied again.
        expect(
          await fixture.payments.allocatableRemaining(given.invoiceId),
          Money.fromMajor(20000),
        );

        final replacement = await fixture.payments.recordPayment(
          fixture.admin,
          PaymentRequest(
            direction: PaymentDirection.inbound,
            method: PaymentMethod.cash,
            amount: Money.fromMajor(10000),
            shopId: shopId,
            allocations: [
              PaymentAllocationRequest(
                invoiceId: given.invoiceId,
                amount: Money.fromMajor(10000),
              ),
            ],
          ),
        );

        await fixture.payments.linkReplacementPayment(
          fixture.admin,
          chequeId: given.chequeId,
          replacementPaymentId: replacement.paymentId,
        );

        expect(await outstanding(given.invoiceId), Money.fromMajor(10000));
        final cheque = await (fixture.db.select(
          fixture.db.cheques,
        )..where((c) => c.id.equals(given.chequeId))).getSingle();
        expect(cheque.replacementPaymentId, replacement.paymentId);
      },
    );

    test('banking a cheque is not the same as clearing it', () async {
      final given = await giveCheque();
      await fixture.payments.depositCheque(
        fixture.admin,
        chequeId: given.chequeId,
      );

      final cheque = await (fixture.db.select(
        fixture.db.cheques,
      )..where((c) => c.id.equals(given.chequeId))).getSingle();
      expect(cheque.status, ChequeStatus.deposited);
      // Still not settlement.
      expect(await outstanding(given.invoiceId), Money.fromMajor(20000));
    });

    test('a post-dated cheque cannot be banked early', () async {
      final given = await giveCheque(
        chequeDate: fixture.harness.clock.nowUtc().add(
          const Duration(days: 30),
        ),
      );

      await expectLater(
        fixture.payments.depositCheque(fixture.admin, chequeId: given.chequeId),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'cheque.not_before_its_date',
          ),
        ),
      );
    });

    test('a cheque cannot bounce twice', () async {
      final given = await giveCheque();
      await fixture.payments.bounceCheque(
        fixture.admin,
        chequeId: given.chequeId,
        reason: 'Insufficient funds',
      );
      await expectLater(
        fixture.payments.bounceCheque(
          fixture.admin,
          chequeId: given.chequeId,
          reason: 'Again',
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'cheque.bounce_once',
          ),
        ),
      );
    });

    test('a bounce needs a reason', () async {
      final given = await giveCheque();
      await expectLater(
        fixture.payments.bounceCheque(
          fixture.admin,
          chequeId: given.chequeId,
          reason: '  ',
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('cheque handling needs the cheque permission', () async {
      final given = await giveCheque();
      final cashier = await fixture.auth.createUser(
        actor: fixture.admin,
        fullName: 'Kamal Silva',
        username: 'kamal',
        password: 'Counter123',
        roleCodes: const ['CASHIER'],
      );
      expect(cashier.can(Permissions.chequeManage), isFalse);

      await expectLater(
        fixture.payments.clearCheque(cashier, chequeId: given.chequeId),
        throwsA(isA<PermissionFailure>()),
      );
    });
  });

  group('transfers, invoices and revenue', () {
    test('a transfer alone creates no receivable', () async {
      await fixture.stockLedger.postMovement(
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

      final agents = await fixture.agents
          .watchAgents(const AgentFilter())
          .first;
      expect(agents.single.billedTotal, Money.zero);
      expect(agents.single.outstandingBalance, Money.zero);
    });

    test('billing the delivery turns it into a receivable', () async {
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

      // The brief's example: 50 at Rs. 3,000 is Rs. 150,000.
      expect(invoice.totals.net, Money.fromMajor(150000));
      expect(invoice.invoiceNumber, startsWith('AINV-'));

      final agents = await fixture.agents
          .watchAgents(const AgentFilter())
          .first;
      expect(agents.single.billedTotal, Money.fromMajor(150000));
      expect(agents.single.outstandingBalance, Money.fromMajor(150000));

      // The invoice points at the delivery it bills.
      final stored = await (fixture.db.select(
        fixture.db.invoices,
      )..where((i) => i.id.equals(invoice.invoiceId))).getSingle();
      expect(stored.stockTransactionId, transfer.transactionId);
    });

    test('billing the gross profit uses the cost the goods carried', () async {
      final transfer = await fixture.stockLedger.postMovement(
        fixture.admin,
        StockMovementRequest(
          documentType: StockDocumentType.warehouseToAgent,
          sourceLocationId: warehouseId,
          destinationLocationId: agentLocationId,
          lines: [
            StockMovementLine(
              productId: chargerId,
              quantity: 10,
              unitPrice: Money.fromMajor(3000),
            ),
          ],
        ),
      );
      final invoice = await fixture.invoices.billDelivery(
        fixture.admin,
        stockTransactionId: transfer.transactionId,
      );

      // 10 sold at 3,000 against a carrying cost of 2,000.
      expect(invoice.cost, Money.fromMajor(20000));
      expect(invoice.grossProfit, Money.fromMajor(10000));
    });

    test('a delivery cannot be billed twice', () async {
      final transfer = await fixture.stockLedger.postMovement(
        fixture.admin,
        StockMovementRequest(
          documentType: StockDocumentType.warehouseToAgent,
          sourceLocationId: warehouseId,
          destinationLocationId: agentLocationId,
          lines: [
            StockMovementLine(
              productId: chargerId,
              quantity: 5,
              unitPrice: Money.fromMajor(3000),
            ),
          ],
        ),
      );
      await fixture.invoices.billDelivery(
        fixture.admin,
        stockTransactionId: transfer.transactionId,
      );

      await expectLater(
        fixture.invoices.billDelivery(
          fixture.admin,
          stockTransactionId: transfer.transactionId,
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'invoice.bill_document_once',
          ),
        ),
      );
    });

    test('an adjustment document is not billable', () async {
      final adjustment = await fixture.locations.byCode(
        AppConstants.adjustmentLocationCode,
      );
      final movement = await fixture.stockLedger.postMovement(
        fixture.admin,
        StockMovementRequest(
          documentType: StockDocumentType.adjustmentIncrease,
          sourceLocationId: adjustment.id,
          destinationLocationId: warehouseId,
          lines: [StockMovementLine(productId: cableId, quantity: 5)],
        ),
      );

      await expectLater(
        fixture.invoices.billDelivery(
          fixture.admin,
          stockTransactionId: movement.transactionId,
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'invoice.billable_document_types',
          ),
        ),
      );
    });
  });

  group('retail sale', () {
    test('moves the shop stock and records the sale in one step', () async {
      // Stock the shop first, via the agent.
      await fixture.stockLedger.postMovement(
        fixture.admin,
        StockMovementRequest(
          documentType: StockDocumentType.warehouseToAgent,
          sourceLocationId: warehouseId,
          destinationLocationId: agentLocationId,
          lines: [StockMovementLine(productId: chargerId, quantity: 50)],
        ),
      );
      await fixture.stockLedger.postMovement(
        fixture.admin,
        StockMovementRequest(
          documentType: StockDocumentType.agentToShop,
          sourceLocationId: agentLocationId,
          destinationLocationId: shopLocationId,
          lines: [StockMovementLine(productId: chargerId, quantity: 20)],
        ),
      );

      final sale = await fixture.invoices.postInvoice(
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
          payment: ImmediatePayment(
            method: PaymentMethod.cash,
            amount: Money.fromMajor(35000),
          ),
          lines: [
            InvoiceLineRequest(
              productId: chargerId,
              quantity: 10,
              unitPrice: Money.fromMajor(3500),
            ),
          ],
        ),
      );

      expect(sale.invoiceNumber, startsWith('RS-'));
      expect(sale.totals.net, Money.fromMajor(35000));
      expect(sale.stockDocumentNumber, isNotNull);

      // The brief's scenario 3 figures, reached through the sale.
      expect(
        await fixture.stockLedger.balanceOf(
          locationId: shopLocationId,
          productId: chargerId,
        ),
        10,
      );
      expect(
        await fixture.stockLedger.balanceOf(
          locationId: customerLocationId,
          productId: chargerId,
        ),
        10,
      );

      // Paid in full at the counter.
      expect(await outstanding(sale.invoiceId), Money.zero);

      // And it is reported apart from what the shop was supplied.
      final shops = await fixture.shops.watchShops(const ShopFilter()).first;
      expect(shops.single.retailSalesTotal, Money.fromMajor(35000));
      expect(shops.single.billedTotal, Money.zero);
    });

    test('a sale beyond the shop stock is refused', () async {
      await expectLater(
        fixture.invoices.postInvoice(
          fixture.admin,
          InvoiceRequest(
            kind: InvoiceKind.retailSale,
            shopId: shopId,
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
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'stock.no_negative_balance',
          ),
        ),
      );

      // Nothing was left behind: no invoice, no stock movement.
      expect(await fixture.db.select(fixture.db.invoices).get(), isEmpty);
      final retailDocuments =
          await (fixture.db.select(fixture.db.stockTransactions)..where(
                (t) => t.documentType.equalsValue(StockDocumentType.retailSale),
              ))
              .get();
      expect(retailDocuments, isEmpty);
    });
  });

  group('immediate payment', () {
    test('a cash sale settles on the spot', () async {
      final invoice = await raiseShopInvoice(
        payment: ImmediatePayment(
          method: PaymentMethod.cash,
          amount: Money.fromMajor(20000),
        ),
      );
      expect(invoice.payment, isNotNull);
      expect(invoice.outstanding, Money.zero);
      expect(await outstanding(invoice.invoiceId), Money.zero);
    });

    test(
      'a cheque taken with the invoice leaves it owed until it clears',
      () async {
        final invoice = await raiseShopInvoice(
          payment: ImmediatePayment(
            method: PaymentMethod.cheque,
            amount: Money.fromMajor(20000),
            chequeNumber: '999',
            bankName: 'Sampath Bank',
            chequeDate: fixture.harness.clock.nowUtc(),
          ),
        );

        expect(invoice.payment!.status, PaymentStatus.pending);
        expect(invoice.outstanding, Money.fromMajor(20000));
        expect(await outstanding(invoice.invoiceId), Money.fromMajor(20000));
      },
    );

    test('refuses a payment larger than the invoice', () async {
      await expectLater(
        raiseShopInvoice(
          payment: ImmediatePayment(
            method: PaymentMethod.cash,
            amount: Money.fromMajor(25000),
          ),
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });
  });

  group('cancelling an invoice', () {
    test(
      'releases received money as an advance and keeps the invoice',
      () async {
        final invoice = await raiseShopInvoice(
          payment: ImmediatePayment(
            method: PaymentMethod.cash,
            amount: Money.fromMajor(12000),
          ),
        );

        final result = await fixture.invoices.cancelInvoice(
          fixture.admin,
          invoiceId: invoice.invoiceId,
          reason: 'Duplicate of SINV-2026-00002',
        );

        expect(result.releasedMoney, Money.fromMajor(12000));
        // The money was received, so it is now held as an advance.
        expect(
          await fixture.payments.advanceBalance(shopId: shopId),
          Money.fromMajor(12000),
        );

        // The invoice and its lines are untouched apart from the status.
        final stored = await (fixture.db.select(
          fixture.db.invoices,
        )..where((i) => i.id.equals(invoice.invoiceId))).getSingle();
        expect(stored.status, InvoiceStatus.cancelled);
        expect(stored.netTotalCents, Money.fromMajor(20000).cents);
        expect(stored.cancelReason, 'Duplicate of SINV-2026-00002');

        final lines = await (fixture.db.select(
          fixture.db.invoiceItems,
        )..where((i) => i.invoiceId.equals(invoice.invoiceId))).get();
        expect(lines.length, 1);

        // It no longer counts against the shop.
        final shops = await fixture.shops.watchShops(const ShopFilter()).first;
        expect(shops.single.billedTotal, Money.zero);
        expect(shops.single.outstandingBalance, Money.zero);
      },
    );

    test('optionally reverses the stock it moved', () async {
      await fixture.stockLedger.postMovement(
        fixture.admin,
        StockMovementRequest(
          documentType: StockDocumentType.warehouseToAgent,
          sourceLocationId: warehouseId,
          destinationLocationId: agentLocationId,
          lines: [StockMovementLine(productId: chargerId, quantity: 50)],
        ),
      );
      await fixture.stockLedger.postMovement(
        fixture.admin,
        StockMovementRequest(
          documentType: StockDocumentType.agentToShop,
          sourceLocationId: agentLocationId,
          destinationLocationId: shopLocationId,
          lines: [StockMovementLine(productId: chargerId, quantity: 20)],
        ),
      );

      final sale = await fixture.invoices.postInvoice(
        fixture.admin,
        InvoiceRequest(
          kind: InvoiceKind.retailSale,
          shopId: shopId,
          stockLinkage: MoveStockWithInvoice(
            documentType: StockDocumentType.retailSale,
            sourceLocationId: shopLocationId,
            destinationLocationId: customerLocationId,
          ),
          lines: [
            InvoiceLineRequest(
              productId: chargerId,
              quantity: 10,
              unitPrice: Money.fromMajor(3500),
            ),
          ],
        ),
      );
      expect(
        await fixture.stockLedger.balanceOf(
          locationId: shopLocationId,
          productId: chargerId,
        ),
        10,
      );

      final result = await fixture.invoices.cancelInvoice(
        fixture.admin,
        invoiceId: sale.invoiceId,
        reason: 'Customer changed their mind',
        reverseStockMovement: true,
      );

      expect(result.stockReversalDocumentNumber, isNotNull);
      // The goods are back on the shop's shelf.
      expect(
        await fixture.stockLedger.balanceOf(
          locationId: shopLocationId,
          productId: chargerId,
        ),
        20,
      );
      expect(await fixture.stockLedger.findUnbalancedProducts(), isEmpty);
    });

    test('leaves a separately posted delivery alone', () async {
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
        reason: 'Billed at the wrong price',
      );

      // Cancelling the bill is not un-shipping the goods.
      expect(
        await fixture.stockLedger.balanceOf(
          locationId: agentLocationId,
          productId: chargerId,
        ),
        50,
      );

      // And the delivery can be billed again at the right price.
      final rebilled = await fixture.invoices.billDelivery(
        fixture.admin,
        stockTransactionId: transfer.transactionId,
        priceOverrides: {chargerId: Money.fromMajor(3200)},
      );
      expect(rebilled.totals.net, Money.fromMajor(160000));
    });

    test('cannot be cancelled twice', () async {
      final invoice = await raiseShopInvoice();
      await fixture.invoices.cancelInvoice(
        fixture.admin,
        invoiceId: invoice.invoiceId,
        reason: 'First',
      );
      await expectLater(
        fixture.invoices.cancelInvoice(
          fixture.admin,
          invoiceId: invoice.invoiceId,
          reason: 'Again',
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'invoice.cancel_posted_only',
          ),
        ),
      );
    });

    test('needs the cancel permission', () async {
      final invoice = await raiseShopInvoice();
      final cashier = await fixture.auth.createUser(
        actor: fixture.admin,
        fullName: 'Kamal Silva',
        username: 'kamal',
        password: 'Counter123',
        roleCodes: const ['CASHIER'],
      );

      await expectLater(
        fixture.invoices.cancelInvoice(
          cashier,
          invoiceId: invoice.invoiceId,
          reason: 'Nope',
        ),
        throwsA(isA<PermissionFailure>()),
      );
    });
  });

  group('invoice validation', () {
    test('refuses an empty invoice', () async {
      await expectLater(
        fixture.invoices.postInvoice(
          fixture.admin,
          const InvoiceRequest(
            kind: InvoiceKind.shopInvoice,
            shopId: 1,
            lines: [],
          ),
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('refuses a duplicated product', () async {
      await expectLater(
        fixture.invoices.postInvoice(
          fixture.admin,
          InvoiceRequest(
            kind: InvoiceKind.shopInvoice,
            shopId: shopId,
            lines: [
              InvoiceLineRequest(
                productId: chargerId,
                quantity: 2,
                unitPrice: Money.fromMajor(3000),
              ),
              InvoiceLineRequest(
                productId: chargerId,
                quantity: 3,
                unitPrice: Money.fromMajor(3000),
              ),
            ],
          ),
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'invoice.no_duplicate_products',
          ),
        ),
      );
    });

    test('refuses a zero price', () async {
      await expectLater(
        raiseShopInvoice(unitPrice: Money.zero),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('requires a party that suits the kind', () async {
      await expectLater(
        fixture.invoices.postInvoice(
          fixture.admin,
          InvoiceRequest(
            kind: InvoiceKind.agentInvoice,
            lines: [
              InvoiceLineRequest(
                productId: chargerId,
                quantity: 1,
                unitPrice: Money.fromMajor(3000),
              ),
            ],
          ),
        ),
        throwsA(isA<NotFoundFailure>()),
      );
    });

    test('refuses an archived product', () async {
      final retired = await fixture.products.create(
        fixture.admin,
        ProductDraft(
          sku: 'OLD-1',
          name: 'Discontinued',
          categoryId:
              (await fixture.categories.selectableCategories()).first.id,
        ),
      );
      await fixture.products.archive(fixture.admin, retired);

      await expectLater(
        fixture.invoices.postInvoice(
          fixture.admin,
          InvoiceRequest(
            kind: InvoiceKind.shopInvoice,
            shopId: shopId,
            lines: [
              InvoiceLineRequest(
                productId: retired,
                quantity: 1,
                unitPrice: Money.fromMajor(100),
              ),
            ],
          ),
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'invoice.product_not_archived',
          ),
        ),
      );
    });

    test('snapshots the product name and the price billed', () async {
      final invoice = await raiseShopInvoice();

      await fixture.products.update(
        fixture.admin,
        ProductDraft(
          id: chargerId,
          sku: 'CHG-25W-V2',
          name: '25W Charger (2027 model)',
          categoryId:
              (await fixture.categories.selectableCategories()).first.id,
          wholesalePrice: Money.fromMajor(9999),
        ),
      );

      final line = await (fixture.db.select(
        fixture.db.invoiceItems,
      )..where((i) => i.invoiceId.equals(invoice.invoiceId))).getSingle();
      expect(line.productNameSnapshot, '25W Charger');
      expect(line.skuSnapshot, 'CHG-25W');
      expect(line.unitPriceCents, Money.fromMajor(2000).cents);
    });

    test('a shop over its credit limit is recorded but not blocked', () async {
      await fixture.shops.update(
        fixture.admin,
        ShopDraft(
          id: shopId,
          name: 'Shop A',
          assignedAgentId: agentId,
          creditLimit: Money.fromMajor(5000),
        ),
      );

      // Refusing this would stop a delivery van at the door, so it goes
      // through and the breach is recorded instead.
      final invoice = await raiseShopInvoice();
      expect(invoice.totals.net, Money.fromMajor(20000));

      final entries = await fixture.auditEntries();
      expect(
        entries.any((entry) => entry.summary.contains('over its credit limit')),
        isTrue,
      );
    });

    test('needs the post permission', () async {
      final viewer = await fixture.createViewer();
      await expectLater(
        raiseShopInvoice(actor: viewer),
        throwsA(isA<PermissionFailure>()),
      );
    });
  });

  group('invoice numbering', () {
    test('uses a different prefix per kind', () async {
      final shopInvoice = await raiseShopInvoice(quantity: 1);
      expect(shopInvoice.invoiceNumber, startsWith('SINV-'));

      final transfer = await fixture.stockLedger.postMovement(
        fixture.admin,
        StockMovementRequest(
          documentType: StockDocumentType.warehouseToAgent,
          sourceLocationId: warehouseId,
          destinationLocationId: agentLocationId,
          lines: [
            StockMovementLine(
              productId: chargerId,
              quantity: 1,
              unitPrice: Money.fromMajor(3000),
            ),
          ],
        ),
      );
      final agentInvoice = await fixture.invoices.billDelivery(
        fixture.admin,
        stockTransactionId: transfer.transactionId,
      );
      expect(agentInvoice.invoiceNumber, startsWith('AINV-'));
    });

    test('numbers are sequential within a kind', () async {
      final first = await raiseShopInvoice(quantity: 1);
      final second = await raiseShopInvoice(quantity: 1);
      expect(first.invoiceNumber, 'SINV-2026-00001');
      expect(second.invoiceNumber, 'SINV-2026-00002');
    });

    test('a failed invoice does not consume a number', () async {
      await expectLater(
        raiseShopInvoice(unitPrice: Money.zero),
        throwsA(isA<ValidationFailure>()),
      );
      final invoice = await raiseShopInvoice(quantity: 1);
      expect(invoice.invoiceNumber, 'SINV-2026-00001');
    });
  });
}
