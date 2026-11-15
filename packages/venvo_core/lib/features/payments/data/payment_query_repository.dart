import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/enums/app_enums.dart';
import '../../../core/utils/money.dart';
import '../domain/payment_models.dart';
import 'package:json_annotation/json_annotation.dart';

part 'payment_query_repository.g.dart';

/// Read-only views over payments and cheques.
class PaymentQueryRepository {
  const PaymentQueryRepository(this._db);

  final AppDatabase _db;

  /// The payment register, newest first.
  Stream<List<PaymentSummary>> watchPayments(PaymentFilter filter) {
    final search = filter.search.trim().toLowerCase();
    final pattern = '%$search%';

    final query = _db.customSelect(
      '''
      SELECT
        p.*,
        COALESCE(a.name, '') AS agent_name,
        COALESCE(s.name, '') AS shop_name,
        COALESCE(e.name, '') AS employee_name,
        u.full_name AS created_by,
        c.id AS cheque_id,
        c.cheque_number,
        c.status AS cheque_status,
        c.cheque_date,
        (
          SELECT GROUP_CONCAT(i.invoice_number, ', ')
          FROM payment_allocations pa
          JOIN invoices i ON i.id = pa.invoice_id
          WHERE pa.payment_id = p.id AND pa.amount_cents > 0
        ) AS invoice_numbers
      FROM payments p
      LEFT JOIN agents a ON a.id = p.agent_id
      LEFT JOIN shops s ON s.id = p.shop_id
      LEFT JOIN employees e ON e.id = p.employee_id
      JOIN users u ON u.id = p.created_by_user_id
      LEFT JOIN cheques c ON c.payment_id = p.id
      WHERE (? IS NULL OR p.direction = ?)
        AND (? IS NULL OR p.method = ?)
        AND (? IS NULL OR p.status = ?)
        AND (? IS NULL OR p.agent_id = ?)
        AND (? IS NULL OR p.shop_id = ?)
        AND (? IS NULL OR p.payment_date >= ?)
        AND (? IS NULL OR p.payment_date <= ?)
        AND (? = 0 OR (p.direction = ? AND p.amount_cents > p.allocated_cents))
        AND (? = '' OR LOWER(p.receipt_number) LIKE ?
             OR LOWER(COALESCE(p.reference_number, '')) LIKE ?
             OR LOWER(COALESCE(c.cheque_number, '')) LIKE ?
             OR LOWER(COALESCE(a.name, '')) LIKE ?
             OR LOWER(COALESCE(s.name, '')) LIKE ?
             OR LOWER(COALESCE(p.payer_name, '')) LIKE ?)
      ORDER BY p.payment_date DESC, p.id DESC
      LIMIT ?
      ''',
      variables: [
        Variable<String>(filter.direction?.name),
        Variable<String>(filter.direction?.name),
        Variable<String>(filter.method?.name),
        Variable<String>(filter.method?.name),
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
        Variable<int>(filter.advancesOnly ? 1 : 0),
        Variable<String>(PaymentDirection.inbound.name),
        Variable<String>(search),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<int>(filter.limit),
      ],
      readsFrom: {
        _db.payments,
        _db.paymentAllocations,
        _db.invoices,
        _db.agents,
        _db.shops,
        _db.employees,
        _db.users,
        _db.cheques,
      },
    );

    return query.watch().map(
      (rows) => rows.map(_mapPayment).toList(growable: false),
    );
  }

  /// The cheque register, with the oldest outstanding first so what needs
  /// chasing is at the top.
  Stream<List<ChequeSummary>> watchCheques(ChequeFilter filter) {
    final search = filter.search.trim().toLowerCase();
    final pattern = '%$search%';
    final statusFilter = filter.statuses.isEmpty
        ? ''
        : 'AND c.status IN '
              '(${filter.statuses.map((s) => "'${s.name}'").join(', ')})';
    final now = DateTime.now().toUtc().toIso8601String();

    final query = _db.customSelect(
      '''
      SELECT
        c.*,
        p.receipt_number,
        p.amount_cents,
        p.payment_date,
        COALESCE(a.name, COALESCE(s.name, COALESCE(p.payer_name, ''))) AS party_name,
        replacement.receipt_number AS replacement_receipt_number,
        (
          SELECT GROUP_CONCAT(i.invoice_number, ', ')
          FROM payment_allocations pa
          JOIN invoices i ON i.id = pa.invoice_id
          WHERE pa.payment_id = p.id AND pa.amount_cents > 0
        ) AS invoice_numbers
      FROM cheques c
      JOIN payments p ON p.id = c.payment_id
      LEFT JOIN agents a ON a.id = p.agent_id
      LEFT JOIN shops s ON s.id = p.shop_id
      LEFT JOIN payments replacement ON replacement.id = c.replacement_payment_id
      WHERE 1 = 1
        $statusFilter
        AND (? IS NULL OR c.cheque_date >= ?)
        AND (? IS NULL OR c.cheque_date <= ?)
        AND (? = 0 OR (c.status = ? AND c.cheque_date <= ?))
        AND (? = '' OR LOWER(c.cheque_number) LIKE ?
             OR LOWER(c.bank_name) LIKE ?
             OR LOWER(p.receipt_number) LIKE ?
             OR LOWER(COALESCE(a.name, '')) LIKE ?
             OR LOWER(COALESCE(s.name, '')) LIKE ?)
      ORDER BY
        CASE c.status
          WHEN 'pending' THEN 0
          WHEN 'deposited' THEN 1
          WHEN 'bounced' THEN 2
          ELSE 3
        END,
        c.cheque_date,
        c.id
      LIMIT ?
      ''',
      variables: [
        Variable<String>(_iso(filter.from)),
        Variable<String>(_iso(filter.from)),
        Variable<String>(_iso(filter.to)),
        Variable<String>(_iso(filter.to)),
        Variable<int>(filter.bankableOnly ? 1 : 0),
        Variable<String>(ChequeStatus.pending.name),
        Variable<String>(now),
        Variable<String>(search),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<int>(filter.limit),
      ],
      readsFrom: {
        _db.cheques,
        _db.payments,
        _db.paymentAllocations,
        _db.invoices,
        _db.agents,
        _db.shops,
      },
    );

    return query.watch().map(
      (rows) => rows.map(_mapCheque).toList(growable: false),
    );
  }

  /// Totals for the payment register's summary bar.
  Future<PaymentTotalsSnapshot> paymentTotals(PaymentFilter filter) async {
    final payments = await watchPayments(filter).first;
    final cleared = payments
        .where((payment) => payment.isCleared)
        .toList(growable: false);

    return PaymentTotalsSnapshot(
      count: payments.length,
      clearedIn: cleared
          .where((p) => p.direction == PaymentDirection.inbound)
          .map((p) => p.amount)
          .sum,
      clearedOut: cleared
          .where((p) => p.direction == PaymentDirection.outbound)
          .map((p) => p.amount)
          .sum,
      pending: payments
          .where((payment) => payment.isPending)
          .map((payment) => payment.amount)
          .sum,
      bounced: payments
          .where((payment) => payment.isBounced)
          .map((payment) => payment.amount)
          .sum,
      advances: payments
          .where((payment) => payment.isCleared && payment.isAdvance)
          .map((payment) => payment.unallocated)
          .sum,
    );
  }

  /// Totals for the cheque register's summary bar.
  Future<ChequeTotalsSnapshot> chequeTotals(ChequeFilter filter) async {
    final cheques = await watchCheques(filter).first;
    final now = DateTime.now().toUtc();

    return ChequeTotalsSnapshot(
      count: cheques.length,
      outstanding: cheques
          .where((cheque) => cheque.isOutstanding)
          .map((cheque) => cheque.amount)
          .sum,
      cleared: cheques
          .where((cheque) => cheque.isCleared)
          .map((cheque) => cheque.amount)
          .sum,
      bounced: cheques
          .where((cheque) => cheque.isBounced)
          .map((cheque) => cheque.amount)
          .sum,
      bankableCount: cheques.where((cheque) => cheque.isBankable(now)).length,
      postDatedCount: cheques.where((cheque) => cheque.isPostDated(now)).length,
    );
  }

  static PaymentSummary _mapPayment(QueryRow row) {
    final partyType = PartyType.values.byName(row.read<String>('party_type'));
    final agentName = row.read<String>('agent_name');
    final shopName = row.read<String>('shop_name');
    final employeeName = row.read<String>('employee_name');
    final payerName = row.readNullable<String>('payer_name');

    final partyName = switch (partyType) {
      PartyType.agent => agentName,
      PartyType.shop => shopName,
      PartyType.employee => employeeName,
      _ => payerName ?? '',
    };

    final chequeStatus = row.readNullable<String>('cheque_status');
    final invoiceNumbers = row.readNullable<String>('invoice_numbers');

    return PaymentSummary(
      id: row.read<int>('id'),
      receiptNumber: row.read<String>('receipt_number'),
      direction: PaymentDirection.values.byName(row.read<String>('direction')),
      method: PaymentMethod.values.byName(row.read<String>('method')),
      status: PaymentStatus.values.byName(row.read<String>('status')),
      paymentDate: row.read<DateTime>('payment_date'),
      partyType: partyType,
      partyName: partyName.isEmpty ? 'Walk-in' : partyName,
      agentId: row.readNullable<int>('agent_id'),
      shopId: row.readNullable<int>('shop_id'),
      amount: Money(row.read<int>('amount_cents')),
      allocated: Money(row.read<int>('allocated_cents')),
      createdBy: row.read<String>('created_by'),
      bankName: row.readNullable<String>('bank_name'),
      referenceNumber: row.readNullable<String>('reference_number'),
      chequeId: row.readNullable<int>('cheque_id'),
      chequeNumber: row.readNullable<String>('cheque_number'),
      chequeStatus: chequeStatus == null
          ? null
          : ChequeStatus.values.byName(chequeStatus),
      chequeDate: row.readNullable<DateTime>('cheque_date'),
      clearedAt: row.readNullable<DateTime>('cleared_at'),
      bouncedAt: row.readNullable<DateTime>('bounced_at'),
      invoiceNumbers: invoiceNumbers == null || invoiceNumbers.isEmpty
          ? const []
          : invoiceNumbers.split(', '),
    );
  }

  static ChequeSummary _mapCheque(QueryRow row) {
    final invoiceNumbers = row.readNullable<String>('invoice_numbers');

    return ChequeSummary(
      id: row.read<int>('id'),
      paymentId: row.read<int>('payment_id'),
      receiptNumber: row.read<String>('receipt_number'),
      chequeNumber: row.read<String>('cheque_number'),
      bankName: row.read<String>('bank_name'),
      branchName: row.readNullable<String>('branch_name'),
      chequeDate: row.read<DateTime>('cheque_date'),
      status: ChequeStatus.values.byName(row.read<String>('status')),
      amount: Money(row.read<int>('amount_cents')),
      partyName: row.read<String>('party_name').isEmpty
          ? 'Walk-in'
          : row.read<String>('party_name'),
      receivedOn: row.read<DateTime>('payment_date'),
      depositedAt: row.readNullable<DateTime>('deposited_at'),
      clearedAt: row.readNullable<DateTime>('cleared_at'),
      bouncedAt: row.readNullable<DateTime>('bounced_at'),
      bounceReason: row.readNullable<String>('bounce_reason'),
      bounceCharge: Money(row.read<int>('bounce_charge_cents')),
      replacementReceiptNumber: row.readNullable<String>(
        'replacement_receipt_number',
      ),
      invoiceNumbers: invoiceNumbers == null || invoiceNumbers.isEmpty
          ? const []
          : invoiceNumbers.split(', '),
    );
  }

  static String? _iso(DateTime? value) => value?.toUtc().toIso8601String();
}

/// Aggregated figures over a filtered set of payments.
@JsonSerializable()
class PaymentTotalsSnapshot {
  const PaymentTotalsSnapshot({
    required this.count,
    required this.clearedIn,
    required this.clearedOut,
    required this.pending,
    required this.bounced,
    required this.advances,
  });

  final int count;

  /// Money actually received: cleared inbound payments only.
  final Money clearedIn;
  final Money clearedOut;

  /// Promised but not yet cleared, which is almost always cheques.
  final Money pending;
  final Money bounced;
  final Money advances;

  Money get netCleared => clearedIn - clearedOut;

  factory PaymentTotalsSnapshot.fromJson(Map<String, dynamic> json) =>
      _$PaymentTotalsSnapshotFromJson(json);

  Map<String, dynamic> toJson() => _$PaymentTotalsSnapshotToJson(this);
}

/// Aggregated figures over a filtered set of cheques.
@JsonSerializable()
class ChequeTotalsSnapshot {
  const ChequeTotalsSnapshot({
    required this.count,
    required this.outstanding,
    required this.cleared,
    required this.bounced,
    required this.bankableCount,
    required this.postDatedCount,
  });

  final int count;

  /// Pending plus deposited: cheques that are neither cash nor failures yet.
  final Money outstanding;
  final Money cleared;
  final Money bounced;

  /// How many can go to the bank today.
  final int bankableCount;
  final int postDatedCount;

  factory ChequeTotalsSnapshot.fromJson(Map<String, dynamic> json) =>
      _$ChequeTotalsSnapshotFromJson(json);

  Map<String, dynamic> toJson() => _$ChequeTotalsSnapshotToJson(this);
}
