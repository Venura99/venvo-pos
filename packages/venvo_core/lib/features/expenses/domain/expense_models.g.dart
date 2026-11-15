// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'expense_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ExpenseDraft _$ExpenseDraftFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('ExpenseDraft', json, ($checkedConvert) {
  final val = ExpenseDraft(
    categoryId: $checkedConvert('categoryId', (v) => (v as num).toInt()),
    description: $checkedConvert('description', (v) => v as String),
    amount: $checkedConvert(
      'amount',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    paymentMethod: $checkedConvert(
      'paymentMethod',
      (v) => $enumDecode(_$PaymentMethodEnumMap, v),
    ),
    id: $checkedConvert('id', (v) => (v as num?)?.toInt()),
    expenseDate: $checkedConvert(
      'expenseDate',
      (v) => v == null ? null : DateTime.parse(v as String),
    ),
    paidByEmployeeId: $checkedConvert(
      'paidByEmployeeId',
      (v) => (v as num?)?.toInt(),
    ),
    referenceNumber: $checkedConvert('referenceNumber', (v) => v as String?),
    fromPettyCash: $checkedConvert('fromPettyCash', (v) => v as bool? ?? false),
    notes: $checkedConvert('notes', (v) => v as String?),
  );
  return val;
});

Map<String, dynamic> _$ExpenseDraftToJson(ExpenseDraft instance) =>
    <String, dynamic>{
      'id': ?instance.id,
      'categoryId': instance.categoryId,
      'description': instance.description,
      'amount': instance.amount.toJson(),
      'paymentMethod': _$PaymentMethodEnumMap[instance.paymentMethod]!,
      'expenseDate': ?instance.expenseDate?.toIso8601String(),
      'paidByEmployeeId': ?instance.paidByEmployeeId,
      'referenceNumber': ?instance.referenceNumber,
      'fromPettyCash': instance.fromPettyCash,
      'notes': ?instance.notes,
    };

const _$PaymentMethodEnumMap = {
  PaymentMethod.cash: 'cash',
  PaymentMethod.bankTransfer: 'bankTransfer',
  PaymentMethod.cheque: 'cheque',
  PaymentMethod.cardOrDigital: 'cardOrDigital',
  PaymentMethod.creditNote: 'creditNote',
  PaymentMethod.openingBalance: 'openingBalance',
};

ExpenseSummary _$ExpenseSummaryFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ExpenseSummary', json, ($checkedConvert) {
      final val = ExpenseSummary(
        id: $checkedConvert('id', (v) => (v as num).toInt()),
        voucherNumber: $checkedConvert('voucherNumber', (v) => v as String),
        expenseDate: $checkedConvert(
          'expenseDate',
          (v) => DateTime.parse(v as String),
        ),
        categoryId: $checkedConvert('categoryId', (v) => (v as num).toInt()),
        categoryName: $checkedConvert('categoryName', (v) => v as String),
        description: $checkedConvert('description', (v) => v as String),
        amount: $checkedConvert(
          'amount',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        paymentMethod: $checkedConvert(
          'paymentMethod',
          (v) => $enumDecode(_$PaymentMethodEnumMap, v),
        ),
        status: $checkedConvert(
          'status',
          (v) => $enumDecode(_$InvoiceStatusEnumMap, v),
        ),
        createdBy: $checkedConvert('createdBy', (v) => v as String),
        paidByEmployeeName: $checkedConvert(
          'paidByEmployeeName',
          (v) => v as String?,
        ),
        referenceNumber: $checkedConvert(
          'referenceNumber',
          (v) => v as String?,
        ),
        pettyCashVoucherNumber: $checkedConvert(
          'pettyCashVoucherNumber',
          (v) => v as String?,
        ),
        notes: $checkedConvert('notes', (v) => v as String?),
        cancelReason: $checkedConvert('cancelReason', (v) => v as String?),
      );
      return val;
    });

Map<String, dynamic> _$ExpenseSummaryToJson(ExpenseSummary instance) =>
    <String, dynamic>{
      'id': instance.id,
      'voucherNumber': instance.voucherNumber,
      'expenseDate': instance.expenseDate.toIso8601String(),
      'categoryId': instance.categoryId,
      'categoryName': instance.categoryName,
      'description': instance.description,
      'amount': instance.amount.toJson(),
      'paymentMethod': _$PaymentMethodEnumMap[instance.paymentMethod]!,
      'status': _$InvoiceStatusEnumMap[instance.status]!,
      'createdBy': instance.createdBy,
      'paidByEmployeeName': ?instance.paidByEmployeeName,
      'referenceNumber': ?instance.referenceNumber,
      'pettyCashVoucherNumber': ?instance.pettyCashVoucherNumber,
      'notes': ?instance.notes,
      'cancelReason': ?instance.cancelReason,
    };

const _$InvoiceStatusEnumMap = {
  InvoiceStatus.draft: 'draft',
  InvoiceStatus.posted: 'posted',
  InvoiceStatus.cancelled: 'cancelled',
};

ExpenseCategorySummary _$ExpenseCategorySummaryFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('ExpenseCategorySummary', json, ($checkedConvert) {
  final val = ExpenseCategorySummary(
    id: $checkedConvert('id', (v) => (v as num).toInt()),
    code: $checkedConvert('code', (v) => v as String),
    name: $checkedConvert('name', (v) => v as String),
    status: $checkedConvert(
      'status',
      (v) => $enumDecode(_$EntityStatusEnumMap, v),
    ),
    isSystem: $checkedConvert('isSystem', (v) => v as bool),
    expenseCount: $checkedConvert('expenseCount', (v) => (v as num).toInt()),
    total: $checkedConvert('total', (v) => Money.fromJson((v as num).toInt())),
    accountCode: $checkedConvert('accountCode', (v) => v as String?),
  );
  return val;
});

Map<String, dynamic> _$ExpenseCategorySummaryToJson(
  ExpenseCategorySummary instance,
) => <String, dynamic>{
  'id': instance.id,
  'code': instance.code,
  'name': instance.name,
  'status': _$EntityStatusEnumMap[instance.status]!,
  'isSystem': instance.isSystem,
  'expenseCount': instance.expenseCount,
  'total': instance.total.toJson(),
  'accountCode': ?instance.accountCode,
};

const _$EntityStatusEnumMap = {
  EntityStatus.active: 'active',
  EntityStatus.inactive: 'inactive',
  EntityStatus.archived: 'archived',
};

ExpenseCategoryTotal _$ExpenseCategoryTotalFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('ExpenseCategoryTotal', json, ($checkedConvert) {
  final val = ExpenseCategoryTotal(
    categoryId: $checkedConvert('categoryId', (v) => (v as num).toInt()),
    categoryName: $checkedConvert('categoryName', (v) => v as String),
    total: $checkedConvert('total', (v) => Money.fromJson((v as num).toInt())),
    count: $checkedConvert('count', (v) => (v as num).toInt()),
  );
  return val;
});

Map<String, dynamic> _$ExpenseCategoryTotalToJson(
  ExpenseCategoryTotal instance,
) => <String, dynamic>{
  'categoryId': instance.categoryId,
  'categoryName': instance.categoryName,
  'total': instance.total.toJson(),
  'count': instance.count,
};

ExpenseTotals _$ExpenseTotalsFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('ExpenseTotals', json, ($checkedConvert) {
  final val = ExpenseTotals(
    count: $checkedConvert('count', (v) => (v as num).toInt()),
    total: $checkedConvert('total', (v) => Money.fromJson((v as num).toInt())),
    fromPettyCash: $checkedConvert(
      'fromPettyCash',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    cancelledCount: $checkedConvert(
      'cancelledCount',
      (v) => (v as num).toInt(),
    ),
    byCategory: $checkedConvert(
      'byCategory',
      (v) => (v as List<dynamic>)
          .map((e) => ExpenseCategoryTotal.fromJson(e as Map<String, dynamic>))
          .toList(),
    ),
  );
  return val;
});

Map<String, dynamic> _$ExpenseTotalsToJson(ExpenseTotals instance) =>
    <String, dynamic>{
      'count': instance.count,
      'total': instance.total.toJson(),
      'fromPettyCash': instance.fromPettyCash.toJson(),
      'cancelledCount': instance.cancelledCount,
      'byCategory': instance.byCategory.map((e) => e.toJson()).toList(),
    };

ExpenseFilter _$ExpenseFilterFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ExpenseFilter', json, ($checkedConvert) {
      final val = ExpenseFilter(
        search: $checkedConvert('search', (v) => v as String? ?? ''),
        categoryId: $checkedConvert('categoryId', (v) => (v as num?)?.toInt()),
        paymentMethod: $checkedConvert(
          'paymentMethod',
          (v) => $enumDecodeNullable(_$PaymentMethodEnumMap, v),
        ),
        status: $checkedConvert(
          'status',
          (v) => $enumDecodeNullable(_$InvoiceStatusEnumMap, v),
        ),
        pettyCashOnly: $checkedConvert(
          'pettyCashOnly',
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

Map<String, dynamic> _$ExpenseFilterToJson(ExpenseFilter instance) =>
    <String, dynamic>{
      'search': instance.search,
      'categoryId': ?instance.categoryId,
      'paymentMethod': ?_$PaymentMethodEnumMap[instance.paymentMethod],
      'status': ?_$InvoiceStatusEnumMap[instance.status],
      'pettyCashOnly': instance.pettyCashOnly,
      'from': ?instance.from?.toIso8601String(),
      'to': ?instance.to?.toIso8601String(),
      'limit': instance.limit,
    };
