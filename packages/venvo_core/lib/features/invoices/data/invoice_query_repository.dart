import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/enums/app_enums.dart';
import '../../../core/errors/guards.dart';
import '../../../core/utils/money.dart';
import '../domain/invoice_models.dart';
import 'package:json_annotation/json_annotation.dart';

part 'invoice_query_repository.g.dart';

/// Read-only views over invoices.
///
/// Every query computes settlement the same way: **cleared** payments and
/// posted credit notes reduce what is owed; pending cheques are reported in
/// their own column and reduce nothing. Keeping that definition in one place
/// is what stops the register, the party balance and the dashboard from
/// disagreeing.
class InvoiceQueryRepository {
  const InvoiceQueryRepository(this._db);

  final AppDatabase _db;

  /// The invoice register, newest first.
  Stream<List<InvoiceSummary>> watchInvoices(InvoiceFilter filter) {
    final search = filter.search.trim().toLowerCase();
    final pattern = '%$search%';
    final kindFilter = filter.kinds.isEmpty
        ? ''
        : 'AND i.kind IN '
              '(${filter.kinds.map((kind) => "'${kind.name}'").join(', ')})';

    final query = _db.customSelect(
      '''
      SELECT
        i.*,
        COALESCE(a.name, '') AS agent_name,
        COALESCE(s.name, '') AS shop_name,
        u.full_name AS created_by,
        approver.full_name AS discount_approved_by,
        st.document_number AS stock_document_number,
        COALESCE(cleared.total, 0) AS settled,
        COALESCE(credited.total, 0) AS credited,
        COALESCE(pending.total, 0) AS pending_cheques,
        (
          SELECT COUNT(*) FROM invoice_items ii WHERE ii.invoice_id = i.id
        ) AS line_count
      FROM invoices i
      LEFT JOIN agents a ON a.id = i.agent_id
      LEFT JOIN shops s ON s.id = i.shop_id
      JOIN users u ON u.id = i.created_by_user_id
      LEFT JOIN users approver ON approver.id = i.discount_approved_by_user_id
      LEFT JOIN stock_transactions st ON st.id = i.stock_transaction_id
      LEFT JOIN (
        SELECT pa.invoice_id, SUM(pa.amount_cents) AS total
        FROM payment_allocations pa
        JOIN payments p ON p.id = pa.payment_id
        WHERE p.status = ?
        GROUP BY pa.invoice_id
      ) cleared ON cleared.invoice_id = i.id
      LEFT JOIN (
        SELECT cna.invoice_id, SUM(cna.amount_cents) AS total
        FROM credit_note_applications cna
        JOIN credit_notes cn ON cn.id = cna.credit_note_id
        WHERE cn.status = ?
        GROUP BY cna.invoice_id
      ) credited ON credited.invoice_id = i.id
      LEFT JOIN (
        SELECT pa.invoice_id, SUM(pa.amount_cents) AS total
        FROM payment_allocations pa
        JOIN payments p ON p.id = pa.payment_id
        WHERE p.status = ?
        GROUP BY pa.invoice_id
      ) pending ON pending.invoice_id = i.id
      WHERE 1 = 1
        $kindFilter
        AND (? IS NULL OR i.status = ?)
        AND (? IS NULL OR i.agent_id = ?)
        AND (? IS NULL OR i.shop_id = ?)
        AND (? IS NULL OR i.invoice_date >= ?)
        AND (? IS NULL OR i.invoice_date <= ?)
        AND (? = '' OR LOWER(i.invoice_number) LIKE ?
             OR LOWER(COALESCE(a.name, '')) LIKE ?
             OR LOWER(COALESCE(s.name, '')) LIKE ?
             OR LOWER(COALESCE(i.customer_name, '')) LIKE ?)
        AND (? = 0 OR (i.status = ? AND i.net_total_cents
             - COALESCE(cleared.total, 0) - COALESCE(credited.total, 0) > 0))
        AND (? = 0 OR (i.status = ? AND i.due_date IS NOT NULL
             AND i.due_date < ? AND i.net_total_cents
             - COALESCE(cleared.total, 0) - COALESCE(credited.total, 0) > 0))
      ORDER BY i.invoice_date DESC, i.id DESC
      LIMIT ?
      ''',
      variables: [
        Variable<String>(PaymentStatus.cleared.name),
        Variable<String>(InvoiceStatus.posted.name),
        Variable<String>(PaymentStatus.pending.name),
        Variable<String>(filter.status?.name),
        Variable<String>(filter.status?.name),
        Variable<int>(filter.agentId),
        Variable<int>(filter.agentId),
        Variable<int>(filter.shopId),
        Variable<int>(filter.shopId),
        Variable<String>(_iso(filter.from)),
        Variable<String>(_iso(filter.from)),
        Variable<String>(_iso(filter.to)),
        Variable<String>(_iso(filter.to)),
        Variable<String>(search),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<int>(filter.unpaidOnly ? 1 : 0),
        Variable<String>(InvoiceStatus.posted.name),
        Variable<int>(filter.overdueOnly ? 1 : 0),
        Variable<String>(InvoiceStatus.posted.name),
        Variable<String>(DateTime.now().toUtc().toIso8601String()),
        Variable<int>(filter.limit),
      ],
      readsFrom: {
        _db.invoices,
        _db.invoiceItems,
        _db.agents,
        _db.shops,
        _db.users,
        _db.stockTransactions,
        _db.payments,
        _db.paymentAllocations,
        _db.creditNotes,
        _db.creditNoteApplications,
      },
    );

    final rows = query.watch().map(
      (rows) => rows.map(_mapSummary).toList(growable: false),
    );

    // The settlement filter is applied in memory, because it is derived from
    // several SQL aggregates and expressing it again in the WHERE clause
    // would mean two places that have to agree.
    final settlement = filter.settlement;
    if (settlement == null) return rows;
    return rows.map(
      (list) => list
          .where((invoice) => invoice.settlementStatus == settlement)
          .toList(growable: false),
    );
  }

  /// One invoice with its lines and the payments that touched it.
  Future<InvoiceDetail> invoiceDetail(int invoiceId) async {
    final header = requireFound(
      await (_db.select(
        _db.invoices,
      )..where((i) => i.id.equals(invoiceId))).getSingleOrNull(),
      'That invoice no longer exists.',
    );

    // Invoice numbers are unique, so searching for this one returns exactly
    // this row - and reuses the register's settlement arithmetic rather than
    // repeating it here, where the two could drift apart.
    final summary = (await watchInvoices(
      InvoiceFilter(search: header.invoiceNumber, limit: 1),
    ).first).single;

    final items =
        await (_db.select(_db.invoiceItems)
              ..where((i) => i.invoiceId.equals(invoiceId))
              ..orderBy([(i) => OrderingTerm.asc(i.lineNumber)]))
            .get();

    final paymentRows = await _db
        .customSelect(
          '''
      SELECT
        p.id AS payment_id,
        p.receipt_number,
        p.payment_date,
        p.method,
        p.status,
        SUM(pa.amount_cents) AS allocated,
        c.cheque_number,
        c.status AS cheque_status
      FROM payment_allocations pa
      JOIN payments p ON p.id = pa.payment_id
      LEFT JOIN cheques c ON c.payment_id = p.id
      WHERE pa.invoice_id = ?
      GROUP BY p.id
      HAVING SUM(pa.amount_cents) <> 0
      ORDER BY p.payment_date DESC, p.id DESC
      ''',
          variables: [Variable<int>(invoiceId)],
          readsFrom: {_db.paymentAllocations, _db.payments, _db.cheques},
        )
        .get();

    String? address;
    String? phone;
    if (header.shopId != null) {
      final shop = await (_db.select(
        _db.shops,
      )..where((s) => s.id.equals(header.shopId!))).getSingleOrNull();
      address = shop?.address;
      phone = shop?.phone;
    } else if (header.agentId != null) {
      final agent = await (_db.select(
        _db.agents,
      )..where((a) => a.id.equals(header.agentId!))).getSingleOrNull();
      address = agent?.address;
      phone = agent?.phone;
    } else {
      phone = header.customerPhone;
    }

    String? cancelledBy;
    if (header.cancelledByUserId != null) {
      cancelledBy =
          (await (_db.select(_db.users)
                    ..where((u) => u.id.equals(header.cancelledByUserId!)))
                  .getSingleOrNull())
              ?.fullName;
    }

    return InvoiceDetail(
      summary: summary,
      lines: items
          .map(
            (item) => InvoiceLine(
              lineNumber: item.lineNumber,
              productId: item.productId,
              productName: item.productNameSnapshot,
              sku: item.skuSnapshot,
              quantity: item.quantity,
              unitPrice: Money(item.unitPriceCents),
              gross: Money(item.grossCents),
              discountType: item.discountType,
              discountValue: item.discountValue,
              discount: Money(item.discountCents),
              net: Money(item.netCents),
              unitCost: Money(item.unitCostSnapshotCents),
              returnedQuantity: item.returnedQuantity,
              notes: item.notes,
            ),
          )
          .toList(growable: false),
      payments: paymentRows
          .map(
            (row) => InvoicePaymentLine(
              paymentId: row.read<int>('payment_id'),
              receiptNumber: row.read<String>('receipt_number'),
              paymentDate: row.read<DateTime>('payment_date'),
              method: PaymentMethod.values.byName(row.read<String>('method')),
              status: PaymentStatus.values.byName(row.read<String>('status')),
              allocated: Money(row.read<int>('allocated')),
              chequeNumber: row.readNullable<String>('cheque_number'),
              chequeStatus: row.readNullable<String>('cheque_status') == null
                  ? null
                  : ChequeStatus.values.byName(
                      row.read<String>('cheque_status'),
                    ),
            ),
          )
          .toList(growable: false),
      notes: header.notes,
      cancelReason: header.cancelReason,
      cancelledBy: cancelledBy,
      partyAddress: address,
      partyPhone: phone,
    );
  }

  /// Posted deliveries that have not been billed yet, so somebody can see
  /// what revenue is waiting to be recognised.
  Stream<List<UnbilledDelivery>> watchUnbilledDeliveries() {
    final billable = [
      StockDocumentType.warehouseToAgent,
      StockDocumentType.agentToShop,
      StockDocumentType.warehouseToShop,
    ].map((type) => "'${type.name}'").join(', ');

    final query = _db.customSelect(
      '''
      SELECT
        t.id,
        t.document_number,
        t.document_type,
        t.document_date,
        t.total_quantity,
        t.total_cents,
        src.name AS source_name,
        dest.name AS destination_name,
        a.name AS agent_name,
        s.name AS shop_name
      FROM stock_transactions t
      JOIN inventory_locations src ON src.id = t.source_location_id
      JOIN inventory_locations dest ON dest.id = t.destination_location_id
      LEFT JOIN agents a ON a.id = t.agent_id
      LEFT JOIN shops s ON s.id = t.shop_id
      WHERE t.status = ?
        AND t.document_type IN ($billable)
        AND NOT EXISTS (
          SELECT 1 FROM invoices i
          WHERE i.stock_transaction_id = t.id AND i.status <> ?
        )
      ORDER BY t.document_date DESC, t.id DESC
      ''',
      variables: [
        Variable<String>(StockDocumentStatus.posted.name),
        Variable<String>(InvoiceStatus.cancelled.name),
      ],
      readsFrom: {
        _db.stockTransactions,
        _db.inventoryLocations,
        _db.agents,
        _db.shops,
        _db.invoices,
      },
    );

    return query.watch().map(
      (rows) => rows
          .map(
            (row) => UnbilledDelivery(
              stockTransactionId: row.read<int>('id'),
              documentNumber: row.read<String>('document_number'),
              documentType: StockDocumentType.values.byName(
                row.read<String>('document_type'),
              ),
              documentDate: row.read<DateTime>('document_date'),
              totalQuantity: row.read<int>('total_quantity'),
              documentValue: Money(row.read<int>('total_cents')),
              sourceName: row.read<String>('source_name'),
              destinationName: row.read<String>('destination_name'),
              agentName: row.readNullable<String>('agent_name'),
              shopName: row.readNullable<String>('shop_name'),
            ),
          )
          .toList(growable: false),
    );
  }

  /// Totals for the register's summary bar and for the sales reports.
  Future<InvoiceTotalsSnapshot> totals(InvoiceFilter filter) async {
    final invoices = await watchInvoices(filter).first;
    final posted = invoices.where((invoice) => invoice.isPosted).toList();

    return InvoiceTotalsSnapshot(
      count: invoices.length,
      gross: posted.map((i) => i.gross).sum,
      discount: posted.map((i) => i.itemDiscount + i.invoiceDiscount).sum,
      net: posted.map((i) => i.net).sum,
      cost: posted.map((i) => i.cost).sum,
      settled: posted.map((i) => i.settled + i.creditApplied).sum,
      outstanding: posted.map((i) => i.outstanding).sum,
      pendingCheques: posted.map((i) => i.pendingCheques).sum,
      cancelledCount: invoices.where((i) => i.isCancelled).length,
    );
  }

  static InvoiceSummary _mapSummary(QueryRow row) {
    final kind = InvoiceKind.values.byName(row.read<String>('kind'));
    final agentName = row.read<String>('agent_name');
    final shopName = row.read<String>('shop_name');
    final customerName = row.readNullable<String>('customer_name');

    final partyName = switch (kind) {
      InvoiceKind.agentInvoice => agentName,
      InvoiceKind.shopInvoice => shopName,
      InvoiceKind.retailSale =>
        (customerName ?? '').isEmpty ? 'Walk-in customer' : customerName!,
    };

    return InvoiceSummary(
      id: row.read<int>('id'),
      invoiceNumber: row.read<String>('invoice_number'),
      kind: kind,
      status: InvoiceStatus.values.byName(row.read<String>('status')),
      invoiceDate: row.read<DateTime>('invoice_date'),
      dueDate: row.readNullable<DateTime>('due_date'),
      partyType: PartyType.values.byName(row.read<String>('party_type')),
      partyName: partyName.isEmpty ? 'Unknown' : partyName,
      agentId: row.readNullable<int>('agent_id'),
      shopId: row.readNullable<int>('shop_id'),
      agentName: agentName.isEmpty ? null : agentName,
      gross: Money(row.read<int>('gross_total_cents')),
      itemDiscount: Money(row.read<int>('item_discount_total_cents')),
      invoiceDiscount: Money(row.read<int>('invoice_discount_cents')),
      net: Money(row.read<int>('net_total_cents')),
      cost: Money(row.read<int>('cost_total_cents')),
      settled: Money(row.read<int>('settled')),
      creditApplied: Money(row.read<int>('credited')),
      pendingCheques: Money(row.read<int>('pending_cheques')),
      lineCount: row.read<int>('line_count'),
      createdBy: row.read<String>('created_by'),
      stockTransactionId: row.readNullable<int>('stock_transaction_id'),
      stockDocumentNumber: row.readNullable<String>('stock_document_number'),
      discountReason: row.readNullable<String>('discount_reason'),
      discountApprovedBy: row.readNullable<String>('discount_approved_by'),
    );
  }

  static String? _iso(DateTime? value) => value?.toUtc().toIso8601String();
}

/// A posted delivery with no invoice against it.
@JsonSerializable()
class UnbilledDelivery {
  const UnbilledDelivery({
    required this.stockTransactionId,
    required this.documentNumber,
    required this.documentType,
    required this.documentDate,
    required this.totalQuantity,
    required this.documentValue,
    required this.sourceName,
    required this.destinationName,
    this.agentName,
    this.shopName,
  });

  final int stockTransactionId;
  final String documentNumber;
  final StockDocumentType documentType;
  final DateTime documentDate;
  final int totalQuantity;

  /// What the delivery note said. Zero when it carried no prices, in which
  /// case billing it needs prices entered.
  final Money documentValue;
  final String sourceName;
  final String destinationName;
  final String? agentName;
  final String? shopName;

  String get partyName => shopName ?? agentName ?? destinationName;

  bool get needsPrices => documentValue.isZero;

  factory UnbilledDelivery.fromJson(Map<String, dynamic> json) =>
      _$UnbilledDeliveryFromJson(json);

  Map<String, dynamic> toJson() => _$UnbilledDeliveryToJson(this);
}

/// Aggregated figures over a filtered set of invoices.
@JsonSerializable()
class InvoiceTotalsSnapshot {
  const InvoiceTotalsSnapshot({
    required this.count,
    required this.gross,
    required this.discount,
    required this.net,
    required this.cost,
    required this.settled,
    required this.outstanding,
    required this.pendingCheques,
    required this.cancelledCount,
  });

  final int count;
  final Money gross;
  final Money discount;
  final Money net;
  final Money cost;
  final Money settled;
  final Money outstanding;
  final Money pendingCheques;
  final int cancelledCount;

  Money get grossProfit => net - cost;

  factory InvoiceTotalsSnapshot.fromJson(Map<String, dynamic> json) =>
      _$InvoiceTotalsSnapshotFromJson(json);

  Map<String, dynamic> toJson() => _$InvoiceTotalsSnapshotToJson(this);
}
