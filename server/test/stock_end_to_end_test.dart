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
import 'package:venvo_core/features/inventory/api/location_api.dart';
import 'package:venvo_core/features/inventory/api/stock_api.dart';
import 'package:venvo_core/features/inventory/domain/stock_models.dart';
import 'package:venvo_core/features/products/api/product_api.dart';
import 'package:venvo_core/features/products/domain/product_models.dart';

import 'support/api_harness.dart';

/// Stock movements driven through the real client against the real server.
///
/// The thing being proved here is not that the endpoints answer. It is that
/// the **double-entry stock ledger still balances** when the movement is
/// posted across a network: the signed pairs, the balance cache, the negative
/// stock guard and the reversal on cancellation all live on the server inside
/// one transaction, and none of them may weaken because the caller is remote.
void main() {
  late ApiHarness api;
  late ApiClient client;
  late AuthApi auth;
  late AuthenticatedUser admin;
  late CategoryApi categories;
  late ProductApi products;
  late AgentApi agents;
  late LocationApi locations;
  late StockQueryApi stockQueries;
  late StockLedgerApi ledger;
  late StockCountApi counts;

  late int warehouseId;
  late int supplierId;
  late int productId;

  setUp(() async {
    api = await ApiHarness.start();
    client = ApiClient(baseUrl: api.base, tokens: InMemoryTokenStore());
    auth = AuthApi(client);
    categories = CategoryApi(client);
    products = ProductApi(client);
    agents = AgentApi(client);
    locations = LocationApi(client);
    stockQueries = StockQueryApi(client);
    ledger = StockLedgerApi(client);
    counts = StockCountApi(client);

    admin = await auth.createFirstAdministrator(
      fullName: 'Venura Admin',
      username: 'admin',
      password: ApiHarness.adminPassword,
    );

    final all = await locations.watchLocations(includeVirtual: true).first;
    warehouseId = all
        .firstWhere((l) => l.code == AppConstants.mainWarehouseCode)
        .id;
    supplierId = all
        .firstWhere((l) => l.code == AppConstants.supplierLocationCode)
        .id;

    final categoryId = await categories.create(
      admin,
      const CategoryDraft(name: 'Chargers'),
    );
    productId = await products.create(
      admin,
      ProductDraft(
        sku: 'CHG-25W',
        name: 'Fast charger 25W',
        categoryId: categoryId,
        costPrice: const Money(100000),
        wholesalePrice: const Money(130000),
      ),
    );
  });

  tearDown(() async {
    await client.close();
    await api.stop();
  });

  Future<StockMovementResult> receive(int quantity) => ledger.postMovement(
    admin,
    StockMovementRequest(
      documentType: StockDocumentType.openingStock,
      sourceLocationId: supplierId,
      destinationLocationId: warehouseId,
      lines: [
        StockMovementLine(
          productId: productId,
          quantity: quantity,
          unitCost: const Money(100000),
        ),
      ],
    ),
  );

  Future<int> balanceAt(int locationId) =>
      ledger.balanceOf(locationId: locationId, productId: productId);

  /// Creates an agent and returns its inventory location id.
  Future<int> createAgentLocation(String name) async {
    final agentId = await agents.create(admin, AgentDraft(name: name));
    final all = await locations.watchLocations().first;
    return all.firstWhere((l) => l.agentId == agentId).id;
  }

  group('posting a movement', () {
    test('opening stock lands, and the ledger still nets to zero', () async {
      final result = await receive(100);
      expect(result.totalQuantity, 100);
      expect(result.lineCount, 1);
      expect(result.documentNumber, isNotEmpty);

      expect(await balanceAt(warehouseId), 100);

      // The invariant the whole inventory design rests on: every movement
      // writes a signed pair, so the sum of all deltas for a product is
      // always zero. If this list is ever non-empty, stock has been created
      // or destroyed out of nothing.
      expect(await ledger.findUnbalancedProducts(), isEmpty);

      // And the cached balance agrees with a replay of the ledger.
      final verified = await ledger.verifyBalance(
        locationId: warehouseId,
        productId: productId,
      );
      expect(verified.matches, isTrue);
      expect(verified.cached, 100);
      expect(verified.fromLedger, 100);
    });

    test('a transfer moves the quantity and nothing else', () async {
      await receive(100);
      final agentLocationId = await createAgentLocation('Kandy route');

      await ledger.postMovement(
        admin,
        StockMovementRequest(
          documentType: StockDocumentType.warehouseToAgent,
          sourceLocationId: warehouseId,
          destinationLocationId: agentLocationId,
          lines: [StockMovementLine(productId: productId, quantity: 30)],
        ),
      );

      expect(await balanceAt(warehouseId), 70);
      expect(await balanceAt(agentLocationId), 30);
      // Still balanced: 100 in from the supplier, 30 moved sideways.
      expect(await ledger.findUnbalancedProducts(), isEmpty);
    });

    test('a movement larger than the stock on hand is refused', () async {
      await receive(10);
      final agentLocationId = await createAgentLocation('Galle route');

      await expectLater(
        ledger.postMovement(
          admin,
          StockMovementRequest(
            documentType: StockDocumentType.warehouseToAgent,
            sourceLocationId: warehouseId,
            destinationLocationId: agentLocationId,
            lines: [StockMovementLine(productId: productId, quantity: 11)],
          ),
        ),
        throwsA(isA<BusinessRuleFailure>()),
      );

      // Refused means nothing moved — not "mostly nothing".
      expect(await balanceAt(warehouseId), 10);
      expect(await balanceAt(agentLocationId), 0);
      expect(await ledger.findUnbalancedProducts(), isEmpty);
    });

    test('the negative-stock override needs a written reason', () async {
      await receive(5);
      final agentLocationId = await createAgentLocation('Matara route');

      await expectLater(
        ledger.postMovement(
          admin,
          StockMovementRequest(
            documentType: StockDocumentType.warehouseToAgent,
            sourceLocationId: warehouseId,
            destinationLocationId: agentLocationId,
            lines: [StockMovementLine(productId: productId, quantity: 50)],
            allowNegativeStock: true,
            // No reason given.
          ),
        ),
        throwsA(
          isA<ValidationFailure>().having(
            (f) => f.field,
            'field',
            'negativeStockReason',
          ),
        ),
      );
      expect(await balanceAt(warehouseId), 5);
    });

    test('the override is refused to a user without the permission', () async {
      await receive(5);
      final agentLocationId = await createAgentLocation('Jaffna route');

      // A manager may transfer stock but may not drive a location negative.
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
      expect(manager.can(Permissions.stockTransfer), isTrue);
      expect(manager.can(Permissions.stockNegativeOverride), isFalse);

      await expectLater(
        StockLedgerApi(managerClient).postMovement(
          manager,
          StockMovementRequest(
            documentType: StockDocumentType.warehouseToAgent,
            sourceLocationId: warehouseId,
            destinationLocationId: agentLocationId,
            lines: [StockMovementLine(productId: productId, quantity: 50)],
            allowNegativeStock: true,
            negativeStockReason: 'Customer waiting',
          ),
        ),
        throwsA(
          isA<PermissionFailure>().having(
            (f) => f.permission,
            'permission',
            Permissions.stockNegativeOverride,
          ),
        ),
      );
      expect(await balanceAt(warehouseId), 5);
    });

    test('a cashier may not post a transfer at all', () async {
      await receive(10);
      final agentLocationId = await createAgentLocation('Negombo route');

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

      await expectLater(
        StockLedgerApi(cashierClient).postMovement(
          cashier,
          StockMovementRequest(
            documentType: StockDocumentType.warehouseToAgent,
            sourceLocationId: warehouseId,
            destinationLocationId: agentLocationId,
            lines: [StockMovementLine(productId: productId, quantity: 1)],
          ),
        ),
        throwsA(isA<PermissionFailure>()),
      );
      expect(await balanceAt(warehouseId), 10);
    });
  });

  group('cancelling a movement', () {
    test('reverses it without deleting anything', () async {
      await receive(100);
      final agentLocationId = await createAgentLocation('Kurunegala route');
      final transfer = await ledger.postMovement(
        admin,
        StockMovementRequest(
          documentType: StockDocumentType.warehouseToAgent,
          sourceLocationId: warehouseId,
          destinationLocationId: agentLocationId,
          lines: [StockMovementLine(productId: productId, quantity: 40)],
        ),
      );
      expect(await balanceAt(warehouseId), 60);

      await ledger.cancelMovement(
        admin,
        transactionId: transfer.transactionId,
        reason: 'Loaded onto the wrong lorry',
      );

      expect(await balanceAt(warehouseId), 100);
      expect(await balanceAt(agentLocationId), 0);
      expect(await ledger.findUnbalancedProducts(), isEmpty);

      // The original document is still there. A completed transaction is
      // reversed, never erased.
      final documents = await stockQueries
          .watchDocuments(const StockDocumentFilter())
          .first;
      expect(documents.map((d) => d.id), contains(transfer.transactionId));
    });

    test('cancelling needs a reason', () async {
      final opening = await receive(10);
      await expectLater(
        ledger.cancelMovement(
          admin,
          transactionId: opening.transactionId,
          reason: '   ',
        ),
        throwsA(isA<ValidationFailure>()),
      );
      expect(await balanceAt(warehouseId), 10);
    });
  });

  group('reads', () {
    test('the stock list re-fetches after a movement', () async {
      final emissions = <List<ProductStockRow>>[];
      final subscription = stockQueries
          .watchProductStock(const StockOverviewFilter(hideZeroStock: false))
          .listen(emissions.add);
      addTearDown(subscription.cancel);

      final deadline = DateTime.now().add(const Duration(seconds: 10));
      Future<void> waitFor(int count) async {
        while (emissions.length < count) {
          if (DateTime.now().isAfter(deadline)) {
            fail('expected $count emissions, saw ${emissions.length}');
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }

      await waitFor(1);
      await receive(25);
      await waitFor(2);
      expect(emissions.last.single.warehouseQuantity, 25);
    });

    test('a document and its detail agree', () async {
      final opening = await receive(60);
      final detail = await stockQueries.documentDetail(opening.transactionId);
      expect(detail.summary.documentNumber, opening.documentNumber);
      expect(detail.lines.single.quantity, 60);

      final ledgerRows = await stockQueries
          .watchLedger(const StockLedgerFilter(includeVirtualLocations: true))
          .first;
      // A movement writes a pair: one row out of the supplier, one into the
      // warehouse.
      expect(ledgerRows.length, greaterThanOrEqualTo(2));
    });

    test('the document type filter is applied, not ignored', () async {
      await receive(10);
      final matching = await stockQueries
          .watchDocuments(
            const StockDocumentFilter(types: {StockDocumentType.openingStock}),
          )
          .first;
      expect(matching, isNotEmpty);

      final other = await stockQueries
          .watchDocuments(
            const StockDocumentFilter(
              types: {StockDocumentType.warehouseToShop},
            ),
          )
          .first;
      expect(other, isEmpty);
    });
  });

  group('reconciliation', () {
    test('a count posts its variance as a real adjustment', () async {
      await receive(100);

      final countId = await counts.createCount(
        admin,
        locationId: warehouseId,
        notes: 'Monthly count',
      );
      final sheet = await counts.loadCount(countId);
      expect(sheet.lines.single.productId, productId);
      expect(sheet.lines.single.systemQuantity, 100);

      // Two short on the shelf.
      await counts.saveCountedQuantities(
        admin,
        countId: countId,
        countedByProductId: {productId: 98},
      );
      expect(
        (await counts.varianceValue(countId)).cents,
        isNot(0),
        reason: 'a two-unit shortfall has a value',
      );

      final movements = await counts.postCount(
        admin,
        countId: countId,
        reason: 'Monthly count',
      );
      expect(movements, isNotEmpty);

      // The correction is itself a ledger movement, so the books still
      // balance and the adjustment is auditable.
      expect(await balanceAt(warehouseId), 98);
      expect(await ledger.findUnbalancedProducts(), isEmpty);
    });

    test('a discarded count changes nothing', () async {
      await receive(50);
      final countId = await counts.createCount(admin, locationId: warehouseId);
      await counts.saveCountedQuantities(
        admin,
        countId: countId,
        countedByProductId: {productId: 1},
      );
      await counts.discardCount(admin, countId);

      expect(await balanceAt(warehouseId), 50);
      expect(await ledger.findUnbalancedProducts(), isEmpty);
    });

    test('an uncounted line is kept distinct from a counted zero', () async {
      await receive(20);
      final countId = await counts.createCount(admin, locationId: warehouseId);
      // null means "not counted yet". If the wire format collapsed it to 0,
      // posting the count would write off the entire stock holding.
      await counts.saveCountedQuantities(
        admin,
        countId: countId,
        countedByProductId: {productId: null},
      );
      final sheet = await counts.loadCount(countId);
      expect(sheet.lines.single.countedQuantity, isNull);
    });
  });
}
