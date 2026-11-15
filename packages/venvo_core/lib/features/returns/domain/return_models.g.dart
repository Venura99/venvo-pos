// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'return_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ReturnLineDraft _$ReturnLineDraftFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ReturnLineDraft', json, ($checkedConvert) {
      final val = ReturnLineDraft(
        productId: $checkedConvert('productId', (v) => (v as num).toInt()),
        quantity: $checkedConvert('quantity', (v) => (v as num).toInt()),
        originInvoiceItemId: $checkedConvert(
          'originInvoiceItemId',
          (v) => (v as num?)?.toInt(),
        ),
        unitPrice: $checkedConvert(
          'unitPrice',
          (v) => v == null ? null : Money.fromJson((v as num).toInt()),
        ),
        notes: $checkedConvert('notes', (v) => v as String?),
      );
      return val;
    });

Map<String, dynamic> _$ReturnLineDraftToJson(ReturnLineDraft instance) =>
    <String, dynamic>{
      'productId': instance.productId,
      'quantity': instance.quantity,
      'originInvoiceItemId': ?instance.originInvoiceItemId,
      'unitPrice': ?instance.unitPrice?.toJson(),
      'notes': ?instance.notes,
    };

ReturnDraft _$ReturnDraftFromJson(Map<String, dynamic> json) => $checkedCreate(
  'ReturnDraft',
  json,
  ($checkedConvert) {
    final val = ReturnDraft(
      route: $checkedConvert(
        'route',
        (v) => $enumDecode(_$ReturnRouteEnumMap, v),
      ),
      fromLocationId: $checkedConvert(
        'fromLocationId',
        (v) => (v as num).toInt(),
      ),
      toLocationId: $checkedConvert('toLocationId', (v) => (v as num).toInt()),
      reason: $checkedConvert(
        'reason',
        (v) => $enumDecode(_$ReturnReasonEnumMap, v),
      ),
      lines: $checkedConvert(
        'lines',
        (v) => (v as List<dynamic>)
            .map((e) => ReturnLineDraft.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      returnDate: $checkedConvert(
        'returnDate',
        (v) => v == null ? null : DateTime.parse(v as String),
      ),
      agentId: $checkedConvert('agentId', (v) => (v as num?)?.toInt()),
      shopId: $checkedConvert('shopId', (v) => (v as num?)?.toInt()),
      originInvoiceId: $checkedConvert(
        'originInvoiceId',
        (v) => (v as num?)?.toInt(),
      ),
      originStockTransactionId: $checkedConvert(
        'originStockTransactionId',
        (v) => (v as num?)?.toInt(),
      ),
      reasonNote: $checkedConvert('reasonNote', (v) => v as String?),
      notes: $checkedConvert('notes', (v) => v as String?),
    );
    return val;
  },
);

Map<String, dynamic> _$ReturnDraftToJson(ReturnDraft instance) =>
    <String, dynamic>{
      'route': _$ReturnRouteEnumMap[instance.route]!,
      'fromLocationId': instance.fromLocationId,
      'toLocationId': instance.toLocationId,
      'reason': _$ReturnReasonEnumMap[instance.reason]!,
      'lines': instance.lines.map((e) => e.toJson()).toList(),
      'returnDate': ?instance.returnDate?.toIso8601String(),
      'agentId': ?instance.agentId,
      'shopId': ?instance.shopId,
      'originInvoiceId': ?instance.originInvoiceId,
      'originStockTransactionId': ?instance.originStockTransactionId,
      'reasonNote': ?instance.reasonNote,
      'notes': ?instance.notes,
    };

const _$ReturnRouteEnumMap = {
  ReturnRoute.customerToShop: 'customerToShop',
  ReturnRoute.shopToAgent: 'shopToAgent',
  ReturnRoute.agentToWarehouse: 'agentToWarehouse',
  ReturnRoute.shopToWarehouse: 'shopToWarehouse',
};

const _$ReturnReasonEnumMap = {
  ReturnReason.customerPaymentFailure: 'customerPaymentFailure',
  ReturnReason.defectiveItem: 'defectiveItem',
  ReturnReason.damagedItem: 'damagedItem',
  ReturnReason.wrongProduct: 'wrongProduct',
  ReturnReason.excessStock: 'excessStock',
  ReturnReason.other: 'other',
};

ReturnPostResult _$ReturnPostResultFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ReturnPostResult', json, ($checkedConvert) {
      final val = ReturnPostResult(
        returnId: $checkedConvert('returnId', (v) => (v as num).toInt()),
        returnNumber: $checkedConvert('returnNumber', (v) => v as String),
        receiptTransactionId: $checkedConvert(
          'receiptTransactionId',
          (v) => (v as num).toInt(),
        ),
        receiptDocumentNumber: $checkedConvert(
          'receiptDocumentNumber',
          (v) => v as String,
        ),
        totalQuantity: $checkedConvert(
          'totalQuantity',
          (v) => (v as num).toInt(),
        ),
        totalValue: $checkedConvert(
          'totalValue',
          (v) => Money.fromJson((v as num).toInt()),
        ),
      );
      return val;
    });

Map<String, dynamic> _$ReturnPostResultToJson(ReturnPostResult instance) =>
    <String, dynamic>{
      'returnId': instance.returnId,
      'returnNumber': instance.returnNumber,
      'receiptTransactionId': instance.receiptTransactionId,
      'receiptDocumentNumber': instance.receiptDocumentNumber,
      'totalQuantity': instance.totalQuantity,
      'totalValue': instance.totalValue.toJson(),
    };

InspectionDecision _$InspectionDecisionFromJson(Map<String, dynamic> json) =>
    $checkedCreate('InspectionDecision', json, ($checkedConvert) {
      final val = InspectionDecision(
        returnItemId: $checkedConvert(
          'returnItemId',
          (v) => (v as num).toInt(),
        ),
        acceptedQuantity: $checkedConvert(
          'acceptedQuantity',
          (v) => (v as num?)?.toInt() ?? 0,
        ),
        damagedQuantity: $checkedConvert(
          'damagedQuantity',
          (v) => (v as num?)?.toInt() ?? 0,
        ),
        scrappedQuantity: $checkedConvert(
          'scrappedQuantity',
          (v) => (v as num?)?.toInt() ?? 0,
        ),
        note: $checkedConvert('note', (v) => v as String?),
      );
      return val;
    });

Map<String, dynamic> _$InspectionDecisionToJson(InspectionDecision instance) =>
    <String, dynamic>{
      'returnItemId': instance.returnItemId,
      'acceptedQuantity': instance.acceptedQuantity,
      'damagedQuantity': instance.damagedQuantity,
      'scrappedQuantity': instance.scrappedQuantity,
      'note': ?instance.note,
    };

InspectionRequest _$InspectionRequestFromJson(Map<String, dynamic> json) =>
    $checkedCreate('InspectionRequest', json, ($checkedConvert) {
      final val = InspectionRequest(
        returnId: $checkedConvert('returnId', (v) => (v as num).toInt()),
        decisions: $checkedConvert(
          'decisions',
          (v) => (v as List<dynamic>)
              .map(
                (e) => InspectionDecision.fromJson(e as Map<String, dynamic>),
              )
              .toList(),
        ),
        notes: $checkedConvert('notes', (v) => v as String?),
      );
      return val;
    });

Map<String, dynamic> _$InspectionRequestToJson(InspectionRequest instance) =>
    <String, dynamic>{
      'returnId': instance.returnId,
      'decisions': instance.decisions.map((e) => e.toJson()).toList(),
      'notes': ?instance.notes,
    };

InspectionResult _$InspectionResultFromJson(Map<String, dynamic> json) =>
    $checkedCreate('InspectionResult', json, ($checkedConvert) {
      final val = InspectionResult(
        returnId: $checkedConvert('returnId', (v) => (v as num).toInt()),
        acceptedQuantity: $checkedConvert(
          'acceptedQuantity',
          (v) => (v as num).toInt(),
        ),
        damagedQuantity: $checkedConvert(
          'damagedQuantity',
          (v) => (v as num).toInt(),
        ),
        scrappedQuantity: $checkedConvert(
          'scrappedQuantity',
          (v) => (v as num).toInt(),
        ),
        creditableValue: $checkedConvert(
          'creditableValue',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        acceptedTransactionId: $checkedConvert(
          'acceptedTransactionId',
          (v) => (v as num?)?.toInt(),
        ),
        damagedTransactionId: $checkedConvert(
          'damagedTransactionId',
          (v) => (v as num?)?.toInt(),
        ),
        scrappedTransactionId: $checkedConvert(
          'scrappedTransactionId',
          (v) => (v as num?)?.toInt(),
        ),
      );
      return val;
    });

Map<String, dynamic> _$InspectionResultToJson(InspectionResult instance) =>
    <String, dynamic>{
      'returnId': instance.returnId,
      'acceptedQuantity': instance.acceptedQuantity,
      'damagedQuantity': instance.damagedQuantity,
      'scrappedQuantity': instance.scrappedQuantity,
      'creditableValue': instance.creditableValue.toJson(),
      'acceptedTransactionId': ?instance.acceptedTransactionId,
      'damagedTransactionId': ?instance.damagedTransactionId,
      'scrappedTransactionId': ?instance.scrappedTransactionId,
    };

ReturnSummary _$ReturnSummaryFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('ReturnSummary', json, ($checkedConvert) {
  final val = ReturnSummary(
    id: $checkedConvert('id', (v) => (v as num).toInt()),
    returnNumber: $checkedConvert('returnNumber', (v) => v as String),
    route: $checkedConvert(
      'route',
      (v) => $enumDecode(_$ReturnRouteEnumMap, v),
    ),
    status: $checkedConvert(
      'status',
      (v) => $enumDecode(_$ReturnStatusEnumMap, v),
    ),
    returnDate: $checkedConvert(
      'returnDate',
      (v) => DateTime.parse(v as String),
    ),
    reason: $checkedConvert(
      'reason',
      (v) => $enumDecode(_$ReturnReasonEnumMap, v),
    ),
    fromLocationName: $checkedConvert('fromLocationName', (v) => v as String),
    toLocationName: $checkedConvert('toLocationName', (v) => v as String),
    totalQuantity: $checkedConvert('totalQuantity', (v) => (v as num).toInt()),
    totalValue: $checkedConvert(
      'totalValue',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    pendingLineCount: $checkedConvert(
      'pendingLineCount',
      (v) => (v as num).toInt(),
    ),
    lineCount: $checkedConvert('lineCount', (v) => (v as num).toInt()),
    createdBy: $checkedConvert('createdBy', (v) => v as String),
    creditedValue: $checkedConvert(
      'creditedValue',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    agentName: $checkedConvert('agentName', (v) => v as String?),
    shopName: $checkedConvert('shopName', (v) => v as String?),
    originInvoiceNumber: $checkedConvert(
      'originInvoiceNumber',
      (v) => v as String?,
    ),
    reasonNote: $checkedConvert('reasonNote', (v) => v as String?),
    creditNoteNumber: $checkedConvert('creditNoteNumber', (v) => v as String?),
  );
  return val;
});

Map<String, dynamic> _$ReturnSummaryToJson(ReturnSummary instance) =>
    <String, dynamic>{
      'id': instance.id,
      'returnNumber': instance.returnNumber,
      'route': _$ReturnRouteEnumMap[instance.route]!,
      'status': _$ReturnStatusEnumMap[instance.status]!,
      'returnDate': instance.returnDate.toIso8601String(),
      'reason': _$ReturnReasonEnumMap[instance.reason]!,
      'fromLocationName': instance.fromLocationName,
      'toLocationName': instance.toLocationName,
      'totalQuantity': instance.totalQuantity,
      'totalValue': instance.totalValue.toJson(),
      'pendingLineCount': instance.pendingLineCount,
      'lineCount': instance.lineCount,
      'createdBy': instance.createdBy,
      'creditedValue': instance.creditedValue.toJson(),
      'agentName': ?instance.agentName,
      'shopName': ?instance.shopName,
      'originInvoiceNumber': ?instance.originInvoiceNumber,
      'reasonNote': ?instance.reasonNote,
      'creditNoteNumber': ?instance.creditNoteNumber,
    };

const _$ReturnStatusEnumMap = {
  ReturnStatus.draft: 'draft',
  ReturnStatus.posted: 'posted',
  ReturnStatus.inspected: 'inspected',
  ReturnStatus.completed: 'completed',
  ReturnStatus.cancelled: 'cancelled',
};

ReturnLineView _$ReturnLineViewFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ReturnLineView', json, ($checkedConvert) {
      final val = ReturnLineView(
        id: $checkedConvert('id', (v) => (v as num).toInt()),
        lineNumber: $checkedConvert('lineNumber', (v) => (v as num).toInt()),
        productId: $checkedConvert('productId', (v) => (v as num).toInt()),
        productName: $checkedConvert('productName', (v) => v as String),
        sku: $checkedConvert('sku', (v) => v as String),
        quantity: $checkedConvert('quantity', (v) => (v as num).toInt()),
        unitPrice: $checkedConvert(
          'unitPrice',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        lineValue: $checkedConvert(
          'lineValue',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        inspectionStatus: $checkedConvert(
          'inspectionStatus',
          (v) => $enumDecode(_$InspectionStatusEnumMap, v),
        ),
        acceptedQuantity: $checkedConvert(
          'acceptedQuantity',
          (v) => (v as num).toInt(),
        ),
        damagedQuantity: $checkedConvert(
          'damagedQuantity',
          (v) => (v as num).toInt(),
        ),
        scrappedQuantity: $checkedConvert(
          'scrappedQuantity',
          (v) => (v as num).toInt(),
        ),
        inspectionNote: $checkedConvert('inspectionNote', (v) => v as String?),
        inspectedBy: $checkedConvert('inspectedBy', (v) => v as String?),
        inspectedAt: $checkedConvert(
          'inspectedAt',
          (v) => v == null ? null : DateTime.parse(v as String),
        ),
        notes: $checkedConvert('notes', (v) => v as String?),
      );
      return val;
    });

Map<String, dynamic> _$ReturnLineViewToJson(ReturnLineView instance) =>
    <String, dynamic>{
      'id': instance.id,
      'lineNumber': instance.lineNumber,
      'productId': instance.productId,
      'productName': instance.productName,
      'sku': instance.sku,
      'quantity': instance.quantity,
      'unitPrice': instance.unitPrice.toJson(),
      'lineValue': instance.lineValue.toJson(),
      'inspectionStatus': _$InspectionStatusEnumMap[instance.inspectionStatus]!,
      'acceptedQuantity': instance.acceptedQuantity,
      'damagedQuantity': instance.damagedQuantity,
      'scrappedQuantity': instance.scrappedQuantity,
      'inspectionNote': ?instance.inspectionNote,
      'inspectedBy': ?instance.inspectedBy,
      'inspectedAt': ?instance.inspectedAt?.toIso8601String(),
      'notes': ?instance.notes,
    };

const _$InspectionStatusEnumMap = {
  InspectionStatus.pending: 'pending',
  InspectionStatus.acceptedToStock: 'acceptedToStock',
  InspectionStatus.movedToDamaged: 'movedToDamaged',
  InspectionStatus.scrapped: 'scrapped',
};

ReturnDetail _$ReturnDetailFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ReturnDetail', json, ($checkedConvert) {
      final val = ReturnDetail(
        summary: $checkedConvert(
          'summary',
          (v) => ReturnSummary.fromJson(v as Map<String, dynamic>),
        ),
        lines: $checkedConvert(
          'lines',
          (v) => (v as List<dynamic>)
              .map((e) => ReturnLineView.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
        creditNotes: $checkedConvert(
          'creditNotes',
          (v) => (v as List<dynamic>)
              .map((e) => CreditNoteSummary.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
        notes: $checkedConvert('notes', (v) => v as String?),
        cancelReason: $checkedConvert('cancelReason', (v) => v as String?),
        authorisedBy: $checkedConvert('authorisedBy', (v) => v as String?),
        receiptDocumentNumber: $checkedConvert(
          'receiptDocumentNumber',
          (v) => v as String?,
        ),
        dispositionDocumentNumber: $checkedConvert(
          'dispositionDocumentNumber',
          (v) => v as String?,
        ),
      );
      return val;
    });

Map<String, dynamic> _$ReturnDetailToJson(ReturnDetail instance) =>
    <String, dynamic>{
      'summary': instance.summary.toJson(),
      'lines': instance.lines.map((e) => e.toJson()).toList(),
      'creditNotes': instance.creditNotes.map((e) => e.toJson()).toList(),
      'notes': ?instance.notes,
      'cancelReason': ?instance.cancelReason,
      'authorisedBy': ?instance.authorisedBy,
      'receiptDocumentNumber': ?instance.receiptDocumentNumber,
      'dispositionDocumentNumber': ?instance.dispositionDocumentNumber,
    };

ReturnFilter _$ReturnFilterFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ReturnFilter', json, ($checkedConvert) {
      final val = ReturnFilter(
        search: $checkedConvert('search', (v) => v as String? ?? ''),
        routes: $checkedConvert(
          'routes',
          (v) =>
              (v as List<dynamic>?)
                  ?.map((e) => $enumDecode(_$ReturnRouteEnumMap, e))
                  .toSet() ??
              const {},
        ),
        status: $checkedConvert(
          'status',
          (v) => $enumDecodeNullable(_$ReturnStatusEnumMap, v),
        ),
        reason: $checkedConvert(
          'reason',
          (v) => $enumDecodeNullable(_$ReturnReasonEnumMap, v),
        ),
        agentId: $checkedConvert('agentId', (v) => (v as num?)?.toInt()),
        shopId: $checkedConvert('shopId', (v) => (v as num?)?.toInt()),
        pendingInspectionOnly: $checkedConvert(
          'pendingInspectionOnly',
          (v) => v as bool? ?? false,
        ),
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

Map<String, dynamic> _$ReturnFilterToJson(ReturnFilter instance) =>
    <String, dynamic>{
      'search': instance.search,
      'routes': instance.routes.map((e) => _$ReturnRouteEnumMap[e]!).toList(),
      'status': ?_$ReturnStatusEnumMap[instance.status],
      'reason': ?_$ReturnReasonEnumMap[instance.reason],
      'agentId': ?instance.agentId,
      'shopId': ?instance.shopId,
      'pendingInspectionOnly': instance.pendingInspectionOnly,
      'from': ?instance.from?.toIso8601String(),
      'to': ?instance.to?.toIso8601String(),
      'limit': instance.limit,
    };

CreditNoteSummary _$CreditNoteSummaryFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('CreditNoteSummary', json, ($checkedConvert) {
  final val = CreditNoteSummary(
    id: $checkedConvert('id', (v) => (v as num).toInt()),
    creditNoteNumber: $checkedConvert('creditNoteNumber', (v) => v as String),
    status: $checkedConvert(
      'status',
      (v) => $enumDecode(_$InvoiceStatusEnumMap, v),
    ),
    issueDate: $checkedConvert('issueDate', (v) => DateTime.parse(v as String)),
    partyType: $checkedConvert(
      'partyType',
      (v) => $enumDecode(_$PartyTypeEnumMap, v),
    ),
    partyName: $checkedConvert('partyName', (v) => v as String),
    amount: $checkedConvert(
      'amount',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    applied: $checkedConvert(
      'applied',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    createdBy: $checkedConvert('createdBy', (v) => v as String),
    agentId: $checkedConvert('agentId', (v) => (v as num?)?.toInt()),
    shopId: $checkedConvert('shopId', (v) => (v as num?)?.toInt()),
    returnNumber: $checkedConvert('returnNumber', (v) => v as String?),
    returnId: $checkedConvert('returnId', (v) => (v as num?)?.toInt()),
    originInvoiceNumber: $checkedConvert(
      'originInvoiceNumber',
      (v) => v as String?,
    ),
    originInvoiceId: $checkedConvert(
      'originInvoiceId',
      (v) => (v as num?)?.toInt(),
    ),
    reason: $checkedConvert('reason', (v) => v as String?),
    cancelReason: $checkedConvert('cancelReason', (v) => v as String?),
  );
  return val;
});

Map<String, dynamic> _$CreditNoteSummaryToJson(CreditNoteSummary instance) =>
    <String, dynamic>{
      'id': instance.id,
      'creditNoteNumber': instance.creditNoteNumber,
      'status': _$InvoiceStatusEnumMap[instance.status]!,
      'issueDate': instance.issueDate.toIso8601String(),
      'partyType': _$PartyTypeEnumMap[instance.partyType]!,
      'partyName': instance.partyName,
      'amount': instance.amount.toJson(),
      'applied': instance.applied.toJson(),
      'createdBy': instance.createdBy,
      'agentId': ?instance.agentId,
      'shopId': ?instance.shopId,
      'returnNumber': ?instance.returnNumber,
      'returnId': ?instance.returnId,
      'originInvoiceNumber': ?instance.originInvoiceNumber,
      'originInvoiceId': ?instance.originInvoiceId,
      'reason': ?instance.reason,
      'cancelReason': ?instance.cancelReason,
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

CreditNoteApplicationView _$CreditNoteApplicationViewFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('CreditNoteApplicationView', json, ($checkedConvert) {
  final val = CreditNoteApplicationView(
    id: $checkedConvert('id', (v) => (v as num).toInt()),
    invoiceId: $checkedConvert('invoiceId', (v) => (v as num).toInt()),
    invoiceNumber: $checkedConvert('invoiceNumber', (v) => v as String),
    amount: $checkedConvert(
      'amount',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    appliedAt: $checkedConvert('appliedAt', (v) => DateTime.parse(v as String)),
    appliedBy: $checkedConvert('appliedBy', (v) => v as String),
  );
  return val;
});

Map<String, dynamic> _$CreditNoteApplicationViewToJson(
  CreditNoteApplicationView instance,
) => <String, dynamic>{
  'id': instance.id,
  'invoiceId': instance.invoiceId,
  'invoiceNumber': instance.invoiceNumber,
  'amount': instance.amount.toJson(),
  'appliedAt': instance.appliedAt.toIso8601String(),
  'appliedBy': instance.appliedBy,
};

CreditNoteDetail _$CreditNoteDetailFromJson(Map<String, dynamic> json) =>
    $checkedCreate('CreditNoteDetail', json, ($checkedConvert) {
      final val = CreditNoteDetail(
        summary: $checkedConvert(
          'summary',
          (v) => CreditNoteSummary.fromJson(v as Map<String, dynamic>),
        ),
        applications: $checkedConvert(
          'applications',
          (v) => (v as List<dynamic>)
              .map(
                (e) => CreditNoteApplicationView.fromJson(
                  e as Map<String, dynamic>,
                ),
              )
              .toList(),
        ),
        notes: $checkedConvert('notes', (v) => v as String?),
      );
      return val;
    });

Map<String, dynamic> _$CreditNoteDetailToJson(CreditNoteDetail instance) =>
    <String, dynamic>{
      'summary': instance.summary.toJson(),
      'applications': instance.applications.map((e) => e.toJson()).toList(),
      'notes': ?instance.notes,
    };

CreditNoteFilter _$CreditNoteFilterFromJson(Map<String, dynamic> json) =>
    $checkedCreate('CreditNoteFilter', json, ($checkedConvert) {
      final val = CreditNoteFilter(
        search: $checkedConvert('search', (v) => v as String? ?? ''),
        status: $checkedConvert(
          'status',
          (v) => $enumDecodeNullable(_$InvoiceStatusEnumMap, v),
        ),
        agentId: $checkedConvert('agentId', (v) => (v as num?)?.toInt()),
        shopId: $checkedConvert('shopId', (v) => (v as num?)?.toInt()),
        withRemainingOnly: $checkedConvert(
          'withRemainingOnly',
          (v) => v as bool? ?? false,
        ),
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

Map<String, dynamic> _$CreditNoteFilterToJson(CreditNoteFilter instance) =>
    <String, dynamic>{
      'search': instance.search,
      'status': ?_$InvoiceStatusEnumMap[instance.status],
      'agentId': ?instance.agentId,
      'shopId': ?instance.shopId,
      'withRemainingOnly': instance.withRemainingOnly,
      'from': ?instance.from?.toIso8601String(),
      'to': ?instance.to?.toIso8601String(),
      'limit': instance.limit,
    };

ReturnableInvoiceLine _$ReturnableInvoiceLineFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('ReturnableInvoiceLine', json, ($checkedConvert) {
  final val = ReturnableInvoiceLine(
    invoiceItemId: $checkedConvert('invoiceItemId', (v) => (v as num).toInt()),
    lineNumber: $checkedConvert('lineNumber', (v) => (v as num).toInt()),
    productId: $checkedConvert('productId', (v) => (v as num).toInt()),
    productName: $checkedConvert('productName', (v) => v as String),
    sku: $checkedConvert('sku', (v) => v as String),
    billedQuantity: $checkedConvert(
      'billedQuantity',
      (v) => (v as num).toInt(),
    ),
    returnedQuantity: $checkedConvert(
      'returnedQuantity',
      (v) => (v as num).toInt(),
    ),
    effectiveUnitPrice: $checkedConvert(
      'effectiveUnitPrice',
      (v) => Money.fromJson((v as num).toInt()),
    ),
  );
  return val;
});

Map<String, dynamic> _$ReturnableInvoiceLineToJson(
  ReturnableInvoiceLine instance,
) => <String, dynamic>{
  'invoiceItemId': instance.invoiceItemId,
  'lineNumber': instance.lineNumber,
  'productId': instance.productId,
  'productName': instance.productName,
  'sku': instance.sku,
  'billedQuantity': instance.billedQuantity,
  'returnedQuantity': instance.returnedQuantity,
  'effectiveUnitPrice': instance.effectiveUnitPrice.toJson(),
};
