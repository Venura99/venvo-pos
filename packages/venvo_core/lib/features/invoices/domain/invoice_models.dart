import '../../../core/enums/app_enums.dart';
import '../../../core/errors/failures.dart';
import '../../../core/utils/money.dart';
import 'package:json_annotation/json_annotation.dart';

part 'invoice_models.g.dart';

/// Whether an invoice is tied to a stock movement, and how.
///
/// This is the type that keeps "goods moved" and "money is owed" separate
/// while letting them be linked. A warehouse-to-agent transfer is posted on
/// its own; billing it is a second, explicit decision.
sealed class InvoiceStockLinkage {
  const InvoiceStockLinkage();

  /// Rebuilds the right subclass from its `kind`.
  ///
  /// A sealed hierarchy needs a discriminator. `toJson` can be generated per
  /// subclass, but `fromJson` has to be *told* which one to build, and
  /// inferring it from which fields happen to be present would eventually pick
  /// the wrong one — the difference between billing goods already delivered
  /// and moving the same goods a second time.
  ///
  /// The `kind` strings are a wire contract: adding one is safe, renaming one
  /// breaks every deployed client.
  factory InvoiceStockLinkage.fromJson(Map<String, dynamic> json) {
    final kind = json['kind'];
    return switch (kind) {
      'none' => NoStockMovement.fromJson(json),
      'existing_delivery' => BillExistingDelivery.fromJson(json),
      'move_with_invoice' => MoveStockWithInvoice.fromJson(json),
      _ => throw ValidationFailure(
        kind == null
            ? 'The invoice did not say how stock should be handled.'
            : 'Unknown stock handling "$kind".',
        field: 'stockLinkage',
      ),
    };
  }

  /// Written into [toJson] so the far side can rebuild this exact subclass.
  String get kind;

  Map<String, dynamic> toJson();
}

/// No goods move and none are referenced. Used for a charge raised on its own.
@JsonSerializable()
class NoStockMovement extends InvoiceStockLinkage {
  const NoStockMovement();

  factory NoStockMovement.fromJson(Map<String, dynamic> json) =>
      _$NoStockMovementFromJson(json);

  @override
  String get kind => 'none';

  @override
  Map<String, dynamic> toJson() => {
    ..._$NoStockMovementToJson(this),
    'kind': kind,
  };
}

/// Bills goods that have already been delivered on a posted stock document.
/// The document is not changed; the invoice points at it.
@JsonSerializable()
class BillExistingDelivery extends InvoiceStockLinkage {
  const BillExistingDelivery(this.stockTransactionId);

  final int stockTransactionId;

  factory BillExistingDelivery.fromJson(Map<String, dynamic> json) =>
      _$BillExistingDeliveryFromJson(json);

  @override
  String get kind => 'existing_delivery';

  @override
  Map<String, dynamic> toJson() => {
    ..._$BillExistingDeliveryToJson(this),
    'kind': kind,
  };
}

/// Posts the goods movement and the invoice together, in one transaction.
/// This is what a retail sale and a supply-and-bill-at-once flow need.
@JsonSerializable()
class MoveStockWithInvoice extends InvoiceStockLinkage {
  const MoveStockWithInvoice({
    required this.documentType,
    required this.sourceLocationId,
    required this.destinationLocationId,
  });

  final StockDocumentType documentType;
  final int sourceLocationId;
  final int destinationLocationId;

  factory MoveStockWithInvoice.fromJson(Map<String, dynamic> json) =>
      _$MoveStockWithInvoiceFromJson(json);

  @override
  String get kind => 'move_with_invoice';

  @override
  Map<String, dynamic> toJson() => {
    ..._$MoveStockWithInvoiceToJson(this),
    'kind': kind,
  };
}

/// One line being billed.
@JsonSerializable()
class InvoiceLineRequest {
  const InvoiceLineRequest({
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    this.discountType = DiscountType.none,
    this.discountValue = 0,
    this.notes,
  });

  final int productId;
  final int quantity;
  final Money unitPrice;
  final DiscountType discountType;

  /// Basis points when [discountType] is a percentage, cents when it is a
  /// fixed amount. The original input is stored alongside the resolved cash
  /// amount, so a printed invoice can still say "10%" years later.
  final int discountValue;
  final String? notes;

  Money get gross => unitPrice * quantity;

  /// The resolved cash discount. A fixed amount is capped at the line value,
  /// because a line cannot be discounted below zero.
  Money get discount => switch (discountType) {
    DiscountType.none => Money.zero,
    DiscountType.percentage => gross.percentage(discountValue),
    DiscountType.fixedAmount =>
      Money(discountValue) > gross ? gross : Money(discountValue),
  };

  Money get net => gross - discount;

  /// The discount as a share of the line, for comparing against the ceiling
  /// however it was entered.
  int get effectiveDiscountBps => discount.bpsOf(gross);

  factory InvoiceLineRequest.fromJson(Map<String, dynamic> json) =>
      _$InvoiceLineRequestFromJson(json);

  Map<String, dynamic> toJson() => _$InvoiceLineRequestToJson(this);
}

/// Money received at the moment the invoice is raised, which is the common
/// counter flow: bill it and take the cash in one step.
@JsonSerializable()
class ImmediatePayment {
  const ImmediatePayment({
    required this.method,
    required this.amount,
    this.referenceNumber,
    this.bankName,
    this.chequeNumber,
    this.chequeDate,
    this.chequeBranch,
  });

  final PaymentMethod method;
  final Money amount;
  final String? referenceNumber;
  final String? bankName;

  /// Required when [method] is a cheque.
  final String? chequeNumber;
  final DateTime? chequeDate;
  final String? chequeBranch;

  bool get isCheque => method == PaymentMethod.cheque;

  factory ImmediatePayment.fromJson(Map<String, dynamic> json) =>
      _$ImmediatePaymentFromJson(json);

  Map<String, dynamic> toJson() => _$ImmediatePaymentToJson(this);
}

/// A request to raise an invoice.
@JsonSerializable()
class InvoiceRequest {
  const InvoiceRequest({
    required this.kind,
    required this.lines,
    this.agentId,
    this.shopId,
    this.customerName,
    this.customerPhone,
    this.invoiceDate,
    this.dueDate,
    this.invoiceDiscountType = DiscountType.none,
    this.invoiceDiscountValue = 0,
    this.discountReason,
    this.stockLinkage = const NoStockMovement(),
    this.payment,
    this.notes,
    this.allowNegativeStock = false,
    this.negativeStockReason,
  });

  final InvoiceKind kind;
  final List<InvoiceLineRequest> lines;

  final int? agentId;
  final int? shopId;

  /// Walk-in customer details for a retail sale. A retail sale is deliberately
  /// not forced to create a party record.
  final String? customerName;
  final String? customerPhone;

  final DateTime? invoiceDate;
  final DateTime? dueDate;

  final DiscountType invoiceDiscountType;
  final int invoiceDiscountValue;
  final String? discountReason;

  final InvoiceStockLinkage stockLinkage;
  final ImmediatePayment? payment;
  final String? notes;

  /// Passed through to the stock movement when one is posted with the invoice.
  final bool allowNegativeStock;
  final String? negativeStockReason;

  /// Which kind of party this invoice is raised on.
  PartyType get partyType => switch (kind) {
    InvoiceKind.agentInvoice => PartyType.agent,
    InvoiceKind.shopInvoice => PartyType.shop,
    InvoiceKind.retailSale => PartyType.customer,
  };

  InvoiceTotals get totals => InvoiceTotals.from(
    lines: lines,
    invoiceDiscountType: invoiceDiscountType,
    invoiceDiscountValue: invoiceDiscountValue,
  );

  factory InvoiceRequest.fromJson(Map<String, dynamic> json) =>
      _$InvoiceRequestFromJson(json);

  Map<String, dynamic> toJson() => _$InvoiceRequestToJson(this);
}

/// The arithmetic of an invoice, in one place so the form, the service and the
/// PDF cannot disagree about it.
///
/// The order matters and is fixed: line discounts come off first, then the
/// invoice-level discount is applied to what is left. Applying an
/// invoice-level percentage to the undiscounted gross would discount the
/// line discounts too.
@JsonSerializable()
class InvoiceTotals {
  const InvoiceTotals({
    required this.gross,
    required this.itemDiscount,
    required this.invoiceDiscount,
    required this.net,
  });

  factory InvoiceTotals.from({
    required List<InvoiceLineRequest> lines,
    required DiscountType invoiceDiscountType,
    required int invoiceDiscountValue,
  }) {
    final gross = lines.map((line) => line.gross).sum;
    final itemDiscount = lines.map((line) => line.discount).sum;
    final afterItemDiscounts = gross - itemDiscount;

    final invoiceDiscount = switch (invoiceDiscountType) {
      DiscountType.none => Money.zero,
      DiscountType.percentage => afterItemDiscounts.percentage(
        invoiceDiscountValue,
      ),
      DiscountType.fixedAmount =>
        Money(invoiceDiscountValue) > afterItemDiscounts
            ? afterItemDiscounts
            : Money(invoiceDiscountValue),
    };

    return InvoiceTotals(
      gross: gross,
      itemDiscount: itemDiscount,
      invoiceDiscount: invoiceDiscount,
      net: afterItemDiscounts - invoiceDiscount,
    );
  }

  static const InvoiceTotals zero = InvoiceTotals(
    gross: Money.zero,
    itemDiscount: Money.zero,
    invoiceDiscount: Money.zero,
    net: Money.zero,
  );

  final Money gross;
  final Money itemDiscount;
  final Money invoiceDiscount;
  final Money net;

  /// Gross less the per-line discounts: what the invoice-level discount is
  /// applied to.
  Money get afterItemDiscounts => gross - itemDiscount;

  Money get totalDiscount => itemDiscount + invoiceDiscount;

  /// The whole discount as a share of gross, for display.
  int get effectiveDiscountBps => totalDiscount.bpsOf(gross);

  /// The invoice-level discount as a share of what it was applied to, which
  /// is what the ceiling is compared against.
  int get invoiceDiscountBps => invoiceDiscount.bpsOf(afterItemDiscounts);

  factory InvoiceTotals.fromJson(Map<String, dynamic> json) =>
      _$InvoiceTotalsFromJson(json);

  Map<String, dynamic> toJson() => _$InvoiceTotalsToJson(this);
}

/// An invoice as the register lists it, with its settlement worked out.
@JsonSerializable()
class InvoiceSummary {
  const InvoiceSummary({
    required this.id,
    required this.invoiceNumber,
    required this.kind,
    required this.status,
    required this.invoiceDate,
    required this.partyType,
    required this.partyName,
    required this.gross,
    required this.itemDiscount,
    required this.invoiceDiscount,
    required this.net,
    required this.cost,
    required this.settled,
    required this.creditApplied,
    required this.pendingCheques,
    required this.lineCount,
    required this.createdBy,
    this.agentId,
    this.shopId,
    this.agentName,
    this.dueDate,
    this.stockTransactionId,
    this.stockDocumentNumber,
    this.discountReason,
    this.discountApprovedBy,
  });

  final int id;
  final String invoiceNumber;
  final InvoiceKind kind;
  final InvoiceStatus status;
  final DateTime invoiceDate;
  final DateTime? dueDate;
  final PartyType partyType;

  /// The agent, shop or customer the invoice is raised on.
  final String partyName;
  final int? agentId;
  final int? shopId;

  /// The agent responsible, on a shop invoice.
  final String? agentName;

  final Money gross;
  final Money itemDiscount;
  final Money invoiceDiscount;
  final Money net;

  /// Cost of the goods, snapshotted at posting, for gross profit.
  final Money cost;

  /// Settled by **cleared** payments only.
  final Money settled;
  final Money creditApplied;

  /// Received as cheques that have not cleared. Not settlement.
  final Money pendingCheques;

  final int lineCount;
  final String createdBy;
  final int? stockTransactionId;
  final String? stockDocumentNumber;
  final String? discountReason;
  final String? discountApprovedBy;

  bool get isPosted => status == InvoiceStatus.posted;
  bool get isCancelled => status == InvoiceStatus.cancelled;

  /// What the party still owes. Counts cleared money and applied credit
  /// notes; a pending cheque does not reduce it.
  Money get outstanding =>
      isPosted ? net - settled - creditApplied : Money.zero;

  /// What would be outstanding if the pending cheques cleared. Shown
  /// alongside [outstanding] so a collector can see both.
  Money get outstandingIfChequesClear => outstanding - pendingCheques;

  Money get grossProfit => net - cost;

  PaymentSettlementStatus get settlementStatus {
    if (!isPosted) return PaymentSettlementStatus.unpaid;
    final applied = settled + creditApplied;
    if (applied.isZero) return PaymentSettlementStatus.unpaid;
    if (applied < net) return PaymentSettlementStatus.partiallyPaid;
    if (applied > net) return PaymentSettlementStatus.overpaid;
    return PaymentSettlementStatus.paid;
  }

  bool get hasPendingCheques => !pendingCheques.isZero;

  /// True when the invoice is past its due date and still owed.
  bool isOverdue(DateTime asOf) {
    final due = dueDate;
    if (due == null || !outstanding.isPositive) return false;
    return asOf.isAfter(due);
  }

  factory InvoiceSummary.fromJson(Map<String, dynamic> json) =>
      _$InvoiceSummaryFromJson(json);

  Map<String, dynamic> toJson() => _$InvoiceSummaryToJson(this);
}

/// A stored invoice line.
@JsonSerializable()
class InvoiceLine {
  const InvoiceLine({
    required this.lineNumber,
    required this.productId,
    required this.productName,
    required this.sku,
    required this.quantity,
    required this.unitPrice,
    required this.gross,
    required this.discountType,
    required this.discountValue,
    required this.discount,
    required this.net,
    required this.unitCost,
    required this.returnedQuantity,
    this.notes,
  });

  final int lineNumber;
  final int productId;

  /// As it was when billed, not as it is now.
  final String productName;
  final String sku;
  final int quantity;
  final Money unitPrice;
  final Money gross;
  final DiscountType discountType;
  final int discountValue;
  final Money discount;
  final Money net;
  final Money unitCost;

  /// How much of this line has already come back, so it cannot be
  /// over-returned in phase 5.
  final int returnedQuantity;
  final String? notes;

  int get returnableQuantity => quantity - returnedQuantity;

  /// How the discount was entered, for printing.
  String get discountLabel => switch (discountType) {
    DiscountType.none => '',
    DiscountType.percentage => formatBps(discountValue),
    DiscountType.fixedAmount => discount.formatted(),
  };

  factory InvoiceLine.fromJson(Map<String, dynamic> json) =>
      _$InvoiceLineFromJson(json);

  Map<String, dynamic> toJson() => _$InvoiceLineToJson(this);
}

/// An invoice with everything needed to view or print it.
@JsonSerializable()
class InvoiceDetail {
  const InvoiceDetail({
    required this.summary,
    required this.lines,
    required this.payments,
    this.notes,
    this.cancelReason,
    this.cancelledBy,
    this.partyAddress,
    this.partyPhone,
  });

  final InvoiceSummary summary;
  final List<InvoiceLine> lines;

  /// Payments touching this invoice, newest first.
  final List<InvoicePaymentLine> payments;

  final String? notes;
  final String? cancelReason;
  final String? cancelledBy;
  final String? partyAddress;
  final String? partyPhone;

  int get totalQuantity =>
      lines.fold(0, (total, line) => total + line.quantity);

  factory InvoiceDetail.fromJson(Map<String, dynamic> json) =>
      _$InvoiceDetailFromJson(json);

  Map<String, dynamic> toJson() => _$InvoiceDetailToJson(this);
}

/// One payment as it appears on an invoice.
@JsonSerializable()
class InvoicePaymentLine {
  const InvoicePaymentLine({
    required this.paymentId,
    required this.receiptNumber,
    required this.paymentDate,
    required this.method,
    required this.status,
    required this.allocated,
    this.chequeNumber,
    this.chequeStatus,
  });

  final int paymentId;
  final String receiptNumber;
  final DateTime paymentDate;
  final PaymentMethod method;
  final PaymentStatus status;

  /// How much of this payment was applied to this invoice.
  final Money allocated;
  final String? chequeNumber;
  final ChequeStatus? chequeStatus;

  /// Only a cleared payment actually reduces what is owed.
  bool get isEffective => status == PaymentStatus.cleared;

  factory InvoicePaymentLine.fromJson(Map<String, dynamic> json) =>
      _$InvoicePaymentLineFromJson(json);

  Map<String, dynamic> toJson() => _$InvoicePaymentLineToJson(this);
}

/// How the invoice register is narrowed.
@JsonSerializable()
class InvoiceFilter {
  const InvoiceFilter({
    this.search = '',
    this.kinds = const {},
    this.status,
    this.settlement,
    this.agentId,
    this.shopId,
    this.from,
    this.to,
    this.unpaidOnly = false,
    this.overdueOnly = false,
    this.limit = 300,
  });

  final String search;

  /// Empty means every kind.
  final Set<InvoiceKind> kinds;
  final InvoiceStatus? status;
  final PaymentSettlementStatus? settlement;
  final int? agentId;
  final int? shopId;
  final DateTime? from;
  final DateTime? to;
  final bool unpaidOnly;
  final bool overdueOnly;
  final int limit;

  bool get hasAnyFilter =>
      search.trim().isNotEmpty ||
      kinds.isNotEmpty ||
      status != null ||
      settlement != null ||
      agentId != null ||
      shopId != null ||
      from != null ||
      to != null ||
      unpaidOnly ||
      overdueOnly;

  InvoiceFilter copyWith({
    String? search,
    Set<InvoiceKind>? kinds,
    InvoiceStatus? status,
    bool clearStatus = false,
    PaymentSettlementStatus? settlement,
    bool clearSettlement = false,
    int? agentId,
    bool clearAgent = false,
    int? shopId,
    bool clearShop = false,
    DateTime? from,
    bool clearFrom = false,
    DateTime? to,
    bool clearTo = false,
    bool? unpaidOnly,
    bool? overdueOnly,
    int? limit,
  }) {
    return InvoiceFilter(
      search: search ?? this.search,
      kinds: kinds ?? this.kinds,
      status: clearStatus ? null : (status ?? this.status),
      settlement: clearSettlement ? null : (settlement ?? this.settlement),
      agentId: clearAgent ? null : (agentId ?? this.agentId),
      shopId: clearShop ? null : (shopId ?? this.shopId),
      from: clearFrom ? null : (from ?? this.from),
      to: clearTo ? null : (to ?? this.to),
      unpaidOnly: unpaidOnly ?? this.unpaidOnly,
      overdueOnly: overdueOnly ?? this.overdueOnly,
      limit: limit ?? this.limit,
    );
  }

  factory InvoiceFilter.fromJson(Map<String, dynamic> json) =>
      _$InvoiceFilterFromJson(json);

  Map<String, dynamic> toJson() => _$InvoiceFilterToJson(this);
}

/// Human label for an invoice kind.
String invoiceKindLabel(InvoiceKind kind) => switch (kind) {
  InvoiceKind.agentInvoice => 'Agent invoice',
  InvoiceKind.shopInvoice => 'Shop invoice',
  InvoiceKind.retailSale => 'Retail sale',
};

/// Human label for a settlement state.
String settlementLabel(PaymentSettlementStatus status) => switch (status) {
  PaymentSettlementStatus.unpaid => 'Unpaid',
  PaymentSettlementStatus.partiallyPaid => 'Part paid',
  PaymentSettlementStatus.paid => 'Paid',
  PaymentSettlementStatus.overpaid => 'Overpaid',
};
