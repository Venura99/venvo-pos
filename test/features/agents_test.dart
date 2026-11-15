import 'package:flutter_test/flutter_test.dart';
import 'package:venvo_core/core/database/app_database.dart';
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

  setUp(() async {
    fixture = await MasterDataFixture.create();
  });

  tearDown(() => fixture.dispose());

  Future<int> addAgent({
    String name = 'Agent A',
    String? code,
    Money openingBalance = Money.zero,
    int? commissionBps,
  }) {
    return fixture.agents.create(
      fixture.admin,
      AgentDraft(
        name: name,
        code: code,
        openingBalance: openingBalance,
        commissionBps: commissionBps,
      ),
    );
  }

  Future<List<AgentListItem>> list([
    AgentFilter filter = const AgentFilter(),
  ]) => fixture.agents.watchAgents(filter).first;

  group('creating', () {
    test('creates an agent with an allocated code', () async {
      final id = await addAgent();
      final agents = await list();

      expect(agents.length, 1);
      expect(agents.single.id, id);
      expect(agents.single.name, 'Agent A');
      expect(agents.single.code, 'AG-00001');
      expect(agents.single.status, EntityStatus.active);
    });

    test('allocates sequential codes', () async {
      await addAgent(name: 'Agent A');
      await addAgent(name: 'Agent B');
      await addAgent(name: 'Agent C');

      final agents = await list();
      expect(agents.map((a) => a.code), ['AG-00001', 'AG-00002', 'AG-00003']);
    });

    test('accepts a code the user supplies, upper-cased', () async {
      await addAgent(code: 'north-1');
      expect((await list()).single.code, 'NORTH-1');
    });

    test('refuses a duplicate code', () async {
      await addAgent(name: 'Agent A', code: 'NORTH');
      await expectLater(
        addAgent(name: 'Agent B', code: 'north'),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'agent.code_unique',
          ),
        ),
      );
    });

    test('creates the agent stock location in the same operation', () async {
      final id = await addAgent(name: 'Agent A');
      final location = await fixture.locations.forAgent(id);

      expect(location, isNotNull);
      expect(location!.kind, LocationKind.agent);
      expect(location.code, 'LOC-AG-00001');
      expect(location.name, 'Agent A (Agent)');
      expect(location.agentId, id);
      expect(location.isActive, isTrue);
    });

    test('rejects a negative opening balance', () async {
      await expectLater(
        addAgent(openingBalance: const Money(-5000)),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('rejects a commission above 100%', () async {
      await expectLater(
        addAgent(commissionBps: 10001),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('requires the manage-agents permission', () async {
      final viewer = await fixture.createViewer();
      await expectLater(
        fixture.agents.create(viewer, const AgentDraft(name: 'Nope')),
        throwsA(isA<PermissionFailure>()),
      );
      expect(await list(), isEmpty);
    });
  });

  group('atomicity', () {
    test('a failure creating the location leaves no agent behind', () async {
      // Occupy the location code the next agent would be given, so inserting
      // its location violates the unique index. The agent insert has already
      // happened at that point, which is exactly the half-applied state the
      // transaction has to prevent.
      await fixture.db
          .into(fixture.db.inventoryLocations)
          .insert(
            InventoryLocationsCompanion.insert(
              code: 'LOC-AG-00001',
              name: 'Squatter',
              kind: LocationKind.warehouse,
              createdAt: fixture.harness.clock.nowUtc(),
            ),
          );

      await expectLater(addAgent(name: 'Agent A'), throwsA(anything));

      // Neither side of the operation survived.
      final agents = await list(
        const AgentFilter(includeInactive: true, includeArchived: true),
      );
      expect(agents, isEmpty);

      final rawAgents = await fixture.db.select(fixture.db.agents).get();
      expect(rawAgents, isEmpty);

      // And the sequence was not consumed, so the next attempt gets the same
      // code once the clash is cleared.
      await (fixture.db.delete(
        fixture.db.inventoryLocations,
      )..where((l) => l.code.equals('LOC-AG-00001'))).go();
      await addAgent(name: 'Agent A');
      expect((await list()).single.code, 'AG-00001');
    });
  });

  group('outstanding balance', () {
    test('is the opening balance when nothing has been invoiced', () async {
      await addAgent(openingBalance: Money.fromMajor(7500));
      final agent = (await list()).single;

      expect(agent.openingBalance, Money.fromMajor(7500));
      expect(agent.billedTotal, Money.zero);
      expect(agent.outstandingBalance, Money.fromMajor(7500));
      expect(agent.owesMoney, isTrue);
    });

    test('adds posted invoices', () async {
      final agentId = await addAgent();
      await fixture.postInvoice(
        number: 'AINV-2026-00001',
        netTotal: Money.fromMajor(150000),
        agentId: agentId,
        kind: InvoiceKind.agentInvoice,
        partyType: PartyType.agent,
      );

      final agent = (await list()).single;
      expect(agent.billedTotal, Money.fromMajor(150000));
      expect(agent.outstandingBalance, Money.fromMajor(150000));
    });

    test('a cleared payment reduces the balance', () async {
      final agentId = await addAgent();
      final invoiceId = await fixture.postInvoice(
        number: 'AINV-2026-00001',
        netTotal: Money.fromMajor(150000),
        agentId: agentId,
        kind: InvoiceKind.agentInvoice,
        partyType: PartyType.agent,
      );
      await fixture.recordPayment(
        number: 'PAY-2026-00001',
        amount: Money.fromMajor(50000),
        method: PaymentMethod.cash,
        status: PaymentStatus.cleared,
        agentId: agentId,
        allocateToInvoiceId: invoiceId,
      );

      final agent = (await list()).single;
      expect(agent.settledTotal, Money.fromMajor(50000));
      expect(agent.outstandingBalance, Money.fromMajor(100000));
    });

    test('a pending cheque does not reduce the balance', () async {
      final agentId = await addAgent();
      final invoiceId = await fixture.postInvoice(
        number: 'AINV-2026-00001',
        netTotal: Money.fromMajor(150000),
        agentId: agentId,
        kind: InvoiceKind.agentInvoice,
        partyType: PartyType.agent,
      );
      await fixture.recordPayment(
        number: 'PAY-2026-00001',
        amount: Money.fromMajor(60000),
        method: PaymentMethod.cheque,
        status: PaymentStatus.pending,
        agentId: agentId,
        allocateToInvoiceId: invoiceId,
      );

      final agent = (await list()).single;
      // Reported in its own bucket...
      expect(agent.pendingChequeTotal, Money.fromMajor(60000));
      // ...and not treated as settlement.
      expect(agent.settledTotal, Money.zero);
      expect(agent.outstandingBalance, Money.fromMajor(150000));
    });

    test('an agent who overpaid is reported as in credit', () async {
      final agentId = await addAgent();
      final invoiceId = await fixture.postInvoice(
        number: 'AINV-2026-00001',
        netTotal: Money.fromMajor(10000),
        agentId: agentId,
        kind: InvoiceKind.agentInvoice,
        partyType: PartyType.agent,
      );
      await fixture.recordPayment(
        number: 'PAY-2026-00001',
        amount: Money.fromMajor(12000),
        method: PaymentMethod.cash,
        status: PaymentStatus.cleared,
        agentId: agentId,
        allocateToInvoiceId: invoiceId,
      );

      final agent = (await list()).single;
      expect(agent.isInCredit, isTrue);
      expect(agent.outstandingBalance, Money.fromMajor(-2000));
    });

    test('the owing filter keeps only agents with a balance', () async {
      await addAgent(name: 'Owes money', openingBalance: Money.fromMajor(5000));
      await addAgent(name: 'Settled up');

      final owing = await list(const AgentFilter(owingOnly: true));
      expect(owing.map((a) => a.name), ['Owes money']);
    });
  });

  group('stock held', () {
    test('reports the units and value an agent is holding', () async {
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

      final agentId = await addAgent();
      final location = await fixture.locations.forAgent(agentId);
      await fixture.giveStock(
        locationId: location!.id,
        productId: productId,
        quantity: 30,
        unitCost: Money.fromMajor(2000),
      );

      final agent = (await list()).single;
      expect(agent.stockUnits, 30);
      expect(agent.stockValueAtCost, Money.fromMajor(60000));
    });
  });

  group('updating', () {
    test('renames the agent and its stock location together', () async {
      final id = await addAgent(name: 'Agent A');
      await fixture.agents.update(
        fixture.admin,
        AgentDraft(id: id, name: 'Agent Alpha'),
      );

      final location = await fixture.locations.forAgent(id);
      expect(location!.name, 'Agent Alpha (Agent)');
      expect((await list()).single.name, 'Agent Alpha');
    });

    test('deactivating the agent deactivates its location', () async {
      final id = await addAgent();
      await fixture.agents.update(
        fixture.admin,
        AgentDraft(id: id, name: 'Agent A', status: EntityStatus.inactive),
      );

      final location = await fixture.locations.forAgent(id);
      expect(location!.isActive, isFalse);
    });

    test('keeps its own code', () async {
      final id = await addAgent(code: 'NORTH');
      await fixture.agents.update(
        fixture.admin,
        const AgentDraft(id: 1, name: 'Agent A', code: 'NORTH'),
      );
      expect(id, 1);
      expect((await list()).single.code, 'NORTH');
    });
  });

  group('archiving', () {
    test('archives an agent with nothing outstanding', () async {
      final id = await addAgent();
      await fixture.agents.archive(fixture.admin, id);

      expect(await list(), isEmpty);
      final all = await list(const AgentFilter(includeArchived: true));
      expect(all.single.status, EntityStatus.archived);

      final location = await fixture.locations.forAgent(id);
      expect(location!.isActive, isFalse);
    });

    test('refuses to archive an agent still holding stock', () async {
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
      final id = await addAgent();
      final location = await fixture.locations.forAgent(id);
      await fixture.giveStock(
        locationId: location!.id,
        productId: productId,
        quantity: 12,
      );

      await expectLater(
        fixture.agents.archive(fixture.admin, id),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'agent.no_stock_when_archiving',
          ),
        ),
      );
    });

    test('refuses to archive an agent with active shops', () async {
      final agentId = await addAgent();
      await fixture.shops.create(
        fixture.admin,
        ShopDraft(name: 'Shop A', assignedAgentId: agentId),
      );

      await expectLater(
        fixture.agents.archive(fixture.admin, agentId),
        throwsA(
          isA<BusinessRuleFailure>()
              .having(
                (failure) => failure.rule,
                'rule',
                'agent.no_active_shops_when_archiving',
              )
              .having(
                (failure) => failure.details,
                'details',
                contains('Shop A'),
              ),
        ),
      );
    });

    test('allows archiving once the shops are reassigned', () async {
      final agentA = await addAgent(name: 'Agent A');
      final agentB = await addAgent(name: 'Agent B');
      final shopId = await fixture.shops.create(
        fixture.admin,
        ShopDraft(name: 'Shop A', assignedAgentId: agentA),
      );

      await fixture.shops.reassignAgent(
        fixture.admin,
        shopId: shopId,
        agentId: agentB,
      );
      await fixture.agents.archive(fixture.admin, agentA);

      final archived = await list(const AgentFilter(includeArchived: true));
      expect(
        archived.firstWhere((a) => a.id == agentA).status,
        EntityStatus.archived,
      );
    });

    test('an agent still owing money can be archived', () async {
      // A defaulting agent has to be removable from daily operation; the debt
      // stays on the books either way.
      final id = await addAgent(openingBalance: Money.fromMajor(25000));
      await fixture.agents.archive(fixture.admin, id);

      final all = await list(const AgentFilter(includeArchived: true));
      expect(all.single.status, EntityStatus.archived);
      expect(all.single.outstandingBalance, Money.fromMajor(25000));
    });

    test('restores an archived agent and its location', () async {
      final id = await addAgent();
      await fixture.agents.archive(fixture.admin, id);
      await fixture.agents.restore(fixture.admin, id);

      expect((await list()).single.status, EntityStatus.active);
      final location = await fixture.locations.forAgent(id);
      expect(location!.isActive, isTrue);
    });
  });

  group('searching', () {
    test('matches name, code, phone and NIC', () async {
      await fixture.agents.create(
        fixture.admin,
        const AgentDraft(
          name: 'Sunil Distributors',
          code: 'NORTH',
          phone: '0771234567',
          nic: '901234567V',
        ),
      );
      await addAgent(name: 'Other Agent');

      Future<int> matches(String search) async =>
          (await list(AgentFilter(search: search))).length;

      expect(await matches('sunil'), 1);
      expect(await matches('north'), 1);
      expect(await matches('077123'), 1);
      expect(await matches('901234'), 1);
      expect(await matches('nothing'), 0);
    });
  });

  group('selectable agents', () {
    test('offers only active agents', () async {
      final activeId = await addAgent(name: 'Active');
      final archivedId = await addAgent(name: 'Archived');
      await fixture.agents.archive(fixture.admin, archivedId);

      final selectable = await fixture.agents.selectableAgents();
      expect(selectable.map((a) => a.id), [activeId]);
    });
  });

  group('audit trail', () {
    test('records creation together with the location it made', () async {
      await addAgent();
      final entries = await fixture.auditEntries();
      final created = entries.firstWhere(
        (entry) =>
            entry.entityKind == EntityKind.agent &&
            entry.action == AuditAction.create,
      );
      expect(created.summary, contains('Agent A'));
      expect(created.summary, contains('stock location'));
    });
  });
}
