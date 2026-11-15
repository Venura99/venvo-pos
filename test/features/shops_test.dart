import 'package:flutter_test/flutter_test.dart';
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
  late int agentAId;
  late int agentBId;

  setUp(() async {
    fixture = await MasterDataFixture.create();
    agentAId = await fixture.agents.create(
      fixture.admin,
      const AgentDraft(name: 'Agent A'),
    );
    agentBId = await fixture.agents.create(
      fixture.admin,
      const AgentDraft(name: 'Agent B'),
    );
  });

  tearDown(() => fixture.dispose());

  Future<int> addShop({
    String name = 'Shop A',
    String? code,
    int? agentId,
    Money openingBalance = Money.zero,
    Money? creditLimit,
  }) {
    return fixture.shops.create(
      fixture.admin,
      ShopDraft(
        name: name,
        code: code,
        assignedAgentId: agentId ?? agentAId,
        openingBalance: openingBalance,
        creditLimit: creditLimit,
      ),
    );
  }

  Future<List<ShopListItem>> list([ShopFilter filter = const ShopFilter()]) =>
      fixture.shops.watchShops(filter).first;

  group('creating', () {
    test(
      'creates a shop with an allocated code and its own location',
      () async {
        final id = await addShop();
        final shops = await list();

        expect(shops.length, 1);
        expect(shops.single.code, 'SH-00001');
        expect(shops.single.assignedAgentId, agentAId);
        expect(shops.single.assignedAgentName, 'Agent A');

        final location = await fixture.locations.forShop(id);
        expect(location, isNot(null));
        expect(location!.kind, LocationKind.shop);
        expect(location.code, 'LOC-SH-00001');
        expect(location.name, 'Shop A (Shop)');
      },
    );

    test('allows a shop with no agent yet', () async {
      await fixture.shops.create(
        fixture.admin,
        const ShopDraft(name: 'Unassigned Shop'),
      );
      final shop = (await list()).single;
      expect(shop.hasAgent, isFalse);
      expect(shop.assignedAgentId, isNull);
    });

    test('refuses an inactive agent', () async {
      await fixture.agents.archive(fixture.admin, agentBId);
      await expectLater(
        addShop(agentId: agentBId),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'shop.agent_active',
          ),
        ),
      );
    });

    test('refuses a duplicate code', () async {
      await addShop(name: 'Shop A', code: 'MAIN');
      await expectLater(
        addShop(name: 'Shop B', code: 'main'),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'shop.code_unique',
          ),
        ),
      );
    });

    test('rejects a negative credit limit', () async {
      await expectLater(
        addShop(creditLimit: const Money(-100)),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('requires the manage-shops permission', () async {
      final viewer = await fixture.createViewer();
      await expectLater(
        fixture.shops.create(viewer, const ShopDraft(name: 'Nope')),
        throwsA(isA<PermissionFailure>()),
      );
    });
  });

  group('reassigning an agent', () {
    test('moves the shop and preserves every past document', () async {
      final shopId = await addShop(agentId: agentAId);

      // A supply invoice raised while Agent A was responsible.
      final invoiceId = await fixture.postInvoice(
        number: 'SINV-2026-00001',
        netTotal: Money.fromMajor(20000),
        shopId: shopId,
        agentId: agentAId,
      );

      await fixture.shops.reassignAgent(
        fixture.admin,
        shopId: shopId,
        agentId: agentBId,
        reason: 'Territory change',
      );

      // The shop now belongs to Agent B...
      final shop = (await list()).single;
      expect(shop.assignedAgentId, agentBId);
      expect(shop.assignedAgentName, 'Agent B');

      // ...but the invoice still records Agent A, so agent-wise history for
      // both agents stays correct.
      final invoice = await (fixture.db.select(
        fixture.db.invoices,
      )..where((i) => i.id.equals(invoiceId))).getSingle();
      expect(invoice.agentId, agentAId);
      // The shop still owes the same amount; nothing financial moved.
      expect(shop.outstandingBalance, Money.fromMajor(20000));
    });

    test('can unassign a shop', () async {
      final shopId = await addShop();
      await fixture.shops.reassignAgent(
        fixture.admin,
        shopId: shopId,
        agentId: null,
      );
      expect((await list()).single.hasAgent, isFalse);
    });

    test('refuses a reassignment that changes nothing', () async {
      final shopId = await addShop(agentId: agentAId);
      await expectLater(
        fixture.shops.reassignAgent(
          fixture.admin,
          shopId: shopId,
          agentId: agentAId,
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'shop.reassign_no_op',
          ),
        ),
      );
    });

    test('refuses an inactive agent', () async {
      final shopId = await addShop(agentId: agentAId);
      await fixture.agents.archive(fixture.admin, agentBId);

      await expectLater(
        fixture.shops.reassignAgent(
          fixture.admin,
          shopId: shopId,
          agentId: agentBId,
        ),
        throwsA(isA<BusinessRuleFailure>()),
      );
    });

    test('records the move, the reason and that history is kept', () async {
      final shopId = await addShop(agentId: agentAId);
      await fixture.shops.reassignAgent(
        fixture.admin,
        shopId: shopId,
        agentId: agentBId,
        reason: 'Territory change',
      );

      final entries = await fixture.auditEntries();
      final move = entries.firstWhere(
        (entry) => entry.summary.contains('Reassigned'),
      );
      expect(move.summary, contains('Agent A'));
      expect(move.summary, contains('Agent B'));
      expect(move.summary, contains('keep their original agent'));
      expect(move.afterJson, contains('Territory change'));
    });

    test('the unassigned filter finds shops needing an agent', () async {
      await addShop(name: 'Served', agentId: agentAId);
      await fixture.shops.create(
        fixture.admin,
        const ShopDraft(name: 'Orphan'),
      );

      final unassigned = await list(const ShopFilter(unassignedOnly: true));
      expect(unassigned.map((s) => s.name), ['Orphan']);
    });

    test('filters shops by agent', () async {
      await addShop(name: 'Shop A', agentId: agentAId);
      await addShop(name: 'Shop B', agentId: agentBId);

      final forAgentB = await list(ShopFilter(agentId: agentBId));
      expect(forAgentB.map((s) => s.name), ['Shop B']);
    });
  });

  group('credit limits', () {
    test('reports available credit', () async {
      final shopId = await addShop(creditLimit: Money.fromMajor(50000));
      await fixture.postInvoice(
        number: 'SINV-2026-00001',
        netTotal: Money.fromMajor(20000),
        shopId: shopId,
        agentId: agentAId,
      );

      final shop = (await list()).single;
      expect(shop.outstandingBalance, Money.fromMajor(20000));
      expect(shop.availableCredit, Money.fromMajor(30000));
      expect(shop.isOverCreditLimit, isFalse);
    });

    test('flags a shop over its limit', () async {
      final shopId = await addShop(creditLimit: Money.fromMajor(10000));
      await fixture.postInvoice(
        number: 'SINV-2026-00001',
        netTotal: Money.fromMajor(15000),
        shopId: shopId,
        agentId: agentAId,
      );

      final shop = (await list()).single;
      expect(shop.isOverCreditLimit, isTrue);
      expect(shop.availableCredit, Money.zero);
    });

    test('a shop with no limit is never over it', () async {
      final shopId = await addShop();
      await fixture.postInvoice(
        number: 'SINV-2026-00001',
        netTotal: Money.fromMajor(900000),
        shopId: shopId,
        agentId: agentAId,
      );

      final shop = (await list()).single;
      expect(shop.creditLimit, isNull);
      expect(shop.isOverCreditLimit, isFalse);
      expect(shop.availableCredit, isNull);
    });

    test('the over-limit filter finds only those shops', () async {
      final overId = await addShop(
        name: 'Over',
        creditLimit: Money.fromMajor(1000),
      );
      await addShop(name: 'Within', creditLimit: Money.fromMajor(100000));
      await fixture.postInvoice(
        number: 'SINV-2026-00001',
        netTotal: Money.fromMajor(5000),
        shopId: overId,
        agentId: agentAId,
      );

      final over = await list(const ShopFilter(overCreditLimitOnly: true));
      expect(over.map((s) => s.name), ['Over']);
    });
  });

  group('retail sales are kept separate', () {
    test('a retail sale is reported apart from what was supplied', () async {
      final shopId = await addShop();

      // The business supplied the shop Rs. 20,000 of goods...
      await fixture.postInvoice(
        number: 'SINV-2026-00001',
        netTotal: Money.fromMajor(20000),
        shopId: shopId,
        agentId: agentAId,
      );
      // ...and the shop sold Rs. 8,000 of them to end customers.
      await fixture.postInvoice(
        number: 'RS-2026-00001',
        netTotal: Money.fromMajor(8000),
        shopId: shopId,
        kind: InvoiceKind.retailSale,
      );

      final shop = (await list()).single;
      expect(shop.billedTotal, Money.fromMajor(20000));
      expect(shop.retailSalesTotal, Money.fromMajor(8000));
      // The retail sale is not a receivable from the shop: the shop already
      // owes for the goods it was supplied.
      expect(shop.outstandingBalance, Money.fromMajor(20000));
    });
  });

  group('archiving', () {
    test('archives a shop with no stock', () async {
      final id = await addShop();
      await fixture.shops.archive(fixture.admin, id);

      expect(await list(), isEmpty);
      final all = await list(const ShopFilter(includeArchived: true));
      expect(all.single.status, EntityStatus.archived);

      final location = await fixture.locations.forShop(id);
      expect(location!.isActive, isFalse);
    });

    test('refuses to archive a shop still holding stock', () async {
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
      final shopId = await addShop();
      final location = await fixture.locations.forShop(shopId);
      await fixture.giveStock(
        locationId: location!.id,
        productId: productId,
        quantity: 20,
      );

      await expectLater(
        fixture.shops.archive(fixture.admin, shopId),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'shop.no_stock_when_archiving',
          ),
        ),
      );
    });

    test('restores an archived shop and its location', () async {
      final id = await addShop();
      await fixture.shops.archive(fixture.admin, id);
      await fixture.shops.restore(fixture.admin, id);

      expect((await list()).single.status, EntityStatus.active);
      final location = await fixture.locations.forShop(id);
      expect(location!.isActive, isTrue);
    });
  });

  group('updating', () {
    test('renames the shop and its stock location together', () async {
      final id = await addShop(name: 'Shop A');
      await fixture.shops.update(
        fixture.admin,
        ShopDraft(id: id, name: 'Shop Alpha', assignedAgentId: agentAId),
      );

      expect((await list()).single.name, 'Shop Alpha');
      final location = await fixture.locations.forShop(id);
      expect(location!.name, 'Shop Alpha (Shop)');
    });
  });

  group('stock held', () {
    test('reports the units and value sitting in the shop', () async {
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
      final shopId = await addShop();
      final location = await fixture.locations.forShop(shopId);
      await fixture.giveStock(
        locationId: location!.id,
        productId: productId,
        quantity: 20,
        unitCost: Money.fromMajor(2000),
      );

      final shop = (await list()).single;
      expect(shop.stockUnits, 20);
      expect(shop.stockValueAtCost, Money.fromMajor(40000));
    });
  });
}
