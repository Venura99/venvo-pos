import 'package:flutter_test/flutter_test.dart';
import 'package:venvo_core/core/constants/app_constants.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/errors/failures.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/agents/domain/agent_models.dart';
import 'package:venvo_core/features/categories/domain/category_models.dart';
import 'package:venvo_core/features/inventory/domain/location_models.dart';
import 'package:venvo_core/features/products/domain/product_models.dart';
import 'package:venvo_core/features/shops/domain/shop_models.dart';

import '../helpers/master_data_fixtures.dart';

void main() {
  late MasterDataFixture fixture;

  setUp(() async {
    fixture = await MasterDataFixture.create();
  });

  tearDown(() => fixture.dispose());

  Future<List<LocationListItem>> list({bool includeVirtual = false}) =>
      fixture.locations.watchLocations(includeVirtual: includeVirtual).first;

  group('seeded locations', () {
    test('hides the virtual counterparties by default', () async {
      final visible = await list();
      final kinds = visible.map((l) => l.kind).toSet();

      expect(kinds, contains(LocationKind.warehouse));
      expect(kinds, contains(LocationKind.damaged));
      expect(kinds, isNot(contains(LocationKind.supplier)));
      expect(kinds, isNot(contains(LocationKind.customer)));
    });

    test('shows the virtual counterparties when asked', () async {
      final all = await list(includeVirtual: true);
      final kinds = all.map((l) => l.kind).toSet();

      expect(
        kinds,
        containsAll(<LocationKind>[
          LocationKind.supplier,
          LocationKind.customer,
          LocationKind.adjustment,
          LocationKind.inTransit,
        ]),
      );
      expect(
        all.where((l) => l.isVirtual).every((l) => l.kind.isVirtual),
        isTrue,
      );
    });

    test('orders warehouses first', () async {
      final visible = await list();
      expect(visible.first.kind, LocationKind.warehouse);
      expect(visible.first.code, AppConstants.mainWarehouseCode);
    });

    test(
      'resolves the main warehouse and other well-known locations',
      () async {
        final warehouse = await fixture.locations.mainWarehouse();
        expect(warehouse.code, AppConstants.mainWarehouseCode);

        final damaged = await fixture.locations.byCode(
          AppConstants.damagedLocationCode,
        );
        expect(damaged.kind, LocationKind.damaged);
      },
    );

    test('throws a readable failure for a missing code', () async {
      await expectLater(
        fixture.locations.byCode('NOT-A-CODE'),
        throwsA(isA<NotFoundFailure>()),
      );
    });
  });

  group('party-owned locations', () {
    test('an agent location is attributed to its agent', () async {
      final agentId = await fixture.agents.create(
        fixture.admin,
        const AgentDraft(name: 'Agent A'),
      );

      final visible = await list();
      final agentLocation = visible.firstWhere((l) => l.agentId == agentId);

      expect(agentLocation.kind, LocationKind.agent);
      expect(agentLocation.ownerName, 'Agent A');
      expect(agentLocation.isPartyOwned, isTrue);
    });

    test('a shop location is attributed to its shop', () async {
      final agentId = await fixture.agents.create(
        fixture.admin,
        const AgentDraft(name: 'Agent A'),
      );
      final shopId = await fixture.shops.create(
        fixture.admin,
        ShopDraft(name: 'Shop A', assignedAgentId: agentId),
      );

      final visible = await list();
      final shopLocation = visible.firstWhere((l) => l.shopId == shopId);

      expect(shopLocation.kind, LocationKind.shop);
      expect(shopLocation.ownerName, 'Shop A');
    });

    test('cannot be renamed through the warehouse operations', () async {
      final agentId = await fixture.agents.create(
        fixture.admin,
        const AgentDraft(name: 'Agent A'),
      );
      final location = await fixture.locations.forAgent(agentId);

      await expectLater(
        fixture.locations.renameWarehouse(
          fixture.admin,
          locationId: location!.id,
          name: 'Hijacked',
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'location.rename_warehouse_only',
          ),
        ),
      );
    });
  });

  group('stock totals', () {
    test('reports units, product lines and value per location', () async {
      final categoryId = await fixture.categories.create(
        fixture.admin,
        const CategoryDraft(name: 'Chargers'),
      );
      final first = await fixture.products.create(
        fixture.admin,
        ProductDraft(
          sku: 'CHG-25W',
          name: '25W Charger',
          categoryId: categoryId,
        ),
      );
      final second = await fixture.products.create(
        fixture.admin,
        ProductDraft(
          sku: 'CHG-66W',
          name: '66W Charger',
          categoryId: categoryId,
        ),
      );

      final warehouse = await fixture.locations.mainWarehouse();
      await fixture.giveStock(
        locationId: warehouse.id,
        productId: first,
        quantity: 50,
        unitCost: Money.fromMajor(2000),
      );
      await fixture.giveStock(
        locationId: warehouse.id,
        productId: second,
        quantity: 20,
        unitCost: Money.fromMajor(3500),
      );

      final visible = await list();
      final row = visible.firstWhere((l) => l.id == warehouse.id);

      expect(row.productLines, 2);
      expect(row.totalUnits, 70);
      // 50 x 2,000 + 20 x 3,500 = 170,000
      expect(row.stockValueAtCost, Money.fromMajor(170000));
      expect(row.hasNegativeStock, isFalse);
    });

    test(
      'surfaces a real location gone negative rather than hiding it',
      () async {
        final categoryId = await fixture.categories.create(
          fixture.admin,
          const CategoryDraft(name: 'Chargers'),
        );
        final productId = await fixture.products.create(
          fixture.admin,
          ProductDraft(
            sku: 'CHG-25W',
            name: '25W Charger',
            categoryId: categoryId,
          ),
        );
        final warehouse = await fixture.locations.mainWarehouse();
        await fixture.giveStock(
          locationId: warehouse.id,
          productId: productId,
          quantity: -5,
        );

        final row = (await list()).firstWhere((l) => l.id == warehouse.id);
        expect(row.totalUnits, -5);
        expect(row.hasNegativeStock, isTrue);
      },
    );

    test('a negative virtual balance is normal and not flagged', () async {
      // Goods flow out of the supplier counterparty into the business, so its
      // balance is negative by design. That is the counterparty doing its job.
      final categoryId = await fixture.categories.create(
        fixture.admin,
        const CategoryDraft(name: 'Chargers'),
      );
      final productId = await fixture.products.create(
        fixture.admin,
        ProductDraft(
          sku: 'CHG-25W',
          name: '25W Charger',
          categoryId: categoryId,
        ),
      );
      final suppliers = await fixture.locations.byCode(
        AppConstants.supplierLocationCode,
      );
      await fixture.giveStock(
        locationId: suppliers.id,
        productId: productId,
        quantity: -500,
      );

      final row = (await list(
        includeVirtual: true,
      )).firstWhere((l) => l.id == suppliers.id);
      expect(row.totalUnits, -500);
      expect(row.hasNegativeStock, isFalse);
    });
  });

  group('additional warehouses', () {
    test('creates one with an allocated code', () async {
      await fixture.locations.createWarehouse(
        fixture.admin,
        name: 'Kandy Warehouse',
      );

      final warehouses = (await list())
          .where((l) => l.kind == LocationKind.warehouse)
          .toList();
      expect(warehouses.length, 2);

      final created = warehouses.firstWhere((l) => l.name == 'Kandy Warehouse');
      expect(created.code, 'WH-00001');
      expect(created.isActive, isTrue);
    });

    test('refuses a duplicate name', () async {
      await fixture.locations.createWarehouse(
        fixture.admin,
        name: 'Kandy Warehouse',
      );
      await expectLater(
        fixture.locations.createWarehouse(
          fixture.admin,
          name: 'kandy warehouse',
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'location.name_unique',
          ),
        ),
      );
    });

    test('renames one', () async {
      final id = await fixture.locations.createWarehouse(
        fixture.admin,
        name: 'Kandy Warehouse',
      );
      await fixture.locations.renameWarehouse(
        fixture.admin,
        locationId: id,
        name: 'Kandy Store',
      );

      final row = (await list()).firstWhere((l) => l.id == id);
      expect(row.name, 'Kandy Store');
    });

    test('deactivates an empty one', () async {
      final id = await fixture.locations.createWarehouse(
        fixture.admin,
        name: 'Kandy Warehouse',
      );
      await fixture.locations.setWarehouseActive(
        fixture.admin,
        locationId: id,
        isActive: false,
      );

      final row = (await list()).firstWhere((l) => l.id == id);
      expect(row.isActive, isFalse);
    });

    test('refuses to deactivate one that still holds stock', () async {
      final categoryId = await fixture.categories.create(
        fixture.admin,
        const CategoryDraft(name: 'Chargers'),
      );
      final productId = await fixture.products.create(
        fixture.admin,
        ProductDraft(
          sku: 'CHG-25W',
          name: '25W Charger',
          categoryId: categoryId,
        ),
      );
      final id = await fixture.locations.createWarehouse(
        fixture.admin,
        name: 'Kandy Warehouse',
      );
      await fixture.giveStock(
        locationId: id,
        productId: productId,
        quantity: 10,
      );

      await expectLater(
        fixture.locations.setWarehouseActive(
          fixture.admin,
          locationId: id,
          isActive: false,
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'location.no_stock_when_deactivating',
          ),
        ),
      );
    });

    test('refuses to deactivate the main warehouse', () async {
      final warehouse = await fixture.locations.mainWarehouse();
      await expectLater(
        fixture.locations.setWarehouseActive(
          fixture.admin,
          locationId: warehouse.id,
          isActive: false,
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'location.keep_main_warehouse',
          ),
        ),
      );
    });

    test('requires the stock-adjust permission', () async {
      final viewer = await fixture.createViewer();
      await expectLater(
        fixture.locations.createWarehouse(viewer, name: 'Sneaky Warehouse'),
        throwsA(isA<PermissionFailure>()),
      );
    });
  });
}
