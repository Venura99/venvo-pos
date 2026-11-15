import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/enums/app_enums.dart';
import '../../../core/errors/failures.dart';
import '../../../core/services/clock.dart';
import '../../../core/utils/money.dart';
import '../../finance/data/financial_ledger_service.dart';
import '../domain/report_catalogue.dart';
import '../domain/report_models.dart';

/// Runs the eighteen reports.
///
/// Every figure here is computed the same way as the screen it corresponds to.
/// That is the whole point of putting the reports in one place: a "collections"
/// total that counted pending cheques, or an "outstanding" figure that ignored
/// credit notes, would contradict the register it was printed beside - and the
/// report is what gets taken to a meeting.
///
/// The definitions that recur:
///
/// * **Posted only.** A cancelled invoice, expense or salary is never counted.
/// * **Cleared money only.** A pending cheque is reported in its own column
///   and settles nothing.
/// * **Credit notes count.** A posted credit note reduces what is owed.
/// * **Retail is separate.** What a shop sold over its counter is never added
///   to the wholesale supply that stocked it.
class ReportRepository {
  const ReportRepository({
    required AppDatabase database,
    required Clock clock,
    required FinancialLedgerService finance,
  }) : _db = database,
       _clock = clock,
       _finance = finance;

  final AppDatabase _db;
  final Clock _clock;
  final FinancialLedgerService _finance;

  /// Runs [definition] over [filter].
  Future<ReportResult> run(
    ReportDefinition definition,
    ReportFilter filter,
  ) async {
    return switch (definition.id) {
      ReportIds.dailySales => _dailySales(definition, filter),
      ReportIds.monthlySales => _monthlySales(definition, filter),
      ReportIds.agentSales => _agentSales(definition, filter),
      ReportIds.shopSales => _shopSales(definition, filter),
      ReportIds.productSales => _productSales(definition, filter),
      ReportIds.warehouseStock => _warehouseStock(definition, filter),
      ReportIds.agentStock => _partyStock(definition, filter, agents: true),
      ReportIds.shopStock => _partyStock(definition, filter, agents: false),
      ReportIds.stockMovement => _stockMovement(definition, filter),
      ReportIds.stockValuation => _stockValuation(definition, filter),
      ReportIds.collections => _collections(definition, filter),
      ReportIds.outstanding => _outstanding(definition, filter),
      ReportIds.discounts => _discounts(definition, filter),
      ReportIds.returns => _returns(definition, filter),
      ReportIds.expenses => _expenses(definition, filter),
      ReportIds.pettyCash => _pettyCash(definition, filter),
      ReportIds.salaries => _salaries(definition, filter),
      ReportIds.profitAndLoss => _profitAndLoss(definition, filter),
      // A report id with no query behind it is a wiring mistake, not
      // something a user can cause.
      _ => throw NotFoundFailure(
        'There is no report called "${definition.id}".',
      ),
    };
  }

  // --- Sales ---------------------------------------------------------------

  /// Wholesale invoices grouped by day.
  ///
  /// Retail sales are excluded: they are what a shop sold to its own
  /// customers, and adding them to the supply that stocked the shop would
  /// count the same goods twice.
  Future<ReportResult> _dailySales(
    ReportDefinition definition,
    ReportFilter filter,
  ) async {
    final rows = await _db
        .customSelect(
          '''
      SELECT DATE(invoice_date) AS bucket,
             COUNT(*) AS invoices,
             COALESCE(SUM(gross_total_cents), 0) AS gross,
             COALESCE(SUM(item_discount_total_cents
                          + invoice_discount_cents), 0) AS discount,
             COALESCE(SUM(net_total_cents), 0) AS net,
             COALESCE(SUM(cost_total_cents), 0) AS cost
      FROM invoices
      WHERE status = ? AND kind IN (?, ?)
        ${_periodClause('invoice_date', filter)}
      GROUP BY DATE(invoice_date)
      ORDER BY bucket DESC
      LIMIT ?
      ''',
          variables: [
            Variable<String>(InvoiceStatus.posted.name),
            Variable<String>(InvoiceKind.agentInvoice.name),
            Variable<String>(InvoiceKind.shopInvoice.name),
            ..._periodVariables(filter),
            Variable<int>(filter.limit),
          ],
          readsFrom: {_db.invoices},
        )
        .get();

    return _salesResult(
      definition,
      filter,
      rows,
      bucketLabel: 'Day',
      bucketValue: (row) =>
          ReportValue.date(DateTime.parse(row.read<String>('bucket'))),
    );
  }

  Future<ReportResult> _monthlySales(
    ReportDefinition definition,
    ReportFilter filter,
  ) async {
    final rows = await _db
        .customSelect(
          '''
      SELECT STRFTIME('%Y-%m', invoice_date) AS bucket,
             COUNT(*) AS invoices,
             COALESCE(SUM(gross_total_cents), 0) AS gross,
             COALESCE(SUM(item_discount_total_cents
                          + invoice_discount_cents), 0) AS discount,
             COALESCE(SUM(net_total_cents), 0) AS net,
             COALESCE(SUM(cost_total_cents), 0) AS cost
      FROM invoices
      WHERE status = ? AND kind IN (?, ?)
        ${_periodClause('invoice_date', filter)}
      GROUP BY STRFTIME('%Y-%m', invoice_date)
      ORDER BY bucket DESC
      LIMIT ?
      ''',
          variables: [
            Variable<String>(InvoiceStatus.posted.name),
            Variable<String>(InvoiceKind.agentInvoice.name),
            Variable<String>(InvoiceKind.shopInvoice.name),
            ..._periodVariables(filter),
            Variable<int>(filter.limit),
          ],
          readsFrom: {_db.invoices},
        )
        .get();

    return _salesResult(
      definition,
      filter,
      rows,
      bucketLabel: 'Month',
      bucketValue: (row) =>
          ReportValue.month(DateTime.parse('${row.read<String>('bucket')}-01')),
    );
  }

  /// Shared shape for the two time-bucketed sales reports.
  ReportResult _salesResult(
    ReportDefinition definition,
    ReportFilter filter,
    List<QueryRow> rows, {
    required String bucketLabel,
    required ReportValue Function(QueryRow row) bucketValue,
  }) {
    const columns = <ReportColumn>[];
    final allColumns = [
      ReportColumn(label: bucketLabel, kind: ReportValueKind.date, width: 130),
      const ReportColumn.integer('Invoices', width: 90),
      const ReportColumn.money('Gross'),
      const ReportColumn.money('Discount'),
      const ReportColumn.money('Net'),
      const ReportColumn.money('Cost'),
      const ReportColumn.money('Gross profit'),
      const ReportColumn(
        label: 'Margin',
        kind: ReportValueKind.percent,
        width: 90,
      ),
      ...columns,
    ];

    final reportRows = <ReportRow>[];
    for (final row in rows) {
      final net = Money(row.read<int>('net'));
      final cost = Money(row.read<int>('cost'));
      final profit = net - cost;
      reportRows.add(
        ReportRow([
          bucketValue(row),
          ReportValue.integer(row.read<int>('invoices')),
          ReportValue.money(Money(row.read<int>('gross'))),
          ReportValue.money(Money(row.read<int>('discount'))),
          ReportValue.money(net),
          ReportValue.money(cost),
          ReportValue.money(profit),
          ReportValue.percent(net.isZero ? 0 : profit.bpsOf(net)),
        ]),
      );
    }

    final totals = ReportResult.sumColumns(allColumns, reportRows);
    final totalNet = totals[4].money ?? Money.zero;
    final totalProfit = totals[6].money ?? Money.zero;
    totals[7] = ReportValue.percent(
      totalNet.isZero ? 0 : totalProfit.bpsOf(totalNet),
    );

    return ReportResult(
      title: definition.title,
      columns: allColumns,
      rows: reportRows,
      totals: totals,
      generatedAt: _clock.nowUtc(),
      filter: filter,
      notes: const [
        ReportNote(
          'Wholesale invoices to agents and shops. What a shop sold over its '
          'own counter is reported separately, so the same goods are never '
          'counted as revenue twice.',
        ),
        ReportNote('Cancelled invoices are excluded.'),
      ],
    );
  }

  Future<ReportResult> _agentSales(
    ReportDefinition definition,
    ReportFilter filter,
  ) async {
    final rows = await _db
        .customSelect(
          '''
      SELECT a.id, a.code, a.name,
             COUNT(i.id) AS invoices,
             COALESCE(SUM(i.net_total_cents), 0) AS net,
             COALESCE(SUM(i.cost_total_cents), 0) AS cost,
             COALESCE(SUM(i.item_discount_total_cents
                          + i.invoice_discount_cents), 0) AS discount
      FROM agents a
      LEFT JOIN invoices i ON i.agent_id = a.id
        AND i.status = ? AND i.party_type = ?
        ${_periodClause('i.invoice_date', filter)}
      WHERE (? IS NULL OR a.id = ?)
      GROUP BY a.id
      HAVING invoices > 0
      ORDER BY net DESC
      LIMIT ?
      ''',
          variables: [
            Variable<String>(InvoiceStatus.posted.name),
            Variable<String>(PartyType.agent.name),
            ..._periodVariables(filter),
            Variable<int>(filter.agentId),
            Variable<int>(filter.agentId),
            Variable<int>(filter.limit),
          ],
          readsFrom: {_db.agents, _db.invoices},
        )
        .get();

    return _partySalesResult(
      definition,
      filter,
      rows,
      partyLabel: 'Agent',
      outstanding: await _outstandingByParty(agents: true),
    );
  }

  Future<ReportResult> _shopSales(
    ReportDefinition definition,
    ReportFilter filter,
  ) async {
    final rows = await _db
        .customSelect(
          '''
      SELECT s.id, s.code, s.name,
             COUNT(i.id) AS invoices,
             COALESCE(SUM(i.net_total_cents), 0) AS net,
             COALESCE(SUM(i.cost_total_cents), 0) AS cost,
             COALESCE(SUM(i.item_discount_total_cents
                          + i.invoice_discount_cents), 0) AS discount
      FROM shops s
      LEFT JOIN invoices i ON i.shop_id = s.id
        AND i.status = ? AND i.party_type = ?
        ${_periodClause('i.invoice_date', filter)}
      WHERE (? IS NULL OR s.id = ?)
        AND (? IS NULL OR s.assigned_agent_id = ?)
      GROUP BY s.id
      HAVING invoices > 0
      ORDER BY net DESC
      LIMIT ?
      ''',
          variables: [
            Variable<String>(InvoiceStatus.posted.name),
            Variable<String>(PartyType.shop.name),
            ..._periodVariables(filter),
            Variable<int>(filter.shopId),
            Variable<int>(filter.shopId),
            Variable<int>(filter.agentId),
            Variable<int>(filter.agentId),
            Variable<int>(filter.limit),
          ],
          readsFrom: {_db.shops, _db.invoices},
        )
        .get();

    return _partySalesResult(
      definition,
      filter,
      rows,
      partyLabel: 'Shop',
      outstanding: await _outstandingByParty(agents: false),
    );
  }

  ReportResult _partySalesResult(
    ReportDefinition definition,
    ReportFilter filter,
    List<QueryRow> rows, {
    required String partyLabel,
    required Map<int, Money> outstanding,
  }) {
    final columns = [
      ReportColumn.text(partyLabel, flex: 3),
      const ReportColumn.text('Code', width: 100),
      const ReportColumn.integer('Invoices', width: 90),
      const ReportColumn.money('Net billed'),
      const ReportColumn.money('Discount'),
      const ReportColumn.money('Cost'),
      const ReportColumn.money('Gross profit'),
      const ReportColumn(
        label: 'Margin',
        kind: ReportValueKind.percent,
        width: 90,
      ),
      const ReportColumn.money('Outstanding now'),
    ];

    final reportRows = <ReportRow>[];
    for (final row in rows) {
      final id = row.read<int>('id');
      final net = Money(row.read<int>('net'));
      final cost = Money(row.read<int>('cost'));
      final profit = net - cost;
      reportRows.add(
        ReportRow([
          ReportValue.text(row.read<String>('name')),
          ReportValue.text(row.read<String>('code')),
          ReportValue.integer(row.read<int>('invoices')),
          ReportValue.money(net),
          ReportValue.money(Money(row.read<int>('discount'))),
          ReportValue.money(cost),
          ReportValue.money(profit),
          ReportValue.percent(net.isZero ? 0 : profit.bpsOf(net)),
          ReportValue.money(outstanding[id] ?? Money.zero),
        ], id: id),
      );
    }

    final totals = ReportResult.sumColumns(columns, reportRows);
    final totalNet = totals[3].money ?? Money.zero;
    final totalProfit = totals[6].money ?? Money.zero;
    totals[7] = ReportValue.percent(
      totalNet.isZero ? 0 : totalProfit.bpsOf(totalNet),
    );

    return ReportResult(
      title: definition.title,
      columns: columns,
      rows: reportRows,
      totals: totals,
      generatedAt: _clock.nowUtc(),
      filter: filter,
      notes: const [
        ReportNote(
          'The billed figures cover the period; "outstanding now" is the '
          'balance as it stands today, counting cleared money and posted '
          'credit notes only.',
        ),
      ],
    );
  }

  Future<ReportResult> _productSales(
    ReportDefinition definition,
    ReportFilter filter,
  ) async {
    final rows = await _db
        .customSelect(
          '''
      SELECT p.id, p.sku, p.name, c.name AS category,
             COALESCE(SUM(ii.quantity), 0) AS units,
             COALESCE(SUM(ii.net_cents), 0) AS net,
             COALESCE(SUM(ii.discount_cents), 0) AS discount,
             COALESCE(SUM(ii.unit_cost_snapshot_cents * ii.quantity), 0)
               AS cost
      FROM products p
      JOIN categories c ON c.id = p.category_id
      JOIN invoice_items ii ON ii.product_id = p.id
      JOIN invoices i ON i.id = ii.invoice_id
      WHERE i.status = ? AND i.kind IN (?, ?)
        ${_periodClause('i.invoice_date', filter)}
        AND (? IS NULL OR p.id = ?)
        AND (? IS NULL OR p.category_id = ?)
      GROUP BY p.id
      ORDER BY net DESC
      LIMIT ?
      ''',
          variables: [
            Variable<String>(InvoiceStatus.posted.name),
            Variable<String>(InvoiceKind.agentInvoice.name),
            Variable<String>(InvoiceKind.shopInvoice.name),
            ..._periodVariables(filter),
            Variable<int>(filter.productId),
            Variable<int>(filter.productId),
            Variable<int>(filter.categoryId),
            Variable<int>(filter.categoryId),
            Variable<int>(filter.limit),
          ],
          readsFrom: {
            _db.products,
            _db.categories,
            _db.invoiceItems,
            _db.invoices,
          },
        )
        .get();

    const columns = [
      ReportColumn.text('Product', flex: 4),
      ReportColumn.text('SKU', width: 120),
      ReportColumn.text('Category', flex: 2),
      ReportColumn.integer('Units sold', width: 110),
      ReportColumn.money('Net revenue'),
      ReportColumn.money('Discount'),
      ReportColumn.money('Cost'),
      ReportColumn.money('Gross profit'),
      ReportColumn(label: 'Margin', kind: ReportValueKind.percent, width: 90),
    ];

    final reportRows = <ReportRow>[];
    for (final row in rows) {
      final net = Money(row.read<int>('net'));
      final cost = Money(row.read<int>('cost'));
      final profit = net - cost;
      reportRows.add(
        ReportRow([
          ReportValue.text(row.read<String>('name')),
          ReportValue.text(row.read<String>('sku')),
          ReportValue.text(row.read<String>('category')),
          ReportValue.integer(row.read<int>('units')),
          ReportValue.money(net),
          ReportValue.money(Money(row.read<int>('discount'))),
          ReportValue.money(cost),
          ReportValue.money(profit),
          ReportValue.percent(net.isZero ? 0 : profit.bpsOf(net)),
        ], id: row.read<int>('id')),
      );
    }

    final totals = ReportResult.sumColumns(columns, reportRows);
    final totalNet = totals[4].money ?? Money.zero;
    final totalProfit = totals[7].money ?? Money.zero;
    totals[8] = ReportValue.percent(
      totalNet.isZero ? 0 : totalProfit.bpsOf(totalNet),
    );

    return ReportResult(
      title: definition.title,
      columns: columns,
      rows: reportRows,
      totals: totals,
      generatedAt: _clock.nowUtc(),
      filter: filter,
      notes: const [
        ReportNote(
          'Revenue and cost come from the invoice lines as they were billed, '
          'not from the catalogue as it stands now, so a later re-pricing '
          'cannot rewrite history.',
        ),
      ],
    );
  }

  // --- Stock ---------------------------------------------------------------

  Future<ReportResult> _warehouseStock(
    ReportDefinition definition,
    ReportFilter filter,
  ) async {
    final rows = await _db
        .customSelect(
          '''
      SELECT p.id, p.sku, p.name, c.name AS category, p.reorder_level,
             l.name AS location,
             sb.quantity, sb.average_cost_cents
      FROM stock_balances sb
      JOIN products p ON p.id = sb.product_id
      JOIN categories c ON c.id = p.category_id
      JOIN inventory_locations l ON l.id = sb.location_id
      WHERE l.kind = ?
        AND sb.quantity <> 0
        AND (? IS NULL OR l.id = ?)
        AND (? IS NULL OR p.category_id = ?)
      ORDER BY l.name, p.name
      LIMIT ?
      ''',
          variables: [
            Variable<String>(LocationKind.warehouse.name),
            Variable<int>(filter.locationId),
            Variable<int>(filter.locationId),
            Variable<int>(filter.categoryId),
            Variable<int>(filter.categoryId),
            Variable<int>(filter.limit),
          ],
          readsFrom: {
            _db.stockBalances,
            _db.products,
            _db.categories,
            _db.inventoryLocations,
          },
        )
        .get();

    const columns = [
      ReportColumn.text('Product', flex: 4),
      ReportColumn.text('SKU', width: 120),
      ReportColumn.text('Category', flex: 2),
      ReportColumn.text('Warehouse', flex: 2),
      ReportColumn.integer('Units', width: 90),
      ReportColumn(
        label: 'Average cost',
        kind: ReportValueKind.money,
        width: 130,
      ),
      ReportColumn.money('Value'),
      ReportColumn(
        label: 'Reorder at',
        kind: ReportValueKind.integer,
        width: 100,
      ),
    ];

    final reportRows = <ReportRow>[];
    for (final row in rows) {
      final quantity = row.read<int>('quantity');
      final cost = Money(row.read<int>('average_cost_cents'));
      reportRows.add(
        ReportRow([
          ReportValue.text(row.read<String>('name')),
          ReportValue.text(row.read<String>('sku')),
          ReportValue.text(row.read<String>('category')),
          ReportValue.text(row.read<String>('location')),
          ReportValue.integer(quantity),
          ReportValue.money(cost),
          ReportValue.money(cost * quantity),
          ReportValue.integer(row.read<int>('reorder_level')),
        ], id: row.read<int>('id')),
      );
    }

    return ReportResult(
      title: definition.title,
      columns: columns,
      rows: reportRows,
      totals: ReportResult.sumColumns(columns, reportRows),
      generatedAt: _clock.nowUtc(),
      filter: filter,
      notes: const [
        ReportNote(
          'A position as it stands now, so the period filter does not apply. '
          'Valued at weighted average cost.',
        ),
      ],
    );
  }

  /// Agent-wise or shop-wise stock, which differ only in which party owns the
  /// location.
  Future<ReportResult> _partyStock(
    ReportDefinition definition,
    ReportFilter filter, {
    required bool agents,
  }) async {
    final partyTable = agents ? 'agents' : 'shops';
    final partyColumn = agents ? 'agent_id' : 'shop_id';
    final partyId = agents ? filter.agentId : filter.shopId;

    final rows = await _db
        .customSelect(
          '''
      SELECT party.id, party.code, party.name,
             COUNT(DISTINCT sb.product_id) AS products,
             COALESCE(SUM(sb.quantity), 0) AS units,
             COALESCE(SUM(sb.quantity * sb.average_cost_cents), 0) AS value
      FROM $partyTable party
      JOIN inventory_locations l ON l.$partyColumn = party.id
      LEFT JOIN stock_balances sb ON sb.location_id = l.id
        AND sb.quantity <> 0
      WHERE (? IS NULL OR party.id = ?)
      GROUP BY party.id
      ORDER BY value DESC
      LIMIT ?
      ''',
          variables: [
            Variable<int>(partyId),
            Variable<int>(partyId),
            Variable<int>(filter.limit),
          ],
          readsFrom: {
            agents ? _db.agents : _db.shops,
            _db.inventoryLocations,
            _db.stockBalances,
          },
        )
        .get();

    final columns = [
      ReportColumn.text(agents ? 'Agent' : 'Shop', flex: 4),
      const ReportColumn.text('Code', width: 110),
      const ReportColumn.integer('Products', width: 110),
      const ReportColumn.integer('Units held', width: 120),
      const ReportColumn.money('Value at cost'),
    ];

    final reportRows = [
      for (final row in rows)
        ReportRow([
          ReportValue.text(row.read<String>('name')),
          ReportValue.text(row.read<String>('code')),
          ReportValue.integer(row.read<int>('products')),
          ReportValue.integer(row.read<int>('units')),
          ReportValue.money(Money(row.read<int>('value'))),
        ], id: row.read<int>('id')),
    ];

    return ReportResult(
      title: definition.title,
      columns: columns,
      rows: reportRows,
      totals: ReportResult.sumColumns(columns, reportRows),
      generatedAt: _clock.nowUtc(),
      filter: filter,
      notes: [
        const ReportNote(
          'A position as it stands now, so the period filter does not apply.',
        ),
        ReportNote(
          agents
              ? 'Stock an agent is holding is still the business\'s stock; it '
                    'becomes theirs to owe for only when an invoice is raised.'
              : 'Stock sitting in a shop, valued at what it cost the '
                    'business.',
        ),
      ],
    );
  }

  Future<ReportResult> _stockMovement(
    ReportDefinition definition,
    ReportFilter filter,
  ) async {
    final rows = await _db
        .customSelect(
          '''
      SELECT e.occurred_at, e.quantity_delta, e.balance_after,
             e.unit_cost_cents,
             st.document_number, st.document_type, st.status,
             l.name AS location, l.kind AS location_kind,
             p.sku, p.name AS product
      FROM stock_ledger_entries e
      JOIN stock_transactions st ON st.id = e.transaction_id
      JOIN inventory_locations l ON l.id = e.location_id
      JOIN products p ON p.id = e.product_id
      WHERE l.kind IN (?, ?, ?, ?)
        ${_periodClause('e.occurred_at', filter)}
        AND (? IS NULL OR e.product_id = ?)
        AND (? IS NULL OR e.location_id = ?)
      ORDER BY e.occurred_at DESC, e.id DESC
      LIMIT ?
      ''',
          variables: [
            Variable<String>(LocationKind.warehouse.name),
            Variable<String>(LocationKind.agent.name),
            Variable<String>(LocationKind.shop.name),
            Variable<String>(LocationKind.damaged.name),
            ..._periodVariables(filter),
            Variable<int>(filter.productId),
            Variable<int>(filter.productId),
            Variable<int>(filter.locationId),
            Variable<int>(filter.locationId),
            Variable<int>(filter.limit),
          ],
          readsFrom: {
            _db.stockLedgerEntries,
            _db.stockTransactions,
            _db.inventoryLocations,
            _db.products,
          },
        )
        .get();

    const columns = [
      ReportColumn(label: 'Date', kind: ReportValueKind.date, width: 120),
      ReportColumn.text('Document', width: 150),
      ReportColumn.text('Movement', flex: 2),
      ReportColumn.text('Location', flex: 2),
      ReportColumn.text('Product', flex: 3),
      ReportColumn.integer('In', width: 80),
      ReportColumn.integer('Out', width: 80),
      ReportColumn(
        label: 'Balance after',
        kind: ReportValueKind.integer,
        width: 120,
      ),
    ];

    final reportRows = [
      for (final row in rows)
        () {
          final delta = row.read<int>('quantity_delta');
          final type = StockDocumentType.values.byName(
            row.read<String>('document_type'),
          );
          final cancelled =
              row.read<String>('status') == StockDocumentStatus.cancelled.name;
          return ReportRow([
            ReportValue.date(row.read<DateTime>('occurred_at')),
            ReportValue.text(
              '${row.read<String>('document_number')}'
              '${cancelled ? ' (cancelled)' : ''}',
            ),
            ReportValue.text(_documentTypeLabel(type)),
            ReportValue.text(row.read<String>('location')),
            ReportValue.text(
              '${row.read<String>('product')} · ${row.read<String>('sku')}',
            ),
            ReportValue.integer(delta > 0 ? delta : 0),
            ReportValue.integer(delta < 0 ? -delta : 0),
            ReportValue.integer(row.read<int>('balance_after')),
          ]);
        }(),
    ];

    // The balance column is a running figure, not something to add up.
    final totals = ReportResult.sumColumns(columns, reportRows);
    totals[7] = ReportValue.empty;

    return ReportResult(
      title: definition.title,
      columns: columns,
      rows: reportRows,
      totals: totals,
      generatedAt: _clock.nowUtc(),
      filter: filter,
      notes: const [
        ReportNote(
          'Read from the append-only stock ledger. The counterparty legs - '
          'suppliers, customers, adjustments, goods in transit - are left out, '
          'so this shows what moved in and out of the business\'s own '
          'locations.',
        ),
        ReportNote(
          'A cancelled document keeps its ledger rows; the compensating '
          'document appears as its own movement.',
        ),
      ],
    );
  }

  Future<ReportResult> _stockValuation(
    ReportDefinition definition,
    ReportFilter filter,
  ) async {
    final rows = await _db
        .customSelect(
          '''
      SELECT p.id, p.sku, p.name, c.name AS category,
             COALESCE(SUM(CASE WHEN l.kind = ? THEN sb.quantity ELSE 0 END), 0)
               AS warehouse,
             COALESCE(SUM(CASE WHEN l.kind = ? THEN sb.quantity ELSE 0 END), 0)
               AS agent,
             COALESCE(SUM(CASE WHEN l.kind = ? THEN sb.quantity ELSE 0 END), 0)
               AS shop,
             COALESCE(SUM(CASE WHEN l.kind = ? THEN sb.quantity ELSE 0 END), 0)
               AS damaged,
             COALESCE(SUM(CASE WHEN l.kind IN (?, ?, ?)
                          THEN sb.quantity * sb.average_cost_cents
                          ELSE 0 END), 0) AS sellable_value,
             COALESCE(SUM(CASE WHEN l.kind = ?
                          THEN sb.quantity * sb.average_cost_cents
                          ELSE 0 END), 0) AS damaged_value
      FROM products p
      JOIN categories c ON c.id = p.category_id
      LEFT JOIN stock_balances sb ON sb.product_id = p.id
      LEFT JOIN inventory_locations l ON l.id = sb.location_id
      WHERE p.status <> ?
        AND (? IS NULL OR p.category_id = ?)
      GROUP BY p.id
      HAVING warehouse <> 0 OR agent <> 0 OR shop <> 0 OR damaged <> 0
      ORDER BY sellable_value DESC
      LIMIT ?
      ''',
          variables: [
            Variable<String>(LocationKind.warehouse.name),
            Variable<String>(LocationKind.agent.name),
            Variable<String>(LocationKind.shop.name),
            Variable<String>(LocationKind.damaged.name),
            Variable<String>(LocationKind.warehouse.name),
            Variable<String>(LocationKind.agent.name),
            Variable<String>(LocationKind.shop.name),
            Variable<String>(LocationKind.damaged.name),
            Variable<String>(EntityStatus.archived.name),
            Variable<int>(filter.categoryId),
            Variable<int>(filter.categoryId),
            Variable<int>(filter.limit),
          ],
          readsFrom: {
            _db.products,
            _db.categories,
            _db.stockBalances,
            _db.inventoryLocations,
          },
        )
        .get();

    const columns = [
      ReportColumn.text('Product', flex: 4),
      ReportColumn.text('SKU', width: 120),
      ReportColumn.text('Category', flex: 2),
      ReportColumn.integer('Warehouse', width: 110),
      ReportColumn.integer('Agents', width: 100),
      ReportColumn.integer('Shops', width: 100),
      ReportColumn.integer('Damaged', width: 100),
      ReportColumn.money('Sellable value'),
      ReportColumn.money('Damaged value'),
    ];

    final reportRows = [
      for (final row in rows)
        ReportRow([
          ReportValue.text(row.read<String>('name')),
          ReportValue.text(row.read<String>('sku')),
          ReportValue.text(row.read<String>('category')),
          ReportValue.integer(row.read<int>('warehouse')),
          ReportValue.integer(row.read<int>('agent')),
          ReportValue.integer(row.read<int>('shop')),
          ReportValue.integer(row.read<int>('damaged')),
          ReportValue.money(Money(row.read<int>('sellable_value'))),
          ReportValue.money(Money(row.read<int>('damaged_value'))),
        ], id: row.read<int>('id')),
    ];

    return ReportResult(
      title: definition.title,
      columns: columns,
      rows: reportRows,
      totals: ReportResult.sumColumns(columns, reportRows),
      generatedAt: _clock.nowUtc(),
      filter: filter,
      notes: const [
        ReportNote(
          'A position as it stands now. Damaged stock is valued separately '
          'because it is owned but not sellable.',
        ),
        ReportNote(
          'Goods in transit - a return that has not been inspected - are not '
          'included: they have left the returning party and have not yet been '
          'accepted.',
        ),
      ],
    );
  }

  // --- Money ---------------------------------------------------------------

  Future<ReportResult> _collections(
    ReportDefinition definition,
    ReportFilter filter,
  ) async {
    final rows = await _db
        .customSelect(
          '''
      SELECT pay.id, pay.receipt_number, pay.payment_date, pay.method,
             pay.status, pay.amount_cents, pay.allocated_cents,
             COALESCE(a.name, s.name, pay.payer_name, 'Walk-in') AS party,
             c.cheque_number, c.status AS cheque_status
      FROM payments pay
      LEFT JOIN agents a ON a.id = pay.agent_id
      LEFT JOIN shops s ON s.id = pay.shop_id
      LEFT JOIN cheques c ON c.payment_id = pay.id
      WHERE pay.direction = ?
        AND pay.status <> ?
        ${_periodClause('pay.payment_date', filter)}
        AND (? IS NULL OR pay.agent_id = ?)
        AND (? IS NULL OR pay.shop_id = ?)
      ORDER BY pay.payment_date DESC, pay.id DESC
      LIMIT ?
      ''',
          variables: [
            Variable<String>(PaymentDirection.inbound.name),
            Variable<String>(PaymentStatus.cancelled.name),
            ..._periodVariables(filter),
            Variable<int>(filter.agentId),
            Variable<int>(filter.agentId),
            Variable<int>(filter.shopId),
            Variable<int>(filter.shopId),
            Variable<int>(filter.limit),
          ],
          readsFrom: {_db.payments, _db.agents, _db.shops, _db.cheques},
        )
        .get();

    const columns = [
      ReportColumn(label: 'Date', kind: ReportValueKind.date, width: 120),
      ReportColumn.text('Receipt', width: 140),
      ReportColumn.text('From', flex: 3),
      ReportColumn.text('Method', flex: 2),
      ReportColumn.money('Collected'),
      ReportColumn.money('Awaiting clearance'),
      ReportColumn.money('Unapplied'),
      ReportColumn.text('Status', width: 120),
    ];

    final reportRows = [
      for (final row in rows)
        () {
          final amount = Money(row.read<int>('amount_cents'));
          final status = PaymentStatus.values.byName(
            row.read<String>('status'),
          );
          final cleared = status == PaymentStatus.cleared;
          final pending = status == PaymentStatus.pending;
          final chequeNumber = row.readNullable<String>('cheque_number');
          return ReportRow([
            ReportValue.date(row.read<DateTime>('payment_date')),
            ReportValue.text(row.read<String>('receipt_number')),
            ReportValue.text(row.read<String>('party')),
            ReportValue.text(
              '${_methodLabel(PaymentMethod.values.byName(row.read<String>('method')))}'
              '${chequeNumber == null ? '' : ' · $chequeNumber'}',
            ),
            ReportValue.money(cleared ? amount : Money.zero),
            ReportValue.money(pending ? amount : Money.zero),
            ReportValue.money(
              cleared
                  ? amount - Money(row.read<int>('allocated_cents'))
                  : Money.zero,
            ),
            ReportValue.text(_paymentStatusLabel(status)),
          ], id: row.read<int>('id'));
        }(),
    ];

    return ReportResult(
      title: definition.title,
      columns: columns,
      rows: reportRows,
      totals: ReportResult.sumColumns(columns, reportRows),
      generatedAt: _clock.nowUtc(),
      filter: filter,
      notes: const [
        ReportNote(
          'Only cleared money counts as collected. A cheque awaiting '
          'clearance is in its own column and has settled nothing; a bounced '
          'one counts as neither.',
        ),
        ReportNote(
          '"Unapplied" is money held for a party that has not been put '
          'against an invoice - their advance, not income.',
        ),
      ],
    );
  }

  Future<ReportResult> _outstanding(
    ReportDefinition definition,
    ReportFilter filter,
  ) async {
    final rows = await _db
        .customSelect(
          '''
      SELECT 'Agent' AS party_kind, a.id, a.code, a.name,
             a.opening_balance_cents AS opening,
             COALESCE(billed.total, 0) AS billed,
             COALESCE(settled.total, 0) AS settled,
             COALESCE(credited.total, 0) AS credited,
             COALESCE(pending.total, 0) AS pending
      FROM agents a
      LEFT JOIN (
        SELECT agent_id, SUM(net_total_cents) AS total FROM invoices
        WHERE status = ? AND party_type = ? AND agent_id IS NOT NULL
        GROUP BY agent_id
      ) billed ON billed.agent_id = a.id
      LEFT JOIN (
        SELECT i.agent_id, SUM(pa.amount_cents) AS total
        FROM payment_allocations pa
        JOIN payments p ON p.id = pa.payment_id
        JOIN invoices i ON i.id = pa.invoice_id
        WHERE p.status = ? AND i.status = ? AND i.agent_id IS NOT NULL
        GROUP BY i.agent_id
      ) settled ON settled.agent_id = a.id
      LEFT JOIN (
        SELECT i.agent_id, SUM(cna.amount_cents) AS total
        FROM credit_note_applications cna
        JOIN credit_notes cn ON cn.id = cna.credit_note_id
        JOIN invoices i ON i.id = cna.invoice_id
        WHERE cn.status = ? AND i.status = ? AND i.agent_id IS NOT NULL
        GROUP BY i.agent_id
      ) credited ON credited.agent_id = a.id
      LEFT JOIN (
        SELECT p.agent_id, SUM(p.amount_cents) AS total
        FROM payments p JOIN cheques c ON c.payment_id = p.id
        WHERE p.status = ? AND c.status IN (?, ?) AND p.agent_id IS NOT NULL
        GROUP BY p.agent_id
      ) pending ON pending.agent_id = a.id
      WHERE a.status <> ?

      UNION ALL

      SELECT 'Shop' AS party_kind, s.id, s.code, s.name,
             s.opening_balance_cents AS opening,
             COALESCE(billed.total, 0) AS billed,
             COALESCE(settled.total, 0) AS settled,
             COALESCE(credited.total, 0) AS credited,
             COALESCE(pending.total, 0) AS pending
      FROM shops s
      LEFT JOIN (
        SELECT shop_id, SUM(net_total_cents) AS total FROM invoices
        WHERE status = ? AND party_type = ? AND shop_id IS NOT NULL
        GROUP BY shop_id
      ) billed ON billed.shop_id = s.id
      LEFT JOIN (
        SELECT i.shop_id, SUM(pa.amount_cents) AS total
        FROM payment_allocations pa
        JOIN payments p ON p.id = pa.payment_id
        JOIN invoices i ON i.id = pa.invoice_id
        WHERE p.status = ? AND i.status = ? AND i.shop_id IS NOT NULL
        GROUP BY i.shop_id
      ) settled ON settled.shop_id = s.id
      LEFT JOIN (
        SELECT i.shop_id, SUM(cna.amount_cents) AS total
        FROM credit_note_applications cna
        JOIN credit_notes cn ON cn.id = cna.credit_note_id
        JOIN invoices i ON i.id = cna.invoice_id
        WHERE cn.status = ? AND i.status = ? AND i.shop_id IS NOT NULL
        GROUP BY i.shop_id
      ) credited ON credited.shop_id = s.id
      LEFT JOIN (
        SELECT p.shop_id, SUM(p.amount_cents) AS total
        FROM payments p JOIN cheques c ON c.payment_id = p.id
        WHERE p.status = ? AND c.status IN (?, ?) AND p.shop_id IS NOT NULL
        GROUP BY p.shop_id
      ) pending ON pending.shop_id = s.id
      WHERE s.status <> ?

      ORDER BY party_kind, name
      LIMIT ?
      ''',
          variables: [
            // Agents
            Variable<String>(InvoiceStatus.posted.name),
            Variable<String>(PartyType.agent.name),
            Variable<String>(PaymentStatus.cleared.name),
            Variable<String>(InvoiceStatus.posted.name),
            Variable<String>(InvoiceStatus.posted.name),
            Variable<String>(InvoiceStatus.posted.name),
            Variable<String>(PaymentStatus.pending.name),
            Variable<String>(ChequeStatus.pending.name),
            Variable<String>(ChequeStatus.deposited.name),
            Variable<String>(EntityStatus.archived.name),
            // Shops
            Variable<String>(InvoiceStatus.posted.name),
            Variable<String>(PartyType.shop.name),
            Variable<String>(PaymentStatus.cleared.name),
            Variable<String>(InvoiceStatus.posted.name),
            Variable<String>(InvoiceStatus.posted.name),
            Variable<String>(InvoiceStatus.posted.name),
            Variable<String>(PaymentStatus.pending.name),
            Variable<String>(ChequeStatus.pending.name),
            Variable<String>(ChequeStatus.deposited.name),
            Variable<String>(EntityStatus.archived.name),
            Variable<int>(filter.limit),
          ],
          readsFrom: {
            _db.agents,
            _db.shops,
            _db.invoices,
            _db.payments,
            _db.paymentAllocations,
            _db.creditNotes,
            _db.creditNoteApplications,
            _db.cheques,
          },
        )
        .get();

    const columns = [
      ReportColumn.text('Kind', width: 90),
      ReportColumn.text('Party', flex: 4),
      ReportColumn.text('Code', width: 110),
      ReportColumn.money('Opening'),
      ReportColumn.money('Billed'),
      ReportColumn.money('Settled'),
      ReportColumn.money('Credit notes'),
      ReportColumn.money('Outstanding'),
      ReportColumn.money('Cheques pending'),
    ];

    final reportRows = <ReportRow>[];
    for (final row in rows) {
      final opening = Money(row.read<int>('opening'));
      final billed = Money(row.read<int>('billed'));
      final settled = Money(row.read<int>('settled'));
      final credited = Money(row.read<int>('credited'));
      final outstanding = opening + billed - settled - credited;
      if (outstanding.isZero && billed.isZero && opening.isZero) continue;

      reportRows.add(
        ReportRow([
          ReportValue.text(row.read<String>('party_kind')),
          ReportValue.text(row.read<String>('name')),
          ReportValue.text(row.read<String>('code')),
          ReportValue.money(opening),
          ReportValue.money(billed),
          ReportValue.money(settled),
          ReportValue.money(credited),
          ReportValue.money(outstanding),
          ReportValue.money(Money(row.read<int>('pending'))),
        ], id: row.read<int>('id')),
      );
    }

    return ReportResult(
      title: definition.title,
      columns: columns,
      rows: reportRows,
      totals: ReportResult.sumColumns(columns, reportRows),
      generatedAt: _clock.nowUtc(),
      filter: filter,
      notes: const [
        ReportNote(
          'Outstanding is opening balance plus posted invoices, less what '
          'cleared payments and posted credit notes have settled. A cheque '
          'awaiting clearance is shown separately and settles nothing.',
        ),
        ReportNote(
          'A balance as it stands now, so the period filter does not apply.',
        ),
      ],
    );
  }

  Future<ReportResult> _discounts(
    ReportDefinition definition,
    ReportFilter filter,
  ) async {
    final rows = await _db
        .customSelect(
          '''
      SELECT d.granted_at, d.scope, d.discount_type, d.discount_value,
             d.discount_cents, d.base_amount_cents, d.reason,
             d.exceeded_limit,
             i.invoice_number,
             COALESCE(a.name, s.name, i.customer_name, 'Walk-in') AS party,
             granter.full_name AS granted_by,
             approver.full_name AS approved_by,
             p.name AS product
      FROM discounts d
      JOIN invoices i ON i.id = d.invoice_id
      LEFT JOIN agents a ON a.id = i.agent_id
      LEFT JOIN shops s ON s.id = i.shop_id
      JOIN users granter ON granter.id = d.granted_by_user_id
      LEFT JOIN users approver ON approver.id = d.approved_by_user_id
      LEFT JOIN products p ON p.id = d.product_id
      WHERE i.status = ?
        ${_periodClause('d.granted_at', filter)}
        AND (? IS NULL OR i.agent_id = ?)
        AND (? IS NULL OR i.shop_id = ?)
      ORDER BY d.granted_at DESC, d.id DESC
      LIMIT ?
      ''',
          variables: [
            Variable<String>(InvoiceStatus.posted.name),
            ..._periodVariables(filter),
            Variable<int>(filter.agentId),
            Variable<int>(filter.agentId),
            Variable<int>(filter.shopId),
            Variable<int>(filter.shopId),
            Variable<int>(filter.limit),
          ],
          readsFrom: {
            _db.discountRecords,
            _db.invoices,
            _db.agents,
            _db.shops,
            _db.users,
            _db.products,
          },
        )
        .get();

    const columns = [
      ReportColumn(label: 'Date', kind: ReportValueKind.date, width: 120),
      ReportColumn.text('Invoice', width: 140),
      ReportColumn.text('Party', flex: 3),
      ReportColumn.text('On', flex: 3),
      ReportColumn.text('As entered', width: 110),
      ReportColumn.money('Applied to'),
      ReportColumn.money('Discount'),
      ReportColumn(
        label: 'Effective',
        kind: ReportValueKind.percent,
        width: 100,
      ),
      ReportColumn.text('Given by', flex: 2),
      ReportColumn.text('Past ceiling', width: 120),
    ];

    final reportRows = <ReportRow>[];
    for (final row in rows) {
      final discount = Money(row.read<int>('discount_cents'));
      final base = Money(row.read<int>('base_amount_cents'));
      final type = DiscountType.values.byName(
        row.read<String>('discount_type'),
      );
      final value = row.read<int>('discount_value');
      final scope = DiscountScope.values.byName(row.read<String>('scope'));
      final approver = row.readNullable<String>('approved_by');

      reportRows.add(
        ReportRow([
          ReportValue.date(row.read<DateTime>('granted_at')),
          ReportValue.text(row.read<String>('invoice_number')),
          ReportValue.text(row.read<String>('party')),
          ReportValue.text(
            scope == DiscountScope.invoice
                ? 'The whole invoice'
                : (row.readNullable<String>('product') ?? 'A line'),
          ),
          // The original input is kept beside the cash amount, so a printed
          // report can still show "10%" years later.
          ReportValue.text(
            type == DiscountType.percentage
                ? formatBps(value)
                : Money(value).formatted(),
          ),
          ReportValue.money(base),
          ReportValue.money(discount),
          ReportValue.percent(base.isZero ? 0 : discount.bpsOf(base)),
          ReportValue.text(row.read<String>('granted_by')),
          ReportValue.text(
            row.read<bool>('exceeded_limit')
                ? 'Yes${approver == null ? '' : ' · $approver'}'
                : 'No',
          ),
        ]),
      );
    }

    final totals = ReportResult.sumColumns(columns, reportRows);
    final totalBase = totals[5].money ?? Money.zero;
    final totalDiscount = totals[6].money ?? Money.zero;
    totals[7] = ReportValue.percent(
      totalBase.isZero ? 0 : totalDiscount.bpsOf(totalBase),
    );

    return ReportResult(
      title: definition.title,
      columns: columns,
      rows: reportRows,
      totals: totals,
      generatedAt: _clock.nowUtc(),
      filter: filter,
      notes: const [
        ReportNote(
          'Every discount is recorded, whatever its size. One past the '
          'configured ceiling names the user who approved it.',
        ),
        ReportNote(
          'Item and invoice-level discounts are separate rows, so the total '
          'is what was actually given away.',
        ),
      ],
    );
  }

  Future<ReportResult> _returns(
    ReportDefinition definition,
    ReportFilter filter,
  ) async {
    final rows = await _db
        .customSelect(
          '''
      SELECT r.id, r.return_number, r.return_date, r.route, r.status,
             r.reason, r.total_quantity, r.total_value_cents,
             COALESCE(a.name, s.name, 'Retail customer') AS party,
             src.name AS from_location,
             inv.invoice_number,
             COALESCE(item.accepted, 0) AS accepted,
             COALESCE(item.damaged, 0) AS damaged,
             COALESCE(item.scrapped, 0) AS scrapped,
             COALESCE(credit.total, 0) AS credited
      FROM returns r
      JOIN inventory_locations src ON src.id = r.from_location_id
      LEFT JOIN agents a ON a.id = r.agent_id
      LEFT JOIN shops s ON s.id = r.shop_id
      LEFT JOIN invoices inv ON inv.id = r.origin_invoice_id
      LEFT JOIN (
        SELECT return_id,
               SUM(accepted_quantity) AS accepted,
               SUM(damaged_quantity) AS damaged,
               SUM(scrapped_quantity) AS scrapped
        FROM return_items GROUP BY return_id
      ) item ON item.return_id = r.id
      LEFT JOIN (
        SELECT return_id, SUM(amount_cents) AS total
        FROM credit_notes WHERE status = ? AND return_id IS NOT NULL
        GROUP BY return_id
      ) credit ON credit.return_id = r.id
      WHERE 1 = 1
        ${_periodClause('r.return_date', filter)}
        AND (? IS NULL OR r.agent_id = ?)
        AND (? IS NULL OR r.shop_id = ?)
      ORDER BY r.return_date DESC, r.id DESC
      LIMIT ?
      ''',
          variables: [
            Variable<String>(InvoiceStatus.posted.name),
            ..._periodVariables(filter),
            Variable<int>(filter.agentId),
            Variable<int>(filter.agentId),
            Variable<int>(filter.shopId),
            Variable<int>(filter.shopId),
            Variable<int>(filter.limit),
          ],
          readsFrom: {
            _db.returnDocuments,
            _db.returnItems,
            _db.inventoryLocations,
            _db.agents,
            _db.shops,
            _db.invoices,
            _db.creditNotes,
          },
        )
        .get();

    const columns = [
      ReportColumn(label: 'Date', kind: ReportValueKind.date, width: 120),
      ReportColumn.text('Return', width: 140),
      ReportColumn.text('From', flex: 3),
      ReportColumn.text('Reason', flex: 2),
      ReportColumn.text('Invoice', width: 130),
      ReportColumn.integer('Units back', width: 110),
      ReportColumn.integer('Accepted', width: 100),
      ReportColumn.integer('Damaged', width: 100),
      ReportColumn.integer('Scrapped', width: 100),
      ReportColumn.money('Value'),
      ReportColumn.money('Credited'),
      ReportColumn.text('Status', width: 150),
    ];

    final reportRows = <ReportRow>[];
    for (final row in rows) {
      final status = ReturnStatus.values.byName(row.read<String>('status'));
      final cancelled = status == ReturnStatus.cancelled;
      reportRows.add(
        ReportRow([
          ReportValue.date(row.read<DateTime>('return_date')),
          ReportValue.text(row.read<String>('return_number')),
          ReportValue.text(
            '${row.read<String>('party')} · '
            '${row.read<String>('from_location')}',
          ),
          ReportValue.text(
            _returnReasonLabel(
              ReturnReason.values.byName(row.read<String>('reason')),
            ),
          ),
          ReportValue.text(
            row.readNullable<String>('invoice_number') ?? 'not traced',
          ),
          ReportValue.integer(cancelled ? 0 : row.read<int>('total_quantity')),
          ReportValue.integer(cancelled ? 0 : row.read<int>('accepted')),
          ReportValue.integer(cancelled ? 0 : row.read<int>('damaged')),
          ReportValue.integer(cancelled ? 0 : row.read<int>('scrapped')),
          ReportValue.money(
            cancelled ? Money.zero : Money(row.read<int>('total_value_cents')),
          ),
          ReportValue.money(Money(row.read<int>('credited'))),
          ReportValue.text(_returnStatusLabel(status)),
        ], id: row.read<int>('id')),
      );
    }

    return ReportResult(
      title: definition.title,
      columns: columns,
      rows: reportRows,
      totals: ReportResult.sumColumns(columns, reportRows),
      generatedAt: _clock.nowUtc(),
      filter: filter,
      notes: const [
        ReportNote(
          'A cancelled return is listed for the trail but counts nothing: its '
          'goods went back where they came from.',
        ),
        ReportNote(
          'Scrapped goods are written off and earn no credit. Damaged goods '
          'are credited and held in quarantine.',
        ),
      ],
    );
  }

  // --- Finance -------------------------------------------------------------

  Future<ReportResult> _expenses(
    ReportDefinition definition,
    ReportFilter filter,
  ) async {
    final rows = await _db
        .customSelect(
          '''
      SELECT c.id, c.name AS category,
             COUNT(x.id) AS vouchers,
             COALESCE(SUM(x.amount_cents), 0) AS total,
             COALESCE(SUM(CASE WHEN x.petty_cash_entry_id IS NOT NULL
                          THEN x.amount_cents ELSE 0 END), 0) AS petty
      FROM expense_categories c
      JOIN expenses x ON x.category_id = c.id AND x.status = ?
        ${_periodClause('x.expense_date', filter)}
      WHERE (? IS NULL OR c.id = ?)
      GROUP BY c.id
      ORDER BY total DESC
      LIMIT ?
      ''',
          variables: [
            Variable<String>(InvoiceStatus.posted.name),
            ..._periodVariables(filter),
            Variable<int>(filter.categoryId),
            Variable<int>(filter.categoryId),
            Variable<int>(filter.limit),
          ],
          readsFrom: {_db.expenseCategories, _db.expenses},
        )
        .get();

    const columns = [
      ReportColumn.text('Category', flex: 4),
      ReportColumn.integer('Vouchers', width: 110),
      ReportColumn.money('Spent'),
      ReportColumn.money('Of which petty cash'),
      ReportColumn(label: 'Share', kind: ReportValueKind.percent, width: 90),
    ];

    final grand = rows
        .map((row) => Money(row.read<int>('total')))
        .fold(Money.zero, (a, b) => a + b);

    final reportRows = [
      for (final row in rows)
        ReportRow([
          ReportValue.text(row.read<String>('category')),
          ReportValue.integer(row.read<int>('vouchers')),
          ReportValue.money(Money(row.read<int>('total'))),
          ReportValue.money(Money(row.read<int>('petty'))),
          ReportValue.percent(
            grand.isZero ? 0 : Money(row.read<int>('total')).bpsOf(grand),
          ),
        ], id: row.read<int>('id')),
    ];

    final totals = ReportResult.sumColumns(columns, reportRows);
    totals[4] = ReportValue.percent(grand.isZero ? 0 : Money.bpsScale);

    return ReportResult(
      title: definition.title,
      columns: columns,
      rows: reportRows,
      totals: totals,
      generatedAt: _clock.nowUtc(),
      filter: filter,
      notes: const [
        ReportNote('Cancelled vouchers are excluded.'),
        ReportNote(
          'An expense paid from the petty cash float reduces the float by one '
          'linked entry, so it is counted here once and not twice.',
        ),
      ],
    );
  }

  Future<ReportResult> _pettyCash(
    ReportDefinition definition,
    ReportFilter filter,
  ) async {
    final rows = await _db
        .customSelect(
          '''
      SELECT e.voucher_number, e.entry_date, e.kind, e.amount_cents,
             e.signed_amount_cents, e.balance_after_cents, e.description,
             x.voucher_number AS expense_voucher
      FROM petty_cash_entries e
      LEFT JOIN expenses x ON x.id = e.expense_id
      WHERE 1 = 1
        ${_periodClause('e.entry_date', filter)}
      ORDER BY e.entry_date DESC, e.id DESC
      LIMIT ?
      ''',
          variables: [..._periodVariables(filter), Variable<int>(filter.limit)],
          readsFrom: {_db.pettyCashEntries, _db.expenses},
        )
        .get();

    const columns = [
      ReportColumn(label: 'Date', kind: ReportValueKind.date, width: 120),
      ReportColumn.text('Voucher', width: 140),
      ReportColumn.text('Kind', flex: 2),
      ReportColumn.text('Description', flex: 4),
      ReportColumn.money('In'),
      ReportColumn.money('Out'),
      ReportColumn(label: 'Balance', kind: ReportValueKind.money, width: 130),
    ];

    final reportRows = [
      for (final row in rows)
        () {
          final signed = Money(row.read<int>('signed_amount_cents'));
          final expenseVoucher = row.readNullable<String>('expense_voucher');
          return ReportRow([
            ReportValue.date(row.read<DateTime>('entry_date')),
            ReportValue.text(row.read<String>('voucher_number')),
            ReportValue.text(
              _pettyCashKindLabel(
                PettyCashEntryKind.values.byName(row.read<String>('kind')),
              ),
            ),
            ReportValue.text(
              '${row.read<String>('description')}'
              '${expenseVoucher == null ? '' : ' ($expenseVoucher)'}',
            ),
            ReportValue.money(signed.isPositive ? signed : Money.zero),
            ReportValue.money(signed.isNegative ? -signed : Money.zero),
            ReportValue.money(Money(row.read<int>('balance_after_cents'))),
          ]);
        }(),
    ];

    final totals = ReportResult.sumColumns(columns, reportRows);
    // The balance is a running figure, so the totals row shows where the
    // float stands rather than a meaningless sum of balances.
    totals[6] = ReportValue.money(
      reportRows.isEmpty ? Money.zero : reportRows.first.values[6].money!,
    );

    return ReportResult(
      title: definition.title,
      columns: columns,
      rows: reportRows,
      totals: totals,
      generatedAt: _clock.nowUtc(),
      filter: filter,
      subtitle: 'Newest first; the balance column reads downwards.',
      notes: const [
        ReportNote(
          'The balance column is the float immediately after each entry, as '
          'it was recorded at the time. The total shows where the float '
          'stands at the newest entry shown.',
        ),
      ],
    );
  }

  Future<ReportResult> _salaries(
    ReportDefinition definition,
    ReportFilter filter,
  ) async {
    final rows = await _db
        .customSelect(
          '''
      SELECT s.id, s.voucher_number, s.period_year, s.period_month,
             s.basic_salary_cents, s.allowances_cents, s.bonus_cents,
             s.deductions_cents, s.advance_deducted_cents,
             s.net_salary_cents, s.paid_cents, s.status,
             e.name AS employee, e.code, e.designation
      FROM salaries s
      JOIN employees e ON e.id = s.employee_id
      WHERE s.status <> ?
        AND (? IS NULL OR s.employee_id = ?)
        ${_salaryPeriodClause(filter)}
      ORDER BY s.period_year DESC, s.period_month DESC, e.name
      LIMIT ?
      ''',
          variables: [
            Variable<String>(SalaryStatus.cancelled.name),
            Variable<int>(filter.employeeId),
            Variable<int>(filter.employeeId),
            Variable<int>(filter.limit),
          ],
          readsFrom: {_db.salaries, _db.employees},
        )
        .get();

    const columns = [
      ReportColumn.text('Employee', flex: 3),
      ReportColumn.text('Period', width: 140),
      ReportColumn.money('Basic'),
      ReportColumn.money('Allowances'),
      ReportColumn.money('Bonus'),
      ReportColumn.money('Deductions'),
      ReportColumn.money('Advance recovered'),
      ReportColumn.money('Net'),
      ReportColumn.money('Paid'),
      ReportColumn.money('Still owed'),
      ReportColumn.text('Status', width: 120),
    ];

    final reportRows = <ReportRow>[];
    for (final row in rows) {
      final net = Money(row.read<int>('net_salary_cents'));
      final paid = Money(row.read<int>('paid_cents'));
      final owed = net - paid;
      final status = SalaryStatus.values.byName(row.read<String>('status'));
      final designation = row.readNullable<String>('designation');

      reportRows.add(
        ReportRow([
          ReportValue.text(
            '${row.read<String>('employee')}'
            '${designation == null ? '' : ' · $designation'}',
          ),
          ReportValue.month(
            DateTime(
              row.read<int>('period_year'),
              row.read<int>('period_month'),
            ),
          ),
          ReportValue.money(Money(row.read<int>('basic_salary_cents'))),
          ReportValue.money(Money(row.read<int>('allowances_cents'))),
          ReportValue.money(Money(row.read<int>('bonus_cents'))),
          ReportValue.money(Money(row.read<int>('deductions_cents'))),
          ReportValue.money(Money(row.read<int>('advance_deducted_cents'))),
          ReportValue.money(net),
          ReportValue.money(paid),
          ReportValue.money(owed.isPositive ? owed : Money.zero),
          ReportValue.text(_salaryStatusLabel(status)),
        ], id: row.read<int>('id')),
      );
    }

    return ReportResult(
      title: definition.title,
      columns: columns,
      rows: reportRows,
      totals: ReportResult.sumColumns(columns, reportRows),
      generatedAt: _clock.nowUtc(),
      filter: filter,
      notes: const [
        ReportNote(
          'A draft salary is listed but owes nothing until it is approved. '
          'Cancelled salaries are excluded.',
        ),
        ReportNote(
          'An advance recovered is a deduction, not a second wage cost: the '
          'money was paid early and is being settled here.',
        ),
      ],
    );
  }

  Future<ReportResult> _profitAndLoss(
    ReportDefinition definition,
    ReportFilter filter,
  ) async {
    final report = await _finance.profitAndLoss(
      from: filter.from,
      to: filter.to,
    );
    final balance = await _finance.trialBalance(
      from: filter.from,
      to: filter.to,
    );

    const columns = [
      ReportColumn.text('Line', flex: 4),
      ReportColumn(label: 'Amount', kind: ReportValueKind.money, width: 160),
    ];

    ReportRow line(String label, Money amount, {bool emphasise = false}) =>
        ReportRow([
          ReportValue.text(label),
          ReportValue.money(amount),
        ], emphasise: emphasise);

    final rows = <ReportRow>[
      line('Sales at full price', report.grossSales),
      if (!report.discounts.isZero) line('Discounts given', -report.discounts),
      if (!report.returns.isZero) line('Goods returned', -report.returns),
      line('Revenue', report.revenue, emphasise: true),
      line('Cost of goods sold', -report.costOfGoodsSold),
      line('Gross profit', report.grossProfit, emphasise: true),
      if (!report.operatingExpenses.isZero)
        line('Operating expenses', -report.operatingExpenses),
      if (!report.salaryExpense.isZero) line('Salaries', -report.salaryExpense),
      if (!report.stockWriteOff.isZero)
        line('Stock written off', -report.stockWriteOff),
      if (!report.otherExpenses.isZero)
        line('Other expenses', -report.otherExpenses),
      line('Net profit', report.netProfit, emphasise: true),
    ];

    return ReportResult(
      title: definition.title,
      subtitle: report.revenue.isZero
          ? null
          : 'Gross margin ${formatBps(report.grossMarginBps)}',
      columns: columns,
      rows: rows,
      generatedAt: _clock.nowUtc(),
      filter: filter,
      notes: [
        const ReportNote(
          'Read from the double-entry journal rather than from the '
          'operational tables, so it agrees with the trial balance by '
          'construction.',
        ),
        ReportNote(
          balance.isBalanced
              ? 'The trial balance for this period balances: debits '
                    '${balance.totalDebits.formatted()} against credits '
                    '${balance.totalCredits.formatted()}.'
              : 'WARNING: the trial balance for this period does not balance '
                    '(debits ${balance.totalDebits.formatted()} against '
                    'credits ${balance.totalCredits.formatted()}). The '
                    'figures above cannot be relied on.',
        ),
      ],
    );
  }

  // --- Internals ----------------------------------------------------------

  /// Outstanding balance per party id, built exactly as the party screens do.
  Future<Map<int, Money>> _outstandingByParty({required bool agents}) async {
    final table = agents ? 'agents' : 'shops';
    final column = agents ? 'agent_id' : 'shop_id';
    final partyType = agents ? PartyType.agent : PartyType.shop;

    final rows = await _db
        .customSelect(
          '''
      SELECT party.id,
             party.opening_balance_cents
               + COALESCE(billed.total, 0)
               - COALESCE(settled.total, 0)
               - COALESCE(credited.total, 0) AS outstanding
      FROM $table party
      LEFT JOIN (
        SELECT $column AS pid, SUM(net_total_cents) AS total FROM invoices
        WHERE status = ? AND party_type = ? AND $column IS NOT NULL
        GROUP BY $column
      ) billed ON billed.pid = party.id
      LEFT JOIN (
        SELECT i.$column AS pid, SUM(pa.amount_cents) AS total
        FROM payment_allocations pa
        JOIN payments p ON p.id = pa.payment_id
        JOIN invoices i ON i.id = pa.invoice_id
        WHERE p.status = ? AND i.status = ? AND i.$column IS NOT NULL
        GROUP BY i.$column
      ) settled ON settled.pid = party.id
      LEFT JOIN (
        SELECT i.$column AS pid, SUM(cna.amount_cents) AS total
        FROM credit_note_applications cna
        JOIN credit_notes cn ON cn.id = cna.credit_note_id
        JOIN invoices i ON i.id = cna.invoice_id
        WHERE cn.status = ? AND i.status = ? AND i.$column IS NOT NULL
        GROUP BY i.$column
      ) credited ON credited.pid = party.id
      ''',
          variables: [
            Variable<String>(InvoiceStatus.posted.name),
            Variable<String>(partyType.name),
            Variable<String>(PaymentStatus.cleared.name),
            Variable<String>(InvoiceStatus.posted.name),
            Variable<String>(InvoiceStatus.posted.name),
            Variable<String>(InvoiceStatus.posted.name),
          ],
          readsFrom: {
            agents ? _db.agents : _db.shops,
            _db.invoices,
            _db.payments,
            _db.paymentAllocations,
            _db.creditNotes,
            _db.creditNoteApplications,
          },
        )
        .get();

    return {
      for (final row in rows)
        row.read<int>('id'): Money(row.read<int>('outstanding')),
    };
  }

  /// `AND column >= ? AND column <= ?`, or nothing when no period is set.
  ///
  /// Interpolated rather than parameterised with `? IS NULL OR` because these
  /// are date columns with indexes on them, and the null-guard form stops
  /// SQLite using the index.
  static String _periodClause(String column, ReportFilter filter) {
    return [
      if (filter.from != null) 'AND $column >= ?',
      if (filter.to != null) 'AND $column <= ?',
    ].join(' ');
  }

  static List<Variable<Object>> _periodVariables(ReportFilter filter) => [
    if (filter.from != null)
      Variable<String>(filter.from!.toUtc().toIso8601String()),
    if (filter.to != null)
      Variable<String>(filter.to!.toUtc().toIso8601String()),
  ];

  /// Salaries are filed by period, not by a date column, so a period filter
  /// has to compare year and month rather than a timestamp.
  static String _salaryPeriodClause(ReportFilter filter) {
    final parts = <String>[];
    if (filter.from != null) {
      final from = filter.from!.toLocal();
      parts.add(
        'AND (s.period_year * 100 + s.period_month) >= '
        '${from.year * 100 + from.month}',
      );
    }
    if (filter.to != null) {
      final to = filter.to!.toLocal();
      parts.add(
        'AND (s.period_year * 100 + s.period_month) <= '
        '${to.year * 100 + to.month}',
      );
    }
    return parts.join(' ');
  }

  static String _documentTypeLabel(StockDocumentType type) => switch (type) {
    StockDocumentType.openingStock => 'Opening stock',
    StockDocumentType.purchaseIn => 'Purchase',
    StockDocumentType.warehouseToAgent => 'Warehouse to agent',
    StockDocumentType.agentToShop => 'Agent to shop',
    StockDocumentType.warehouseToShop => 'Warehouse to shop',
    StockDocumentType.retailSale => 'Retail sale',
    StockDocumentType.customerToShopReturn => 'Customer return',
    StockDocumentType.shopToAgentReturn => 'Shop return',
    StockDocumentType.agentToWarehouseReturn => 'Agent return',
    StockDocumentType.shopToWarehouseReturn => 'Shop return (direct)',
    StockDocumentType.damageWriteOff => 'Damage write-off',
    StockDocumentType.adjustmentIncrease => 'Adjustment up',
    StockDocumentType.adjustmentDecrease => 'Adjustment down',
    StockDocumentType.reconciliation => 'Reconciliation',
    StockDocumentType.interLocationTransfer => 'Internal transfer',
  };

  static String _methodLabel(PaymentMethod method) => switch (method) {
    PaymentMethod.cash => 'Cash',
    PaymentMethod.bankTransfer => 'Bank transfer',
    PaymentMethod.cheque => 'Cheque',
    PaymentMethod.cardOrDigital => 'Card or digital',
    PaymentMethod.creditNote => 'Credit note',
    PaymentMethod.openingBalance => 'Opening balance',
  };

  static String _paymentStatusLabel(PaymentStatus status) => switch (status) {
    PaymentStatus.pending => 'Awaiting clearance',
    PaymentStatus.cleared => 'Cleared',
    PaymentStatus.bounced => 'Bounced',
    PaymentStatus.cancelled => 'Cancelled',
  };

  static String _returnReasonLabel(ReturnReason reason) => switch (reason) {
    ReturnReason.customerPaymentFailure => 'Customer payment failed',
    ReturnReason.defectiveItem => 'Defective',
    ReturnReason.damagedItem => 'Damaged in handling',
    ReturnReason.wrongProduct => 'Wrong product',
    ReturnReason.excessStock => 'Excess stock',
    ReturnReason.other => 'Other',
  };

  static String _returnStatusLabel(ReturnStatus status) => switch (status) {
    ReturnStatus.draft => 'Draft',
    ReturnStatus.posted => 'Awaiting inspection',
    ReturnStatus.inspected => 'Inspected',
    ReturnStatus.completed => 'Completed',
    ReturnStatus.cancelled => 'Cancelled',
  };

  static String _pettyCashKindLabel(PettyCashEntryKind kind) => switch (kind) {
    PettyCashEntryKind.opening => 'Opening float',
    PettyCashEntryKind.cashReceived => 'Cash in',
    PettyCashEntryKind.cashIssued => 'Cash out',
    PettyCashEntryKind.expense => 'Expense paid',
    PettyCashEntryKind.adjustment => 'Adjustment',
  };

  static String _salaryStatusLabel(SalaryStatus status) => switch (status) {
    SalaryStatus.draft => 'Draft',
    SalaryStatus.approved => 'Approved',
    SalaryStatus.partiallyPaid => 'Part paid',
    SalaryStatus.paid => 'Paid',
    SalaryStatus.cancelled => 'Cancelled',
  };
}
