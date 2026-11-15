// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stock_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StockMovementLine _$StockMovementLineFromJson(Map<String, dynamic> json) =>
    $checkedCreate('StockMovementLine', json, ($checkedConvert) {
      final val = StockMovementLine(
        productId: $checkedConvert('productId', (v) => (v as num).toInt()),
        quantity: $checkedConvert('quantity', (v) => (v as num).toInt()),
        unitCost: $checkedConvert(
          'unitCost',
          (v) => v == null ? null : Money.fromJson((v as num).toInt()),
        ),
        unitPrice: $checkedConvert(
          'unitPrice',
          (v) => v == null ? Money.zero : Money.fromJson((v as num).toInt()),
        ),
        discountType: $checkedConvert(
          'discountType',
          (v) =>
              $enumDecodeNullable(_$DiscountTypeEnumMap, v) ??
              DiscountType.none,
        ),
        discountValue: $checkedConvert(
          'discountValue',
          (v) => (v as num?)?.toInt() ?? 0,
        ),
        notes: $checkedConvert('notes', (v) => v as String?),
      );
      return val;
    });

Map<String, dynamic> _$StockMovementLineToJson(StockMovementLine instance) =>
    <String, dynamic>{
      'productId': instance.productId,
      'quantity': instance.quantity,
      'unitCost': ?instance.unitCost?.toJson(),
      'unitPrice': instance.unitPrice.toJson(),
      'discountType': _$DiscountTypeEnumMap[instance.discountType]!,
      'discountValue': instance.discountValue,
      'notes': ?instance.notes,
    };

const _$DiscountTypeEnumMap = {
  DiscountType.none: 'none',
  DiscountType.percentage: 'percentage',
  DiscountType.fixedAmount: 'fixedAmount',
};

StockMovementRequest _$StockMovementRequestFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('StockMovementRequest', json, ($checkedConvert) {
  final val = StockMovementRequest(
    documentType: $checkedConvert(
      'documentType',
      (v) => $enumDecode(_$StockDocumentTypeEnumMap, v),
    ),
    sourceLocationId: $checkedConvert(
      'sourceLocationId',
      (v) => (v as num).toInt(),
    ),
    destinationLocationId: $checkedConvert(
      'destinationLocationId',
      (v) => (v as num).toInt(),
    ),
    lines: $checkedConvert(
      'lines',
      (v) => (v as List<dynamic>)
          .map((e) => StockMovementLine.fromJson(e as Map<String, dynamic>))
          .toList(),
    ),
    documentDate: $checkedConvert(
      'documentDate',
      (v) => v == null ? null : DateTime.parse(v as String),
    ),
    agentId: $checkedConvert('agentId', (v) => (v as num?)?.toInt()),
    shopId: $checkedConvert('shopId', (v) => (v as num?)?.toInt()),
    referenceNote: $checkedConvert('referenceNote', (v) => v as String?),
    notes: $checkedConvert('notes', (v) => v as String?),
    allowNegativeStock: $checkedConvert(
      'allowNegativeStock',
      (v) => v as bool? ?? false,
    ),
    negativeStockReason: $checkedConvert(
      'negativeStockReason',
      (v) => v as String?,
    ),
  );
  return val;
});

Map<String, dynamic> _$StockMovementRequestToJson(
  StockMovementRequest instance,
) => <String, dynamic>{
  'documentType': _$StockDocumentTypeEnumMap[instance.documentType]!,
  'sourceLocationId': instance.sourceLocationId,
  'destinationLocationId': instance.destinationLocationId,
  'lines': instance.lines.map((e) => e.toJson()).toList(),
  'documentDate': ?instance.documentDate?.toIso8601String(),
  'agentId': ?instance.agentId,
  'shopId': ?instance.shopId,
  'referenceNote': ?instance.referenceNote,
  'notes': ?instance.notes,
  'allowNegativeStock': instance.allowNegativeStock,
  'negativeStockReason': ?instance.negativeStockReason,
};

const _$StockDocumentTypeEnumMap = {
  StockDocumentType.openingStock: 'openingStock',
  StockDocumentType.purchaseIn: 'purchaseIn',
  StockDocumentType.warehouseToAgent: 'warehouseToAgent',
  StockDocumentType.agentToShop: 'agentToShop',
  StockDocumentType.warehouseToShop: 'warehouseToShop',
  StockDocumentType.retailSale: 'retailSale',
  StockDocumentType.customerToShopReturn: 'customerToShopReturn',
  StockDocumentType.shopToAgentReturn: 'shopToAgentReturn',
  StockDocumentType.agentToWarehouseReturn: 'agentToWarehouseReturn',
  StockDocumentType.shopToWarehouseReturn: 'shopToWarehouseReturn',
  StockDocumentType.damageWriteOff: 'damageWriteOff',
  StockDocumentType.adjustmentIncrease: 'adjustmentIncrease',
  StockDocumentType.adjustmentDecrease: 'adjustmentDecrease',
  StockDocumentType.reconciliation: 'reconciliation',
  StockDocumentType.interLocationTransfer: 'interLocationTransfer',
};

StockMovementResult _$StockMovementResultFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('StockMovementResult', json, ($checkedConvert) {
  final val = StockMovementResult(
    transactionId: $checkedConvert('transactionId', (v) => (v as num).toInt()),
    documentNumber: $checkedConvert('documentNumber', (v) => v as String),
    lineCount: $checkedConvert('lineCount', (v) => (v as num).toInt()),
    totalQuantity: $checkedConvert('totalQuantity', (v) => (v as num).toInt()),
    sourceBalances: $checkedConvert(
      'sourceBalances',
      (v) => (v as Map<String, dynamic>).map(
        (k, e) => MapEntry(int.parse(k), (e as num).toInt()),
      ),
    ),
    destinationBalances: $checkedConvert(
      'destinationBalances',
      (v) => (v as Map<String, dynamic>).map(
        (k, e) => MapEntry(int.parse(k), (e as num).toInt()),
      ),
    ),
  );
  return val;
});

Map<String, dynamic> _$StockMovementResultToJson(
  StockMovementResult instance,
) => <String, dynamic>{
  'transactionId': instance.transactionId,
  'documentNumber': instance.documentNumber,
  'lineCount': instance.lineCount,
  'totalQuantity': instance.totalQuantity,
  'sourceBalances': instance.sourceBalances.map(
    (k, e) => MapEntry(k.toString(), e),
  ),
  'destinationBalances': instance.destinationBalances.map(
    (k, e) => MapEntry(k.toString(), e),
  ),
};

StockBalanceRow _$StockBalanceRowFromJson(Map<String, dynamic> json) =>
    $checkedCreate('StockBalanceRow', json, ($checkedConvert) {
      final val = StockBalanceRow(
        productId: $checkedConvert('productId', (v) => (v as num).toInt()),
        sku: $checkedConvert('sku', (v) => v as String),
        productName: $checkedConvert('productName', (v) => v as String),
        categoryName: $checkedConvert('categoryName', (v) => v as String),
        locationId: $checkedConvert('locationId', (v) => (v as num).toInt()),
        locationName: $checkedConvert('locationName', (v) => v as String),
        locationKind: $checkedConvert(
          'locationKind',
          (v) => $enumDecode(_$LocationKindEnumMap, v),
        ),
        quantity: $checkedConvert('quantity', (v) => (v as num).toInt()),
        averageCost: $checkedConvert(
          'averageCost',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        reorderLevel: $checkedConvert(
          'reorderLevel',
          (v) => (v as num).toInt(),
        ),
      );
      return val;
    });

Map<String, dynamic> _$StockBalanceRowToJson(StockBalanceRow instance) =>
    <String, dynamic>{
      'productId': instance.productId,
      'sku': instance.sku,
      'productName': instance.productName,
      'categoryName': instance.categoryName,
      'locationId': instance.locationId,
      'locationName': instance.locationName,
      'locationKind': _$LocationKindEnumMap[instance.locationKind]!,
      'quantity': instance.quantity,
      'averageCost': instance.averageCost.toJson(),
      'reorderLevel': instance.reorderLevel,
    };

const _$LocationKindEnumMap = {
  LocationKind.warehouse: 'warehouse',
  LocationKind.agent: 'agent',
  LocationKind.shop: 'shop',
  LocationKind.damaged: 'damaged',
  LocationKind.supplier: 'supplier',
  LocationKind.customer: 'customer',
  LocationKind.adjustment: 'adjustment',
  LocationKind.inTransit: 'inTransit',
};

ProductStockRow _$ProductStockRowFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('ProductStockRow', json, ($checkedConvert) {
  final val = ProductStockRow(
    productId: $checkedConvert('productId', (v) => (v as num).toInt()),
    sku: $checkedConvert('sku', (v) => v as String),
    productName: $checkedConvert('productName', (v) => v as String),
    categoryName: $checkedConvert('categoryName', (v) => v as String),
    reorderLevel: $checkedConvert('reorderLevel', (v) => (v as num).toInt()),
    averageCost: $checkedConvert(
      'averageCost',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    warehouseQuantity: $checkedConvert(
      'warehouseQuantity',
      (v) => (v as num).toInt(),
    ),
    agentQuantity: $checkedConvert('agentQuantity', (v) => (v as num).toInt()),
    shopQuantity: $checkedConvert('shopQuantity', (v) => (v as num).toInt()),
    damagedQuantity: $checkedConvert(
      'damagedQuantity',
      (v) => (v as num).toInt(),
    ),
    inTransitQuantity: $checkedConvert(
      'inTransitQuantity',
      (v) => (v as num).toInt(),
    ),
  );
  return val;
});

Map<String, dynamic> _$ProductStockRowToJson(ProductStockRow instance) =>
    <String, dynamic>{
      'productId': instance.productId,
      'sku': instance.sku,
      'productName': instance.productName,
      'categoryName': instance.categoryName,
      'reorderLevel': instance.reorderLevel,
      'averageCost': instance.averageCost.toJson(),
      'warehouseQuantity': instance.warehouseQuantity,
      'agentQuantity': instance.agentQuantity,
      'shopQuantity': instance.shopQuantity,
      'damagedQuantity': instance.damagedQuantity,
      'inTransitQuantity': instance.inTransitQuantity,
    };

StockLedgerRow _$StockLedgerRowFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('StockLedgerRow', json, ($checkedConvert) {
  final val = StockLedgerRow(
    id: $checkedConvert('id', (v) => (v as num).toInt()),
    occurredAt: $checkedConvert(
      'occurredAt',
      (v) => DateTime.parse(v as String),
    ),
    documentNumber: $checkedConvert('documentNumber', (v) => v as String),
    documentType: $checkedConvert(
      'documentType',
      (v) => $enumDecode(_$StockDocumentTypeEnumMap, v),
    ),
    documentStatus: $checkedConvert(
      'documentStatus',
      (v) => $enumDecode(_$StockDocumentStatusEnumMap, v),
    ),
    locationName: $checkedConvert('locationName', (v) => v as String),
    locationKind: $checkedConvert(
      'locationKind',
      (v) => $enumDecode(_$LocationKindEnumMap, v),
    ),
    productId: $checkedConvert('productId', (v) => (v as num).toInt()),
    sku: $checkedConvert('sku', (v) => v as String),
    productName: $checkedConvert('productName', (v) => v as String),
    quantityDelta: $checkedConvert('quantityDelta', (v) => (v as num).toInt()),
    balanceAfter: $checkedConvert('balanceAfter', (v) => (v as num).toInt()),
    unitCost: $checkedConvert(
      'unitCost',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    recordedBy: $checkedConvert('recordedBy', (v) => v as String),
    counterpartyName: $checkedConvert('counterpartyName', (v) => v as String?),
    narration: $checkedConvert('narration', (v) => v as String?),
  );
  return val;
});

Map<String, dynamic> _$StockLedgerRowToJson(StockLedgerRow instance) =>
    <String, dynamic>{
      'id': instance.id,
      'occurredAt': instance.occurredAt.toIso8601String(),
      'documentNumber': instance.documentNumber,
      'documentType': _$StockDocumentTypeEnumMap[instance.documentType]!,
      'documentStatus': _$StockDocumentStatusEnumMap[instance.documentStatus]!,
      'locationName': instance.locationName,
      'locationKind': _$LocationKindEnumMap[instance.locationKind]!,
      'productId': instance.productId,
      'sku': instance.sku,
      'productName': instance.productName,
      'quantityDelta': instance.quantityDelta,
      'balanceAfter': instance.balanceAfter,
      'unitCost': instance.unitCost.toJson(),
      'recordedBy': instance.recordedBy,
      'counterpartyName': ?instance.counterpartyName,
      'narration': ?instance.narration,
    };

const _$StockDocumentStatusEnumMap = {
  StockDocumentStatus.draft: 'draft',
  StockDocumentStatus.posted: 'posted',
  StockDocumentStatus.cancelled: 'cancelled',
};

StockCountLine _$StockCountLineFromJson(Map<String, dynamic> json) =>
    $checkedCreate('StockCountLine', json, ($checkedConvert) {
      final val = StockCountLine(
        productId: $checkedConvert('productId', (v) => (v as num).toInt()),
        sku: $checkedConvert('sku', (v) => v as String),
        productName: $checkedConvert('productName', (v) => v as String),
        systemQuantity: $checkedConvert(
          'systemQuantity',
          (v) => (v as num).toInt(),
        ),
        countedQuantity: $checkedConvert(
          'countedQuantity',
          (v) => (v as num?)?.toInt(),
        ),
        notes: $checkedConvert('notes', (v) => v as String?),
      );
      return val;
    });

Map<String, dynamic> _$StockCountLineToJson(StockCountLine instance) =>
    <String, dynamic>{
      'productId': instance.productId,
      'sku': instance.sku,
      'productName': instance.productName,
      'systemQuantity': instance.systemQuantity,
      'countedQuantity': ?instance.countedQuantity,
      'notes': ?instance.notes,
    };

StockCountSheet _$StockCountSheetFromJson(Map<String, dynamic> json) =>
    $checkedCreate('StockCountSheet', json, ($checkedConvert) {
      final val = StockCountSheet(
        id: $checkedConvert('id', (v) => (v as num).toInt()),
        documentNumber: $checkedConvert('documentNumber', (v) => v as String),
        locationId: $checkedConvert('locationId', (v) => (v as num).toInt()),
        locationName: $checkedConvert('locationName', (v) => v as String),
        countDate: $checkedConvert(
          'countDate',
          (v) => DateTime.parse(v as String),
        ),
        status: $checkedConvert(
          'status',
          (v) => $enumDecode(_$StockDocumentStatusEnumMap, v),
        ),
        lines: $checkedConvert(
          'lines',
          (v) => (v as List<dynamic>)
              .map((e) => StockCountLine.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
        increaseTransactionId: $checkedConvert(
          'increaseTransactionId',
          (v) => (v as num?)?.toInt(),
        ),
        decreaseTransactionId: $checkedConvert(
          'decreaseTransactionId',
          (v) => (v as num?)?.toInt(),
        ),
        notes: $checkedConvert('notes', (v) => v as String?),
      );
      return val;
    });

Map<String, dynamic> _$StockCountSheetToJson(StockCountSheet instance) =>
    <String, dynamic>{
      'id': instance.id,
      'documentNumber': instance.documentNumber,
      'locationId': instance.locationId,
      'locationName': instance.locationName,
      'countDate': instance.countDate.toIso8601String(),
      'status': _$StockDocumentStatusEnumMap[instance.status]!,
      'lines': instance.lines.map((e) => e.toJson()).toList(),
      'increaseTransactionId': ?instance.increaseTransactionId,
      'decreaseTransactionId': ?instance.decreaseTransactionId,
      'notes': ?instance.notes,
    };

StockDocumentSummary _$StockDocumentSummaryFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('StockDocumentSummary', json, ($checkedConvert) {
  final val = StockDocumentSummary(
    id: $checkedConvert('id', (v) => (v as num).toInt()),
    documentNumber: $checkedConvert('documentNumber', (v) => v as String),
    documentType: $checkedConvert(
      'documentType',
      (v) => $enumDecode(_$StockDocumentTypeEnumMap, v),
    ),
    status: $checkedConvert(
      'status',
      (v) => $enumDecode(_$StockDocumentStatusEnumMap, v),
    ),
    documentDate: $checkedConvert(
      'documentDate',
      (v) => DateTime.parse(v as String),
    ),
    sourceName: $checkedConvert('sourceName', (v) => v as String),
    destinationName: $checkedConvert('destinationName', (v) => v as String),
    totalQuantity: $checkedConvert('totalQuantity', (v) => (v as num).toInt()),
    lineCount: $checkedConvert('lineCount', (v) => (v as num).toInt()),
    total: $checkedConvert('total', (v) => Money.fromJson((v as num).toInt())),
    createdBy: $checkedConvert('createdBy', (v) => v as String),
    agentName: $checkedConvert('agentName', (v) => v as String?),
    shopName: $checkedConvert('shopName', (v) => v as String?),
    referenceNote: $checkedConvert('referenceNote', (v) => v as String?),
    reversesDocumentNumber: $checkedConvert(
      'reversesDocumentNumber',
      (v) => v as String?,
    ),
    reversedByDocumentNumber: $checkedConvert(
      'reversedByDocumentNumber',
      (v) => v as String?,
    ),
    hasNegativeOverride: $checkedConvert(
      'hasNegativeOverride',
      (v) => v as bool? ?? false,
    ),
  );
  return val;
});

Map<String, dynamic> _$StockDocumentSummaryToJson(
  StockDocumentSummary instance,
) => <String, dynamic>{
  'id': instance.id,
  'documentNumber': instance.documentNumber,
  'documentType': _$StockDocumentTypeEnumMap[instance.documentType]!,
  'status': _$StockDocumentStatusEnumMap[instance.status]!,
  'documentDate': instance.documentDate.toIso8601String(),
  'sourceName': instance.sourceName,
  'destinationName': instance.destinationName,
  'totalQuantity': instance.totalQuantity,
  'lineCount': instance.lineCount,
  'total': instance.total.toJson(),
  'createdBy': instance.createdBy,
  'agentName': ?instance.agentName,
  'shopName': ?instance.shopName,
  'referenceNote': ?instance.referenceNote,
  'reversesDocumentNumber': ?instance.reversesDocumentNumber,
  'reversedByDocumentNumber': ?instance.reversedByDocumentNumber,
  'hasNegativeOverride': instance.hasNegativeOverride,
};

StockDocumentLine _$StockDocumentLineFromJson(Map<String, dynamic> json) =>
    $checkedCreate('StockDocumentLine', json, ($checkedConvert) {
      final val = StockDocumentLine(
        lineNumber: $checkedConvert('lineNumber', (v) => (v as num).toInt()),
        productId: $checkedConvert('productId', (v) => (v as num).toInt()),
        productName: $checkedConvert('productName', (v) => v as String),
        sku: $checkedConvert('sku', (v) => v as String),
        quantity: $checkedConvert('quantity', (v) => (v as num).toInt()),
        unitCost: $checkedConvert(
          'unitCost',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        unitPrice: $checkedConvert(
          'unitPrice',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        discount: $checkedConvert(
          'discount',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        lineTotal: $checkedConvert(
          'lineTotal',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        notes: $checkedConvert('notes', (v) => v as String?),
      );
      return val;
    });

Map<String, dynamic> _$StockDocumentLineToJson(StockDocumentLine instance) =>
    <String, dynamic>{
      'lineNumber': instance.lineNumber,
      'productId': instance.productId,
      'productName': instance.productName,
      'sku': instance.sku,
      'quantity': instance.quantity,
      'unitCost': instance.unitCost.toJson(),
      'unitPrice': instance.unitPrice.toJson(),
      'discount': instance.discount.toJson(),
      'lineTotal': instance.lineTotal.toJson(),
      'notes': ?instance.notes,
    };

StockDocumentDetail _$StockDocumentDetailFromJson(Map<String, dynamic> json) =>
    $checkedCreate('StockDocumentDetail', json, ($checkedConvert) {
      final val = StockDocumentDetail(
        summary: $checkedConvert(
          'summary',
          (v) => StockDocumentSummary.fromJson(v as Map<String, dynamic>),
        ),
        lines: $checkedConvert(
          'lines',
          (v) => (v as List<dynamic>)
              .map((e) => StockDocumentLine.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
        notes: $checkedConvert('notes', (v) => v as String?),
        cancelReason: $checkedConvert('cancelReason', (v) => v as String?),
        overrideReason: $checkedConvert('overrideReason', (v) => v as String?),
        cancelledBy: $checkedConvert('cancelledBy', (v) => v as String?),
      );
      return val;
    });

Map<String, dynamic> _$StockDocumentDetailToJson(
  StockDocumentDetail instance,
) => <String, dynamic>{
  'summary': instance.summary.toJson(),
  'lines': instance.lines.map((e) => e.toJson()).toList(),
  'notes': ?instance.notes,
  'cancelReason': ?instance.cancelReason,
  'overrideReason': ?instance.overrideReason,
  'cancelledBy': ?instance.cancelledBy,
};

StockDocumentFilter _$StockDocumentFilterFromJson(Map<String, dynamic> json) =>
    $checkedCreate('StockDocumentFilter', json, ($checkedConvert) {
      final val = StockDocumentFilter(
        search: $checkedConvert('search', (v) => v as String? ?? ''),
        types: $checkedConvert(
          'types',
          (v) =>
              (v as List<dynamic>?)
                  ?.map((e) => $enumDecode(_$StockDocumentTypeEnumMap, e))
                  .toSet() ??
              const {},
        ),
        status: $checkedConvert(
          'status',
          (v) => $enumDecodeNullable(_$StockDocumentStatusEnumMap, v),
        ),
        agentId: $checkedConvert('agentId', (v) => (v as num?)?.toInt()),
        shopId: $checkedConvert('shopId', (v) => (v as num?)?.toInt()),
        locationId: $checkedConvert('locationId', (v) => (v as num?)?.toInt()),
        from: $checkedConvert(
          'from',
          (v) => v == null ? null : DateTime.parse(v as String),
        ),
        to: $checkedConvert(
          'to',
          (v) => v == null ? null : DateTime.parse(v as String),
        ),
        limit: $checkedConvert('limit', (v) => (v as num?)?.toInt() ?? 300),
      );
      return val;
    });

Map<String, dynamic> _$StockDocumentFilterToJson(
  StockDocumentFilter instance,
) => <String, dynamic>{
  'search': instance.search,
  'types': instance.types.map((e) => _$StockDocumentTypeEnumMap[e]!).toList(),
  'status': ?_$StockDocumentStatusEnumMap[instance.status],
  'agentId': ?instance.agentId,
  'shopId': ?instance.shopId,
  'locationId': ?instance.locationId,
  'from': ?instance.from?.toIso8601String(),
  'to': ?instance.to?.toIso8601String(),
  'limit': instance.limit,
};

StockLedgerFilter _$StockLedgerFilterFromJson(Map<String, dynamic> json) =>
    $checkedCreate('StockLedgerFilter', json, ($checkedConvert) {
      final val = StockLedgerFilter(
        search: $checkedConvert('search', (v) => v as String? ?? ''),
        productId: $checkedConvert('productId', (v) => (v as num?)?.toInt()),
        locationId: $checkedConvert('locationId', (v) => (v as num?)?.toInt()),
        from: $checkedConvert(
          'from',
          (v) => v == null ? null : DateTime.parse(v as String),
        ),
        to: $checkedConvert(
          'to',
          (v) => v == null ? null : DateTime.parse(v as String),
        ),
        includeVirtualLocations: $checkedConvert(
          'includeVirtualLocations',
          (v) => v as bool? ?? false,
        ),
        limit: $checkedConvert('limit', (v) => (v as num?)?.toInt() ?? 500),
      );
      return val;
    });

Map<String, dynamic> _$StockLedgerFilterToJson(StockLedgerFilter instance) =>
    <String, dynamic>{
      'search': instance.search,
      'productId': ?instance.productId,
      'locationId': ?instance.locationId,
      'from': ?instance.from?.toIso8601String(),
      'to': ?instance.to?.toIso8601String(),
      'includeVirtualLocations': instance.includeVirtualLocations,
      'limit': instance.limit,
    };

StockOverviewFilter _$StockOverviewFilterFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('StockOverviewFilter', json, ($checkedConvert) {
  final val = StockOverviewFilter(
    search: $checkedConvert('search', (v) => v as String? ?? ''),
    categoryId: $checkedConvert('categoryId', (v) => (v as num?)?.toInt()),
    lowStockOnly: $checkedConvert('lowStockOnly', (v) => v as bool? ?? false),
    hideZeroStock: $checkedConvert('hideZeroStock', (v) => v as bool? ?? true),
  );
  return val;
});

Map<String, dynamic> _$StockOverviewFilterToJson(
  StockOverviewFilter instance,
) => <String, dynamic>{
  'search': instance.search,
  'categoryId': ?instance.categoryId,
  'lowStockOnly': instance.lowStockOnly,
  'hideZeroStock': instance.hideZeroStock,
};
