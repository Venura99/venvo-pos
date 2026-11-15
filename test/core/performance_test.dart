import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/agents/domain/agent_models.dart';
import 'package:venvo_core/features/categories/domain/category_models.dart';
import 'package:venvo_core/features/inventory/domain/stock_models.dart';
import 'package:venvo_core/features/invoices/domain/invoice_models.dart';
import 'package:venvo_core/features/payments/domain/payment_models.dart';
import 'package:venvo_core/features/products/domain/product_models.dart';
import 'package:venvo_core/features/reports/domain/report_catalogue.dart';
import 'package:venvo_core/features/reports/domain/report_models.dart';
import 'package:venvo_core/features/shops/domain/shop_models.dart';

import '../helpers/master_data_fixtures.dart';

/// Performance, checked two ways.
///
/// **By query plan.** SQLite is asked how it would run each hot query, and the
/// test fails if it says it would scan a table that grows with the business.
/// This is deterministic: it does not depend on how fast the machine running
/// it happens to be, and it fails the moment somebody adds an access pattern
/// no index covers — which is when it is cheap to fix, rather than a year in
/// when the table has a million rows.
///
/// **By doing it at size.** A few thousand rows are posted through the real
/// services, and the figures every screen leads with are read back. The time
/// bounds are deliberately generous: they are there to catch an accidental
/// O(n^2), not to measure a machine.
void main() {
  late MasterDataFixture fixture;

  /// Tables that grow with the business. A full scan of one of these is a
  /// problem; a scan of a small lookup table such as `accounts` or
  /// `inventory_locations` is often the fastest thing SQLite can do.
  const growingTables = <String>[
    'invoices',
    'invoice_items',
    'payments',
    'payment_allocations',
    'stock_transactions',
    'stock_transaction_items',
    'stock_ledger_entries',
    'stock_balances',
    'financial_ledger_entries',
    'audit_logs',
    'returns',
    'return_items',
    'credit_notes',
    'credit_note_applications',
    'expenses',
    'petty_cash_entries',
    'salaries',
    'salary_payments',
    'discounts',
  ];

  setUp(() async {
    fixture = await MasterDataFixture.create();
  });

  tearDown(() => fixture.dispose());

  /// Asks SQLite how it would run [sql] and returns the plan lines.
  Future<List<String>> plan(
    String sql, [
    List<Variable<Object>> args = const [],
  ]) async {
    final rows = await fixture.db
        .customSelect('EXPLAIN QUERY PLAN $sql', variables: args)
        .get();
    return rows
        .map((row) => row.read<String>('detail'))
        .toList(growable: false);
  }

  /// Fails when the plan reads a growing table without an index, or sorts one
  /// in a temporary B-tree.
  ///
  /// SQLite words an index-ordered traversal as `SCAN t USING INDEX idx`,
  /// which is exactly what is wanted and must not be mistaken for a full
  /// scan. The two things worth failing on are a bare `SCAN t` and a
  /// `USE TEMP B-TREE FOR ORDER BY`, which is SQLite saying it will sort the
  /// whole result rather than walk an index in order.
  Future<void> expectIndexedAccess(
    String description,
    String sql, [
    List<Variable<Object>> args = const [],
  ]) async {
    final lines = await plan(sql, args);

    for (final table in growingTables) {
      final unindexed = lines.where(
        (line) => line.startsWith('SCAN $table') && !line.contains('USING'),
      );
      expect(
        unindexed,
        isEmpty,
        reason:
            '$description reads "$table" without an index.\n'
            '${lines.join('\n')}',
      );
    }

    expect(
      lines.where((line) => line.contains('TEMP B-TREE FOR ORDER BY')),
      isEmpty,
      reason:
          '$description sorts in a temporary B-tree rather than walking an '
          'index in order.\n${lines.join('\n')}',
    );
  }

  group('the hot queries use an index', () {
    test('a stock balance read for one product at one location', () async {
      await expectIndexedAccess(
        'reading a stock balance',
        'SELECT quantity FROM stock_balances '
            'WHERE location_id = ? AND product_id = ?',
        [const Variable<int>(1), const Variable<int>(1)],
      );
    });

    test('replaying the ledger for one product at one location', () async {
      await expectIndexedAccess(
        'replaying a balance from the ledger',
        'SELECT SUM(quantity_delta) FROM stock_ledger_entries '
            'WHERE location_id = ? AND product_id = ?',
        [const Variable<int>(1), const Variable<int>(1)],
      );
    });

    test('the movement history for one product over a period', () async {
      await expectIndexedAccess(
        'the stock movement history',
        'SELECT * FROM stock_ledger_entries '
            'WHERE product_id = ? AND occurred_at >= ? '
            'ORDER BY occurred_at DESC',
        [const Variable<int>(1), const Variable<String>('2026-01-01')],
      );
    });

    test('settlement for one invoice', () async {
      await expectIndexedAccess(
        'summing what is applied to an invoice',
        'SELECT SUM(pa.amount_cents) FROM payment_allocations pa '
            'JOIN payments p ON p.id = pa.payment_id '
            'WHERE pa.invoice_id = ? AND p.status = ?',
        [const Variable<int>(1), const Variable<String>('cleared')],
      );
    });

    test('credit applied to one invoice', () async {
      await expectIndexedAccess(
        'summing credit applied to an invoice',
        'SELECT SUM(cna.amount_cents) FROM credit_note_applications cna '
            'JOIN credit_notes cn ON cn.id = cna.credit_note_id '
            'WHERE cna.invoice_id = ? AND cn.status = ?',
        [const Variable<int>(1), const Variable<String>('posted')],
      );
    });

    test('an invoice looked up by its number', () async {
      await expectIndexedAccess(
        'finding an invoice by number',
        'SELECT * FROM invoices WHERE invoice_number = ?',
        [const Variable<String>('SINV-2026-00001')],
      );
    });

    test('the invoice register for one party', () async {
      await expectIndexedAccess(
        'the invoice register for a shop',
        'SELECT * FROM invoices WHERE shop_id = ? AND status = ? '
            'ORDER BY invoice_date DESC',
        [const Variable<int>(1), const Variable<String>('posted')],
      );
    });

    test('the journal for one account over a period', () async {
      await expectIndexedAccess(
        'the financial ledger for an account',
        'SELECT * FROM financial_ledger_entries '
            'WHERE account_id = ? AND entry_date >= ?',
        [const Variable<int>(1), const Variable<String>('2026-01-01')],
      );
    });

    test('the journal batch behind one record', () async {
      await expectIndexedAccess(
        'tracing a journal batch to its source',
        'SELECT * FROM financial_ledger_entries '
            'WHERE source_kind = ? AND source_id = ?',
        [const Variable<String>('invoice'), const Variable<int>(1)],
      );
    });

    test('a document number sequence', () async {
      await expectIndexedAccess(
        'allocating a document number',
        'SELECT * FROM document_sequences '
            'WHERE sequence_key = ? AND period_key = ?',
        [const Variable<String>('SINV'), const Variable<String>('2026')],
      );
    });

    test('the audit log, newest first', () async {
      await expectIndexedAccess(
        'the audit log',
        'SELECT * FROM audit_logs ORDER BY occurred_at DESC LIMIT 200',
      );
    });

    test('a return traced to its invoice', () async {
      await expectIndexedAccess(
        'returns against an invoice',
        'SELECT * FROM returns WHERE origin_invoice_id = ?',
        [const Variable<int>(1)],
      );
    });

    test('the petty cash book over a period', () async {
      await expectIndexedAccess(
        'the petty cash book',
        'SELECT * FROM petty_cash_entries WHERE entry_date >= ? '
            'ORDER BY entry_date DESC',
        [const Variable<String>('2026-01-01')],
      );
    });

    test('salaries for one employee', () async {
      await expectIndexedAccess(
        'salaries for an employee',
        'SELECT * FROM salaries WHERE employee_id = ?',
        [const Variable<int>(1)],
      );
    });

    test('expenses over a period', () async {
      await expectIndexedAccess(
        'the expense register',
        'SELECT * FROM expenses WHERE expense_date >= ? AND status = ?',
        [
          const Variable<String>('2026-01-01'),
          const Variable<String>('posted'),
        ],
      );
    });

    test('discounts over a period', () async {
      await expectIndexedAccess(
        'the discount report',
        'SELECT * FROM discounts WHERE granted_at >= ?',
        [const Variable<String>('2026-01-01')],
      );
    });
  });

  group('the schema keeps the indexes it needs', () {
    test('every index the hot paths rely on is present', () async {
      final rows = await fixture.db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' "
            "AND name LIKE 'idx_%'",
          )
          .get();
      final names = rows.map((row) => row.read<String>('name')).toSet();

      // Named rather than counted: a count tells you something changed, a
      // name tells you what, and these are the ones the queries above need.
      expect(
        names,
        containsAll(<String>[
          'idx_ledger_loc_product',
          'idx_ledger_occurred',
          'idx_ledger_product',
          'idx_balance_product',
          'idx_alloc_invoice',
          'idx_alloc_payment',
          'idx_cn_app_invoice',
          'idx_invoices_number',
          'idx_invoices_date',
          'idx_fin_ledger_account_date',
          'idx_fin_ledger_source',
          'idx_fin_ledger_batch',
          'idx_audit_at',
          'idx_returns_origin_invoice',
          'idx_petty_cash_date',
          'idx_salaries_employee',
          'idx_expenses_date',
          'idx_discounts_granted',
        ]),
      );
    });

    test('the balance cache is unique per location and product', () async {
      // Not a performance matter alone: two rows for the same pair would mean
      // two answers to "how much is there".
      // Declared as a unique key on the table, which SQLite implements as an
      // auto-index rather than a named one, so the constraint is read off the
      // table definition itself.
      final row = await fixture.db
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE type = 'table' "
            "AND name = 'stock_balances'",
          )
          .getSingle();
      final definition = row.read<String>('sql').toLowerCase();

      expect(definition, contains('unique'));
      expect(
        definition.replaceAll(RegExp(r'\s+'), ' '),
        contains('unique ("location_id", "product_id")'),
      );
    });
  });

  group('at a few thousand rows', () {
    late int chargerId;
    late int warehouseId;
    late int agentId;
    late int agentLocationId;
    late int shopId;
    late int shopLocationId;

    setUp(() async {
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
      shopLocationId = (await fixture.locations.forShop(shopId))!.id;

      await fixture.postOpeningStock(
        locationId: warehouseId,
        productId: chargerId,
        quantity: 100000,
        unitCost: Money.fromMajor(2000),
      );
    });

    test('the ledger stays consistent and the reads stay quick', () async {
      // 200 transfers and 200 invoices: 600-odd stock ledger rows, 200
      // invoices with their lines, discounts and journal batches. Enough that
      // an accidental full scan or an N+1 shows up as time.
      const cycles = 200;
      for (var cycle = 0; cycle < cycles; cycle++) {
        await fixture.stockLedger.postMovement(
          fixture.admin,
          StockMovementRequest(
            documentType: StockDocumentType.warehouseToAgent,
            sourceLocationId: warehouseId,
            destinationLocationId: agentLocationId,
            lines: [StockMovementLine(productId: chargerId, quantity: 20)],
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
            lines: [StockMovementLine(productId: chargerId, quantity: 10)],
          ),
        );
        await fixture.invoices.postInvoice(
          fixture.admin,
          InvoiceRequest(
            kind: InvoiceKind.shopInvoice,
            shopId: shopId,
            agentId: agentId,
            lines: [
              InvoiceLineRequest(
                productId: chargerId,
                quantity: 5,
                unitPrice: Money.fromMajor(3000),
              ),
            ],
          ),
        );
      }

      // The invariants still hold at size. This is the assertion that
      // matters: a fast system with a wrong balance is worthless.
      expect(await fixture.stockLedger.findUnbalancedProducts(), isEmpty);
      expect(await fixture.stockLedger.findBalanceDiscrepancies(), isEmpty);
      expect(await fixture.finance.findUnbalancedBatches(), isEmpty);

      final trial = await fixture.finance.trialBalance();
      expect(trial.totalDebits, trial.totalCredits);

      // And the figures a screen leads with come back promptly.
      final watch = Stopwatch()..start();

      final dashboard = await fixture.dashboard.load();
      final dashboardMs = watch.elapsedMilliseconds;
      expect(dashboard.monthSales, Money.fromMajor(cycles * 15000));

      watch.reset();
      final balance = await fixture.stockLedger.balanceOf(
        locationId: shopLocationId,
        productId: chargerId,
      );
      final balanceMs = watch.elapsedMilliseconds;
      // Every cycle moved 10 units into the shop. The invoices bill without
      // moving goods — a transfer is not a sale, and an invoice with no stock
      // linkage charges for a delivery that already happened — so none of
      // them takes anything back out.
      expect(balance, cycles * 10);

      watch.reset();
      final report = await fixture.reports.run(
        reportById(ReportIds.productSales)!,
        const ReportFilter(),
      );
      final reportMs = watch.elapsedMilliseconds;
      expect(report.rows, hasLength(1));

      watch.reset();
      final profit = await fixture.finance.profitAndLoss();
      final profitMs = watch.elapsedMilliseconds;
      expect(profit.revenue, Money.fromMajor(cycles * 15000));

      // Generous on purpose. These bounds exist to catch an accidental
      // O(n^2), not to benchmark a machine: the dashboard is eighteen
      // aggregate queries over every table in the schema.
      expect(
        dashboardMs,
        lessThan(5000),
        reason: 'the dashboard took ${dashboardMs}ms',
      );
      expect(
        balanceMs,
        lessThan(500),
        reason: 'a single balance read took ${balanceMs}ms',
      );
      expect(
        reportMs,
        lessThan(5000),
        reason: 'the product sales report took ${reportMs}ms',
      );
      expect(
        profitMs,
        lessThan(5000),
        reason: 'the profit and loss took ${profitMs}ms',
      );
    });

    test('a payment allocated across many invoices stays exact', () async {
      // Settlement is the arithmetic most likely to drift at size: many
      // allocations against many invoices, each read back through the same
      // query the screens use.
      final invoices = <int>[];
      for (var index = 0; index < 60; index++) {
        final invoice = await fixture.invoices.postInvoice(
          fixture.admin,
          InvoiceRequest(
            kind: InvoiceKind.shopInvoice,
            shopId: shopId,
            agentId: agentId,
            lines: [
              InvoiceLineRequest(
                productId: chargerId,
                quantity: 1,
                unitPrice: Money.fromMajor(1000),
              ),
            ],
          ),
        );
        invoices.add(invoice.invoiceId);
      }

      await fixture.payments.recordPayment(
        fixture.admin,
        PaymentRequest(
          direction: PaymentDirection.inbound,
          method: PaymentMethod.cash,
          amount: Money.fromMajor(60000),
          shopId: shopId,
          allocations: [
            for (final invoiceId in invoices)
              PaymentAllocationRequest(
                invoiceId: invoiceId,
                amount: Money.fromMajor(1000),
              ),
          ],
        ),
      );

      for (final invoiceId in invoices) {
        expect(
          await fixture.payments.outstandingOf(invoiceId),
          Money.zero,
          reason: 'invoice $invoiceId was not fully settled',
        );
      }

      final shops = await fixture.shops.watchShops(const ShopFilter()).first;
      expect(shops.single.outstandingBalance, Money.zero);
      expect(await fixture.finance.findUnbalancedBatches(), isEmpty);
    });
  });
}
