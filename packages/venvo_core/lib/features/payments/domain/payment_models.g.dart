// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'payment_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ChequeDetails _$ChequeDetailsFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ChequeDetails', json, ($checkedConvert) {
      final val = ChequeDetails(
        chequeNumber: $checkedConvert('chequeNumber', (v) => v as String),
        bankName: $checkedConvert('bankName', (v) => v as String),
        chequeDate: $checkedConvert(
          'chequeDate',
          (v) => DateTime.parse(v as String),
        ),
        branchName: $checkedConvert('branchName', (v) => v as String?),
      );
      return val;
    });

Map<String, dynamic> _$ChequeDetailsToJson(ChequeDetails instance) =>
    <String, dynamic>{
      'chequeNumber': instance.chequeNumber,
      'bankName': instance.bankName,
      'chequeDate': instance.chequeDate.toIso8601String(),
      'branchName': ?instance.branchName,
    };

PaymentAllocationRequest _$PaymentAllocationRequestFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('PaymentAllocationRequest', json, ($checkedConvert) {
  final val = PaymentAllocationRequest(
    invoiceId: $checkedConvert('invoiceId', (v) => (v as num).toInt()),
    amount: $checkedConvert(
      'amount',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    notes: $checkedConvert('notes', (v) => v as String?),
  );
  return val;
});

Map<String, dynamic> _$PaymentAllocationRequestToJson(
  PaymentAllocationRequest instance,
) => <String, dynamic>{
  'invoiceId': instance.invoiceId,
  'amount': instance.amount.toJson(),
  'notes': ?instance.notes,
};

PaymentRequest _$PaymentRequestFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('PaymentRequest', json, ($checkedConvert) {
  final val = PaymentRequest(
    direction: $checkedConvert(
      'direction',
      (v) => $enumDecode(_$PaymentDirectionEnumMap, v),
    ),
    method: $checkedConvert(
      'method',
      (v) => $enumDecode(_$PaymentMethodEnumMap, v),
    ),
    amount: $checkedConvert(
      'amount',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    partyType: $checkedConvert(
      'partyType',
      (v) => $enumDecodeNullable(_$PartyTypeEnumMap, v),
    ),
    agentId: $checkedConvert('agentId', (v) => (v as num?)?.toInt()),
    shopId: $checkedConvert('shopId', (v) => (v as num?)?.toInt()),
    employeeId: $checkedConvert('employeeId', (v) => (v as num?)?.toInt()),
    payerName: $checkedConvert('payerName', (v) => v as String?),
    paymentDate: $checkedConvert(
      'paymentDate',
      (v) => v == null ? null : DateTime.parse(v as String),
    ),
    bankName: $checkedConvert('bankName', (v) => v as String?),
    referenceNumber: $checkedConvert('referenceNumber', (v) => v as String?),
    notes: $checkedConvert('notes', (v) => v as String?),
    allocations: $checkedConvert(
      'allocations',
      (v) =>
          (v as List<dynamic>?)
              ?.map(
                (e) => PaymentAllocationRequest.fromJson(
                  e as Map<String, dynamic>,
                ),
              )
              .toList() ??
          const [],
    ),
    cheque: $checkedConvert(
      'cheque',
      (v) =>
          v == null ? null : ChequeDetails.fromJson(v as Map<String, dynamic>),
    ),
  );
  return val;
});

Map<String, dynamic> _$PaymentRequestToJson(PaymentRequest instance) =>
    <String, dynamic>{
      'direction': _$PaymentDirectionEnumMap[instance.direction]!,
      'method': _$PaymentMethodEnumMap[instance.method]!,
      'amount': instance.amount.toJson(),
      'partyType': ?_$PartyTypeEnumMap[instance.partyType],
      'agentId': ?instance.agentId,
      'shopId': ?instance.shopId,
      'employeeId': ?instance.employeeId,
      'payerName': ?instance.payerName,
      'paymentDate': ?instance.paymentDate?.toIso8601String(),
      'bankName': ?instance.bankName,
      'referenceNumber': ?instance.referenceNumber,
      'notes': ?instance.notes,
      'allocations': instance.allocations.map((e) => e.toJson()).toList(),
      'cheque': ?instance.cheque?.toJson(),
    };

const _$PaymentDirectionEnumMap = {
  PaymentDirection.inbound: 'inbound',
  PaymentDirection.outbound: 'outbound',
};

const _$PaymentMethodEnumMap = {
  PaymentMethod.cash: 'cash',
  PaymentMethod.bankTransfer: 'bankTransfer',
  PaymentMethod.cheque: 'cheque',
  PaymentMethod.cardOrDigital: 'cardOrDigital',
  PaymentMethod.creditNote: 'creditNote',
  PaymentMethod.openingBalance: 'openingBalance',
};

const _$PartyTypeEnumMap = {
  PartyType.agent: 'agent',
  PartyType.shop: 'shop',
  PartyType.customer: 'customer',
  PartyType.employee: 'employee',
  PartyType.supplier: 'supplier',
};

PaymentResult _$PaymentResultFromJson(Map<String, dynamic> json) =>
    $checkedCreate('PaymentResult', json, ($checkedConvert) {
      final val = PaymentResult(
        paymentId: $checkedConvert('paymentId', (v) => (v as num).toInt()),
        receiptNumber: $checkedConvert('receiptNumber', (v) => v as String),
        status: $checkedConvert(
          'status',
          (v) => $enumDecode(_$PaymentStatusEnumMap, v),
        ),
        amount: $checkedConvert(
          'amount',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        allocated: $checkedConvert(
          'allocated',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        chequeId: $checkedConvert('chequeId', (v) => (v as num?)?.toInt()),
      );
      return val;
    });

Map<String, dynamic> _$PaymentResultToJson(PaymentResult instance) =>
    <String, dynamic>{
      'paymentId': instance.paymentId,
      'receiptNumber': instance.receiptNumber,
      'status': _$PaymentStatusEnumMap[instance.status]!,
      'amount': instance.amount.toJson(),
      'allocated': instance.allocated.toJson(),
      'chequeId': ?instance.chequeId,
    };

const _$PaymentStatusEnumMap = {
  PaymentStatus.pending: 'pending',
  PaymentStatus.cleared: 'cleared',
  PaymentStatus.bounced: 'bounced',
  PaymentStatus.cancelled: 'cancelled',
};

PaymentSummary _$PaymentSummaryFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('PaymentSummary', json, ($checkedConvert) {
  final val = PaymentSummary(
    id: $checkedConvert('id', (v) => (v as num).toInt()),
    receiptNumber: $checkedConvert('receiptNumber', (v) => v as String),
    direction: $checkedConvert(
      'direction',
      (v) => $enumDecode(_$PaymentDirectionEnumMap, v),
    ),
    method: $checkedConvert(
      'method',
      (v) => $enumDecode(_$PaymentMethodEnumMap, v),
    ),
    status: $checkedConvert(
      'status',
      (v) => $enumDecode(_$PaymentStatusEnumMap, v),
    ),
    paymentDate: $checkedConvert(
      'paymentDate',
      (v) => DateTime.parse(v as String),
    ),
    partyType: $checkedConvert(
      'partyType',
      (v) => $enumDecode(_$PartyTypeEnumMap, v),
    ),
    partyName: $checkedConvert('partyName', (v) => v as String),
    amount: $checkedConvert(
      'amount',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    allocated: $checkedConvert(
      'allocated',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    createdBy: $checkedConvert('createdBy', (v) => v as String),
    agentId: $checkedConvert('agentId', (v) => (v as num?)?.toInt()),
    shopId: $checkedConvert('shopId', (v) => (v as num?)?.toInt()),
    bankName: $checkedConvert('bankName', (v) => v as String?),
    referenceNumber: $checkedConvert('referenceNumber', (v) => v as String?),
    chequeId: $checkedConvert('chequeId', (v) => (v as num?)?.toInt()),
    chequeNumber: $checkedConvert('chequeNumber', (v) => v as String?),
    chequeStatus: $checkedConvert(
      'chequeStatus',
      (v) => $enumDecodeNullable(_$ChequeStatusEnumMap, v),
    ),
    chequeDate: $checkedConvert(
      'chequeDate',
      (v) => v == null ? null : DateTime.parse(v as String),
    ),
    clearedAt: $checkedConvert(
      'clearedAt',
      (v) => v == null ? null : DateTime.parse(v as String),
    ),
    bouncedAt: $checkedConvert(
      'bouncedAt',
      (v) => v == null ? null : DateTime.parse(v as String),
    ),
    invoiceNumbers: $checkedConvert(
      'invoiceNumbers',
      (v) =>
          (v as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
    ),
  );
  return val;
});

Map<String, dynamic> _$PaymentSummaryToJson(PaymentSummary instance) =>
    <String, dynamic>{
      'id': instance.id,
      'receiptNumber': instance.receiptNumber,
      'direction': _$PaymentDirectionEnumMap[instance.direction]!,
      'method': _$PaymentMethodEnumMap[instance.method]!,
      'status': _$PaymentStatusEnumMap[instance.status]!,
      'paymentDate': instance.paymentDate.toIso8601String(),
      'partyType': _$PartyTypeEnumMap[instance.partyType]!,
      'partyName': instance.partyName,
      'agentId': ?instance.agentId,
      'shopId': ?instance.shopId,
      'amount': instance.amount.toJson(),
      'allocated': instance.allocated.toJson(),
      'createdBy': instance.createdBy,
      'bankName': ?instance.bankName,
      'referenceNumber': ?instance.referenceNumber,
      'chequeId': ?instance.chequeId,
      'chequeNumber': ?instance.chequeNumber,
      'chequeStatus': ?_$ChequeStatusEnumMap[instance.chequeStatus],
      'chequeDate': ?instance.chequeDate?.toIso8601String(),
      'clearedAt': ?instance.clearedAt?.toIso8601String(),
      'bouncedAt': ?instance.bouncedAt?.toIso8601String(),
      'invoiceNumbers': instance.invoiceNumbers,
    };

const _$ChequeStatusEnumMap = {
  ChequeStatus.pending: 'pending',
  ChequeStatus.deposited: 'deposited',
  ChequeStatus.cleared: 'cleared',
  ChequeStatus.bounced: 'bounced',
  ChequeStatus.returned: 'returned',
  ChequeStatus.cancelled: 'cancelled',
};

ChequeSummary _$ChequeSummaryFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ChequeSummary', json, ($checkedConvert) {
      final val = ChequeSummary(
        id: $checkedConvert('id', (v) => (v as num).toInt()),
        paymentId: $checkedConvert('paymentId', (v) => (v as num).toInt()),
        receiptNumber: $checkedConvert('receiptNumber', (v) => v as String),
        chequeNumber: $checkedConvert('chequeNumber', (v) => v as String),
        bankName: $checkedConvert('bankName', (v) => v as String),
        chequeDate: $checkedConvert(
          'chequeDate',
          (v) => DateTime.parse(v as String),
        ),
        status: $checkedConvert(
          'status',
          (v) => $enumDecode(_$ChequeStatusEnumMap, v),
        ),
        amount: $checkedConvert(
          'amount',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        partyName: $checkedConvert('partyName', (v) => v as String),
        receivedOn: $checkedConvert(
          'receivedOn',
          (v) => DateTime.parse(v as String),
        ),
        branchName: $checkedConvert('branchName', (v) => v as String?),
        depositedAt: $checkedConvert(
          'depositedAt',
          (v) => v == null ? null : DateTime.parse(v as String),
        ),
        clearedAt: $checkedConvert(
          'clearedAt',
          (v) => v == null ? null : DateTime.parse(v as String),
        ),
        bouncedAt: $checkedConvert(
          'bouncedAt',
          (v) => v == null ? null : DateTime.parse(v as String),
        ),
        bounceReason: $checkedConvert('bounceReason', (v) => v as String?),
        bounceCharge: $checkedConvert(
          'bounceCharge',
          (v) => v == null ? Money.zero : Money.fromJson((v as num).toInt()),
        ),
        replacementReceiptNumber: $checkedConvert(
          'replacementReceiptNumber',
          (v) => v as String?,
        ),
        invoiceNumbers: $checkedConvert(
          'invoiceNumbers',
          (v) =>
              (v as List<dynamic>?)?.map((e) => e as String).toList() ??
              const [],
        ),
      );
      return val;
    });

Map<String, dynamic> _$ChequeSummaryToJson(ChequeSummary instance) =>
    <String, dynamic>{
      'id': instance.id,
      'paymentId': instance.paymentId,
      'receiptNumber': instance.receiptNumber,
      'chequeNumber': instance.chequeNumber,
      'bankName': instance.bankName,
      'branchName': ?instance.branchName,
      'chequeDate': instance.chequeDate.toIso8601String(),
      'status': _$ChequeStatusEnumMap[instance.status]!,
      'amount': instance.amount.toJson(),
      'partyName': instance.partyName,
      'receivedOn': instance.receivedOn.toIso8601String(),
      'depositedAt': ?instance.depositedAt?.toIso8601String(),
      'clearedAt': ?instance.clearedAt?.toIso8601String(),
      'bouncedAt': ?instance.bouncedAt?.toIso8601String(),
      'bounceReason': ?instance.bounceReason,
      'bounceCharge': instance.bounceCharge.toJson(),
      'replacementReceiptNumber': ?instance.replacementReceiptNumber,
      'invoiceNumbers': instance.invoiceNumbers,
    };

AllocatableInvoice _$AllocatableInvoiceFromJson(Map<String, dynamic> json) =>
    $checkedCreate('AllocatableInvoice', json, ($checkedConvert) {
      final val = AllocatableInvoice(
        invoiceId: $checkedConvert('invoiceId', (v) => (v as num).toInt()),
        invoiceNumber: $checkedConvert('invoiceNumber', (v) => v as String),
        invoiceDate: $checkedConvert(
          'invoiceDate',
          (v) => DateTime.parse(v as String),
        ),
        net: $checkedConvert('net', (v) => Money.fromJson((v as num).toInt())),
        outstanding: $checkedConvert(
          'outstanding',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        allocatable: $checkedConvert(
          'allocatable',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        pendingCheques: $checkedConvert(
          'pendingCheques',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        dueDate: $checkedConvert(
          'dueDate',
          (v) => v == null ? null : DateTime.parse(v as String),
        ),
      );
      return val;
    });

Map<String, dynamic> _$AllocatableInvoiceToJson(AllocatableInvoice instance) =>
    <String, dynamic>{
      'invoiceId': instance.invoiceId,
      'invoiceNumber': instance.invoiceNumber,
      'invoiceDate': instance.invoiceDate.toIso8601String(),
      'dueDate': ?instance.dueDate?.toIso8601String(),
      'net': instance.net.toJson(),
      'outstanding': instance.outstanding.toJson(),
      'allocatable': instance.allocatable.toJson(),
      'pendingCheques': instance.pendingCheques.toJson(),
    };

PaymentFilter _$PaymentFilterFromJson(Map<String, dynamic> json) =>
    $checkedCreate('PaymentFilter', json, ($checkedConvert) {
      final val = PaymentFilter(
        search: $checkedConvert('search', (v) => v as String? ?? ''),
        direction: $checkedConvert(
          'direction',
          (v) => $enumDecodeNullable(_$PaymentDirectionEnumMap, v),
        ),
        method: $checkedConvert(
          'method',
          (v) => $enumDecodeNullable(_$PaymentMethodEnumMap, v),
        ),
        status: $checkedConvert(
          'status',
          (v) => $enumDecodeNullable(_$PaymentStatusEnumMap, v),
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
        advancesOnly: $checkedConvert(
          'advancesOnly',
          (v) => v as bool? ?? false,
        ),
        limit: $checkedConvert('limit', (v) => (v as num?)?.toInt() ?? 300),
      );
      return val;
    });

Map<String, dynamic> _$PaymentFilterToJson(PaymentFilter instance) =>
    <String, dynamic>{
      'search': instance.search,
      'direction': ?_$PaymentDirectionEnumMap[instance.direction],
      'method': ?_$PaymentMethodEnumMap[instance.method],
      'status': ?_$PaymentStatusEnumMap[instance.status],
      'agentId': ?instance.agentId,
      'shopId': ?instance.shopId,
      'from': ?instance.from?.toIso8601String(),
      'to': ?instance.to?.toIso8601String(),
      'advancesOnly': instance.advancesOnly,
      'limit': instance.limit,
    };

ChequeFilter _$ChequeFilterFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ChequeFilter', json, ($checkedConvert) {
      final val = ChequeFilter(
        search: $checkedConvert('search', (v) => v as String? ?? ''),
        statuses: $checkedConvert(
          'statuses',
          (v) =>
              (v as List<dynamic>?)
                  ?.map((e) => $enumDecode(_$ChequeStatusEnumMap, e))
                  .toSet() ??
              const {},
        ),
        from: $checkedConvert(
          'from',
          (v) => v == null ? null : DateTime.parse(v as String),
        ),
        to: $checkedConvert(
          'to',
          (v) => v == null ? null : DateTime.parse(v as String),
        ),
        bankableOnly: $checkedConvert(
          'bankableOnly',
          (v) => v as bool? ?? false,
        ),
        limit: $checkedConvert('limit', (v) => (v as num?)?.toInt() ?? 300),
      );
      return val;
    });

Map<String, dynamic> _$ChequeFilterToJson(
  ChequeFilter instance,
) => <String, dynamic>{
  'search': instance.search,
  'statuses': instance.statuses.map((e) => _$ChequeStatusEnumMap[e]!).toList(),
  'from': ?instance.from?.toIso8601String(),
  'to': ?instance.to?.toIso8601String(),
  'bankableOnly': instance.bankableOnly,
  'limit': instance.limit,
};
