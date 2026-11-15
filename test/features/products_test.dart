import 'package:flutter_test/flutter_test.dart';
import 'package:venvo_core/core/constants/app_constants.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/errors/failures.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/agents/domain/agent_models.dart';
import 'package:venvo_core/features/categories/domain/category_models.dart';
import 'package:venvo_core/features/products/domain/product_models.dart';
import 'package:venvo_core/features/shops/domain/shop_models.dart';

import '../helpers/master_data_fixtures.dart';

void main() {
  late MasterDataFixture fixture;
  late int chargersId;
  late int cablesId;

  setUp(() async {
    fixture = await MasterDataFixture.create();
    chargersId = await fixture.categories.create(
      fixture.admin,
      const CategoryDraft(name: 'Chargers'),
    );
    cablesId = await fixture.categories.create(
      fixture.admin,
      const CategoryDraft(name: 'Cables'),
    );
  });

  tearDown(() => fixture.dispose());

  Future<int> addProduct({
    String sku = 'CHG-25W',
    String name = '25W Charger',
    int? categoryId,
    String? barcode,
    String? brand,
    Money cost = const Money(200000),
    Money wholesale = const Money(300000),
    Money retail = const Money(350000),
    int reorderLevel = 0,
    int unitsPerPack = 1,
  }) {
    return fixture.products.create(
      fixture.admin,
      ProductDraft(
        sku: sku,
        name: name,
        categoryId: categoryId ?? chargersId,
        barcode: barcode,
        brand: brand,
        costPrice: cost,
        wholesalePrice: wholesale,
        retailPrice: retail,
        reorderLevel: reorderLevel,
        unitsPerPack: unitsPerPack,
      ),
    );
  }

  Future<List<ProductListItem>> list([
    ProductFilter filter = const ProductFilter(),
  ]) => fixture.products.watchProducts(filter).first;

  group('creating', () {
    test('creates a product with its prices intact', () async {
      await addProduct();
      final products = await list();

      expect(products.length, 1);
      final product = products.single;
      expect(product.sku, 'CHG-25W');
      expect(product.name, '25W Charger');
      expect(product.categoryName, 'Chargers');
      expect(product.costPrice, const Money(200000));
      expect(product.wholesalePrice, const Money(300000));
      expect(product.retailPrice, const Money(350000));
      expect(product.sellableQuantity, 0);
      expect(product.status, EntityStatus.active);
    });

    test('upper-cases the SKU', () async {
      await addProduct(sku: 'chg-25w');
      final products = await list();
      expect(products.single.sku, 'CHG-25W');
    });

    test('refuses a duplicate SKU regardless of case', () async {
      await addProduct(sku: 'CHG-25W');
      await expectLater(
        addProduct(sku: 'chg-25w', name: 'Another charger'),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'product.sku_unique',
          ),
        ),
      );
      expect((await list()).length, 1);
    });

    test('rejects a SKU with unusable characters', () async {
      await expectLater(
        addProduct(sku: 'CHG 25W!'),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('refuses a duplicate barcode', () async {
      await addProduct(sku: 'CHG-25W', barcode: '8901234567890');
      await expectLater(
        addProduct(
          sku: 'CHG-66W',
          name: '66W Charger',
          barcode: '8901234567890',
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'product.barcode_unique',
          ),
        ),
      );
    });

    test('allows many products with no barcode', () async {
      await addProduct(sku: 'CHG-25W');
      await addProduct(sku: 'CHG-66W', name: '66W Charger');
      await addProduct(
        sku: 'CBL-C',
        name: 'Type-C Cable',
        categoryId: cablesId,
      );
      expect((await list()).length, 3);
    });

    test('refuses an inactive category', () async {
      await fixture.categories.archive(fixture.admin, cablesId);
      await expectLater(
        addProduct(sku: 'CBL-C', categoryId: cablesId),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'product.category_active',
          ),
        ),
      );
    });

    test('refuses a pack size below one', () async {
      await expectLater(
        addProduct(unitsPerPack: 0),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('refuses a negative price', () async {
      await expectLater(
        addProduct(cost: const Money(-100)),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('requires the manage-products permission', () async {
      final viewer = await fixture.createViewer();
      await expectLater(
        fixture.products.create(
          viewer,
          ProductDraft(
            sku: 'NOPE',
            name: 'Not allowed',
            categoryId: chargersId,
          ),
        ),
        throwsA(isA<PermissionFailure>()),
      );
    });
  });

  group('margins', () {
    test('computes the wholesale margin exactly', () async {
      await addProduct(
        cost: Money.fromMajor(2000),
        wholesale: Money.fromMajor(3000),
      );
      final product = (await list()).single;

      expect(product.wholesaleMargin, Money.fromMajor(1000));
      // 1000 of 3000 is 33.33%
      expect(product.wholesaleMarginBps, 3333);
      expect(product.sellsBelowCost, isFalse);
    });

    test('flags a product priced below cost', () async {
      await addProduct(
        cost: Money.fromMajor(3000),
        wholesale: Money.fromMajor(2500),
      );
      final product = (await list()).single;

      expect(product.sellsBelowCost, isTrue);
      expect(product.wholesaleMargin, Money.fromMajor(-500));
    });

    test('does not flag a product with no wholesale price set', () async {
      await addProduct(cost: Money.fromMajor(3000), wholesale: Money.zero);
      expect((await list()).single.sellsBelowCost, isFalse);
    });
  });

  group('stock aggregation', () {
    test(
      'splits stock by location kind and excludes damaged from sellable',
      () async {
        final productId = await addProduct();
        final warehouse = await fixture.locations.mainWarehouse();
        final damaged = await fixture.locations.byCode(
          AppConstants.damagedLocationCode,
        );

        final agentId = await fixture.agents.create(
          fixture.admin,
          const AgentDraft(name: 'Agent A'),
        );
        final agentLocation = await fixture.locations.forAgent(agentId);
        final shopId = await fixture.shops.create(
          fixture.admin,
          ShopDraftForTest.shop('Shop A', agentId),
        );
        final shopLocation = await fixture.locations.forShop(shopId);

        await fixture.giveStock(
          locationId: warehouse.id,
          productId: productId,
          quantity: 50,
        );
        await fixture.giveStock(
          locationId: agentLocation!.id,
          productId: productId,
          quantity: 30,
        );
        await fixture.giveStock(
          locationId: shopLocation!.id,
          productId: productId,
          quantity: 20,
        );
        await fixture.giveStock(
          locationId: damaged.id,
          productId: productId,
          quantity: 5,
        );

        final product = (await list()).single;
        expect(product.warehouseQuantity, 50);
        expect(product.agentQuantity, 30);
        expect(product.shopQuantity, 20);
        expect(product.damagedQuantity, 5);
        // Damaged stock is not sellable.
        expect(product.sellableQuantity, 100);
        expect(product.stockValueAtCost, const Money(200000) * 100);
      },
    );

    test('reports where the stock sits', () async {
      final productId = await addProduct();
      final warehouse = await fixture.locations.mainWarehouse();
      await fixture.giveStock(
        locationId: warehouse.id,
        productId: productId,
        quantity: 40,
      );

      final holdings = await fixture.products.stockByLocation(productId);
      expect(holdings.length, 1);
      expect(holdings.single.quantity, 40);
      expect(holdings.single.locationKind, LocationKind.warehouse);
    });
  });

  group('low stock', () {
    test('flags a product at or below its reorder level', () async {
      final warehouse = await fixture.locations.mainWarehouse();

      final atLevel = await addProduct(sku: 'AT', reorderLevel: 10);
      final below = await addProduct(sku: 'BELOW', reorderLevel: 10);
      final above = await addProduct(sku: 'ABOVE', reorderLevel: 10);
      final untracked = await addProduct(sku: 'UNTRACKED');

      await fixture.giveStock(
        locationId: warehouse.id,
        productId: atLevel,
        quantity: 10,
      );
      await fixture.giveStock(
        locationId: warehouse.id,
        productId: below,
        quantity: 9,
      );
      await fixture.giveStock(
        locationId: warehouse.id,
        productId: above,
        quantity: 11,
      );
      await fixture.giveStock(
        locationId: warehouse.id,
        productId: untracked,
        quantity: 0,
      );

      final products = await list();
      bool isLow(String sku) =>
          products.firstWhere((p) => p.sku == sku).isLowStock;

      expect(isLow('AT'), isTrue);
      expect(isLow('BELOW'), isTrue);
      expect(isLow('ABOVE'), isFalse);
      // A reorder level of zero means the product is not tracked.
      expect(isLow('UNTRACKED'), isFalse);
    });

    test('the low-stock filter returns only tracked, low products', () async {
      await addProduct(sku: 'LOW', reorderLevel: 10);
      await addProduct(sku: 'UNTRACKED');

      final low = await list(const ProductFilter(lowStockOnly: true));
      expect(low.map((p) => p.sku), ['LOW']);
    });
  });

  group('filtering and sorting', () {
    setUp(() async {
      await addProduct(
        sku: 'CHG-25W',
        name: '25W Charger',
        brand: 'Anker',
        wholesale: Money.fromMajor(3000),
      );
      await addProduct(
        sku: 'CHG-66W',
        name: '66W Charger',
        brand: 'Anker',
        wholesale: Money.fromMajor(5500),
      );
      await addProduct(
        sku: 'CBL-C',
        name: 'Type-C Cable',
        categoryId: cablesId,
        brand: 'Baseus',
        barcode: '8901234567890',
        wholesale: Money.fromMajor(450),
      );
    });

    test('searches name, SKU, brand and barcode', () async {
      expect((await list(const ProductFilter(search: 'charger'))).length, 2);
      expect(
        (await list(const ProductFilter(search: 'cbl'))).single.sku,
        'CBL-C',
      );
      expect(
        (await list(const ProductFilter(search: 'baseus'))).single.sku,
        'CBL-C',
      );
      expect(
        (await list(const ProductFilter(search: '890123'))).single.sku,
        'CBL-C',
      );
    });

    test('search is case-insensitive', () async {
      expect((await list(const ProductFilter(search: 'ANKER'))).length, 2);
    });

    test('filters by category', () async {
      final cables = await list(ProductFilter(categoryId: cablesId));
      expect(cables.map((p) => p.sku), ['CBL-C']);
    });

    test('filters by brand', () async {
      final baseus = await list(const ProductFilter(brand: 'Baseus'));
      expect(baseus.map((p) => p.sku), ['CBL-C']);
    });

    test('lists the brands in use', () async {
      final brands = await fixture.products.watchBrands().first;
      expect(brands, ['Anker', 'Baseus']);
    });

    test('sorts by wholesale price, both ways', () async {
      final ascending = await list(
        const ProductFilter(sortKey: ProductSortKey.wholesalePrice),
      );
      expect(ascending.map((p) => p.sku), ['CBL-C', 'CHG-25W', 'CHG-66W']);

      final descending = await list(
        const ProductFilter(
          sortKey: ProductSortKey.wholesalePrice,
          sortAscending: false,
        ),
      );
      expect(descending.map((p) => p.sku), ['CHG-66W', 'CHG-25W', 'CBL-C']);
    });

    test('sorts by name by default', () async {
      final products = await list();
      expect(products.map((p) => p.name), [
        '25W Charger',
        '66W Charger',
        'Type-C Cable',
      ]);
    });

    test('hides inactive and archived products unless asked', () async {
      final products = await list();
      final cable = products.firstWhere((p) => p.sku == 'CBL-C');
      await fixture.products.update(
        fixture.admin,
        ProductDraft(
          id: cable.id,
          sku: cable.sku,
          name: cable.name,
          categoryId: cable.categoryId,
          status: EntityStatus.inactive,
        ),
      );

      expect((await list()).length, 2);
      expect(
        (await list(const ProductFilter(includeInactive: true))).length,
        3,
      );
    });
  });

  group('archiving', () {
    test('archives a product with no stock', () async {
      final id = await addProduct();
      await fixture.products.archive(fixture.admin, id);

      expect(await list(), isEmpty);
      final all = await list(const ProductFilter(includeArchived: true));
      expect(all.single.status, EntityStatus.archived);
    });

    test('refuses to archive a product that still holds stock', () async {
      final id = await addProduct();
      final warehouse = await fixture.locations.mainWarehouse();
      await fixture.giveStock(
        locationId: warehouse.id,
        productId: id,
        quantity: 25,
      );

      await expectLater(
        fixture.products.archive(fixture.admin, id),
        throwsA(
          isA<BusinessRuleFailure>()
              .having(
                (failure) => failure.rule,
                'rule',
                'product.no_stock_when_archiving',
              )
              .having(
                (failure) => failure.details,
                'details',
                contains('Main Warehouse: 25'),
              ),
        ),
      );
      expect((await list()).single.status, EntityStatus.active);
    });

    test(
      'ignores stock sitting in a virtual location when archiving',
      () async {
        // The customer counterparty accumulates everything ever sold. It must
        // not stop a discontinued product being archived.
        final id = await addProduct();
        final customers = await fixture.locations.byCode(
          AppConstants.customerLocationCode,
        );
        await fixture.giveStock(
          locationId: customers.id,
          productId: id,
          quantity: 500,
        );

        await fixture.products.archive(fixture.admin, id);
        final all = await list(const ProductFilter(includeArchived: true));
        expect(all.single.status, EntityStatus.archived);
      },
    );

    test('restores an archived product', () async {
      final id = await addProduct();
      await fixture.products.archive(fixture.admin, id);
      await fixture.products.restore(fixture.admin, id);
      expect((await list()).single.status, EntityStatus.active);
    });
  });

  group('audit trail', () {
    test('records the before and after of a price change', () async {
      final id = await addProduct(wholesale: Money.fromMajor(3000));
      await fixture.products.update(
        fixture.admin,
        ProductDraft(
          id: id,
          sku: 'CHG-25W',
          name: '25W Charger',
          categoryId: chargersId,
          costPrice: const Money(200000),
          wholesalePrice: Money.fromMajor(3200),
          retailPrice: const Money(350000),
        ),
      );

      final entries = await fixture.auditEntries();
      final update = entries.firstWhere(
        (entry) =>
            entry.entityKind == EntityKind.product &&
            entry.action == AuditAction.update,
      );
      expect(update.beforeJson, contains('300000'));
      expect(update.afterJson, contains('320000'));
      // Only the changed fields are recorded.
      expect(update.beforeJson, isNot(contains('reorderLevel')));
    });
  });

  group('bulk category move', () {
    test('moves several products and audits each one', () async {
      final first = await addProduct(sku: 'CHG-25W');
      final second = await addProduct(sku: 'CHG-66W', name: '66W Charger');

      final moved = await fixture.products.bulkUpdateCategory(
        actor: fixture.admin,
        productIds: [first, second],
        categoryId: cablesId,
      );

      expect(moved, 2);
      final products = await list();
      expect(products.every((p) => p.categoryName == 'Cables'), isTrue);

      final entries = await fixture.auditEntries();
      expect(
        entries.where((entry) => entry.summary.contains('Moved')).length,
        2,
      );
    });

    test('skips products already in the target category', () async {
      final id = await addProduct();
      final moved = await fixture.products.bulkUpdateCategory(
        actor: fixture.admin,
        productIds: [id],
        categoryId: chargersId,
      );
      expect(moved, 0);
    });

    test('rejects an empty selection', () async {
      await expectLater(
        fixture.products.bulkUpdateCategory(
          actor: fixture.admin,
          productIds: const [],
          categoryId: cablesId,
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });
  });
}

/// Small helper so the product tests can create a shop without repeating the
/// whole draft.
abstract final class ShopDraftForTest {
  static ShopDraft shop(String name, int agentId) =>
      ShopDraft(name: name, assignedAgentId: agentId);
}
