import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/enums/app_enums.dart';
import '../../../core/errors/guards.dart';
import '../../../core/utils/money.dart';
import '../domain/stock_models.dart';

/// Read-only views over the stock ledger and its balances.
///
/// Kept separate from the ledger service so that nothing which only reads
/// stock can accidentally reach a method that writes it.
class StockQueryRepository {
  const StockQueryRepository(this._db);

  final AppDatabase _db;

  /// One row per product, with its balance split by location kind.
  Stream<List<ProductStockRow>> watchProductStock(StockOverviewFilter filter) {
    final search = filter.search.trim().toLowerCase();
    final pattern = '%$search%';

    final query = _db.customSelect(
      '''
      SELECT
        p.id AS product_id,
        p.sku,
        p.name AS product_name,
        p.reorder_level,
        c.name AS category_name,
        COALESCE(stock.average_cost, p.cost_price_cents) AS average_cost,
        COALESCE(stock.warehouse_quantity, 0) AS warehouse_quantity,
        COALESCE(stock.agent_quantity, 0) AS agent_quantity,
        COALESCE(stock.shop_quantity, 0) AS shop_quantity,
        COALESCE(stock.damaged_quantity, 0) AS damaged_quantity,
        COALESCE(stock.in_transit_quantity, 0) AS in_transit_quantity
      FROM products p
      JOIN categories c ON c.id = p.category_id
      LEFT JOIN (
        SELECT
          sb.product_id,
          SUM(CASE WHEN l.kind = ? THEN sb.quantity ELSE 0 END)
            AS warehouse_quantity,
          SUM(CASE WHEN l.kind = ? THEN sb.quantity ELSE 0 END)
            AS agent_quantity,
          SUM(CASE WHEN l.kind = ? THEN sb.quantity ELSE 0 END)
            AS shop_quantity,
          SUM(CASE WHEN l.kind = ? THEN sb.quantity ELSE 0 END)
            AS damaged_quantity,
          SUM(CASE WHEN l.kind = ? THEN sb.quantity ELSE 0 END)
            AS in_transit_quantity,
          -- Weighted average across the real locations holding the product.
          CASE
            WHEN SUM(CASE WHEN l.kind IN (?, ?, ?) THEN sb.quantity ELSE 0 END) > 0
            THEN SUM(CASE WHEN l.kind IN (?, ?, ?)
                     THEN sb.quantity * sb.average_cost_cents ELSE 0 END)
                 / SUM(CASE WHEN l.kind IN (?, ?, ?) THEN sb.quantity ELSE 0 END)
            ELSE NULL
          END AS average_cost
        FROM stock_balances sb
        JOIN inventory_locations l ON l.id = sb.location_id
        GROUP BY sb.product_id
      ) stock ON stock.product_id = p.id
      WHERE p.status <> ?
        AND (? = '' OR LOWER(p.name) LIKE ? OR LOWER(p.sku) LIKE ?)
        AND (? IS NULL OR p.category_id = ?)
        AND (? = 0 OR (p.reorder_level > 0
             AND COALESCE(stock.warehouse_quantity, 0)
               + COALESCE(stock.agent_quantity, 0)
               + COALESCE(stock.shop_quantity, 0) <= p.reorder_level))
        AND (? = 0 OR COALESCE(stock.warehouse_quantity, 0)
               + COALESCE(stock.agent_quantity, 0)
               + COALESCE(stock.shop_quantity, 0)
               + COALESCE(stock.damaged_quantity, 0)
               + COALESCE(stock.in_transit_quantity, 0) <> 0)
      ORDER BY p.name
      ''',
      variables: [
        Variable<String>(LocationKind.warehouse.name),
        Variable<String>(LocationKind.agent.name),
        Variable<String>(LocationKind.shop.name),
        Variable<String>(LocationKind.damaged.name),
        Variable<String>(LocationKind.inTransit.name),
        // Three repetitions for the weighted-average expression.
        for (var i = 0; i < 3; i++) ...[
          Variable<String>(LocationKind.warehouse.name),
          Variable<String>(LocationKind.agent.name),
          Variable<String>(LocationKind.shop.name),
        ],
        Variable<String>(EntityStatus.archived.name),
        Variable<String>(search),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<int>(filter.categoryId),
        Variable<int>(filter.categoryId),
        Variable<int>(filter.lowStockOnly ? 1 : 0),
        Variable<int>(filter.hideZeroStock ? 1 : 0),
      ],
      readsFrom: {
        _db.products,
        _db.categories,
        _db.stockBalances,
        _db.inventoryLocations,
      },
    );

    return query.watch().map(
      (rows) => rows
          .map(
            (row) => ProductStockRow(
              productId: row.read<int>('product_id'),
              sku: row.read<String>('sku'),
              productName: row.read<String>('product_name'),
              categoryName: row.read<String>('category_name'),
              reorderLevel: row.read<int>('reorder_level'),
              averageCost: Money(row.read<int>('average_cost')),
              warehouseQuantity: row.read<int>('warehouse_quantity'),
              agentQuantity: row.read<int>('agent_quantity'),
              shopQuantity: row.read<int>('shop_quantity'),
              damagedQuantity: row.read<int>('damaged_quantity'),
              inTransitQuantity: row.read<int>('in_transit_quantity'),
            ),
          )
          .toList(growable: false),
    );
  }

  /// Everything one location is holding.
  Stream<List<StockBalanceRow>> watchLocationStock(
    int locationId, {
    String search = '',
    bool hideZero = true,
  }) {
    final cleanSearch = search.trim().toLowerCase();
    final pattern = '%$cleanSearch%';

    final query = _db.customSelect(
      '''
      SELECT
        sb.product_id,
        p.sku,
        p.name AS product_name,
        p.reorder_level,
        c.name AS category_name,
        sb.location_id,
        l.name AS location_name,
        l.kind AS location_kind,
        sb.quantity,
        sb.average_cost_cents
      FROM stock_balances sb
      JOIN products p ON p.id = sb.product_id
      JOIN categories c ON c.id = p.category_id
      JOIN inventory_locations l ON l.id = sb.location_id
      WHERE sb.location_id = ?
        AND (? = 0 OR sb.quantity <> 0)
        AND (? = '' OR LOWER(p.name) LIKE ? OR LOWER(p.sku) LIKE ?)
      ORDER BY p.name
      ''',
      variables: [
        Variable<int>(locationId),
        Variable<int>(hideZero ? 1 : 0),
        Variable<String>(cleanSearch),
        Variable<String>(pattern),
        Variable<String>(pattern),
      ],
      readsFrom: {
        _db.stockBalances,
        _db.products,
        _db.categories,
        _db.inventoryLocations,
      },
    );

    return query.watch().map(
      (rows) => rows.map(_mapBalanceRow).toList(growable: false),
    );
  }

  /// The stock ledger itself, newest first.
  Stream<List<StockLedgerRow>> watchLedger(StockLedgerFilter filter) {
    final search = filter.search.trim().toLowerCase();
    final pattern = '%$search%';
    final virtualKinds = [
      LocationKind.supplier,
      LocationKind.customer,
      LocationKind.adjustment,
      LocationKind.inTransit,
    ].map((kind) => "'${kind.name}'").join(', ');

    final query = _db.customSelect(
      '''
      SELECT
        e.id,
        e.occurred_at,
        e.quantity_delta,
        e.balance_after,
        e.unit_cost_cents,
        e.narration,
        e.product_id,
        t.document_number,
        t.document_type,
        t.status AS document_status,
        l.name AS location_name,
        l.kind AS location_kind,
        p.sku,
        p.name AS product_name,
        u.full_name AS recorded_by,
        CASE
          WHEN e.location_id = t.source_location_id THEN dest.name
          ELSE src.name
        END AS counterparty_name
      FROM stock_ledger_entries e
      JOIN stock_transactions t ON t.id = e.transaction_id
      JOIN inventory_locations l ON l.id = e.location_id
      JOIN inventory_locations src ON src.id = t.source_location_id
      JOIN inventory_locations dest ON dest.id = t.destination_location_id
      JOIN products p ON p.id = e.product_id
      JOIN users u ON u.id = e.recorded_by_user_id
      WHERE (? = 1 OR l.kind NOT IN ($virtualKinds))
        AND (? IS NULL OR e.product_id = ?)
        AND (? IS NULL OR e.location_id = ?)
        AND (? IS NULL OR e.occurred_at >= ?)
        AND (? IS NULL OR e.occurred_at <= ?)
        AND (? = '' OR LOWER(p.name) LIKE ? OR LOWER(p.sku) LIKE ?
             OR LOWER(t.document_number) LIKE ?)
      ORDER BY e.occurred_at DESC, e.id DESC
      LIMIT ?
      ''',
      variables: [
        Variable<int>(filter.includeVirtualLocations ? 1 : 0),
        Variable<int>(filter.productId),
        Variable<int>(filter.productId),
        Variable<int>(filter.locationId),
        Variable<int>(filter.locationId),
        Variable<String>(_iso(filter.from)),
        Variable<String>(_iso(filter.from)),
        Variable<String>(_iso(filter.to)),
        Variable<String>(_iso(filter.to)),
        Variable<String>(search),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<int>(filter.limit),
      ],
      readsFrom: {
        _db.stockLedgerEntries,
        _db.stockTransactions,
        _db.inventoryLocations,
        _db.products,
        _db.users,
      },
    );

    return query.watch().map(
      (rows) => rows
          .map(
            (row) => StockLedgerRow(
              id: row.read<int>('id'),
              occurredAt: row.read<DateTime>('occurred_at'),
              documentNumber: row.read<String>('document_number'),
              documentType: StockDocumentType.values.byName(
                row.read<String>('document_type'),
              ),
              documentStatus: StockDocumentStatus.values.byName(
                row.read<String>('document_status'),
              ),
              locationName: row.read<String>('location_name'),
              locationKind: LocationKind.values.byName(
                row.read<String>('location_kind'),
              ),
              productId: row.read<int>('product_id'),
              sku: row.read<String>('sku'),
              productName: row.read<String>('product_name'),
              quantityDelta: row.read<int>('quantity_delta'),
              balanceAfter: row.read<int>('balance_after'),
              unitCost: Money(row.read<int>('unit_cost_cents')),
              recordedBy: row.read<String>('recorded_by'),
              counterpartyName: row.readNullable<String>('counterparty_name'),
              narration: row.readNullable<String>('narration'),
            ),
          )
          .toList(growable: false),
    );
  }

  /// The stock document register, newest first.
  Stream<List<StockDocumentSummary>> watchDocuments(
    StockDocumentFilter filter,
  ) {
    final search = filter.search.trim().toLowerCase();
    final pattern = '%$search%';
    final typeFilter = filter.types.isEmpty
        ? ''
        : 'AND t.document_type IN '
              '(${filter.types.map((type) => "'${type.name}'").join(', ')})';

    final query = _db.customSelect(
      '''
      SELECT
        t.id,
        t.document_number,
        t.document_type,
        t.status,
        t.document_date,
        t.total_quantity,
        t.total_cents,
        t.reference_note,
        t.negative_stock_override,
        src.name AS source_name,
        dest.name AS destination_name,
        a.name AS agent_name,
        s.name AS shop_name,
        u.full_name AS created_by,
        original.document_number AS reverses_document_number,
        reversal.document_number AS reversed_by_document_number,
        (
          SELECT COUNT(*) FROM stock_transaction_items i
          WHERE i.transaction_id = t.id
        ) AS line_count
      FROM stock_transactions t
      JOIN inventory_locations src ON src.id = t.source_location_id
      JOIN inventory_locations dest ON dest.id = t.destination_location_id
      JOIN users u ON u.id = t.created_by_user_id
      LEFT JOIN agents a ON a.id = t.agent_id
      LEFT JOIN shops s ON s.id = t.shop_id
      LEFT JOIN stock_transactions original
        ON original.id = t.reverses_transaction_id
      LEFT JOIN stock_transactions reversal
        ON reversal.reverses_transaction_id = t.id
      WHERE 1 = 1
        $typeFilter
        AND (? IS NULL OR t.status = ?)
        AND (? IS NULL OR t.agent_id = ?)
        AND (? IS NULL OR t.shop_id = ?)
        AND (? IS NULL OR t.source_location_id = ?
             OR t.destination_location_id = ?)
        AND (? IS NULL OR t.document_date >= ?)
        AND (? IS NULL OR t.document_date <= ?)
        AND (? = '' OR LOWER(t.document_number) LIKE ?
             OR LOWER(COALESCE(t.reference_note, '')) LIKE ?
             OR LOWER(COALESCE(a.name, '')) LIKE ?
             OR LOWER(COALESCE(s.name, '')) LIKE ?)
      ORDER BY t.document_date DESC, t.id DESC
      LIMIT ?
      ''',
      variables: [
        Variable<String>(filter.status?.name),
        Variable<String>(filter.status?.name),
        Variable<int>(filter.agentId),
        Variable<int>(filter.agentId),
        Variable<int>(filter.shopId),
        Variable<int>(filter.shopId),
        Variable<int>(filter.locationId),
        Variable<int>(filter.locationId),
        Variable<int>(filter.locationId),
        Variable<String>(_iso(filter.from)),
        Variable<String>(_iso(filter.from)),
        Variable<String>(_iso(filter.to)),
        Variable<String>(_iso(filter.to)),
        Variable<String>(search),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<int>(filter.limit),
      ],
      readsFrom: {
        _db.stockTransactions,
        _db.stockTransactionItems,
        _db.inventoryLocations,
        _db.agents,
        _db.shops,
        _db.users,
      },
    );

    return query.watch().map(
      (rows) => rows.map(_mapDocumentSummary).toList(growable: false),
    );
  }

  /// One document with its lines.
  Future<StockDocumentDetail> documentDetail(int transactionId) async {
    final header = requireFound(
      await (_db.select(
        _db.stockTransactions,
      )..where((t) => t.id.equals(transactionId))).getSingleOrNull(),
      'That document no longer exists.',
    );

    final source = await (_db.select(
      _db.inventoryLocations,
    )..where((l) => l.id.equals(header.sourceLocationId))).getSingle();
    final destination = await (_db.select(
      _db.inventoryLocations,
    )..where((l) => l.id.equals(header.destinationLocationId))).getSingle();
    final createdBy = await (_db.select(
      _db.users,
    )..where((u) => u.id.equals(header.createdByUserId))).getSingle();

    String? agentName;
    if (header.agentId != null) {
      agentName = (await (_db.select(
        _db.agents,
      )..where((a) => a.id.equals(header.agentId!))).getSingleOrNull())?.name;
    }
    String? shopName;
    if (header.shopId != null) {
      shopName = (await (_db.select(
        _db.shops,
      )..where((s) => s.id.equals(header.shopId!))).getSingleOrNull())?.name;
    }
    String? cancelledBy;
    if (header.cancelledByUserId != null) {
      cancelledBy =
          (await (_db.select(_db.users)
                    ..where((u) => u.id.equals(header.cancelledByUserId!)))
                  .getSingleOrNull())
              ?.fullName;
    }
    String? reversesNumber;
    if (header.reversesTransactionId != null) {
      reversesNumber =
          (await (_db.select(_db.stockTransactions)
                    ..where((t) => t.id.equals(header.reversesTransactionId!)))
                  .getSingleOrNull())
              ?.documentNumber;
    }
    final reversal =
        await (_db.select(_db.stockTransactions)
              ..where((t) => t.reversesTransactionId.equals(transactionId)))
            .getSingleOrNull();

    final items =
        await (_db.select(_db.stockTransactionItems)
              ..where((i) => i.transactionId.equals(transactionId))
              ..orderBy([(i) => OrderingTerm.asc(i.lineNumber)]))
            .get();

    return StockDocumentDetail(
      summary: StockDocumentSummary(
        id: header.id,
        documentNumber: header.documentNumber,
        documentType: header.documentType,
        status: header.status,
        documentDate: header.documentDate,
        sourceName: source.name,
        destinationName: destination.name,
        totalQuantity: header.totalQuantity,
        lineCount: items.length,
        total: Money(header.totalCents),
        createdBy: createdBy.fullName,
        agentName: agentName,
        shopName: shopName,
        referenceNote: header.referenceNote,
        reversesDocumentNumber: reversesNumber,
        reversedByDocumentNumber: reversal?.documentNumber,
        hasNegativeOverride: header.negativeStockOverride,
      ),
      lines: items
          .map(
            (item) => StockDocumentLine(
              lineNumber: item.lineNumber,
              productId: item.productId,
              productName: item.productNameSnapshot,
              sku: item.skuSnapshot,
              quantity: item.quantity,
              unitCost: Money(item.unitCostCents),
              unitPrice: Money(item.unitPriceCents),
              discount: Money(item.discountCents),
              lineTotal: Money(item.lineTotalCents),
              notes: item.notes,
            ),
          )
          .toList(growable: false),
      notes: header.notes,
      cancelReason: header.cancelReason,
      overrideReason: header.overrideReason,
      cancelledBy: cancelledBy,
    );
  }

  /// Products a location is holding, for pre-filling a transfer or a count.
  Future<List<StockBalanceRow>> stockAtLocation(int locationId) {
    return watchLocationStock(locationId).first;
  }

  static StockBalanceRow _mapBalanceRow(QueryRow row) => StockBalanceRow(
    productId: row.read<int>('product_id'),
    sku: row.read<String>('sku'),
    productName: row.read<String>('product_name'),
    categoryName: row.read<String>('category_name'),
    locationId: row.read<int>('location_id'),
    locationName: row.read<String>('location_name'),
    locationKind: LocationKind.values.byName(row.read<String>('location_kind')),
    quantity: row.read<int>('quantity'),
    averageCost: Money(row.read<int>('average_cost_cents')),
    reorderLevel: row.read<int>('reorder_level'),
  );

  static StockDocumentSummary _mapDocumentSummary(QueryRow row) =>
      StockDocumentSummary(
        id: row.read<int>('id'),
        documentNumber: row.read<String>('document_number'),
        documentType: StockDocumentType.values.byName(
          row.read<String>('document_type'),
        ),
        status: StockDocumentStatus.values.byName(row.read<String>('status')),
        documentDate: row.read<DateTime>('document_date'),
        sourceName: row.read<String>('source_name'),
        destinationName: row.read<String>('destination_name'),
        totalQuantity: row.read<int>('total_quantity'),
        lineCount: row.read<int>('line_count'),
        total: Money(row.read<int>('total_cents')),
        createdBy: row.read<String>('created_by'),
        agentName: row.readNullable<String>('agent_name'),
        shopName: row.readNullable<String>('shop_name'),
        referenceNote: row.readNullable<String>('reference_note'),
        reversesDocumentNumber: row.readNullable<String>(
          'reverses_document_number',
        ),
        reversedByDocumentNumber: row.readNullable<String>(
          'reversed_by_document_number',
        ),
        hasNegativeOverride: row.read<bool>('negative_stock_override'),
      );

  static String? _iso(DateTime? value) => value?.toUtc().toIso8601String();
}
