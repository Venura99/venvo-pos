import '../../../core/enums/app_enums.dart';
import '../../../core/utils/money.dart';
import 'package:json_annotation/json_annotation.dart';

part 'payment_models.g.dart';

/// Cheque details, required when a payment is made by cheque.
@JsonSerializable()
class ChequeDetails {
  const ChequeDetails({
    required this.chequeNumber,
    required this.bankName,
    required this.chequeDate,
    this.branchName,
  });

  final String chequeNumber;
  final String bankName;

  /// The date written on the cheque, which may be later than the date it was
  /// received. A post-dated cheque is still only a promise until it clears.
  final DateTime chequeDate;
  final String? branchName;

  bool isPostDated(DateTime asOf) => chequeDate.isAfter(asOf);

  factory ChequeDetails.fromJson(Map<String, dynamic> json) =>
      _$ChequeDetailsFromJson(json);

  Map<String, dynamic> toJson() => _$ChequeDetailsToJson(this);
}

/// Applying part of a payment to one invoice.
@JsonSerializable()
class PaymentAllocationRequest {
  const PaymentAllocationRequest({
    required this.invoiceId,
    required this.amount,
    this.notes,
  });

  final int invoiceId;
  final Money amount;
  final String? notes;

  factory PaymentAllocationRequest.fromJson(Map<String, dynamic> json) =>
      _$PaymentAllocationRequestFromJson(json);

  Map<String, dynamic> toJson() => _$PaymentAllocationRequestToJson(this);
}

/// A request to record money moving.
@JsonSerializable()
class PaymentRequest {
  const PaymentRequest({
    required this.direction,
    required this.method,
    required this.amount,
    this.partyType,
    this.agentId,
    this.shopId,
    this.employeeId,
    this.payerName,
    this.paymentDate,
    this.bankName,
    this.referenceNumber,
    this.notes,
    this.allocations = const [],
    this.cheque,
  });

  final PaymentDirection direction;
  final PaymentMethod method;

  /// Always positive. Direction says which way it went.
  final Money amount;

  final PartyType? partyType;
  final int? agentId;
  final int? shopId;
  final int? employeeId;

  /// For a walk-in payer with no party record.
  final String? payerName;

  final DateTime? paymentDate;
  final String? bankName;
  final String? referenceNumber;
  final String? notes;

  /// Invoices this money settles. May be empty: unallocated inbound money is
  /// the party's advance, which is a legitimate state and not an error.
  final List<PaymentAllocationRequest> allocations;

  final ChequeDetails? cheque;

  Money get allocatedTotal => allocations.map((a) => a.amount).sum;

  Money get unallocated => amount - allocatedTotal;

  /// Cash, bank transfers and card payments are money in hand the moment they
  /// are recorded. A cheque is a promise, so it starts pending and has to be
  /// cleared explicitly.
  PaymentStatus get initialStatus => method == PaymentMethod.cheque
      ? PaymentStatus.pending
      : PaymentStatus.cleared;

  factory PaymentRequest.fromJson(Map<String, dynamic> json) =>
      _$PaymentRequestFromJson(json);

  Map<String, dynamic> toJson() => _$PaymentRequestToJson(this);
}

/// What recording a payment produced.
@JsonSerializable()
class PaymentResult {
  const PaymentResult({
    required this.paymentId,
    required this.receiptNumber,
    required this.status,
    required this.amount,
    required this.allocated,
    this.chequeId,
  });

  final int paymentId;
  final String receiptNumber;
  final PaymentStatus status;
  final Money amount;
  final Money allocated;
  final int? chequeId;

  Money get unallocated => amount - allocated;

  bool get isPending => status == PaymentStatus.pending;

  factory PaymentResult.fromJson(Map<String, dynamic> json) =>
      _$PaymentResultFromJson(json);

  Map<String, dynamic> toJson() => _$PaymentResultToJson(this);
}

/// A payment as the register lists it.
@JsonSerializable()
class PaymentSummary {
  const PaymentSummary({
    required this.id,
    required this.receiptNumber,
    required this.direction,
    required this.method,
    required this.status,
    required this.paymentDate,
    required this.partyType,
    required this.partyName,
    required this.amount,
    required this.allocated,
    required this.createdBy,
    this.agentId,
    this.shopId,
    this.bankName,
    this.referenceNumber,
    this.chequeId,
    this.chequeNumber,
    this.chequeStatus,
    this.chequeDate,
    this.clearedAt,
    this.bouncedAt,
    this.invoiceNumbers = const [],
  });

  final int id;
  final String receiptNumber;
  final PaymentDirection direction;
  final PaymentMethod method;
  final PaymentStatus status;
  final DateTime paymentDate;
  final PartyType partyType;
  final String partyName;
  final int? agentId;
  final int? shopId;

  final Money amount;

  /// Sum of this payment's allocations, including any that are pending.
  final Money allocated;

  final String createdBy;
  final String? bankName;
  final String? referenceNumber;

  final int? chequeId;
  final String? chequeNumber;
  final ChequeStatus? chequeStatus;
  final DateTime? chequeDate;
  final DateTime? clearedAt;
  final DateTime? bouncedAt;

  /// The invoices this payment was applied to.
  final List<String> invoiceNumbers;

  Money get unallocated => amount - allocated;

  /// True while the money is only a promise.
  bool get isPending => status == PaymentStatus.pending;
  bool get isCleared => status == PaymentStatus.cleared;
  bool get isBounced => status == PaymentStatus.bounced;
  bool get isCancelled => status == PaymentStatus.cancelled;

  bool get isCheque => method == PaymentMethod.cheque;

  /// Money received and not applied to anything is the party's advance.
  bool get isAdvance =>
      direction == PaymentDirection.inbound && unallocated.isPositive;

  /// A cheque dated in the future cannot be banked yet.
  bool isPostDated(DateTime asOf) =>
      chequeDate != null && chequeDate!.isAfter(asOf);

  factory PaymentSummary.fromJson(Map<String, dynamic> json) =>
      _$PaymentSummaryFromJson(json);

  Map<String, dynamic> toJson() => _$PaymentSummaryToJson(this);
}

/// A cheque as the cheque register lists it.
@JsonSerializable()
class ChequeSummary {
  const ChequeSummary({
    required this.id,
    required this.paymentId,
    required this.receiptNumber,
    required this.chequeNumber,
    required this.bankName,
    required this.chequeDate,
    required this.status,
    required this.amount,
    required this.partyName,
    required this.receivedOn,
    this.branchName,
    this.depositedAt,
    this.clearedAt,
    this.bouncedAt,
    this.bounceReason,
    this.bounceCharge = Money.zero,
    this.replacementReceiptNumber,
    this.invoiceNumbers = const [],
  });

  final int id;
  final int paymentId;
  final String receiptNumber;
  final String chequeNumber;
  final String bankName;
  final String? branchName;
  final DateTime chequeDate;
  final ChequeStatus status;
  final Money amount;
  final String partyName;
  final DateTime receivedOn;

  final DateTime? depositedAt;
  final DateTime? clearedAt;
  final DateTime? bouncedAt;
  final String? bounceReason;
  final Money bounceCharge;
  final String? replacementReceiptNumber;
  final List<String> invoiceNumbers;

  /// Still waiting: neither cleared nor failed.
  bool get isOutstanding =>
      status == ChequeStatus.pending || status == ChequeStatus.deposited;

  bool get isCleared => status == ChequeStatus.cleared;
  bool get isBounced => status == ChequeStatus.bounced;

  /// Cannot be banked before the date written on it.
  bool isPostDated(DateTime asOf) => chequeDate.isAfter(asOf);

  /// Ready to bank: pending and no longer post-dated.
  bool isBankable(DateTime asOf) =>
      status == ChequeStatus.pending && !isPostDated(asOf);

  /// Days since it was deposited, for chasing the bank.
  int? daysSinceDeposit(DateTime asOf) {
    final deposited = depositedAt;
    return deposited == null ? null : asOf.difference(deposited).inDays;
  }

  factory ChequeSummary.fromJson(Map<String, dynamic> json) =>
      _$ChequeSummaryFromJson(json);

  Map<String, dynamic> toJson() => _$ChequeSummaryToJson(this);
}

/// An invoice awaiting settlement, as the allocation picker shows it.
@JsonSerializable()
class AllocatableInvoice {
  const AllocatableInvoice({
    required this.invoiceId,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.net,
    required this.outstanding,
    required this.allocatable,
    required this.pendingCheques,
    this.dueDate,
  });

  final int invoiceId;
  final String invoiceNumber;
  final DateTime invoiceDate;
  final DateTime? dueDate;
  final Money net;

  /// What is still owed, counting cleared money only.
  final Money outstanding;

  /// What may still be allocated. Lower than [outstanding] when a pending
  /// cheque has already been promised against this invoice, so the same
  /// invoice is not allocated twice.
  final Money allocatable;

  final Money pendingCheques;

  bool get hasPendingCheques => !pendingCheques.isZero;

  factory AllocatableInvoice.fromJson(Map<String, dynamic> json) =>
      _$AllocatableInvoiceFromJson(json);

  Map<String, dynamic> toJson() => _$AllocatableInvoiceToJson(this);
}

/// How the payment register is narrowed.
@JsonSerializable()
class PaymentFilter {
  const PaymentFilter({
    this.search = '',
    this.direction,
    this.method,
    this.status,
    this.agentId,
    this.shopId,
    this.from,
    this.to,
    this.advancesOnly = false,
    this.limit = 300,
  });

  final String search;
  final PaymentDirection? direction;
  final PaymentMethod? method;
  final PaymentStatus? status;
  final int? agentId;
  final int? shopId;
  final DateTime? from;
  final DateTime? to;

  /// Only money received that has not been applied to an invoice.
  final bool advancesOnly;
  final int limit;

  bool get hasAnyFilter =>
      search.trim().isNotEmpty ||
      direction != null ||
      method != null ||
      status != null ||
      agentId != null ||
      shopId != null ||
      from != null ||
      to != null ||
      advancesOnly;

  PaymentFilter copyWith({
    String? search,
    PaymentDirection? direction,
    bool clearDirection = false,
    PaymentMethod? method,
    bool clearMethod = false,
    PaymentStatus? status,
    bool clearStatus = false,
    int? agentId,
    bool clearAgent = false,
    int? shopId,
    bool clearShop = false,
    DateTime? from,
    bool clearFrom = false,
    DateTime? to,
    bool clearTo = false,
    bool? advancesOnly,
    int? limit,
  }) {
    return PaymentFilter(
      search: search ?? this.search,
      direction: clearDirection ? null : (direction ?? this.direction),
      method: clearMethod ? null : (method ?? this.method),
      status: clearStatus ? null : (status ?? this.status),
      agentId: clearAgent ? null : (agentId ?? this.agentId),
      shopId: clearShop ? null : (shopId ?? this.shopId),
      from: clearFrom ? null : (from ?? this.from),
      to: clearTo ? null : (to ?? this.to),
      advancesOnly: advancesOnly ?? this.advancesOnly,
      limit: limit ?? this.limit,
    );
  }

  factory PaymentFilter.fromJson(Map<String, dynamic> json) =>
      _$PaymentFilterFromJson(json);

  Map<String, dynamic> toJson() => _$PaymentFilterToJson(this);
}

/// How the cheque register is narrowed.
@JsonSerializable()
class ChequeFilter {
  const ChequeFilter({
    this.search = '',
    this.statuses = const {},
    this.from,
    this.to,
    this.bankableOnly = false,
    this.limit = 300,
  });

  final String search;

  /// Empty means every status.
  final Set<ChequeStatus> statuses;
  final DateTime? from;
  final DateTime? to;

  /// Pending and no longer post-dated: the cheques that can go to the bank.
  final bool bankableOnly;
  final int limit;

  bool get hasAnyFilter =>
      search.trim().isNotEmpty ||
      statuses.isNotEmpty ||
      from != null ||
      to != null ||
      bankableOnly;

  ChequeFilter copyWith({
    String? search,
    Set<ChequeStatus>? statuses,
    DateTime? from,
    bool clearFrom = false,
    DateTime? to,
    bool clearTo = false,
    bool? bankableOnly,
    int? limit,
  }) {
    return ChequeFilter(
      search: search ?? this.search,
      statuses: statuses ?? this.statuses,
      from: clearFrom ? null : (from ?? this.from),
      to: clearTo ? null : (to ?? this.to),
      bankableOnly: bankableOnly ?? this.bankableOnly,
      limit: limit ?? this.limit,
    );
  }

  factory ChequeFilter.fromJson(Map<String, dynamic> json) =>
      _$ChequeFilterFromJson(json);

  Map<String, dynamic> toJson() => _$ChequeFilterToJson(this);
}

/// Human label for a payment method.
String paymentMethodLabel(PaymentMethod method) => switch (method) {
  PaymentMethod.cash => 'Cash',
  PaymentMethod.bankTransfer => 'Bank transfer',
  PaymentMethod.cheque => 'Cheque',
  PaymentMethod.cardOrDigital => 'Card or digital',
  PaymentMethod.creditNote => 'Credit note',
  PaymentMethod.openingBalance => 'Opening balance',
};

/// Human label for a cheque status.
String chequeStatusLabel(ChequeStatus status) => switch (status) {
  ChequeStatus.pending => 'Pending',
  ChequeStatus.deposited => 'Deposited',
  ChequeStatus.cleared => 'Cleared',
  ChequeStatus.bounced => 'Bounced',
  ChequeStatus.returned => 'Returned',
  ChequeStatus.cancelled => 'Cancelled',
};

/// Human label for a payment status.
String paymentStatusLabel(PaymentStatus status) => switch (status) {
  PaymentStatus.pending => 'Pending',
  PaymentStatus.cleared => 'Cleared',
  PaymentStatus.bounced => 'Bounced',
  PaymentStatus.cancelled => 'Cancelled',
};
