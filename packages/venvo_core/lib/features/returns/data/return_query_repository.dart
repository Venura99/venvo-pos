import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/enums/app_enums.dart';
import '../../../core/errors/guards.dart';
import '../../../core/utils/money.dart';
import '../domain/return_models.dart';
import 'package:json_annotation/json_annotation.dart';

part 'return_query_repository.g.dart';

/// Read-only views over returns and credit notes.
///
/// Two definitions are kept in one place here so that no screen invents its
/// own: a return's **credited** total counts posted credit notes only, and a
/// credit note's **remaining** balance is its amount less the net of its
/// applications. A cancelled note contributes nothing to either.
class ReturnQueryRepository {
  const ReturnQueryRepository(this._db);

  final AppDatabase _db;

  /// The returns register, newest first.
  Stream<List<ReturnSummary>> watchReturns(ReturnFilter filter) {
    final search = filter.search.trim().toLowerCase();
    final pattern = '%$search%';
    final routeFilter = filter.routes.isEmpty
        ? ''
        : 'AND r.route IN '
              '(${filter.routes.map((route) => "'${route.name}'").join(', ')})';

    final query = _db.customSelect(
      '''
      SELECT
        r.*,
        src.name AS from_location_name,
        dst.name AS to_location_name,
        COALESCE(a.name, '') AS agent_name,
        COALESCE(s.name, '') AS shop_name,
        u.full_name AS created_by,
        inv.invoice_number AS origin_invoice_number,
        COALESCE(credited.total, 0) AS credited,
        credited.numbers AS credit_note_numbers,
        (
          SELECT COUNT(*) FROM return_items ri WHERE ri.return_id = r.id
        ) AS line_count,
        (
          SELECT COUNT(*) FROM return_items ri
          WHERE ri.return_id = r.id AND ri.inspection_status = ?
        ) AS pending_line_count
      FROM returns r
      JOIN inventory_locations src ON src.id = r.from_location_id
      JOIN inventory_locations dst ON dst.id = r.to_location_id
      LEFT JOIN agents a ON a.id = r.agent_id
      LEFT JOIN shops s ON s.id = r.shop_id
      JOIN users u ON u.id = r.created_by_user_id
      LEFT JOIN invoices inv ON inv.id = r.origin_invoice_id
      LEFT JOIN (
        SELECT cn.return_id,
               SUM(cn.amount_cents) AS total,
               GROUP_CONCAT(cn.credit_note_number) AS numbers
        FROM credit_notes cn
        WHERE cn.status = ? AND cn.return_id IS NOT NULL
        GROUP BY cn.return_id
      ) credited ON credited.return_id = r.id
      WHERE 1 = 1
        $routeFilter
        AND (? IS NULL OR r.status = ?)
        AND (? IS NULL OR r.reason = ?)
        AND (? IS NULL OR r.agent_id = ?)
        AND (? IS NULL OR r.shop_id = ?)
        AND (? IS NULL OR r.return_date >= ?)
        AND (? IS NULL OR r.return_date <= ?)
        AND (? = 0 OR r.status = ?)
        AND (? = '' OR LOWER(r.return_number) LIKE ?
             OR LOWER(COALESCE(inv.invoice_number, '')) LIKE ?
             OR LOWER(COALESCE(a.name, '')) LIKE ?
             OR LOWER(COALESCE(s.name, '')) LIKE ?
             OR LOWER(src.name) LIKE ?)
      ORDER BY r.return_date DESC, r.id DESC
      LIMIT ?
      ''',
      variables: [
        Variable<String>(InspectionStatus.pending.name),
        Variable<String>(InvoiceStatus.posted.name),
        Variable<String>(filter.status?.name),
        Variable<String>(filter.status?.name),
        Variable<String>(filter.reason?.name),
        Variable<String>(filter.reason?.name),
        Variable<int>(filter.agentId),
        Variable<int>(filter.agentId),
        Variable<int>(filter.shopId),
        Variable<int>(filter.shopId),
        Variable<String>(_iso(filter.from)),
        Variable<String>(_iso(filter.from)),
        Variable<String>(_iso(filter.to)),
        Variable<String>(_iso(filter.to)),
        Variable<int>(filter.pendingInspectionOnly ? 1 : 0),
        Variable<String>(ReturnStatus.posted.name),
        Variable<String>(search),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<int>(filter.limit),
      ],
      readsFrom: {
        _db.returnDocuments,
        _db.returnItems,
        _db.inventoryLocations,
        _db.agents,
        _db.shops,
        _db.users,
        _db.invoices,
        _db.creditNotes,
      },
    );

    return query.watch().map(
      (rows) => rows.map(_mapReturn).toList(growable: false),
    );
  }

  /// One return with its lines and any credit raised against it.
  Future<ReturnDetail> returnDetail(int returnId) async {
    final header = requireFound(
      await (_db.select(
        _db.returnDocuments,
      )..where((r) => r.id.equals(returnId))).getSingleOrNull(),
      'That return no longer exists.',
    );

    // Return numbers are unique, so this reuses the register's own arithmetic
    // rather than repeating it here where the two could drift apart.
    final summary = (await watchReturns(
      ReturnFilter(search: header.returnNumber, limit: 1),
    ).first).single;

    final lineRows = await _db
        .customSelect(
          '''
      SELECT ri.*, u.full_name AS inspected_by
      FROM return_items ri
      LEFT JOIN users u ON u.id = ri.inspected_by_user_id
      WHERE ri.return_id = ?
      ORDER BY ri.line_number
      ''',
          variables: [Variable<int>(returnId)],
          readsFrom: {_db.returnItems, _db.users},
        )
        .get();

    final creditNotes = await watchCreditNotes(const CreditNoteFilter()).first
        .then(
          (notes) => notes
              .where((note) => note.returnId == returnId)
              .toList(growable: false),
        );

    String? authorisedBy;
    if (header.authorisedByUserId != null) {
      final user =
          await (_db.select(_db.users)
                ..where((u) => u.id.equals(header.authorisedByUserId!)))
              .getSingleOrNull();
      authorisedBy = user?.fullName;
    }

    return ReturnDetail(
      summary: summary,
      lines: lineRows
          .map(
            (row) => ReturnLineView(
              id: row.read<int>('id'),
              lineNumber: row.read<int>('line_number'),
              productId: row.read<int>('product_id'),
              productName: row.read<String>('product_name_snapshot'),
              sku: row.read<String>('sku_snapshot'),
              quantity: row.read<int>('quantity'),
              unitPrice: Money(row.read<int>('unit_price_cents')),
              lineValue: Money(row.read<int>('line_value_cents')),
              inspectionStatus: InspectionStatus.values.byName(
                row.read<String>('inspection_status'),
              ),
              acceptedQuantity: row.read<int>('accepted_quantity'),
              damagedQuantity: row.read<int>('damaged_quantity'),
              scrappedQuantity: row.read<int>('scrapped_quantity'),
              inspectionNote: row.readNullable<String>('inspection_note'),
              inspectedBy: row.readNullable<String>('inspected_by'),
              inspectedAt: row.readNullable<DateTime>('inspected_at'),
              notes: row.readNullable<String>('notes'),
            ),
          )
          .toList(growable: false),
      creditNotes: creditNotes,
      notes: header.notes,
      cancelReason: header.cancelReason,
      authorisedBy: authorisedBy,
      receiptDocumentNumber: await _documentNumber(header.receiptTransactionId),
      dispositionDocumentNumber: await _documentNumber(
        header.dispositionTransactionId,
      ),
    );
  }

  /// Headline figures for the returns register, over the same filter.
  Future<ReturnTotals> returnTotals(ReturnFilter filter) async {
    final returns = await watchReturns(filter).first;
    return ReturnTotals(
      documentCount: returns.length,
      totalUnits: returns
          .where((r) => !r.isCancelled)
          .fold(0, (total, r) => total + r.totalQuantity),
      totalValue: returns
          .where((r) => !r.isCancelled)
          .map((r) => r.totalValue)
          .sum,
      awaitingInspection: returns.where((r) => r.awaitsInspection).length,
      creditedValue: returns.map((r) => r.creditedValue).sum,
    );
  }

  /// The credit note register, newest first.
  Stream<List<CreditNoteSummary>> watchCreditNotes(CreditNoteFilter filter) {
    final search = filter.search.trim().toLowerCase();
    final pattern = '%$search%';

    final query = _db.customSelect(
      '''
      SELECT
        cn.*,
        -- Follows party_type rather than whichever join happens to be
        -- non-null: a shop's return is routed through its agent, so both ids
        -- are set and COALESCE would show the wrong name.
        COALESCE(
          CASE cn.party_type
            WHEN 'shop' THEN s.name
            WHEN 'agent' THEN a.name
          END,
          s.name, a.name, 'Retail customer'
        ) AS party_name,
        u.full_name AS created_by,
        r.return_number,
        inv.invoice_number AS origin_invoice_number,
        COALESCE(applied.total, 0) AS applied_total
      FROM credit_notes cn
      LEFT JOIN agents a ON a.id = cn.agent_id
      LEFT JOIN shops s ON s.id = cn.shop_id
      JOIN users u ON u.id = cn.created_by_user_id
      LEFT JOIN returns r ON r.id = cn.return_id
      LEFT JOIN invoices inv ON inv.id = cn.origin_invoice_id
      LEFT JOIN (
        SELECT cna.credit_note_id, SUM(cna.amount_cents) AS total
        FROM credit_note_applications cna
        GROUP BY cna.credit_note_id
      ) applied ON applied.credit_note_id = cn.id
      WHERE 1 = 1
        AND (? IS NULL OR cn.status = ?)
        AND (? IS NULL OR cn.agent_id = ?)
        AND (? IS NULL OR cn.shop_id = ?)
        AND (? IS NULL OR cn.issue_date >= ?)
        AND (? IS NULL OR cn.issue_date <= ?)
        AND (? = 0 OR (cn.status = ?
             AND cn.amount_cents - COALESCE(applied.total, 0) > 0))
        AND (? = '' OR LOWER(cn.credit_note_number) LIKE ?
             OR LOWER(COALESCE(r.return_number, '')) LIKE ?
             OR LOWER(COALESCE(inv.invoice_number, '')) LIKE ?
             OR LOWER(COALESCE(a.name, '')) LIKE ?
             OR LOWER(COALESCE(s.name, '')) LIKE ?)
      ORDER BY cn.issue_date DESC, cn.id DESC
      LIMIT ?
      ''',
      variables: [
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
        Variable<int>(filter.withRemainingOnly ? 1 : 0),
        Variable<String>(InvoiceStatus.posted.name),
        Variable<String>(search),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<int>(filter.limit),
      ],
      readsFrom: {
        _db.creditNotes,
        _db.creditNoteApplications,
        _db.agents,
        _db.shops,
        _db.users,
        _db.returnDocuments,
        _db.invoices,
      },
    );

    return query.watch().map(
      (rows) => rows.map(_mapCreditNote).toList(growable: false),
    );
  }

  /// One credit note with everything it has been used for.
  Future<CreditNoteDetail> creditNoteDetail(int creditNoteId) async {
    final header = requireFound(
      await (_db.select(
        _db.creditNotes,
      )..where((c) => c.id.equals(creditNoteId))).getSingleOrNull(),
      'That credit note no longer exists.',
    );

    final summary = (await watchCreditNotes(
      CreditNoteFilter(search: header.creditNoteNumber, limit: 1),
    ).first).single;

    final rows = await _db
        .customSelect(
          '''
      SELECT cna.*, i.invoice_number, u.full_name AS applied_by
      FROM credit_note_applications cna
      JOIN invoices i ON i.id = cna.invoice_id
      JOIN users u ON u.id = cna.created_by_user_id
      WHERE cna.credit_note_id = ?
      ORDER BY cna.created_at DESC, cna.id DESC
      ''',
          variables: [Variable<int>(creditNoteId)],
          readsFrom: {_db.creditNoteApplications, _db.invoices, _db.users},
        )
        .get();

    return CreditNoteDetail(
      summary: summary,
      notes: header.notes,
      applications: rows
          .map(
            (row) => CreditNoteApplicationView(
              id: row.read<int>('id'),
              invoiceId: row.read<int>('invoice_id'),
              invoiceNumber: row.read<String>('invoice_number'),
              amount: Money(row.read<int>('amount_cents')),
              appliedAt: row.read<DateTime>('created_at'),
              appliedBy: row.read<String>('applied_by'),
            ),
          )
          .toList(growable: false),
    );
  }

  /// Unapplied credit held for a party, which a collection screen can offset
  /// before asking for money.
  Future<Money> availableCredit({int? agentId, int? shopId}) async {
    final row = await _db
        .customSelect(
          '''
      SELECT COALESCE(SUM(cn.amount_cents - cn.applied_cents), 0) AS available
      FROM credit_notes cn
      WHERE cn.status = ?
        AND (? IS NULL OR cn.agent_id = ?)
        AND (? IS NULL OR cn.shop_id = ?)
      ''',
          variables: [
            Variable<String>(InvoiceStatus.posted.name),
            Variable<int>(agentId),
            Variable<int>(agentId),
            Variable<int>(shopId),
            Variable<int>(shopId),
          ],
          readsFrom: {_db.creditNotes},
        )
        .getSingle();
    return Money(row.read<int>('available'));
  }

  Future<String?> _documentNumber(int? transactionId) async {
    if (transactionId == null) return null;
    final row = await (_db.select(
      _db.stockTransactions,
    )..where((t) => t.id.equals(transactionId))).getSingleOrNull();
    return row?.documentNumber;
  }

  static ReturnSummary _mapReturn(QueryRow row) {
    final agentName = row.read<String>('agent_name');
    final shopName = row.read<String>('shop_name');
    final numbers = row.readNullable<String>('credit_note_numbers');

    return ReturnSummary(
      id: row.read<int>('id'),
      returnNumber: row.read<String>('return_number'),
      route: ReturnRoute.values.byName(row.read<String>('route')),
      status: ReturnStatus.values.byName(row.read<String>('status')),
      returnDate: row.read<DateTime>('return_date'),
      reason: ReturnReason.values.byName(row.read<String>('reason')),
      fromLocationName: row.read<String>('from_location_name'),
      toLocationName: row.read<String>('to_location_name'),
      totalQuantity: row.read<int>('total_quantity'),
      totalValue: Money(row.read<int>('total_value_cents')),
      pendingLineCount: row.read<int>('pending_line_count'),
      lineCount: row.read<int>('line_count'),
      createdBy: row.read<String>('created_by'),
      creditedValue: Money(row.read<int>('credited')),
      agentName: agentName.isEmpty ? null : agentName,
      shopName: shopName.isEmpty ? null : shopName,
      originInvoiceNumber: row.readNullable<String>('origin_invoice_number'),
      reasonNote: row.readNullable<String>('reason_note'),
      creditNoteNumber: numbers,
    );
  }

  static CreditNoteSummary _mapCreditNote(QueryRow row) {
    return CreditNoteSummary(
      id: row.read<int>('id'),
      creditNoteNumber: row.read<String>('credit_note_number'),
      status: InvoiceStatus.values.byName(row.read<String>('status')),
      issueDate: row.read<DateTime>('issue_date'),
      partyType: PartyType.values.byName(row.read<String>('party_type')),
      partyName: row.read<String>('party_name'),
      amount: Money(row.read<int>('amount_cents')),
      applied: Money(row.read<int>('applied_total')),
      createdBy: row.read<String>('created_by'),
      agentId: row.readNullable<int>('agent_id'),
      shopId: row.readNullable<int>('shop_id'),
      returnNumber: row.readNullable<String>('return_number'),
      returnId: row.readNullable<int>('return_id'),
      originInvoiceNumber: row.readNullable<String>('origin_invoice_number'),
      originInvoiceId: row.readNullable<int>('origin_invoice_id'),
      reason: row.readNullable<String>('reason'),
      cancelReason: row.readNullable<String>('cancel_reason'),
    );
  }

  static String? _iso(DateTime? value) => value?.toUtc().toIso8601String();
}

/// Headline figures over the returns register.
@JsonSerializable()
class ReturnTotals {
  const ReturnTotals({
    required this.documentCount,
    required this.totalUnits,
    required this.totalValue,
    required this.awaitingInspection,
    required this.creditedValue,
  });

  static const ReturnTotals empty = ReturnTotals(
    documentCount: 0,
    totalUnits: 0,
    totalValue: Money.zero,
    awaitingInspection: 0,
    creditedValue: Money.zero,
  );

  final int documentCount;
  final int totalUnits;
  final Money totalValue;

  /// Returns whose goods are still sitting in transit, uninspected.
  final int awaitingInspection;

  final Money creditedValue;

  factory ReturnTotals.fromJson(Map<String, dynamic> json) =>
      _$ReturnTotalsFromJson(json);

  Map<String, dynamic> toJson() => _$ReturnTotalsToJson(this);
}
