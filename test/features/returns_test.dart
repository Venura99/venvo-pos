import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_test/flutter_test.dart';
import 'package:venvo_core/core/constants/app_constants.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/database/app_database.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/errors/failures.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/agents/domain/agent_models.dart';
import 'package:venvo_core/features/authentication/domain/authenticated_user.dart';
import 'package:venvo_core/features/categories/domain/category_models.dart';
import 'package:venvo_core/features/inventory/domain/stock_models.dart';
import 'package:venvo_core/features/invoices/domain/invoice_models.dart';
import 'package:venvo_core/features/products/domain/product_models.dart';
import 'package:venvo_core/features/returns/domain/return_models.dart';
import 'package:venvo_core/features/shops/domain/shop_models.dart';

import '../helpers/master_data_fixtures.dart';

/// Returns, inspection and the credit that follows.
///
/// Two things are checked over and over here, because they are what the
/// module exists for: a returned unit never becomes sellable stock before
/// somebody has inspected it, and credit never moves unless goods did.
void main() {
  late MasterDataFixture fixture;
  late int chargerId;
  late int cableId;
  late int warehouseId;
  late int agentId;
  late int agentLocationId;
  late int shopId;
  late int shopLocationId;
  late int transitId;
  late int damagedId;
  late int adjustmentId;
  late int customerId;

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
    transitId = (await fixture.locations.byCode(
      AppConstants.inTransitLocationCode,
    )).id;
    damagedId = (await fixture.locations.byCode(
      AppConstants.damagedLocationCode,
    )).id;
    adjustmentId = (await fixture.locations.byCode(
      AppConstants.adjustmentLocationCode,
    )).id;
    customerId = (await fixture.locations.byCode(
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

  Future<int> balanceAt(int locationId, [int? productId]) {
    return fixture.stockLedger.balanceOf(
      locationId: locationId,
      productId: productId ?? chargerId,
    );
  }

  /// Moves [quantity] chargers warehouse -> agent -> shop, so a shop has
  /// something to send back.
  Future<void> supplyTheShop({int quantity = 20}) async {
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

  Future<ReturnPostResult> postShopReturn({
    int quantity = 5,
    ReturnReason reason = ReturnReason.defectiveItem,
    String? reasonNote,
    int? originInvoiceId,
    int? originInvoiceItemId,
    Money? unitPrice,
    AuthenticatedUser? actor,
  }) {
    return fixture.returns.postReturn(
      actor ?? fixture.admin,
      ReturnDraft(
        route: ReturnRoute.shopToAgent,
        fromLocationId: shopLocationId,
        toLocationId: agentLocationId,
        agentId: agentId,
        shopId: shopId,
        reason: reason,
        reasonNote: reasonNote,
        originInvoiceId: originInvoiceId,
        lines: [
          ReturnLineDraft(
            productId: chargerId,
            quantity: quantity,
            originInvoiceItemId: originInvoiceItemId,
            unitPrice: unitPrice,
          ),
        ],
      ),
    );
  }

  Future<List<ReturnItem>> itemsOf(int returnId) {
    return (fixture.db.select(fixture.db.returnItems)
          ..where((row) => row.returnId.equals(returnId))
          ..orderBy([(row) => OrderingTerm.asc(row.lineNumber)]))
        .get();
  }

  /// Inspects a whole return with one outcome for every unit.
  Future<InspectionResult> inspectAll(
    int returnId, {
    String outcome = 'accept',
    AuthenticatedUser? actor,
  }) async {
    final items = await itemsOf(returnId);
    return fixture.returns.recordInspection(
      actor ?? fixture.admin,
      InspectionRequest(
        returnId: returnId,
        decisions: [
          for (final item in items)
            InspectionDecision(
              returnItemId: item.id,
              acceptedQuantity: outcome == 'accept' ? item.quantity : 0,
              damagedQuantity: outcome == 'damage' ? item.quantity : 0,
              scrappedQuantity: outcome == 'scrap' ? item.quantity : 0,
            ),
        ],
      ),
    );
  }

  group('posting a return', () {
    test(
      'takes the goods out of the shop but not into sellable stock',
      () async {
        await supplyTheShop();
        expect(await balanceAt(shopLocationId), 20);
        final agentBefore = await balanceAt(agentLocationId);

        final posted = await postShopReturn(quantity: 5);

        // The shop no longer holds them.
        expect(await balanceAt(shopLocationId), 15);
        // The agent does not hold them either: they are in transit, waiting for
        // somebody to look at them. This is rule I7.
        expect(await balanceAt(agentLocationId), agentBefore);
        expect(await balanceAt(transitId), 5);

        expect(posted.totalQuantity, 5);
        expect(posted.returnNumber, startsWith('RET-'));
        expect(posted.receiptDocumentNumber, startsWith('RET-'));
      },
    );

    test('files the return as awaiting inspection', () async {
      await supplyTheShop();
      final posted = await postShopReturn();

      final summary =
          (await fixture.returnQueries.watchReturns(const ReturnFilter()).first)
              .single;

      expect(summary.returnNumber, posted.returnNumber);
      expect(summary.status, ReturnStatus.posted);
      expect(summary.awaitsInspection, isTrue);
      expect(summary.pendingLineCount, 1);
      expect(summary.lineCount, 1);
      expect(summary.shopName, 'Shop A');
      expect(summary.fromLocationName, contains('Shop A'));
    });

    test('writes the stock movement as a return document', () async {
      await supplyTheShop();
      await postShopReturn();

      final document =
          await (fixture.db.select(fixture.db.stockTransactions)
                ..orderBy([(row) => OrderingTerm.desc(row.id)])
                ..limit(1))
              .getSingle();

      expect(document.documentType, StockDocumentType.shopToAgentReturn);
      expect(document.sourceLocationId, shopLocationId);
      expect(document.destinationLocationId, transitId);
    });

    test('refuses a return with no lines', () async {
      await expectLater(
        fixture.returns.postReturn(
          fixture.admin,
          ReturnDraft(
            route: ReturnRoute.shopToAgent,
            fromLocationId: shopLocationId,
            toLocationId: agentLocationId,
            reason: ReturnReason.excessStock,
            lines: const [],
          ),
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('refuses more than the shop is holding', () async {
      await supplyTheShop(quantity: 3);

      await expectLater(
        postShopReturn(quantity: 10),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'stock.no_negative_balance',
          ),
        ),
      );
      // Nothing half-posted: no return row, no stock in transit.
      expect(await balanceAt(transitId), 0);
      expect(
        await fixture.returnQueries.watchReturns(const ReturnFilter()).first,
        isEmpty,
      );
    });

    test('refuses a route whose locations do not match it', () async {
      await supplyTheShop();

      await expectLater(
        fixture.returns.postReturn(
          fixture.admin,
          ReturnDraft(
            // Says agent-to-warehouse, but hands it a shop.
            route: ReturnRoute.agentToWarehouse,
            fromLocationId: shopLocationId,
            toLocationId: warehouseId,
            reason: ReturnReason.excessStock,
            lines: [ReturnLineDraft(productId: chargerId, quantity: 1)],
          ),
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'return.route_source_kind',
          ),
        ),
      );
    });

    test(
      'a shop-direct-to-warehouse return needs explicit authorisation',
      () async {
        await supplyTheShop();

        final storeKeeper = await fixture.auth.createUser(
          actor: fixture.admin,
          fullName: 'Sunil Silva',
          username: 'sunil',
          password: 'Store1234',
          roleCodes: const ['STORE_KEEPER'],
        );
        // The store keeper may record returns, but not bypass the agent.
        expect(storeKeeper.can(Permissions.returnCreate), isTrue);
        expect(storeKeeper.can(Permissions.returnDirectToWarehouse), isFalse);

        Future<ReturnPostResult> direct(AuthenticatedUser actor) {
          return fixture.returns.postReturn(
            actor,
            ReturnDraft(
              route: ReturnRoute.shopToWarehouse,
              fromLocationId: shopLocationId,
              toLocationId: warehouseId,
              shopId: shopId,
              reason: ReturnReason.wrongProduct,
              lines: [ReturnLineDraft(productId: chargerId, quantity: 2)],
            ),
          );
        }

        await expectLater(
          direct(storeKeeper),
          throwsA(isA<PermissionFailure>()),
        );

        final posted = await direct(fixture.admin);
        final row = await (fixture.db.select(
          fixture.db.returnDocuments,
        )..where((r) => r.id.equals(posted.returnId))).getSingle();
        // Who waved it through is recorded on the document.
        expect(row.authorisedByUserId, fixture.admin.id);
      },
    );

    test('a reason of "other" has to be explained', () async {
      await supplyTheShop();

      await expectLater(
        postShopReturn(reason: ReturnReason.other),
        throwsA(isA<ValidationFailure>()),
      );

      final posted = await postShopReturn(
        reason: ReturnReason.other,
        reasonNote: 'Shop closing down, stock sent back',
      );
      final row = await (fixture.db.select(
        fixture.db.returnDocuments,
      )..where((r) => r.id.equals(posted.returnId))).getSingle();
      expect(row.reasonNote, 'Shop closing down, stock sent back');
    });

    test(
      'an untraced return is allowed and priced from what was entered',
      () async {
        await supplyTheShop();

        final posted = await postShopReturn(
          quantity: 4,
          unitPrice: Money.fromMajor(3000),
        );

        expect(posted.totalValue, Money.fromMajor(12000));
        final items = await itemsOf(posted.returnId);
        expect(items.single.originInvoiceItemId, isNull);
        expect(items.single.unitPriceCents, Money.fromMajor(3000).cents);
        // The snapshot is the product as it was, not a live join.
        expect(items.single.productNameSnapshot, '25W Charger');
        expect(items.single.skuSnapshot, 'CHG-25W');
      },
    );

    test('records the posting in the audit log', () async {
      await supplyTheShop();
      final posted = await postShopReturn();

      final entry = (await fixture.auditEntries()).firstWhere(
        (row) => row.entityKind == EntityKind.returnDocument,
      );
      expect(entry.action, AuditAction.post);
      expect(entry.summary, contains(posted.returnNumber));
      expect(entry.summary, contains('awaiting inspection'));
    });

    test(
      'a failure part-way through a multi-line return leaves nothing',
      () async {
        await supplyTheShop();
        // The shop holds 20 chargers and no cables at all.
        await expectLater(
          fixture.returns.postReturn(
            fixture.admin,
            ReturnDraft(
              route: ReturnRoute.shopToAgent,
              fromLocationId: shopLocationId,
              toLocationId: agentLocationId,
              reason: ReturnReason.excessStock,
              lines: [
                ReturnLineDraft(productId: chargerId, quantity: 2),
                ReturnLineDraft(productId: cableId, quantity: 1),
              ],
            ),
          ),
          throwsA(isA<BusinessRuleFailure>()),
        );

        expect(await balanceAt(shopLocationId), 20);
        expect(await balanceAt(transitId), 0);
        expect(await itemsOf(1), isEmpty);
      },
    );
  });

  group('returning against an invoice', () {
    late int invoiceId;
    late int invoiceItemId;

    setUp(() async {
      await supplyTheShop(quantity: 100);
      final invoice = await fixture.invoices.postInvoice(
        fixture.admin,
        InvoiceRequest(
          kind: InvoiceKind.shopInvoice,
          shopId: shopId,
          agentId: agentId,
          lines: [
            InvoiceLineRequest(
              productId: chargerId,
              quantity: 10,
              unitPrice: Money.fromMajor(2000),
            ),
          ],
        ),
      );
      invoiceId = invoice.invoiceId;
      invoiceItemId = (await (fixture.db.select(
        fixture.db.invoiceItems,
      )..where((i) => i.invoiceId.equals(invoiceId))).getSingle()).id;
    });

    test('reports what is still returnable on each line', () async {
      final lines = await fixture.returns.returnableLines(invoiceId);

      expect(lines, hasLength(1));
      expect(lines.single.billedQuantity, 10);
      expect(lines.single.returnedQuantity, 0);
      expect(lines.single.returnableQuantity, 10);
      expect(lines.single.effectiveUnitPrice, Money.fromMajor(2000));
    });

    test(
      'prices the return at what was billed, not at today\'s price',
      () async {
        // Somebody raises the catalogue price after the sale.
        await fixture.products.update(
          fixture.admin,
          ProductDraft(
            id: chargerId,
            sku: 'CHG-25W',
            name: '25W Charger',
            categoryId:
                (await fixture.categories.selectableCategories()).first.id,
            costPrice: Money.fromMajor(2000),
            wholesalePrice: Money.fromMajor(5000),
            retailPrice: Money.fromMajor(5500),
          ),
        );

        final posted = await postShopReturn(
          quantity: 4,
          originInvoiceId: invoiceId,
          originInvoiceItemId: invoiceItemId,
          // Even an explicit price loses to the billed one.
          unitPrice: Money.fromMajor(9999),
        );

        expect(posted.totalValue, Money.fromMajor(8000));
      },
    );

    test('caps the return at what was billed and remembers it', () async {
      await postShopReturn(
        quantity: 6,
        originInvoiceId: invoiceId,
        originInvoiceItemId: invoiceItemId,
      );

      final lines = await fixture.returns.returnableLines(invoiceId);
      expect(lines.single.returnedQuantity, 6);
      expect(lines.single.returnableQuantity, 4);

      // A second return may take the remaining four, but not five.
      await expectLater(
        postShopReturn(
          quantity: 5,
          originInvoiceId: invoiceId,
          originInvoiceItemId: invoiceItemId,
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'return.within_billed_quantity',
          ),
        ),
      );

      await postShopReturn(
        quantity: 4,
        originInvoiceId: invoiceId,
        originInvoiceItemId: invoiceItemId,
      );
      final after = await fixture.returns.returnableLines(invoiceId);
      expect(after.single.isFullyReturned, isTrue);
    });

    test(
      'spreads an invoice-level discount into the unit price it credits',
      () async {
        // A second invoice with 10% off the whole document: 10 x Rs. 2,000 is
        // Rs. 20,000 gross, Rs. 18,000 net, so a unit really cost Rs. 1,800.
        final discounted = await fixture.invoices.postInvoice(
          fixture.admin,
          InvoiceRequest(
            kind: InvoiceKind.shopInvoice,
            shopId: shopId,
            agentId: agentId,
            invoiceDiscountType: DiscountType.percentage,
            invoiceDiscountValue: 1000,
            discountReason: 'Volume deal',
            lines: [
              InvoiceLineRequest(
                productId: chargerId,
                quantity: 10,
                unitPrice: Money.fromMajor(2000),
              ),
            ],
          ),
        );

        final lines = await fixture.returns.returnableLines(
          discounted.invoiceId,
        );
        expect(lines.single.effectiveUnitPrice, Money.fromMajor(1800));

        final posted = await postShopReturn(
          quantity: 5,
          originInvoiceId: discounted.invoiceId,
          originInvoiceItemId: lines.single.invoiceItemId,
        );
        // Credit worth Rs. 9,000, not the Rs. 10,000 the headline price implies.
        expect(posted.totalValue, Money.fromMajor(9000));
      },
    );

    test('refuses a line that is not on the stated invoice', () async {
      await expectLater(
        fixture.returns.postReturn(
          fixture.admin,
          ReturnDraft(
            route: ReturnRoute.shopToAgent,
            fromLocationId: shopLocationId,
            toLocationId: agentLocationId,
            shopId: shopId,
            agentId: agentId,
            reason: ReturnReason.wrongProduct,
            originInvoiceId: invoiceId,
            lines: [
              ReturnLineDraft(
                productId: chargerId,
                quantity: 1,
                originInvoiceItemId: invoiceItemId + 9999,
              ),
            ],
          ),
        ),
        throwsA(isA<NotFoundFailure>()),
      );
    });

    test('refuses to return against a cancelled invoice', () async {
      await fixture.invoices.cancelInvoice(
        fixture.admin,
        invoiceId: invoiceId,
        reason: 'Raised on the wrong shop',
      );

      await expectLater(
        fixture.returns.returnableLines(invoiceId),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'return.origin_invoice_posted_only',
          ),
        ),
      );
    });
  });

  group('inspection', () {
    test(
      'accepted goods leave transit and land in the receiving location',
      () async {
        await supplyTheShop();
        final agentBefore = await balanceAt(agentLocationId);
        final posted = await postShopReturn(quantity: 5);

        final result = await inspectAll(posted.returnId);

        expect(result.acceptedQuantity, 5);
        expect(await balanceAt(agentLocationId), agentBefore + 5);
        expect(await balanceAt(transitId), 0);
        expect(await balanceAt(damagedId), 0);
      },
    );

    test('defective goods go to quarantine, never to sellable stock', () async {
      await supplyTheShop();
      final agentBefore = await balanceAt(agentLocationId);
      final posted = await postShopReturn(quantity: 5);

      final result = await inspectAll(posted.returnId, outcome: 'damage');

      expect(result.damagedQuantity, 5);
      // Rule I8: not one unit reached the agent's sellable stock.
      expect(await balanceAt(agentLocationId), agentBefore);
      expect(await balanceAt(damagedId), 5);
      expect(await balanceAt(transitId), 0);
    });

    test('scrapped goods leave the business entirely', () async {
      await supplyTheShop();
      final posted = await postShopReturn(quantity: 5);

      final result = await inspectAll(posted.returnId, outcome: 'scrap');

      expect(result.scrappedQuantity, 5);
      expect(result.creditableValue, Money.zero);
      expect(await balanceAt(transitId), 0);
      expect(await balanceAt(damagedId), 0);
      // The adjustment counterparty is the other side of the write-off, so the
      // ledger still balances to zero across every location.
      expect(await balanceAt(adjustmentId), 5);
      expect(await fixture.stockLedger.findUnbalancedProducts(), isEmpty);
    });

    test(
      'splits one line three ways and sends each part to its own place',
      () async {
        await supplyTheShop();
        final agentBefore = await balanceAt(agentLocationId);
        final posted = await postShopReturn(quantity: 10);
        final items = await itemsOf(posted.returnId);

        final result = await fixture.returns.recordInspection(
          fixture.admin,
          InspectionRequest(
            returnId: posted.returnId,
            decisions: [
              InspectionDecision(
                returnItemId: items.single.id,
                acceptedQuantity: 6,
                damagedQuantity: 3,
                scrappedQuantity: 1,
                note: 'Three with bent pins, one crushed',
              ),
            ],
          ),
        );

        expect(result.acceptedQuantity, 6);
        expect(result.damagedQuantity, 3);
        expect(result.scrappedQuantity, 1);
        expect(await balanceAt(agentLocationId), agentBefore + 6);
        expect(await balanceAt(damagedId), 3);
        expect(await balanceAt(adjustmentId), 1);
        expect(await balanceAt(transitId), 0);
      },
    );

    test('refuses a split that does not account for every unit', () async {
      await supplyTheShop();
      final posted = await postShopReturn(quantity: 10);
      final items = await itemsOf(posted.returnId);

      await expectLater(
        fixture.returns.recordInspection(
          fixture.admin,
          InspectionRequest(
            returnId: posted.returnId,
            decisions: [
              // Nine of the ten.
              InspectionDecision(
                returnItemId: items.single.id,
                acceptedQuantity: 6,
                damagedQuantity: 3,
              ),
            ],
          ),
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'return.inspection_accounts_for_every_unit',
          ),
        ),
      );
      // The goods are still in transit, exactly where they were.
      expect(await balanceAt(transitId), 10);
    });

    test('refuses to close a return with a line left undecided', () async {
      await supplyTheShop();
      await fixture.postOpeningStock(
        locationId: shopLocationId,
        productId: cableId,
        quantity: 10,
        unitCost: Money.fromMajor(300),
      );

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
            ReturnLineDraft(productId: chargerId, quantity: 2),
            ReturnLineDraft(productId: cableId, quantity: 3),
          ],
        ),
      );
      final items = await itemsOf(posted.returnId);

      await expectLater(
        fixture.returns.recordInspection(
          fixture.admin,
          InspectionRequest(
            returnId: posted.returnId,
            decisions: [
              InspectionDecision(
                returnItemId: items.first.id,
                acceptedQuantity: 2,
              ),
            ],
          ),
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'return.inspect_every_line',
          ),
        ),
      );
    });

    test('cannot be done twice', () async {
      await supplyTheShop();
      final posted = await postShopReturn();
      await inspectAll(posted.returnId);

      await expectLater(
        inspectAll(posted.returnId),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'return.inspect_posted_only',
          ),
        ),
      );
    });

    test('needs the inspection permission', () async {
      await supplyTheShop();
      final posted = await postShopReturn();
      final viewer = await fixture.createViewer();

      await expectLater(
        inspectAll(posted.returnId, actor: viewer),
        throwsA(isA<PermissionFailure>()),
      );
    });

    test('records who inspected each line and what they decided', () async {
      await supplyTheShop();
      final posted = await postShopReturn(quantity: 5);
      await inspectAll(posted.returnId, outcome: 'damage');

      final detail = await fixture.returnQueries.returnDetail(posted.returnId);
      final line = detail.lines.single;

      expect(line.inspectionStatus, InspectionStatus.movedToDamaged);
      expect(line.damagedQuantity, 5);
      expect(line.acceptedQuantity, 0);
      expect(line.inspectedBy, 'Nimal Perera');
      expect(line.inspectedAt, isNotNull);
      expect(detail.summary.isInspected, isTrue);
      expect(detail.summary.pendingLineCount, 0);
    });

    test(
      'closes a wholly scrapped return outright, with nothing to credit',
      () async {
        await supplyTheShop();
        final posted = await postShopReturn(quantity: 3);
        await inspectAll(posted.returnId, outcome: 'scrap');

        final detail = await fixture.returnQueries.returnDetail(
          posted.returnId,
        );
        expect(detail.summary.status, ReturnStatus.completed);
        expect(detail.creditableValue, Money.zero);
        expect(detail.canIssueCredit, isFalse);
      },
    );
  });

  group('credit notes', () {
    late int invoiceId;
    late int invoiceItemId;

    setUp(() async {
      await supplyTheShop(quantity: 100);
      final invoice = await fixture.invoices.postInvoice(
        fixture.admin,
        InvoiceRequest(
          kind: InvoiceKind.shopInvoice,
          shopId: shopId,
          agentId: agentId,
          lines: [
            InvoiceLineRequest(
              productId: chargerId,
              quantity: 10,
              unitPrice: Money.fromMajor(2000),
            ),
          ],
        ),
      );
      invoiceId = invoice.invoiceId;
      invoiceItemId = (await (fixture.db.select(
        fixture.db.invoiceItems,
      )..where((i) => i.invoiceId.equals(invoiceId))).getSingle()).id;
    });

    /// Returns five chargers against the invoice and inspects them.
    Future<int> returnAndInspect({String outcome = 'accept'}) async {
      final posted = await postShopReturn(
        quantity: 5,
        originInvoiceId: invoiceId,
        originInvoiceItemId: invoiceItemId,
      );
      await inspectAll(posted.returnId, outcome: outcome);
      return posted.returnId;
    }

    test('cannot be issued before the goods have been inspected', () async {
      final posted = await postShopReturn(
        quantity: 5,
        originInvoiceId: invoiceId,
        originInvoiceItemId: invoiceItemId,
      );

      await expectLater(
        fixture.returns.issueCreditNote(
          fixture.admin,
          returnId: posted.returnId,
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'credit_note.requires_inspection',
          ),
        ),
      );
    });

    test('defaults to the value the inspection accepted', () async {
      final returnId = await returnAndInspect();

      final creditNoteId = await fixture.returns.issueCreditNote(
        fixture.admin,
        returnId: returnId,
      );

      final note = (await fixture.returnQueries.creditNoteDetail(
        creditNoteId,
      )).summary;
      expect(note.creditNoteNumber, startsWith('CN-'));
      expect(note.amount, Money.fromMajor(10000));
      expect(note.status, InvoiceStatus.posted);
      expect(note.partyType, PartyType.shop);
      expect(note.partyName, 'Shop A');
      expect(note.remaining, Money.fromMajor(10000));
    });

    test('credits damaged goods but never scrapped ones', () async {
      final damagedReturn = await returnAndInspect(outcome: 'damage');
      final damagedNote = await fixture.returns.issueCreditNote(
        fixture.admin,
        returnId: damagedReturn,
      );
      expect(
        (await fixture.returnQueries.creditNoteDetail(
          damagedNote,
        )).summary.amount,
        Money.fromMajor(10000),
      );

      final scrappedReturn = await returnAndInspect(outcome: 'scrap');
      await expectLater(
        fixture.returns.issueCreditNote(
          fixture.admin,
          returnId: scrappedReturn,
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'credit_note.nothing_left_to_credit',
          ),
        ),
      );
    });

    test('cannot exceed what came back', () async {
      final returnId = await returnAndInspect();

      await expectLater(
        fixture.returns.issueCreditNote(
          fixture.admin,
          returnId: returnId,
          amount: Money.fromMajor(10001),
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'credit_note.within_returned_value',
          ),
        ),
      );
    });

    test('can be issued in parts until the return is fully credited', () async {
      final returnId = await returnAndInspect();

      await fixture.returns.issueCreditNote(
        fixture.admin,
        returnId: returnId,
        amount: Money.fromMajor(4000),
      );
      await fixture.returns.issueCreditNote(
        fixture.admin,
        returnId: returnId,
        amount: Money.fromMajor(6000),
      );

      final detail = await fixture.returnQueries.returnDetail(returnId);
      expect(detail.summary.creditedValue, Money.fromMajor(10000));
      expect(detail.uncreditedValue, Money.zero);
      expect(detail.summary.status, ReturnStatus.completed);
      expect(detail.creditNotes, hasLength(2));

      await expectLater(
        fixture.returns.issueCreditNote(fixture.admin, returnId: returnId),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'credit_note.nothing_left_to_credit',
          ),
        ),
      );
    });

    test('needs the credit note permission', () async {
      final returnId = await returnAndInspect();
      final storeKeeper = await fixture.auth.createUser(
        actor: fixture.admin,
        fullName: 'Sunil Silva',
        username: 'sunil',
        password: 'Store1234',
        roleCodes: const ['STORE_KEEPER'],
      );
      // Deliberate: a store keeper handles goods, not money.
      expect(storeKeeper.can(Permissions.returnInspect), isTrue);
      expect(storeKeeper.can(Permissions.creditNoteIssue), isFalse);

      await expectLater(
        fixture.returns.issueCreditNote(storeKeeper, returnId: returnId),
        throwsA(isA<PermissionFailure>()),
      );
    });
  });

  group('credit against an outstanding balance', () {
    late int invoiceId;
    late int invoiceItemId;
    late int returnId;

    setUp(() async {
      await supplyTheShop(quantity: 100);
      final invoice = await fixture.invoices.postInvoice(
        fixture.admin,
        InvoiceRequest(
          kind: InvoiceKind.shopInvoice,
          shopId: shopId,
          agentId: agentId,
          lines: [
            InvoiceLineRequest(
              productId: chargerId,
              quantity: 10,
              unitPrice: Money.fromMajor(2000),
            ),
          ],
        ),
      );
      invoiceId = invoice.invoiceId;
      invoiceItemId = (await (fixture.db.select(
        fixture.db.invoiceItems,
      )..where((i) => i.invoiceId.equals(invoiceId))).getSingle()).id;

      final posted = await postShopReturn(
        quantity: 5,
        originInvoiceId: invoiceId,
        originInvoiceItemId: invoiceItemId,
      );
      await inspectAll(posted.returnId);
      returnId = posted.returnId;
    });

    Future<Money> shopOutstanding() async {
      final shops = await fixture.shops.watchShops(const ShopFilter()).first;
      return shops.single.outstandingBalance;
    }

    test('an unapplied credit note does not yet reduce the invoice', () async {
      expect(
        await fixture.payments.outstandingOf(invoiceId),
        Money.fromMajor(20000),
      );

      await fixture.returns.issueCreditNote(fixture.admin, returnId: returnId);

      // The credit exists but has not been pointed at anything, exactly like
      // an unallocated payment. Rule M8: it cannot vanish into a balance.
      expect(
        await fixture.payments.outstandingOf(invoiceId),
        Money.fromMajor(20000),
      );
      expect(
        await fixture.returnQueries.availableCredit(shopId: shopId),
        Money.fromMajor(10000),
      );
    });

    test(
      'applying it reduces the invoice and the shop balance together',
      () async {
        final creditNoteId = await fixture.returns.issueCreditNote(
          fixture.admin,
          returnId: returnId,
        );

        await fixture.returns.applyToInvoice(
          fixture.admin,
          creditNoteId: creditNoteId,
          invoiceId: invoiceId,
          amount: Money.fromMajor(10000),
        );

        // Phase 4 already counts posted credit notes everywhere it counts
        // settlement, so one write moves all of these at once.
        expect(
          await fixture.payments.outstandingOf(invoiceId),
          Money.fromMajor(10000),
        );
        expect(await shopOutstanding(), Money.fromMajor(10000));
        expect(
          await fixture.returnQueries.availableCredit(shopId: shopId),
          Money.zero,
        );
      },
    );

    test(
      'credit and a pending cheque cannot both claim the same balance',
      () async {
        final creditNoteId = await fixture.returns.issueCreditNote(
          fixture.admin,
          returnId: returnId,
        );
        // A cheque for Rs. 15,000 is already sitting against the invoice.
        await fixture.recordPayment(
          number: 'PAY-1',
          amount: Money.fromMajor(15000),
          method: PaymentMethod.cheque,
          status: PaymentStatus.pending,
          shopId: shopId,
          allocateToInvoiceId: invoiceId,
        );

        // Only Rs. 5,000 of the invoice is unclaimed, so the full Rs. 10,000
        // credit will not fit.
        await expectLater(
          fixture.returns.applyToInvoice(
            fixture.admin,
            creditNoteId: creditNoteId,
            invoiceId: invoiceId,
            amount: Money.fromMajor(10000),
          ),
          throwsA(
            isA<BusinessRuleFailure>().having(
              (failure) => failure.rule,
              'rule',
              'credit_note.no_over_allocation',
            ),
          ),
        );

        await fixture.returns.applyToInvoice(
          fixture.admin,
          creditNoteId: creditNoteId,
          invoiceId: invoiceId,
          amount: Money.fromMajor(5000),
        );
        expect(
          await fixture.returnQueries.availableCredit(shopId: shopId),
          Money.fromMajor(5000),
        );
      },
    );

    test('cannot be applied beyond the credit note itself', () async {
      final creditNoteId = await fixture.returns.issueCreditNote(
        fixture.admin,
        returnId: returnId,
      );

      await expectLater(
        fixture.returns.applyToInvoice(
          fixture.admin,
          creditNoteId: creditNoteId,
          invoiceId: invoiceId,
          amount: Money.fromMajor(10001),
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'credit_note.no_over_application',
          ),
        ),
      );
    });

    test('cannot be applied to another party\'s invoice', () async {
      final creditNoteId = await fixture.returns.issueCreditNote(
        fixture.admin,
        returnId: returnId,
      );
      final otherShop = await fixture.shops.create(
        fixture.admin,
        ShopDraft(name: 'Shop B', assignedAgentId: agentId),
      );
      final otherInvoice = await fixture.postInvoice(
        number: 'SINV-OTHER',
        netTotal: Money.fromMajor(5000),
        shopId: otherShop,
      );

      await expectLater(
        fixture.returns.applyToInvoice(
          fixture.admin,
          creditNoteId: creditNoteId,
          invoiceId: otherInvoice,
          amount: Money.fromMajor(1000),
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'credit_note.same_party',
          ),
        ),
      );
    });

    test(
      'withdrawing an application restores the debt and keeps the trail',
      () async {
        final creditNoteId = await fixture.returns.issueCreditNote(
          fixture.admin,
          returnId: returnId,
        );
        await fixture.returns.applyToInvoice(
          fixture.admin,
          creditNoteId: creditNoteId,
          invoiceId: invoiceId,
          amount: Money.fromMajor(10000),
        );
        final applied = await fixture.returnQueries.creditNoteDetail(
          creditNoteId,
        );

        await fixture.returns.withdrawApplication(
          fixture.admin,
          applicationId: applied.applications.single.id,
          reason: 'Applied to the wrong invoice',
        );

        expect(
          await fixture.payments.outstandingOf(invoiceId),
          Money.fromMajor(20000),
        );
        final after = await fixture.returnQueries.creditNoteDetail(
          creditNoteId,
        );
        // Rule M7: the original row is still there, with an opposing one beside
        // it, rather than being deleted.
        expect(after.applications, hasLength(2));
        expect(after.applications.where((a) => a.isWithdrawal), hasLength(1));
        expect(after.summary.remaining, Money.fromMajor(10000));
      },
    );

    test('a used credit note cannot be cancelled until it is freed', () async {
      final creditNoteId = await fixture.returns.issueCreditNote(
        fixture.admin,
        returnId: returnId,
      );
      await fixture.returns.applyToInvoice(
        fixture.admin,
        creditNoteId: creditNoteId,
        invoiceId: invoiceId,
        amount: Money.fromMajor(3000),
      );

      await expectLater(
        fixture.returns.cancelCreditNote(
          fixture.admin,
          creditNoteId: creditNoteId,
          reason: 'Issued in error',
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'credit_note.cancel_requires_no_applications',
          ),
        ),
      );
    });

    test('cancelling a credit note reopens the return for crediting', () async {
      final creditNoteId = await fixture.returns.issueCreditNote(
        fixture.admin,
        returnId: returnId,
      );
      expect(
        (await fixture.returnQueries.returnDetail(returnId)).summary.status,
        ReturnStatus.completed,
      );

      await fixture.returns.cancelCreditNote(
        fixture.admin,
        creditNoteId: creditNoteId,
        reason: 'Raised against the wrong return',
      );

      final detail = await fixture.returnQueries.returnDetail(returnId);
      expect(detail.summary.status, ReturnStatus.inspected);
      expect(detail.summary.creditedValue, Money.zero);
      expect(detail.canIssueCredit, isTrue);
      expect(
        await fixture.returnQueries.availableCredit(shopId: shopId),
        Money.zero,
      );
    });
  });

  group('cancelling a return', () {
    test('reverses both legs and puts the goods back', () async {
      await supplyTheShop();
      final posted = await postShopReturn(quantity: 5);
      await inspectAll(posted.returnId);
      expect(await balanceAt(shopLocationId), 15);

      await fixture.returns.cancelReturn(
        fixture.admin,
        returnId: posted.returnId,
        reason: 'Goods never actually arrived',
      );

      expect(await balanceAt(shopLocationId), 20);
      expect(await balanceAt(agentLocationId), 0);
      expect(await balanceAt(transitId), 0);
      // The ledger still nets to zero: the goods were put back by opposing
      // entries, not by deleting the originals.
      expect(await fixture.stockLedger.findUnbalancedProducts(), isEmpty);
      expect(await fixture.stockLedger.findBalanceDiscrepancies(), isEmpty);
    });

    test('keeps the original document and marks it cancelled', () async {
      await supplyTheShop();
      final posted = await postShopReturn(quantity: 5);

      await fixture.returns.cancelReturn(
        fixture.admin,
        returnId: posted.returnId,
        reason: 'Duplicate entry',
      );

      final detail = await fixture.returnQueries.returnDetail(posted.returnId);
      expect(detail.summary.status, ReturnStatus.cancelled);
      expect(detail.summary.isCancelled, isTrue);
      expect(detail.cancelReason, 'Duplicate entry');
      // The lines are still readable: history is preserved, not erased.
      expect(detail.lines.single.quantity, 5);
    });

    test('makes the units returnable again', () async {
      await supplyTheShop(quantity: 100);
      final invoice = await fixture.invoices.postInvoice(
        fixture.admin,
        InvoiceRequest(
          kind: InvoiceKind.shopInvoice,
          shopId: shopId,
          agentId: agentId,
          lines: [
            InvoiceLineRequest(
              productId: chargerId,
              quantity: 10,
              unitPrice: Money.fromMajor(2000),
            ),
          ],
        ),
      );
      final itemId = (await (fixture.db.select(
        fixture.db.invoiceItems,
      )..where((i) => i.invoiceId.equals(invoice.invoiceId))).getSingle()).id;

      final posted = await postShopReturn(
        quantity: 6,
        originInvoiceId: invoice.invoiceId,
        originInvoiceItemId: itemId,
      );
      expect(
        (await fixture.returns.returnableLines(
          invoice.invoiceId,
        )).single.returnableQuantity,
        4,
      );

      await fixture.returns.cancelReturn(
        fixture.admin,
        returnId: posted.returnId,
        reason: 'Entered against the wrong invoice',
      );

      expect(
        (await fixture.returns.returnableLines(
          invoice.invoiceId,
        )).single.returnableQuantity,
        10,
      );
    });

    test('is refused while credit stands against it', () async {
      await supplyTheShop();
      final posted = await postShopReturn(
        quantity: 5,
        unitPrice: Money.fromMajor(3000),
      );
      await inspectAll(posted.returnId);
      final creditNoteId = await fixture.returns.issueCreditNote(
        fixture.admin,
        returnId: posted.returnId,
      );

      await expectLater(
        fixture.returns.cancelReturn(
          fixture.admin,
          returnId: posted.returnId,
          reason: 'Changed our mind',
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'return.cancel_requires_no_credit',
          ),
        ),
      );

      // Withdraw the money side first, and the goods side can follow.
      await fixture.returns.cancelCreditNote(
        fixture.admin,
        creditNoteId: creditNoteId,
        reason: 'Cancelling the whole return',
      );
      await fixture.returns.cancelReturn(
        fixture.admin,
        returnId: posted.returnId,
        reason: 'Changed our mind',
      );
      expect(await balanceAt(shopLocationId), 20);
    });

    test('cannot be done twice', () async {
      await supplyTheShop();
      final posted = await postShopReturn();
      await fixture.returns.cancelReturn(
        fixture.admin,
        returnId: posted.returnId,
        reason: 'First time',
      );

      await expectLater(
        fixture.returns.cancelReturn(
          fixture.admin,
          returnId: posted.returnId,
          reason: 'Second time',
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'return.cancel_once',
          ),
        ),
      );
    });

    test('requires a reason', () async {
      await supplyTheShop();
      final posted = await postShopReturn();

      await expectLater(
        fixture.returns.cancelReturn(
          fixture.admin,
          returnId: posted.returnId,
          reason: '   ',
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });
  });

  group('a customer returning to a shop', () {
    test(
      'comes back through the customer counterparty into the shop',
      () async {
        await supplyTheShop(quantity: 20);
        // The shop sells 10 over the counter.
        await fixture.stockLedger.postMovement(
          fixture.admin,
          StockMovementRequest(
            documentType: StockDocumentType.retailSale,
            sourceLocationId: shopLocationId,
            destinationLocationId: customerId,
            shopId: shopId,
            lines: [StockMovementLine(productId: chargerId, quantity: 10)],
          ),
        );
        expect(await balanceAt(shopLocationId), 10);
        expect(await balanceAt(customerId), 10);

        final posted = await fixture.returns.postReturn(
          fixture.admin,
          ReturnDraft(
            route: ReturnRoute.customerToShop,
            fromLocationId: customerId,
            toLocationId: shopLocationId,
            shopId: shopId,
            reason: ReturnReason.customerPaymentFailure,
            lines: [
              ReturnLineDraft(
                productId: chargerId,
                quantity: 2,
                unitPrice: Money.fromMajor(3500),
              ),
            ],
          ),
        );

        // Two units are on their way back, and the shop does not have them yet.
        expect(await balanceAt(customerId), 8);
        expect(await balanceAt(shopLocationId), 10);
        expect(await balanceAt(transitId), 2);

        await inspectAll(posted.returnId);

        expect(await balanceAt(shopLocationId), 12);
        expect(await balanceAt(transitId), 0);
        expect(await fixture.stockLedger.findUnbalancedProducts(), isEmpty);
      },
    );
  });

  group('the register', () {
    test('lists the inspector\'s working pile on its own', () async {
      await supplyTheShop(quantity: 50);
      final waiting = await postShopReturn(quantity: 3);
      final done = await postShopReturn(quantity: 4);
      await inspectAll(done.returnId);

      final pending = await fixture.returnQueries
          .watchReturns(const ReturnFilter(pendingInspectionOnly: true))
          .first;

      expect(pending, hasLength(1));
      expect(pending.single.returnNumber, waiting.returnNumber);
    });

    test('totals units, value and what is still waiting', () async {
      await supplyTheShop(quantity: 50);
      await postShopReturn(quantity: 3, unitPrice: Money.fromMajor(1000));
      final second = await postShopReturn(
        quantity: 2,
        unitPrice: Money.fromMajor(1000),
      );
      await inspectAll(second.returnId);
      await fixture.returns.issueCreditNote(
        fixture.admin,
        returnId: second.returnId,
      );

      final totals = await fixture.returnQueries.returnTotals(
        const ReturnFilter(),
      );

      expect(totals.documentCount, 2);
      expect(totals.totalUnits, 5);
      expect(totals.totalValue, Money.fromMajor(5000));
      expect(totals.awaitingInspection, 1);
      expect(totals.creditedValue, Money.fromMajor(2000));
    });

    test('finds a return by its number, invoice or party', () async {
      await supplyTheShop();
      final posted = await postShopReturn();

      Future<int> matches(String search) async {
        final rows = await fixture.returnQueries
            .watchReturns(ReturnFilter(search: search))
            .first;
        return rows.length;
      }

      expect(await matches(posted.returnNumber), 1);
      expect(await matches('shop a'), 1);
      expect(await matches('no such thing'), 0);
    });

    test('lists credit notes with what is left on each', () async {
      await supplyTheShop();
      final posted = await postShopReturn(
        quantity: 5,
        unitPrice: Money.fromMajor(1000),
      );
      await inspectAll(posted.returnId);
      await fixture.returns.issueCreditNote(
        fixture.admin,
        returnId: posted.returnId,
        amount: Money.fromMajor(2000),
      );

      final notes = await fixture.returnQueries
          .watchCreditNotes(const CreditNoteFilter(withRemainingOnly: true))
          .first;

      expect(notes, hasLength(1));
      expect(notes.single.amount, Money.fromMajor(2000));
      expect(notes.single.applied, Money.zero);
      expect(notes.single.remaining, Money.fromMajor(2000));
      expect(notes.single.returnNumber, posted.returnNumber);
      expect(notes.single.canBeCancelled, isTrue);
    });
  });
}
