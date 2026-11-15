import '../../../core/enums/app_enums.dart';
import '../../../core/utils/money.dart';
import 'package:json_annotation/json_annotation.dart';

part 'stock_models.g.dart';

/// One product on a stock document.
///
/// [quantity] is always positive and always in base units; which way the goods
/// move comes from the document's source and destination, never from the sign
/// of a line.
@JsonSerializable()
class StockMovementLine {
  const StockMovementLine({
    required this.productId,
    required this.quantity,
    this.unitCost,
    this.unitPrice = Money.zero,
    this.discountType = DiscountType.none,
    this.discountValue = 0,
    this.notes,
  });

  final int productId;
  final int quantity;

  /// Valuation cost per base unit.
  ///
  /// Only consulted when the goods are entering the business from a virtual
  /// counterparty (a purchase, opening stock, an adjustment increase). When
  /// goods move between real locations the cost travels with them, because
  /// moving your own stock from one shelf to another does not change what it
  /// cost you.
  final Money? unitCost;

  /// Price shown on the accompanying delivery note, if any. A price here does
  /// not create revenue: that needs an invoice.
  final Money unitPrice;

  final DiscountType discountType;

  /// Basis points when [discountType] is percentage, cents when fixed amount.
  final int discountValue;
  final String? notes;

  /// Gross value of the line at [unitPrice].
  Money get grossValue => unitPrice * quantity;

  /// Resolved cash discount for the line.
  Money get discount => switch (discountType) {
    DiscountType.none => Money.zero,
    DiscountType.percentage => grossValue.percentage(discountValue),
    DiscountType.fixedAmount => Money(discountValue),
  };

  Money get lineTotal => grossValue - discount;

  factory StockMovementLine.fromJson(Map<String, dynamic> json) =>
      _$StockMovementLineFromJson(json);

  Map<String, dynamic> toJson() => _$StockMovementLineToJson(this);
}

/// A request to post a stock movement.
///
/// One request becomes one immutable document plus a balanced pair of ledger
/// entries per line.
@JsonSerializable()
class StockMovementRequest {
  const StockMovementRequest({
    required this.documentType,
    required this.sourceLocationId,
    required this.destinationLocationId,
    required this.lines,
    this.documentDate,
    this.agentId,
    this.shopId,
    this.referenceNote,
    this.notes,
    this.allowNegativeStock = false,
    this.negativeStockReason,
  });

  final StockDocumentType documentType;
  final int sourceLocationId;
  final int destinationLocationId;
  final List<StockMovementLine> lines;

  /// Defaults to now when omitted.
  final DateTime? documentDate;

  /// Denormalised party pointers, so agent-wise and shop-wise stock reports
  /// need no join through the location table.
  final int? agentId;
  final int? shopId;

  final String? referenceNote;
  final String? notes;

  /// Set only when the user has knowingly chosen to drive a real location
  /// negative. Requires the stock override permission, and the decision plus
  /// its reason are recorded on the document.
  final bool allowNegativeStock;
  final String? negativeStockReason;

  int get totalQuantity =>
      lines.fold(0, (total, line) => total + line.quantity);

  Money get subtotal => lines.map((line) => line.grossValue).sum;

  Money get discountTotal => lines.map((line) => line.discount).sum;

  Money get total => subtotal - discountTotal;

  factory StockMovementRequest.fromJson(Map<String, dynamic> json) =>
      _$StockMovementRequestFromJson(json);

  Map<String, dynamic> toJson() => _$StockMovementRequestToJson(this);
}

/// The result of posting a movement, with enough detail to confirm to the user
/// exactly what changed.
@JsonSerializable()
class StockMovementResult {
  const StockMovementResult({
    required this.transactionId,
    required this.documentNumber,
    required this.lineCount,
    required this.totalQuantity,
    required this.sourceBalances,
    required this.destinationBalances,
  });

  final int transactionId;
  final String documentNumber;
  final int lineCount;
  final int totalQuantity;

  /// Balance at the source location after posting, per product.
  final Map<int, int> sourceBalances;
  final Map<int, int> destinationBalances;

  factory StockMovementResult.fromJson(Map<String, dynamic> json) =>
      _$StockMovementResultFromJson(json);

  Map<String, dynamic> toJson() => _$StockMovementResultToJson(this);
}

/// A product's balance at one location.
@JsonSerializable()
class StockBalanceRow {
  const StockBalanceRow({
    required this.productId,
    required this.sku,
    required this.productName,
    required this.categoryName,
    required this.locationId,
    required this.locationName,
    required this.locationKind,
    required this.quantity,
    required this.averageCost,
    required this.reorderLevel,
  });

  final int productId;
  final String sku;
  final String productName;
  final String categoryName;
  final int locationId;
  final String locationName;
  final LocationKind locationKind;
  final int quantity;
  final Money averageCost;
  final int reorderLevel;

  Money get value => averageCost * quantity;

  bool get isNegative => quantity < 0;

  factory StockBalanceRow.fromJson(Map<String, dynamic> json) =>
      _$StockBalanceRowFromJson(json);

  Map<String, dynamic> toJson() => _$StockBalanceRowToJson(this);
}

/// One product across every location, for the stock overview grid.
@JsonSerializable()
class ProductStockRow {
  const ProductStockRow({
    required this.productId,
    required this.sku,
    required this.productName,
    required this.categoryName,
    required this.reorderLevel,
    required this.averageCost,
    required this.warehouseQuantity,
    required this.agentQuantity,
    required this.shopQuantity,
    required this.damagedQuantity,
    required this.inTransitQuantity,
  });

  final int productId;
  final String sku;
  final String productName;
  final String categoryName;
  final int reorderLevel;
  final Money averageCost;

  final int warehouseQuantity;
  final int agentQuantity;
  final int shopQuantity;
  final int damagedQuantity;
  final int inTransitQuantity;

  int get sellableQuantity => warehouseQuantity + agentQuantity + shopQuantity;

  Money get sellableValue => averageCost * sellableQuantity;

  bool get isLowStock => reorderLevel > 0 && sellableQuantity <= reorderLevel;

  bool get hasAnyStock =>
      sellableQuantity != 0 || damagedQuantity != 0 || inTransitQuantity != 0;

  factory ProductStockRow.fromJson(Map<String, dynamic> json) =>
      _$ProductStockRowFromJson(json);

  Map<String, dynamic> toJson() => _$ProductStockRowToJson(this);
}

/// One row of the stock ledger, as the movement history screen shows it.
@JsonSerializable()
class StockLedgerRow {
  const StockLedgerRow({
    required this.id,
    required this.occurredAt,
    required this.documentNumber,
    required this.documentType,
    required this.documentStatus,
    required this.locationName,
    required this.locationKind,
    required this.productId,
    required this.sku,
    required this.productName,
    required this.quantityDelta,
    required this.balanceAfter,
    required this.unitCost,
    required this.recordedBy,
    this.counterpartyName,
    this.narration,
  });

  final int id;
  final DateTime occurredAt;
  final String documentNumber;
  final StockDocumentType documentType;
  final StockDocumentStatus documentStatus;
  final String locationName;
  final LocationKind locationKind;
  final int productId;
  final String sku;
  final String productName;

  /// Signed: negative where goods left, positive where they arrived.
  final int quantityDelta;
  final int balanceAfter;
  final Money unitCost;
  final String recordedBy;

  /// The other end of the movement.
  final String? counterpartyName;
  final String? narration;

  bool get isInbound => quantityDelta > 0;

  Money get value => unitCost * quantityDelta.abs();

  factory StockLedgerRow.fromJson(Map<String, dynamic> json) =>
      _$StockLedgerRowFromJson(json);

  Map<String, dynamic> toJson() => _$StockLedgerRowToJson(this);
}

/// A reconciliation sheet line: what the system thinks is there, and what was
/// actually found.
@JsonSerializable()
class StockCountLine {
  const StockCountLine({
    required this.productId,
    required this.sku,
    required this.productName,
    required this.systemQuantity,
    this.countedQuantity,
    this.notes,
  });

  final int productId;
  final String sku;
  final String productName;
  final int systemQuantity;

  /// Null until somebody fills it in.
  final int? countedQuantity;
  final String? notes;

  bool get isCounted => countedQuantity != null;

  /// Positive when more was found than expected.
  int get variance =>
      countedQuantity == null ? 0 : countedQuantity! - systemQuantity;

  bool get hasVariance => isCounted && variance != 0;

  StockCountLine copyWith({
    int? countedQuantity,
    bool clearCount = false,
    String? notes,
  }) {
    return StockCountLine(
      productId: productId,
      sku: sku,
      productName: productName,
      systemQuantity: systemQuantity,
      countedQuantity: clearCount
          ? null
          : (countedQuantity ?? this.countedQuantity),
      notes: notes ?? this.notes,
    );
  }

  factory StockCountLine.fromJson(Map<String, dynamic> json) =>
      _$StockCountLineFromJson(json);

  Map<String, dynamic> toJson() => _$StockCountLineToJson(this);
}

/// A reconciliation and its lines.
@JsonSerializable()
class StockCountSheet {
  const StockCountSheet({
    required this.id,
    required this.documentNumber,
    required this.locationId,
    required this.locationName,
    required this.countDate,
    required this.status,
    required this.lines,
    this.increaseTransactionId,
    this.decreaseTransactionId,
    this.notes,
  });

  final int id;
  final String documentNumber;
  final int locationId;
  final String locationName;
  final DateTime countDate;
  final StockDocumentStatus status;
  final List<StockCountLine> lines;
  final int? increaseTransactionId;
  final int? decreaseTransactionId;
  final String? notes;

  bool get isPosted => status == StockDocumentStatus.posted;

  int get countedLineCount => lines.where((line) => line.isCounted).length;

  List<StockCountLine> get variances =>
      lines.where((line) => line.hasVariance).toList(growable: false);

  /// Units found over and above what the system expected.
  int get surplusUnits => variances
      .where((line) => line.variance > 0)
      .fold(0, (total, line) => total + line.variance);

  /// Units missing against what the system expected, as a positive number.
  int get shortageUnits => variances
      .where((line) => line.variance < 0)
      .fold(0, (total, line) => total - line.variance);

  bool get hasVariances => variances.isNotEmpty;

  factory StockCountSheet.fromJson(Map<String, dynamic> json) =>
      _$StockCountSheetFromJson(json);

  Map<String, dynamic> toJson() => _$StockCountSheetToJson(this);
}

/// A stock document as the register lists it.
@JsonSerializable()
class StockDocumentSummary {
  const StockDocumentSummary({
    required this.id,
    required this.documentNumber,
    required this.documentType,
    required this.status,
    required this.documentDate,
    required this.sourceName,
    required this.destinationName,
    required this.totalQuantity,
    required this.lineCount,
    required this.total,
    required this.createdBy,
    this.agentName,
    this.shopName,
    this.referenceNote,
    this.reversesDocumentNumber,
    this.reversedByDocumentNumber,
    this.hasNegativeOverride = false,
  });

  final int id;
  final String documentNumber;
  final StockDocumentType documentType;
  final StockDocumentStatus status;
  final DateTime documentDate;
  final String sourceName;
  final String destinationName;
  final int totalQuantity;
  final int lineCount;
  final Money total;
  final String createdBy;
  final String? agentName;
  final String? shopName;
  final String? referenceNote;

  /// Set when this document exists to undo another one.
  final String? reversesDocumentNumber;

  /// Set when this document has been undone by another one.
  final String? reversedByDocumentNumber;

  final bool hasNegativeOverride;

  bool get isCancelled => status == StockDocumentStatus.cancelled;
  bool get isReversal => reversesDocumentNumber != null;
  bool get canBeCancelled =>
      status == StockDocumentStatus.posted && reversedByDocumentNumber == null;

  factory StockDocumentSummary.fromJson(Map<String, dynamic> json) =>
      _$StockDocumentSummaryFromJson(json);

  Map<String, dynamic> toJson() => _$StockDocumentSummaryToJson(this);
}

/// One line of a stock document, as stored.
@JsonSerializable()
class StockDocumentLine {
  const StockDocumentLine({
    required this.lineNumber,
    required this.productId,
    required this.productName,
    required this.sku,
    required this.quantity,
    required this.unitCost,
    required this.unitPrice,
    required this.discount,
    required this.lineTotal,
    this.notes,
  });

  final int lineNumber;
  final int productId;

  /// The name as it was when the document was raised, not as it is now.
  final String productName;
  final String sku;
  final int quantity;
  final Money unitCost;
  final Money unitPrice;
  final Money discount;
  final Money lineTotal;
  final String? notes;

  factory StockDocumentLine.fromJson(Map<String, dynamic> json) =>
      _$StockDocumentLineFromJson(json);

  Map<String, dynamic> toJson() => _$StockDocumentLineToJson(this);
}

/// A stock document with its lines, for viewing or printing.
@JsonSerializable()
class StockDocumentDetail {
  const StockDocumentDetail({
    required this.summary,
    required this.lines,
    this.notes,
    this.cancelReason,
    this.overrideReason,
    this.cancelledBy,
  });

  final StockDocumentSummary summary;
  final List<StockDocumentLine> lines;
  final String? notes;
  final String? cancelReason;
  final String? overrideReason;
  final String? cancelledBy;

  Money get subtotal => lines.map((line) => line.lineTotal).sum;

  /// Value of the goods at the cost they were carried at.
  Money get costValue => lines.map((line) => line.unitCost * line.quantity).sum;

  factory StockDocumentDetail.fromJson(Map<String, dynamic> json) =>
      _$StockDocumentDetailFromJson(json);

  Map<String, dynamic> toJson() => _$StockDocumentDetailToJson(this);
}

/// How the stock document register is narrowed.
@JsonSerializable()
class StockDocumentFilter {
  const StockDocumentFilter({
    this.search = '',
    this.types = const {},
    this.status,
    this.agentId,
    this.shopId,
    this.locationId,
    this.from,
    this.to,
    this.limit = 300,
  });

  final String search;

  /// Empty means every type.
  final Set<StockDocumentType> types;
  final StockDocumentStatus? status;
  final int? agentId;
  final int? shopId;

  /// Matches documents with this location at either end.
  final int? locationId;
  final DateTime? from;
  final DateTime? to;
  final int limit;

  bool get hasAnyFilter =>
      search.trim().isNotEmpty ||
      types.isNotEmpty ||
      status != null ||
      agentId != null ||
      shopId != null ||
      locationId != null ||
      from != null ||
      to != null;

  StockDocumentFilter copyWith({
    String? search,
    Set<StockDocumentType>? types,
    StockDocumentStatus? status,
    bool clearStatus = false,
    int? agentId,
    bool clearAgent = false,
    int? shopId,
    bool clearShop = false,
    int? locationId,
    bool clearLocation = false,
    DateTime? from,
    bool clearFrom = false,
    DateTime? to,
    bool clearTo = false,
    int? limit,
  }) {
    return StockDocumentFilter(
      search: search ?? this.search,
      types: types ?? this.types,
      status: clearStatus ? null : (status ?? this.status),
      agentId: clearAgent ? null : (agentId ?? this.agentId),
      shopId: clearShop ? null : (shopId ?? this.shopId),
      locationId: clearLocation ? null : (locationId ?? this.locationId),
      from: clearFrom ? null : (from ?? this.from),
      to: clearTo ? null : (to ?? this.to),
      limit: limit ?? this.limit,
    );
  }

  factory StockDocumentFilter.fromJson(Map<String, dynamic> json) =>
      _$StockDocumentFilterFromJson(json);

  Map<String, dynamic> toJson() => _$StockDocumentFilterToJson(this);
}

/// How the stock ledger history is narrowed.
@JsonSerializable()
class StockLedgerFilter {
  const StockLedgerFilter({
    this.search = '',
    this.productId,
    this.locationId,
    this.from,
    this.to,
    this.includeVirtualLocations = false,
    this.limit = 500,
  });

  final String search;
  final int? productId;
  final int? locationId;
  final DateTime? from;
  final DateTime? to;

  /// The counterparty legs are hidden by default: an operator wants to see
  /// what moved in and out of their own locations, not the mirror rows.
  final bool includeVirtualLocations;
  final int limit;

  bool get hasAnyFilter =>
      search.trim().isNotEmpty ||
      productId != null ||
      locationId != null ||
      from != null ||
      to != null;

  StockLedgerFilter copyWith({
    String? search,
    int? productId,
    bool clearProduct = false,
    int? locationId,
    bool clearLocation = false,
    DateTime? from,
    bool clearFrom = false,
    DateTime? to,
    bool clearTo = false,
    bool? includeVirtualLocations,
    int? limit,
  }) {
    return StockLedgerFilter(
      search: search ?? this.search,
      productId: clearProduct ? null : (productId ?? this.productId),
      locationId: clearLocation ? null : (locationId ?? this.locationId),
      from: clearFrom ? null : (from ?? this.from),
      to: clearTo ? null : (to ?? this.to),
      includeVirtualLocations:
          includeVirtualLocations ?? this.includeVirtualLocations,
      limit: limit ?? this.limit,
    );
  }

  factory StockLedgerFilter.fromJson(Map<String, dynamic> json) =>
      _$StockLedgerFilterFromJson(json);

  Map<String, dynamic> toJson() => _$StockLedgerFilterToJson(this);
}

/// How the stock overview grid is narrowed.
@JsonSerializable()
class StockOverviewFilter {
  const StockOverviewFilter({
    this.search = '',
    this.categoryId,
    this.lowStockOnly = false,
    this.hideZeroStock = true,
  });

  final String search;
  final int? categoryId;
  final bool lowStockOnly;

  /// Products with nothing anywhere are hidden by default, because a stock
  /// report is about what is there.
  final bool hideZeroStock;

  bool get hasAnyFilter =>
      search.trim().isNotEmpty || categoryId != null || lowStockOnly;

  StockOverviewFilter copyWith({
    String? search,
    int? categoryId,
    bool clearCategory = false,
    bool? lowStockOnly,
    bool? hideZeroStock,
  }) {
    return StockOverviewFilter(
      search: search ?? this.search,
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      lowStockOnly: lowStockOnly ?? this.lowStockOnly,
      hideZeroStock: hideZeroStock ?? this.hideZeroStock,
    );
  }

  factory StockOverviewFilter.fromJson(Map<String, dynamic> json) =>
      _$StockOverviewFilterFromJson(json);

  Map<String, dynamic> toJson() => _$StockOverviewFilterToJson(this);
}

/// Human labels for document types.
String stockDocumentTypeLabel(StockDocumentType type) => switch (type) {
  StockDocumentType.openingStock => 'Opening stock',
  StockDocumentType.purchaseIn => 'Purchase',
  StockDocumentType.warehouseToAgent => 'Warehouse to agent',
  StockDocumentType.agentToShop => 'Agent to shop',
  StockDocumentType.warehouseToShop => 'Warehouse to shop',
  StockDocumentType.retailSale => 'Retail sale',
  StockDocumentType.customerToShopReturn => 'Customer return to shop',
  StockDocumentType.shopToAgentReturn => 'Shop return to agent',
  StockDocumentType.agentToWarehouseReturn => 'Agent return to warehouse',
  StockDocumentType.shopToWarehouseReturn => 'Shop return to warehouse',
  StockDocumentType.damageWriteOff => 'Damage write-off',
  StockDocumentType.adjustmentIncrease => 'Adjustment increase',
  StockDocumentType.adjustmentDecrease => 'Adjustment decrease',
  StockDocumentType.reconciliation => 'Reconciliation',
  StockDocumentType.interLocationTransfer => 'Internal transfer',
};

/// Short label for a ledger row's effect, used in the movement history.
String stockDocumentShortLabel(StockDocumentType type) => switch (type) {
  StockDocumentType.openingStock => 'Opening',
  StockDocumentType.purchaseIn => 'Purchase',
  StockDocumentType.warehouseToAgent => 'To agent',
  StockDocumentType.agentToShop => 'To shop',
  StockDocumentType.warehouseToShop => 'To shop',
  StockDocumentType.retailSale => 'Sold',
  StockDocumentType.customerToShopReturn => 'Return',
  StockDocumentType.shopToAgentReturn => 'Return',
  StockDocumentType.agentToWarehouseReturn => 'Return',
  StockDocumentType.shopToWarehouseReturn => 'Return',
  StockDocumentType.damageWriteOff => 'Damaged',
  StockDocumentType.adjustmentIncrease => 'Adjusted up',
  StockDocumentType.adjustmentDecrease => 'Adjusted down',
  StockDocumentType.reconciliation => 'Recount',
  StockDocumentType.interLocationTransfer => 'Transfer',
};
