// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'invoice_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

NoStockMovement _$NoStockMovementFromJson(Map<String, dynamic> json) =>
    $checkedCreate('NoStockMovement', json, ($checkedConvert) {
      final val = NoStockMovement();
      return val;
    });

Map<String, dynamic> _$NoStockMovementToJson(NoStockMovement instance) =>
    <String, dynamic>{};

BillExistingDelivery _$BillExistingDeliveryFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('BillExistingDelivery', json, ($checkedConvert) {
  final val = BillExistingDelivery(
    $checkedConvert('stockTransactionId', (v) => (v as num).toInt()),
  );
  return val;
});

Map<String, dynamic> _$BillExistingDeliveryToJson(
  BillExistingDelivery instance,
) => <String, dynamic>{'stockTransactionId': instance.stockTransactionId};

MoveStockWithInvoice _$MoveStockWithInvoiceFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('MoveStockWithInvoice', json, ($checkedConvert) {
  final val = MoveStockWithInvoice(
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
  );
  return val;
});

Map<String, dynamic> _$MoveStockWithInvoiceToJson(
  MoveStockWithInvoice instance,
) => <String, dynamic>{
  'documentType': _$StockDocumentTypeEnumMap[instance.documentType]!,
  'sourceLocationId': instance.sourceLocationId,
  'destinationLocationId': instance.destinationLocationId,
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

InvoiceLineRequest _$InvoiceLineRequestFromJson(Map<String, dynamic> json) =>
    $checkedCreate('InvoiceLineRequest', json, ($checkedConvert) {
      final val = InvoiceLineRequest(
        productId: $checkedConvert('productId', (v) => (v as num).toInt()),
        quantity: $checkedConvert('quantity', (v) => (v as num).toInt()),
        unitPrice: $checkedConvert(
          'unitPrice',
          (v) => Money.fromJson((v as num).toInt()),
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

Map<String, dynamic> _$InvoiceLineRequestToJson(InvoiceLineRequest instance) =>
    <String, dynamic>{
      'productId': instance.productId,
      'quantity': instance.quantity,
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

ImmediatePayment _$ImmediatePaymentFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ImmediatePayment', json, ($checkedConvert) {
      final val = ImmediatePayment(
        method: $checkedConvert(
          'method',
          (v) => $enumDecode(_$PaymentMethodEnumMap, v),
        ),
        amount: $checkedConvert(
          'amount',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        referenceNumber: $checkedConvert(
          'referenceNumber',
          (v) => v as String?,
        ),
        bankName: $checkedConvert('bankName', (v) => v as String?),
        chequeNumber: $checkedConvert('chequeNumber', (v) => v as String?),
        chequeDate: $checkedConvert(
          'chequeDate',
          (v) => v == null ? null : DateTime.parse(v as String),
        ),
        chequeBranch: $checkedConvert('chequeBranch', (v) => v as String?),
      );
      return val;
    });

Map<String, dynamic> _$ImmediatePaymentToJson(ImmediatePayment instance) =>
    <String, dynamic>{
      'method': _$PaymentMethodEnumMap[instance.method]!,
      'amount': instance.amount.toJson(),
      'referenceNumber': ?instance.referenceNumber,
      'bankName': ?instance.bankName,
      'chequeNumber': ?instance.chequeNumber,
      'chequeDate': ?instance.chequeDate?.toIso8601String(),
      'chequeBranch': ?instance.chequeBranch,
    };

const _$PaymentMethodEnumMap = {
  PaymentMethod.cash: 'cash',
  PaymentMethod.bankTransfer: 'bankTransfer',
  PaymentMethod.cheque: 'cheque',
  PaymentMethod.cardOrDigital: 'cardOrDigital',
  PaymentMethod.creditNote: 'creditNote',
  PaymentMethod.openingBalance: 'openingBalance',
};

InvoiceRequest _$InvoiceRequestFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('InvoiceRequest', json, ($checkedConvert) {
  final val = InvoiceRequest(
    kind: $checkedConvert('kind', (v) => $enumDecode(_$InvoiceKindEnumMap, v)),
    lines: $checkedConvert(
      'lines',
      (v) => (v as List<dynamic>)
          .map((e) => InvoiceLineRequest.fromJson(e as Map<String, dynamic>))
          .toList(),
    ),
    agentId: $checkedConvert('agentId', (v) => (v as num?)?.toInt()),
    shopId: $checkedConvert('shopId', (v) => (v as num?)?.toInt()),
    customerName: $checkedConvert('customerName', (v) => v as String?),
    customerPhone: $checkedConvert('customerPhone', (v) => v as String?),
    invoiceDate: $checkedConvert(
      'invoiceDate',
      (v) => v == null ? null : DateTime.parse(v as String),
    ),
    dueDate: $checkedConvert(
      'dueDate',
      (v) => v == null ? null : DateTime.parse(v as String),
    ),
    invoiceDiscountType: $checkedConvert(
      'invoiceDiscountType',
      (v) => $enumDecodeNullable(_$DiscountTypeEnumMap, v) ?? DiscountType.none,
    ),
    invoiceDiscountValue: $checkedConvert(
      'invoiceDiscountValue',
      (v) => (v as num?)?.toInt() ?? 0,
    ),
    discountReason: $checkedConvert('discountReason', (v) => v as String?),
    stockLinkage: $checkedConvert(
      'stockLinkage',
      (v) => v == null
          ? const NoStockMovement()
          : InvoiceStockLinkage.fromJson(v as Map<String, dynamic>),
    ),
    payment: $checkedConvert(
      'payment',
      (v) => v == null
          ? null
          : ImmediatePayment.fromJson(v as Map<String, dynamic>),
    ),
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

Map<String, dynamic> _$InvoiceRequestToJson(
  InvoiceRequest instance,
) => <String, dynamic>{
  'kind': _$InvoiceKindEnumMap[instance.kind]!,
  'lines': instance.lines.map((e) => e.toJson()).toList(),
  'agentId': ?instance.agentId,
  'shopId': ?instance.shopId,
  'customerName': ?instance.customerName,
  'customerPhone': ?instance.customerPhone,
  'invoiceDate': ?instance.invoiceDate?.toIso8601String(),
  'dueDate': ?instance.dueDate?.toIso8601String(),
  'invoiceDiscountType': _$DiscountTypeEnumMap[instance.invoiceDiscountType]!,
  'invoiceDiscountValue': instance.invoiceDiscountValue,
  'discountReason': ?instance.discountReason,
  'stockLinkage': instance.stockLinkage.toJson(),
  'payment': ?instance.payment?.toJson(),
  'notes': ?instance.notes,
  'allowNegativeStock': instance.allowNegativeStock,
  'negativeStockReason': ?instance.negativeStockReason,
};

const _$InvoiceKindEnumMap = {
  InvoiceKind.agentInvoice: 'agentInvoice',
  InvoiceKind.shopInvoice: 'shopInvoice',
  InvoiceKind.retailSale: 'retailSale',
};

InvoiceTotals _$InvoiceTotalsFromJson(Map<String, dynamic> json) =>
    $checkedCreate('InvoiceTotals', json, ($checkedConvert) {
      final val = InvoiceTotals(
        gross: $checkedConvert(
          'gross',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        itemDiscount: $checkedConvert(
          'itemDiscount',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        invoiceDiscount: $checkedConvert(
          'invoiceDiscount',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        net: $checkedConvert('net', (v) => Money.fromJson((v as num).toInt())),
      );
      return val;
    });

Map<String, dynamic> _$InvoiceTotalsToJson(InvoiceTotals instance) =>
    <String, dynamic>{
      'gross': instance.gross.toJson(),
      'itemDiscount': instance.itemDiscount.toJson(),
      'invoiceDiscount': instance.invoiceDiscount.toJson(),
      'net': instance.net.toJson(),
    };

InvoiceSummary _$InvoiceSummaryFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('InvoiceSummary', json, ($checkedConvert) {
  final val = InvoiceSummary(
    id: $checkedConvert('id', (v) => (v as num).toInt()),
    invoiceNumber: $checkedConvert('invoiceNumber', (v) => v as String),
    kind: $checkedConvert('kind', (v) => $enumDecode(_$InvoiceKindEnumMap, v)),
    status: $checkedConvert(
      'status',
      (v) => $enumDecode(_$InvoiceStatusEnumMap, v),
    ),
    invoiceDate: $checkedConvert(
      'invoiceDate',
      (v) => DateTime.parse(v as String),
    ),
    partyType: $checkedConvert(
      'partyType',
      (v) => $enumDecode(_$PartyTypeEnumMap, v),
    ),
    partyName: $checkedConvert('partyName', (v) => v as String),
    gross: $checkedConvert('gross', (v) => Money.fromJson((v as num).toInt())),
    itemDiscount: $checkedConvert(
      'itemDiscount',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    invoiceDiscount: $checkedConvert(
      'invoiceDiscount',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    net: $checkedConvert('net', (v) => Money.fromJson((v as num).toInt())),
    cost: $checkedConvert('cost', (v) => Money.fromJson((v as num).toInt())),
    settled: $checkedConvert(
      'settled',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    creditApplied: $checkedConvert(
      'creditApplied',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    pendingCheques: $checkedConvert(
      'pendingCheques',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    lineCount: $checkedConvert('lineCount', (v) => (v as num).toInt()),
    createdBy: $checkedConvert('createdBy', (v) => v as String),
    agentId: $checkedConvert('agentId', (v) => (v as num?)?.toInt()),
    shopId: $checkedConvert('shopId', (v) => (v as num?)?.toInt()),
    agentName: $checkedConvert('agentName', (v) => v as String?),
    dueDate: $checkedConvert(
      'dueDate',
      (v) => v == null ? null : DateTime.parse(v as String),
    ),
    stockTransactionId: $checkedConvert(
      'stockTransactionId',
      (v) => (v as num?)?.toInt(),
    ),
    stockDocumentNumber: $checkedConvert(
      'stockDocumentNumber',
      (v) => v as String?,
    ),
    discountReason: $checkedConvert('discountReason', (v) => v as String?),
    discountApprovedBy: $checkedConvert(
      'discountApprovedBy',
      (v) => v as String?,
    ),
  );
  return val;
});

Map<String, dynamic> _$InvoiceSummaryToJson(InvoiceSummary instance) =>
    <String, dynamic>{
      'id': instance.id,
      'invoiceNumber': instance.invoiceNumber,
      'kind': _$InvoiceKindEnumMap[instance.kind]!,
      'status': _$InvoiceStatusEnumMap[instance.status]!,
      'invoiceDate': instance.invoiceDate.toIso8601String(),
      'dueDate': ?instance.dueDate?.toIso8601String(),
      'partyType': _$PartyTypeEnumMap[instance.partyType]!,
      'partyName': instance.partyName,
      'agentId': ?instance.agentId,
      'shopId': ?instance.shopId,
      'agentName': ?instance.agentName,
      'gross': instance.gross.toJson(),
      'itemDiscount': instance.itemDiscount.toJson(),
      'invoiceDiscount': instance.invoiceDiscount.toJson(),
      'net': instance.net.toJson(),
      'cost': instance.cost.toJson(),
      'settled': instance.settled.toJson(),
      'creditApplied': instance.creditApplied.toJson(),
      'pendingCheques': instance.pendingCheques.toJson(),
      'lineCount': instance.lineCount,
      'createdBy': instance.createdBy,
      'stockTransactionId': ?instance.stockTransactionId,
      'stockDocumentNumber': ?instance.stockDocumentNumber,
      'discountReason': ?instance.discountReason,
      'discountApprovedBy': ?instance.discountApprovedBy,
    };

const _$InvoiceStatusEnumMap = {
  InvoiceStatus.draft: 'draft',
  InvoiceStatus.posted: 'posted',
  InvoiceStatus.cancelled: 'cancelled',
};

const _$PartyTypeEnumMap = {
  PartyType.agent: 'agent',
  PartyType.shop: 'shop',
  PartyType.customer: 'customer',
  PartyType.employee: 'employee',
  PartyType.supplier: 'supplier',
};

InvoiceLine _$InvoiceLineFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('InvoiceLine', json, ($checkedConvert) {
  final val = InvoiceLine(
    lineNumber: $checkedConvert('lineNumber', (v) => (v as num).toInt()),
    productId: $checkedConvert('productId', (v) => (v as num).toInt()),
    productName: $checkedConvert('productName', (v) => v as String),
    sku: $checkedConvert('sku', (v) => v as String),
    quantity: $checkedConvert('quantity', (v) => (v as num).toInt()),
    unitPrice: $checkedConvert(
      'unitPrice',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    gross: $checkedConvert('gross', (v) => Money.fromJson((v as num).toInt())),
    discountType: $checkedConvert(
      'discountType',
      (v) => $enumDecode(_$DiscountTypeEnumMap, v),
    ),
    discountValue: $checkedConvert('discountValue', (v) => (v as num).toInt()),
    discount: $checkedConvert(
      'discount',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    net: $checkedConvert('net', (v) => Money.fromJson((v as num).toInt())),
    unitCost: $checkedConvert(
      'unitCost',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    returnedQuantity: $checkedConvert(
      'returnedQuantity',
      (v) => (v as num).toInt(),
    ),
    notes: $checkedConvert('notes', (v) => v as String?),
  );
  return val;
});

Map<String, dynamic> _$InvoiceLineToJson(InvoiceLine instance) =>
    <String, dynamic>{
      'lineNumber': instance.lineNumber,
      'productId': instance.productId,
      'productName': instance.productName,
      'sku': instance.sku,
      'quantity': instance.quantity,
      'unitPrice': instance.unitPrice.toJson(),
      'gross': instance.gross.toJson(),
      'discountType': _$DiscountTypeEnumMap[instance.discountType]!,
      'discountValue': instance.discountValue,
      'discount': instance.discount.toJson(),
      'net': instance.net.toJson(),
      'unitCost': instance.unitCost.toJson(),
      'returnedQuantity': instance.returnedQuantity,
      'notes': ?instance.notes,
    };

InvoiceDetail _$InvoiceDetailFromJson(Map<String, dynamic> json) =>
    $checkedCreate('InvoiceDetail', json, ($checkedConvert) {
      final val = InvoiceDetail(
        summary: $checkedConvert(
          'summary',
          (v) => InvoiceSummary.fromJson(v as Map<String, dynamic>),
        ),
        lines: $checkedConvert(
          'lines',
          (v) => (v as List<dynamic>)
              .map((e) => InvoiceLine.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
        payments: $checkedConvert(
          'payments',
          (v) => (v as List<dynamic>)
              .map(
                (e) => InvoicePaymentLine.fromJson(e as Map<String, dynamic>),
              )
              .toList(),
        ),
        notes: $checkedConvert('notes', (v) => v as String?),
        cancelReason: $checkedConvert('cancelReason', (v) => v as String?),
        cancelledBy: $checkedConvert('cancelledBy', (v) => v as String?),
        partyAddress: $checkedConvert('partyAddress', (v) => v as String?),
        partyPhone: $checkedConvert('partyPhone', (v) => v as String?),
      );
      return val;
    });

Map<String, dynamic> _$InvoiceDetailToJson(InvoiceDetail instance) =>
    <String, dynamic>{
      'summary': instance.summary.toJson(),
      'lines': instance.lines.map((e) => e.toJson()).toList(),
      'payments': instance.payments.map((e) => e.toJson()).toList(),
      'notes': ?instance.notes,
      'cancelReason': ?instance.cancelReason,
      'cancelledBy': ?instance.cancelledBy,
      'partyAddress': ?instance.partyAddress,
      'partyPhone': ?instance.partyPhone,
    };

InvoicePaymentLine _$InvoicePaymentLineFromJson(Map<String, dynamic> json) =>
    $checkedCreate('InvoicePaymentLine', json, ($checkedConvert) {
      final val = InvoicePaymentLine(
        paymentId: $checkedConvert('paymentId', (v) => (v as num).toInt()),
        receiptNumber: $checkedConvert('receiptNumber', (v) => v as String),
        paymentDate: $checkedConvert(
          'paymentDate',
          (v) => DateTime.parse(v as String),
        ),
        method: $checkedConvert(
          'method',
          (v) => $enumDecode(_$PaymentMethodEnumMap, v),
        ),
        status: $checkedConvert(
          'status',
          (v) => $enumDecode(_$PaymentStatusEnumMap, v),
        ),
        allocated: $checkedConvert(
          'allocated',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        chequeNumber: $checkedConvert('chequeNumber', (v) => v as String?),
        chequeStatus: $checkedConvert(
          'chequeStatus',
          (v) => $enumDecodeNullable(_$ChequeStatusEnumMap, v),
        ),
      );
      return val;
    });

Map<String, dynamic> _$InvoicePaymentLineToJson(InvoicePaymentLine instance) =>
    <String, dynamic>{
      'paymentId': instance.paymentId,
      'receiptNumber': instance.receiptNumber,
      'paymentDate': instance.paymentDate.toIso8601String(),
      'method': _$PaymentMethodEnumMap[instance.method]!,
      'status': _$PaymentStatusEnumMap[instance.status]!,
      'allocated': instance.allocated.toJson(),
      'chequeNumber': ?instance.chequeNumber,
      'chequeStatus': ?_$ChequeStatusEnumMap[instance.chequeStatus],
    };

const _$PaymentStatusEnumMap = {
  PaymentStatus.pending: 'pending',
  PaymentStatus.cleared: 'cleared',
  PaymentStatus.bounced: 'bounced',
  PaymentStatus.cancelled: 'cancelled',
};

const _$ChequeStatusEnumMap = {
  ChequeStatus.pending: 'pending',
  ChequeStatus.deposited: 'deposited',
  ChequeStatus.cleared: 'cleared',
  ChequeStatus.bounced: 'bounced',
  ChequeStatus.returned: 'returned',
  ChequeStatus.cancelled: 'cancelled',
};

InvoiceFilter _$InvoiceFilterFromJson(Map<String, dynamic> json) =>
    $checkedCreate('InvoiceFilter', json, ($checkedConvert) {
      final val = InvoiceFilter(
        search: $checkedConvert('search', (v) => v as String? ?? ''),
        kinds: $checkedConvert(
          'kinds',
          (v) =>
              (v as List<dynamic>?)
                  ?.map((e) => $enumDecode(_$InvoiceKindEnumMap, e))
                  .toSet() ??
              const {},
        ),
        status: $checkedConvert(
          'status',
          (v) => $enumDecodeNullable(_$InvoiceStatusEnumMap, v),
        ),
        settlement: $checkedConvert(
          'settlement',
          (v) => $enumDecodeNullable(_$PaymentSettlementStatusEnumMap, v),
        ),
        agentId: $checkedConvert('agentId', (v) => (v as num?)?.toInt()),
        shopId: $checkedConvert('shopId', (v) => (v as num?)?.toInt()),
        from: $checkedConvert(
          'from',
          (v) => v == null ? null : DateTime.parse(v as String),
        ),
        to: $checkedConvert(
          'to',
          (v) => v == null ? null : DateTime.parse(v as String),
        ),
        unpaidOnly: $checkedConvert('unpaidOnly', (v) => v as bool? ?? false),
        overdueOnly: $checkedConvert('overdueOnly', (v) => v as bool? ?? false),
        limit: $checkedConvert('limit', (v) => (v as num?)?.toInt() ?? 300),
      );
      return val;
    });

Map<String, dynamic> _$InvoiceFilterToJson(InvoiceFilter instance) =>
    <String, dynamic>{
      'search': instance.search,
      'kinds': instance.kinds.map((e) => _$InvoiceKindEnumMap[e]!).toList(),
      'status': ?_$InvoiceStatusEnumMap[instance.status],
      'settlement': ?_$PaymentSettlementStatusEnumMap[instance.settlement],
      'agentId': ?instance.agentId,
      'shopId': ?instance.shopId,
      'from': ?instance.from?.toIso8601String(),
      'to': ?instance.to?.toIso8601String(),
      'unpaidOnly': instance.unpaidOnly,
      'overdueOnly': instance.overdueOnly,
      'limit': instance.limit,
    };

const _$PaymentSettlementStatusEnumMap = {
  PaymentSettlementStatus.unpaid: 'unpaid',
  PaymentSettlementStatus.partiallyPaid: 'partiallyPaid',
  PaymentSettlementStatus.paid: 'paid',
  PaymentSettlementStatus.overpaid: 'overpaid',
};
