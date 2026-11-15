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
import 'package:venvo_core/features/products/api/product_api.dart';
import 'package:venvo_core/features/products/domain/product_models.dart';
import 'package:venvo_core/features/returns/api/return_api.dart';
import 'package:venvo_core/features/returns/domain/return_models.dart';
import 'package:venvo_core/features/shops/api/shop_api.dart';
import 'package:venvo_core/features/shops/domain/shop_models.dart';

import 'support/api_harness.dart';

/// Goods coming back, and the credit raised for them.
///
/// The design this exercises: a return is a **two-leg** move through an
/// in-transit location, returned goods never re-enter sellable stock until
/// somebody has inspected them, and only the accepted and damaged units are
/// worth crediting — scrapped goods are worth nothing.
void main() {
  late ApiHarness api;
  late ApiClient client;
  late AuthApi auth;
  late AuthenticatedUser admin;
  late ReturnApi returns;
  late ReturnQueryApi returnQueries;
  late StockLedgerApi ledger;
  late PaymentApi payments;
  late FinanceApi finance;

  late int warehouseId;
  late int shopLocationId;
  late int agentLocationId;
  late int damagedLocationId;
  late int inTransitLocationId;
  late int shopId;
  late int agentId;
  late int productId;
  late InvoicePostResult invoice;

  const unitPrice = Money(130000); // Rs 1,300.00

  setUp(() async {
    api = await ApiHarness.start();
    client = ApiClient(baseUrl: api.base, tokens: InMemoryTokenStore());
    auth = AuthApi(client);
    returns = ReturnApi(client);
    returnQueries = ReturnQueryApi(client);
    ledger = StockLedgerApi(client);
    payments = PaymentApi(client);
    finance = FinanceApi(client);

    admin = await auth.createFirstAdministrator(
      fullName: 'Venura Admin',
      username: 'admin',
      password: ApiHarness.adminPassword,
    );

    final locations = LocationApi(client);
    final all = await locations.watchLocations(includeVirtual: true).first;
    int byCode(String code) => all.firstWhere((l) => l.code == code).id;
    warehouseId = byCode(AppConstants.mainWarehouseCode);
    damagedLocationId = byCode(AppConstants.damagedLocationCode);
    inTransitLocationId = byCode(AppConstants.inTransitLocationCode);
    final supplierId = byCode(AppConstants.supplierLocationCode);

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

    agentId = await AgentApi(
      client,
    ).create(admin, const AgentDraft(name: 'Kandy route'));
    shopId = await ShopApi(client).create(
      admin,
      ShopDraft(name: 'Sea Street Mobiles', assignedAgentId: agentId),
    );
    final withParties = await locations.watchLocations().first;
    shopLocationId = withParties.firstWhere((l) => l.shopId == shopId).id;
    agentLocationId = withParties.firstWhere((l) => l.agentId == agentId).id;

    await ledger.postMovement(
      admin,
      StockMovementRequest(
        documentType: StockDocumentType.openingStock,
        sourceLocationId: supplierId,
        destinationLocationId: warehouseId,
        lines: [
          StockMovementLine(
            productId: productId,
            quantity: 100,
            unitCost: const Money(100000),
          ),
        ],
      ),
    );

    // Sell 50 to the shop, so there is something to return and an invoice to
    // credit against.
    invoice = await InvoiceApi(client).postInvoice(
      admin,
      InvoiceRequest(
        kind: InvoiceKind.shopInvoice,
        shopId: shopId,
        lines: [
          InvoiceLineRequest(
            productId: productId,
            quantity: 50,
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
  });

  tearDown(() async {
    await client.close();
    await api.stop();
  });

  Future<int> balanceAt(int locationId) =>
      ledger.balanceOf(locationId: locationId, productId: productId);

  Future<void> expectBooksBalanced() async {
    expect(await finance.findUnbalancedBatches(), isEmpty);
    expect((await finance.trialBalance()).isBalanced, isTrue);
    expect(await ledger.findUnbalancedProducts(), isEmpty);
  }

  /// Builds the return the way a client should: from the invoice's returnable
  /// lines, so each returned unit is linked to the line it was billed on
  /// through `originInvoiceItemId`.
  ///
  /// That link is what traces a return back to its billed line. Omitting it
  /// does not get the request refused — the aggregate "no more than was
  /// billed" guard still holds, because that counts against the origin
  /// invoice — but the per-line returned quantity stays at zero, so a screen
  /// built on `returnableLines` would keep offering goods that have already
  /// come back.
  Future<ReturnPostResult> returnFromShop(int quantity) async {
    final line = (await returns.returnableLines(invoice.invoiceId)).single;
    return returns.postReturn(
      admin,
      ReturnDraft(
        route: ReturnRoute.shopToAgent,
        fromLocationId: shopLocationId,
        toLocationId: agentLocationId,
        reason: ReturnReason.excessStock,
        shopId: shopId,
        agentId: agentId,
        originInvoiceId: invoice.invoiceId,
        lines: [
          ReturnLineDraft(
            productId: productId,
            quantity: quantity,
            originInvoiceItemId: line.invoiceItemId,
            unitPrice: unitPrice,
          ),
        ],
      ),
    );
  }

  group('receiving a return', () {
    test('goods leave the shop and wait in transit', () async {
      expect(await balanceAt(shopLocationId), 50);

      final result = await returnFromShop(10);
      expect(result.returnNumber, isNotEmpty);
      expect(result.totalQuantity, 10);
      expect(result.receiptDocumentNumber, isNotEmpty);

      // Gone from the shop…
      expect(await balanceAt(shopLocationId), 40);
      // …but not yet the agent's to sell. This is the point of the two-leg
      // route: goods in a lorry are neither the shop's nor the agent's, and
      // nothing should be sellable until somebody has looked at it.
      expect(await balanceAt(agentLocationId), 0);
      expect(await balanceAt(inTransitLocationId), 10);
      await expectBooksBalanced();
    });

    test('more than was billed cannot come back', () async {
      await expectLater(
        returnFromShop(51),
        throwsA(isA<BusinessRuleFailure>()),
      );
      expect(await balanceAt(shopLocationId), 50);
      await expectBooksBalanced();
    });

    test('returnable lines shrink as goods come back', () async {
      final before = await returns.returnableLines(invoice.invoiceId);
      expect(before.single.billedQuantity, 50);
      expect(before.single.returnedQuantity, 0);
      expect(before.single.effectiveUnitPrice, unitPrice);

      await returnFromShop(12);

      final after = await returns.returnableLines(invoice.invoiceId);
      expect(after.single.returnedQuantity, 12);
    });

    test(
      'a direct shop-to-warehouse return needs the extra permission',
      () async {
        // Bypassing the agent is a deliberate exception, so it carries its own
        // permission on top of being allowed to record returns at all.
        final managerClient = ApiClient(
          baseUrl: api.base,
          tokens: InMemoryTokenStore(),
        );
        addTearDown(managerClient.close);
        final managerAuth = AuthApi(managerClient);
        await auth.createUser(
          actor: admin,
          fullName: 'Manager',
          username: 'manager',
          password: 'Initial1Pass',
          roleCodes: [RoleCodes.manager],
        );
        final manager = await managerAuth.signIn(
          username: 'manager',
          password: 'Initial1Pass',
        );
        await managerAuth.changeOwnPassword(
          user: manager,
          currentPassword: 'Initial1Pass',
          newPassword: 'Chosen2Pass9',
        );
        expect(manager.can(Permissions.returnCreate), isTrue);
        expect(manager.can(Permissions.returnDirectToWarehouse), isFalse);

        await expectLater(
          ReturnApi(managerClient).postReturn(
            manager,
            ReturnDraft(
              route: ReturnRoute.shopToWarehouse,
              fromLocationId: shopLocationId,
              toLocationId: warehouseId,
              reason: ReturnReason.defectiveItem,
              shopId: shopId,
              lines: [ReturnLineDraft(productId: productId, quantity: 5)],
            ),
          ),
          throwsA(
            isA<PermissionFailure>().having(
              (f) => f.permission,
              'permission',
              Permissions.returnDirectToWarehouse,
            ),
          ),
        );
        expect(await balanceAt(shopLocationId), 50);
      },
    );
  });

  group('inspection', () {
    test('each part of the quantity is routed where it belongs', () async {
      final posted = await returnFromShop(10);
      final detail = await returnQueries.returnDetail(posted.returnId);
      final itemId = detail.lines.single.id;
      expect(detail.lines.single.inspectionStatus, InspectionStatus.pending);

      final result = await returns.recordInspection(
        admin,
        InspectionRequest(
          returnId: posted.returnId,
          decisions: [
            InspectionDecision(
              returnItemId: itemId,
              acceptedQuantity: 6,
              damagedQuantity: 3,
              scrappedQuantity: 1,
            ),
          ],
        ),
      );

      expect(result.acceptedQuantity, 6);
      expect(result.damagedQuantity, 3);
      expect(result.scrappedQuantity, 1);

      // Six are sellable by the agent, three are quarantined, one is gone.
      expect(await balanceAt(agentLocationId), 6);
      expect(await balanceAt(damagedLocationId), 3);
      expect(await balanceAt(inTransitLocationId), 0);
      await expectBooksBalanced();
    });

    test('a decision that does not add up is refused', () async {
      final posted = await returnFromShop(10);
      final detail = await returnQueries.returnDetail(posted.returnId);
      final itemId = detail.lines.single.id;

      // 5 + 3 + 1 is nine of ten. The missing unit is the whole danger: stock
      // that left the shop and was never accounted for anywhere.
      await expectLater(
        returns.recordInspection(
          admin,
          InspectionRequest(
            returnId: posted.returnId,
            decisions: [
              InspectionDecision(
                returnItemId: itemId,
                acceptedQuantity: 5,
                damagedQuantity: 3,
                scrappedQuantity: 1,
              ),
            ],
          ),
        ),
        throwsA(isA<AppFailure>()),
      );

      // Still waiting in transit, untouched.
      expect(await balanceAt(inTransitLocationId), 10);
      expect(await balanceAt(agentLocationId), 0);
      await expectBooksBalanced();
    });

    test('the creditable value excludes what was scrapped', () async {
      final posted = await returnFromShop(10);
      final detail = await returnQueries.returnDetail(posted.returnId);

      final result = await returns.recordInspection(
        admin,
        InspectionRequest(
          returnId: posted.returnId,
          decisions: [
            InspectionDecision(
              returnItemId: detail.lines.single.id,
              acceptedQuantity: 6,
              damagedQuantity: 3,
              scrappedQuantity: 1,
            ),
          ],
        ),
      );

      // Nine units are worth crediting at the price charged; the scrapped one
      // is worth nothing. Crediting all ten would hand back money for goods
      // that no longer exist in any usable form.
      expect(result.creditableValue, const Money(9 * 130000));
    });
  });

  group('credit notes', () {
    /// Returns 10, inspects 6 accepted / 3 damaged / 1 scrapped, and returns
    /// the creditable value.
    Future<(int returnId, Money creditable)> returnAndInspect() async {
      final posted = await returnFromShop(10);
      final detail = await returnQueries.returnDetail(posted.returnId);
      final result = await returns.recordInspection(
        admin,
        InspectionRequest(
          returnId: posted.returnId,
          decisions: [
            InspectionDecision(
              returnItemId: detail.lines.single.id,
              acceptedQuantity: 6,
              damagedQuantity: 3,
              scrappedQuantity: 1,
            ),
          ],
        ),
      );
      return (posted.returnId, result.creditableValue);
    }

    test('issuing one gives the shop credit to spend', () async {
      final (returnId, creditable) = await returnAndInspect();

      final creditNoteId = await returns.issueCreditNote(
        admin,
        returnId: returnId,
        reason: 'Excess stock returned',
      );

      final detail = await returnQueries.creditNoteDetail(creditNoteId);
      expect(detail.summary.amount, creditable);
      expect(await returnQueries.availableCredit(shopId: shopId), creditable);
      await expectBooksBalanced();
    });

    test('applying it reduces what the invoice still owes', () async {
      final (returnId, creditable) = await returnAndInspect();
      final creditNoteId = await returns.issueCreditNote(
        admin,
        returnId: returnId,
      );

      final owedBefore = await payments.outstandingOf(invoice.invoiceId);
      await returns.applyToInvoice(
        admin,
        creditNoteId: creditNoteId,
        invoiceId: invoice.invoiceId,
        amount: creditable,
      );

      expect(
        await payments.outstandingOf(invoice.invoiceId),
        owedBefore - creditable,
      );
      // And the credit is spent, so it cannot be used twice.
      expect(await returnQueries.availableCredit(shopId: shopId), Money.zero);
      await expectBooksBalanced();
    });

    test('more than the note holds cannot be applied', () async {
      final (returnId, creditable) = await returnAndInspect();
      final creditNoteId = await returns.issueCreditNote(
        admin,
        returnId: returnId,
      );

      await expectLater(
        returns.applyToInvoice(
          admin,
          creditNoteId: creditNoteId,
          invoiceId: invoice.invoiceId,
          amount: creditable + const Money(1),
        ),
        throwsA(isA<AppFailure>()),
      );
      expect(await returnQueries.availableCredit(shopId: shopId), creditable);
      await expectBooksBalanced();
    });

    test('withdrawing an application gives the credit back', () async {
      final (returnId, creditable) = await returnAndInspect();
      final creditNoteId = await returns.issueCreditNote(
        admin,
        returnId: returnId,
      );
      await returns.applyToInvoice(
        admin,
        creditNoteId: creditNoteId,
        invoiceId: invoice.invoiceId,
        amount: creditable,
      );
      expect(await returnQueries.availableCredit(shopId: shopId), Money.zero);

      final detail = await returnQueries.creditNoteDetail(creditNoteId);
      final applicationId = detail.applications.single.id;
      await returns.withdrawApplication(
        admin,
        applicationId: applicationId,
        reason: 'Applied to the wrong invoice',
      );

      expect(await returnQueries.availableCredit(shopId: shopId), creditable);
      await expectBooksBalanced();
    });

    test('issuing needs the credit-note permission', () async {
      final (returnId, _) = await returnAndInspect();

      final keeperClient = ApiClient(
        baseUrl: api.base,
        tokens: InMemoryTokenStore(),
      );
      addTearDown(keeperClient.close);
      final keeperAuth = AuthApi(keeperClient);
      await auth.createUser(
        actor: admin,
        fullName: 'Store Keeper',
        username: 'keeper',
        password: 'Initial1Pass',
        roleCodes: [RoleCodes.storeKeeper],
      );
      final keeper = await keeperAuth.signIn(
        username: 'keeper',
        password: 'Initial1Pass',
      );
      await keeperAuth.changeOwnPassword(
        user: keeper,
        currentPassword: 'Initial1Pass',
        newPassword: 'Chosen2Pass9',
      );
      // A storekeeper inspects goods but does not decide what money goes back.
      expect(keeper.can(Permissions.returnInspect), isTrue);
      expect(keeper.can(Permissions.creditNoteIssue), isFalse);

      await expectLater(
        ReturnApi(keeperClient).issueCreditNote(keeper, returnId: returnId),
        throwsA(
          isA<PermissionFailure>().having(
            (f) => f.permission,
            'permission',
            Permissions.creditNoteIssue,
          ),
        ),
      );
      expect(await returnQueries.availableCredit(shopId: shopId), Money.zero);
    });
  });
}
