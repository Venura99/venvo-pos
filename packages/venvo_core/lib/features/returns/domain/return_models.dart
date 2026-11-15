import '../../../core/enums/app_enums.dart';
import '../../../core/utils/money.dart';
import 'package:json_annotation/json_annotation.dart';

part 'return_models.g.dart';

/// One product on a return being composed.
///
/// [quantity] is always positive. Which way the goods travel comes from the
/// return's route, never from the sign of a line.
@JsonSerializable()
class ReturnLineDraft {
  const ReturnLineDraft({
    required this.productId,
    required this.quantity,
    this.originInvoiceItemId,
    this.unitPrice,
    this.notes,
  });

  final int productId;
  final int quantity;

  /// The invoice line these goods were billed on, when the return is traced
  /// to an invoice. Supplying it caps the quantity at what is still
  /// outstanding on that line and recovers the price actually charged.
  final int? originInvoiceItemId;

  /// Only consulted for an untraced return. When the line is linked to an
  /// invoice item the billed price wins, because a credit note must repay what
  /// was charged rather than what somebody types today.
  final Money? unitPrice;

  final String? notes;

  factory ReturnLineDraft.fromJson(Map<String, dynamic> json) =>
      _$ReturnLineDraftFromJson(json);

  Map<String, dynamic> toJson() => _$ReturnLineDraftToJson(this);
}

/// A return being composed, before it is posted.
@JsonSerializable()
class ReturnDraft {
  const ReturnDraft({
    required this.route,
    required this.fromLocationId,
    required this.toLocationId,
    required this.reason,
    required this.lines,
    this.returnDate,
    this.agentId,
    this.shopId,
    this.originInvoiceId,
    this.originStockTransactionId,
    this.reasonNote,
    this.notes,
  });

  final ReturnRoute route;

  /// Where the goods are coming back from.
  final int fromLocationId;

  /// Where accepted goods will land once inspected. Damaged and scrapped
  /// quantities never go here.
  final int toLocationId;

  final ReturnReason reason;
  final List<ReturnLineDraft> lines;

  /// Defaults to now.
  final DateTime? returnDate;

  final int? agentId;
  final int? shopId;

  /// The invoice being returned against, when the goods can be traced to one.
  final int? originInvoiceId;

  /// The transfer or supply document the goods originally arrived on.
  final int? originStockTransactionId;

  final String? reasonNote;
  final String? notes;

  int get totalQuantity =>
      lines.fold(0, (total, line) => total + line.quantity);

  factory ReturnDraft.fromJson(Map<String, dynamic> json) =>
      _$ReturnDraftFromJson(json);

  Map<String, dynamic> toJson() => _$ReturnDraftToJson(this);
}

/// The outcome of posting a return.
@JsonSerializable()
class ReturnPostResult {
  const ReturnPostResult({
    required this.returnId,
    required this.returnNumber,
    required this.receiptTransactionId,
    required this.receiptDocumentNumber,
    required this.totalQuantity,
    required this.totalValue,
  });

  final int returnId;
  final String returnNumber;

  /// The movement that took the goods out of the returning location and into
  /// goods-in-transit, where they wait for inspection.
  final int receiptTransactionId;
  final String receiptDocumentNumber;

  final int totalQuantity;

  /// Value of the goods at the prices they were originally billed.
  final Money totalValue;

  factory ReturnPostResult.fromJson(Map<String, dynamic> json) =>
      _$ReturnPostResultFromJson(json);

  Map<String, dynamic> toJson() => _$ReturnPostResultToJson(this);
}

/// What the inspector decided about one returned line.
///
/// The three quantities must add up to the quantity that came back: every
/// returned unit is accounted for, so none can quietly disappear between the
/// returning location and stock.
@JsonSerializable()
class InspectionDecision {
  const InspectionDecision({
    required this.returnItemId,
    this.acceptedQuantity = 0,
    this.damagedQuantity = 0,
    this.scrappedQuantity = 0,
    this.note,
  });

  final int returnItemId;

  /// Good condition - goes into the return's receiving location.
  final int acceptedQuantity;

  /// Defective but still physically present - goes to the damaged store.
  final int damagedQuantity;

  /// Written off entirely - leaves the business through the adjustment
  /// counterparty.
  final int scrappedQuantity;

  final String? note;

  int get total => acceptedQuantity + damagedQuantity + scrappedQuantity;

  /// Status to record on the line. A mixed split is filed under whichever
  /// outcome took most of the units, with the exact numbers kept alongside.
  InspectionStatus get status {
    if (acceptedQuantity >= damagedQuantity &&
        acceptedQuantity >= scrappedQuantity) {
      return InspectionStatus.acceptedToStock;
    }
    return damagedQuantity >= scrappedQuantity
        ? InspectionStatus.movedToDamaged
        : InspectionStatus.scrapped;
  }

  factory InspectionDecision.fromJson(Map<String, dynamic> json) =>
      _$InspectionDecisionFromJson(json);

  Map<String, dynamic> toJson() => _$InspectionDecisionToJson(this);
}

/// An inspection covering every line of one return.
@JsonSerializable()
class InspectionRequest {
  const InspectionRequest({
    required this.returnId,
    required this.decisions,
    this.notes,
  });

  final int returnId;
  final List<InspectionDecision> decisions;
  final String? notes;

  factory InspectionRequest.fromJson(Map<String, dynamic> json) =>
      _$InspectionRequestFromJson(json);

  Map<String, dynamic> toJson() => _$InspectionRequestToJson(this);
}

/// The outcome of an inspection.
@JsonSerializable()
class InspectionResult {
  const InspectionResult({
    required this.returnId,
    required this.acceptedQuantity,
    required this.damagedQuantity,
    required this.scrappedQuantity,
    required this.creditableValue,
    this.acceptedTransactionId,
    this.damagedTransactionId,
    this.scrappedTransactionId,
  });

  final int returnId;
  final int acceptedQuantity;
  final int damagedQuantity;
  final int scrappedQuantity;

  /// Value of the quantities that qualify for a credit note. Deciding that a
  /// line is creditable is separate from putting it back in stock: a defective
  /// item may still be credited, a scrapped one never is.
  final Money creditableValue;

  final int? acceptedTransactionId;
  final int? damagedTransactionId;
  final int? scrappedTransactionId;

  factory InspectionResult.fromJson(Map<String, dynamic> json) =>
      _$InspectionResultFromJson(json);

  Map<String, dynamic> toJson() => _$InspectionResultToJson(this);
}

/// A return as the register lists it.
@JsonSerializable()
class ReturnSummary {
  const ReturnSummary({
    required this.id,
    required this.returnNumber,
    required this.route,
    required this.status,
    required this.returnDate,
    required this.reason,
    required this.fromLocationName,
    required this.toLocationName,
    required this.totalQuantity,
    required this.totalValue,
    required this.pendingLineCount,
    required this.lineCount,
    required this.createdBy,
    required this.creditedValue,
    this.agentName,
    this.shopName,
    this.originInvoiceNumber,
    this.reasonNote,
    this.creditNoteNumber,
  });

  final int id;
  final String returnNumber;
  final ReturnRoute route;
  final ReturnStatus status;
  final DateTime returnDate;
  final ReturnReason reason;
  final String fromLocationName;
  final String toLocationName;
  final int totalQuantity;
  final Money totalValue;

  /// Lines still waiting for a disposition.
  final int pendingLineCount;
  final int lineCount;
  final String createdBy;

  /// Total of posted credit notes raised against this return.
  final Money creditedValue;

  final String? agentName;
  final String? shopName;
  final String? originInvoiceNumber;
  final String? reasonNote;
  final String? creditNoteNumber;

  bool get isCancelled => status == ReturnStatus.cancelled;
  bool get awaitsInspection => status == ReturnStatus.posted;
  bool get isInspected =>
      status == ReturnStatus.inspected || status == ReturnStatus.completed;
  bool get hasCredit => creditedValue.isPositive;

  /// A return can be cancelled while no credit has been raised against it.
  /// Afterwards the credit note has to be cancelled first, so the money and
  /// the goods never disagree.
  bool get canBeCancelled =>
      status != ReturnStatus.cancelled && !creditedValue.isPositive;

  factory ReturnSummary.fromJson(Map<String, dynamic> json) =>
      _$ReturnSummaryFromJson(json);

  Map<String, dynamic> toJson() => _$ReturnSummaryToJson(this);
}

/// One line of a return, as stored.
@JsonSerializable()
class ReturnLineView {
  const ReturnLineView({
    required this.id,
    required this.lineNumber,
    required this.productId,
    required this.productName,
    required this.sku,
    required this.quantity,
    required this.unitPrice,
    required this.lineValue,
    required this.inspectionStatus,
    required this.acceptedQuantity,
    required this.damagedQuantity,
    required this.scrappedQuantity,
    this.inspectionNote,
    this.inspectedBy,
    this.inspectedAt,
    this.notes,
  });

  final int id;
  final int lineNumber;
  final int productId;

  /// The name as it was when the goods came back, not as it is now.
  final String productName;
  final String sku;
  final int quantity;
  final Money unitPrice;
  final Money lineValue;
  final InspectionStatus inspectionStatus;
  final int acceptedQuantity;
  final int damagedQuantity;
  final int scrappedQuantity;
  final String? inspectionNote;
  final String? inspectedBy;
  final DateTime? inspectedAt;
  final String? notes;

  bool get isPending => inspectionStatus == InspectionStatus.pending;

  int get disposedQuantity =>
      acceptedQuantity + damagedQuantity + scrappedQuantity;

  /// Value of the units that may be credited: accepted and damaged goods were
  /// genuinely returned, scrapped ones are a write-off.
  Money get creditableValue => unitPrice * (acceptedQuantity + damagedQuantity);

  factory ReturnLineView.fromJson(Map<String, dynamic> json) =>
      _$ReturnLineViewFromJson(json);

  Map<String, dynamic> toJson() => _$ReturnLineViewToJson(this);
}

/// A return with its lines, for viewing or printing.
@JsonSerializable()
class ReturnDetail {
  const ReturnDetail({
    required this.summary,
    required this.lines,
    required this.creditNotes,
    this.notes,
    this.cancelReason,
    this.authorisedBy,
    this.receiptDocumentNumber,
    this.dispositionDocumentNumber,
  });

  final ReturnSummary summary;
  final List<ReturnLineView> lines;

  /// Credit notes raised against this return, posted or cancelled.
  final List<CreditNoteSummary> creditNotes;

  final String? notes;
  final String? cancelReason;
  final String? authorisedBy;
  final String? receiptDocumentNumber;
  final String? dispositionDocumentNumber;

  Money get creditableValue => lines.map((line) => line.creditableValue).sum;

  /// What may still be credited: what inspection accepted, less credit notes
  /// already posted.
  Money get uncreditedValue {
    final remaining = creditableValue - summary.creditedValue;
    return remaining.isPositive ? remaining : Money.zero;
  }

  bool get canIssueCredit =>
      summary.isInspected && !summary.isCancelled && uncreditedValue.isPositive;

  factory ReturnDetail.fromJson(Map<String, dynamic> json) =>
      _$ReturnDetailFromJson(json);

  Map<String, dynamic> toJson() => _$ReturnDetailToJson(this);
}

/// How the returns register is narrowed.
@JsonSerializable()
class ReturnFilter {
  const ReturnFilter({
    this.search = '',
    this.routes = const {},
    this.status,
    this.reason,
    this.agentId,
    this.shopId,
    this.pendingInspectionOnly = false,
    this.from,
    this.to,
    this.limit = 300,
  });

  final String search;

  /// Empty means every route.
  final Set<ReturnRoute> routes;
  final ReturnStatus? status;
  final ReturnReason? reason;
  final int? agentId;
  final int? shopId;

  /// The inspector's working list.
  final bool pendingInspectionOnly;
  final DateTime? from;
  final DateTime? to;
  final int limit;

  bool get hasAnyFilter =>
      search.trim().isNotEmpty ||
      routes.isNotEmpty ||
      status != null ||
      reason != null ||
      agentId != null ||
      shopId != null ||
      pendingInspectionOnly ||
      from != null ||
      to != null;

  ReturnFilter copyWith({
    String? search,
    Set<ReturnRoute>? routes,
    ReturnStatus? status,
    bool clearStatus = false,
    ReturnReason? reason,
    bool clearReason = false,
    int? agentId,
    bool clearAgent = false,
    int? shopId,
    bool clearShop = false,
    bool? pendingInspectionOnly,
    DateTime? from,
    bool clearFrom = false,
    DateTime? to,
    bool clearTo = false,
    int? limit,
  }) {
    return ReturnFilter(
      search: search ?? this.search,
      routes: routes ?? this.routes,
      status: clearStatus ? null : (status ?? this.status),
      reason: clearReason ? null : (reason ?? this.reason),
      agentId: clearAgent ? null : (agentId ?? this.agentId),
      shopId: clearShop ? null : (shopId ?? this.shopId),
      pendingInspectionOnly:
          pendingInspectionOnly ?? this.pendingInspectionOnly,
      from: clearFrom ? null : (from ?? this.from),
      to: clearTo ? null : (to ?? this.to),
      limit: limit ?? this.limit,
    );
  }

  factory ReturnFilter.fromJson(Map<String, dynamic> json) =>
      _$ReturnFilterFromJson(json);

  Map<String, dynamic> toJson() => _$ReturnFilterToJson(this);
}

/// A credit note as the register lists it.
@JsonSerializable()
class CreditNoteSummary {
  const CreditNoteSummary({
    required this.id,
    required this.creditNoteNumber,
    required this.status,
    required this.issueDate,
    required this.partyType,
    required this.partyName,
    required this.amount,
    required this.applied,
    required this.createdBy,
    this.agentId,
    this.shopId,
    this.returnNumber,
    this.returnId,
    this.originInvoiceNumber,
    this.originInvoiceId,
    this.reason,
    this.cancelReason,
  });

  final int id;
  final String creditNoteNumber;
  final InvoiceStatus status;
  final DateTime issueDate;
  final PartyType partyType;
  final String partyName;
  final Money amount;

  /// How much of [amount] has been offset against invoices or refunded.
  final Money applied;

  final String createdBy;

  /// Both are set on a shop's credit note, because a shop's goods come
  /// through its agent. [partyType] says which of them owns the balance.
  final int? agentId;
  final int? shopId;

  final String? returnNumber;
  final int? returnId;
  final String? originInvoiceNumber;
  final int? originInvoiceId;
  final String? reason;
  final String? cancelReason;

  bool get isPosted => status == InvoiceStatus.posted;
  bool get isCancelled => status == InvoiceStatus.cancelled;

  /// Credit the party still has in hand.
  Money get remaining {
    final left = amount - applied;
    return left.isPositive ? left : Money.zero;
  }

  bool get isFullyApplied => isPosted && remaining.isZero;

  /// A credit note can only be withdrawn while none of it has been used.
  bool get canBeCancelled => isPosted && applied.isZero;

  factory CreditNoteSummary.fromJson(Map<String, dynamic> json) =>
      _$CreditNoteSummaryFromJson(json);

  Map<String, dynamic> toJson() => _$CreditNoteSummaryToJson(this);
}

/// One application of a credit note against an invoice.
@JsonSerializable()
class CreditNoteApplicationView {
  const CreditNoteApplicationView({
    required this.id,
    required this.invoiceId,
    required this.invoiceNumber,
    required this.amount,
    required this.appliedAt,
    required this.appliedBy,
  });

  final int id;
  final int invoiceId;
  final String invoiceNumber;

  /// Negative when the application was withdrawn.
  final Money amount;

  final DateTime appliedAt;
  final String appliedBy;

  bool get isWithdrawal => amount.isNegative;

  factory CreditNoteApplicationView.fromJson(Map<String, dynamic> json) =>
      _$CreditNoteApplicationViewFromJson(json);

  Map<String, dynamic> toJson() => _$CreditNoteApplicationViewToJson(this);
}

/// A credit note with everything it has been used for.
@JsonSerializable()
class CreditNoteDetail {
  const CreditNoteDetail({
    required this.summary,
    required this.applications,
    this.notes,
  });

  final CreditNoteSummary summary;
  final List<CreditNoteApplicationView> applications;
  final String? notes;

  factory CreditNoteDetail.fromJson(Map<String, dynamic> json) =>
      _$CreditNoteDetailFromJson(json);

  Map<String, dynamic> toJson() => _$CreditNoteDetailToJson(this);
}

/// How the credit note register is narrowed.
@JsonSerializable()
class CreditNoteFilter {
  const CreditNoteFilter({
    this.search = '',
    this.status,
    this.agentId,
    this.shopId,
    this.withRemainingOnly = false,
    this.from,
    this.to,
    this.limit = 300,
  });

  final String search;
  final InvoiceStatus? status;
  final int? agentId;
  final int? shopId;

  /// Credit the business still owes somebody.
  final bool withRemainingOnly;
  final DateTime? from;
  final DateTime? to;
  final int limit;

  bool get hasAnyFilter =>
      search.trim().isNotEmpty ||
      status != null ||
      agentId != null ||
      shopId != null ||
      withRemainingOnly ||
      from != null ||
      to != null;

  CreditNoteFilter copyWith({
    String? search,
    InvoiceStatus? status,
    bool clearStatus = false,
    int? agentId,
    bool clearAgent = false,
    int? shopId,
    bool clearShop = false,
    bool? withRemainingOnly,
    DateTime? from,
    bool clearFrom = false,
    DateTime? to,
    bool clearTo = false,
    int? limit,
  }) {
    return CreditNoteFilter(
      search: search ?? this.search,
      status: clearStatus ? null : (status ?? this.status),
      agentId: clearAgent ? null : (agentId ?? this.agentId),
      shopId: clearShop ? null : (shopId ?? this.shopId),
      withRemainingOnly: withRemainingOnly ?? this.withRemainingOnly,
      from: clearFrom ? null : (from ?? this.from),
      to: clearTo ? null : (to ?? this.to),
      limit: limit ?? this.limit,
    );
  }

  factory CreditNoteFilter.fromJson(Map<String, dynamic> json) =>
      _$CreditNoteFilterFromJson(json);

  Map<String, dynamic> toJson() => _$CreditNoteFilterToJson(this);
}

/// One invoice line, with how much of it is still returnable.
@JsonSerializable()
class ReturnableInvoiceLine {
  const ReturnableInvoiceLine({
    required this.invoiceItemId,
    required this.lineNumber,
    required this.productId,
    required this.productName,
    required this.sku,
    required this.billedQuantity,
    required this.returnedQuantity,
    required this.effectiveUnitPrice,
  });

  final int invoiceItemId;
  final int lineNumber;
  final int productId;
  final String productName;
  final String sku;
  final int billedQuantity;

  /// Units already returned against this line on earlier returns.
  final int returnedQuantity;

  /// What one unit actually cost the party, after both the line discount and
  /// the line's share of any invoice-level discount. This is the rate a credit
  /// note repays at.
  final Money effectiveUnitPrice;

  int get returnableQuantity => billedQuantity - returnedQuantity;

  bool get isFullyReturned => returnableQuantity <= 0;

  factory ReturnableInvoiceLine.fromJson(Map<String, dynamic> json) =>
      _$ReturnableInvoiceLineFromJson(json);

  Map<String, dynamic> toJson() => _$ReturnableInvoiceLineToJson(this);
}

/// Human label for a return route.
String returnRouteLabel(ReturnRoute route) => switch (route) {
  ReturnRoute.customerToShop => 'Customer to shop',
  ReturnRoute.shopToAgent => 'Shop to agent',
  ReturnRoute.agentToWarehouse => 'Agent to warehouse',
  ReturnRoute.shopToWarehouse => 'Shop direct to warehouse',
};

/// What the route means in practice, shown under the picker so the wrong one
/// is not chosen by accident.
String returnRouteExplanation(ReturnRoute route) => switch (route) {
  ReturnRoute.customerToShop =>
    'An end customer brings goods back to a shop. Stock returns to that '
        'shop once inspected.',
  ReturnRoute.shopToAgent =>
    'A shop sends goods back to the agent who supplied them.',
  ReturnRoute.agentToWarehouse => 'An agent sends goods back to the warehouse.',
  ReturnRoute.shopToWarehouse =>
    'A shop sends goods straight to the warehouse, bypassing the agent. '
        'Needs explicit authorisation.',
};

String returnReasonLabel(ReturnReason reason) => switch (reason) {
  ReturnReason.customerPaymentFailure => 'Customer payment failed',
  ReturnReason.defectiveItem => 'Defective item',
  ReturnReason.damagedItem => 'Damaged in handling',
  ReturnReason.wrongProduct => 'Wrong product supplied',
  ReturnReason.excessStock => 'Excess stock',
  ReturnReason.other => 'Other',
};

String returnStatusLabel(ReturnStatus status) => switch (status) {
  ReturnStatus.draft => 'Draft',
  ReturnStatus.posted => 'Awaiting inspection',
  ReturnStatus.inspected => 'Inspected',
  ReturnStatus.completed => 'Completed',
  ReturnStatus.cancelled => 'Cancelled',
};

String inspectionStatusLabel(InspectionStatus status) => switch (status) {
  InspectionStatus.pending => 'Pending',
  InspectionStatus.acceptedToStock => 'Accepted',
  InspectionStatus.movedToDamaged => 'Damaged',
  InspectionStatus.scrapped => 'Scrapped',
};
