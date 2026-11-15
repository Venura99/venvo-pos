// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'petty_cash_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PettyCashDraft _$PettyCashDraftFromJson(Map<String, dynamic> json) =>
    $checkedCreate('PettyCashDraft', json, ($checkedConvert) {
      final val = PettyCashDraft(
        kind: $checkedConvert(
          'kind',
          (v) => $enumDecode(_$PettyCashEntryKindEnumMap, v),
        ),
        amount: $checkedConvert(
          'amount',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        description: $checkedConvert('description', (v) => v as String),
        entryDate: $checkedConvert(
          'entryDate',
          (v) => v == null ? null : DateTime.parse(v as String),
        ),
        referenceNumber: $checkedConvert(
          'referenceNumber',
          (v) => v as String?,
        ),
        handledByEmployeeId: $checkedConvert(
          'handledByEmployeeId',
          (v) => (v as num?)?.toInt(),
        ),
        adjustmentAddsToFloat: $checkedConvert(
          'adjustmentAddsToFloat',
          (v) => v as bool? ?? false,
        ),
      );
      return val;
    });

Map<String, dynamic> _$PettyCashDraftToJson(PettyCashDraft instance) =>
    <String, dynamic>{
      'kind': _$PettyCashEntryKindEnumMap[instance.kind]!,
      'amount': instance.amount.toJson(),
      'description': instance.description,
      'entryDate': ?instance.entryDate?.toIso8601String(),
      'referenceNumber': ?instance.referenceNumber,
      'handledByEmployeeId': ?instance.handledByEmployeeId,
      'adjustmentAddsToFloat': instance.adjustmentAddsToFloat,
    };

const _$PettyCashEntryKindEnumMap = {
  PettyCashEntryKind.opening: 'opening',
  PettyCashEntryKind.cashReceived: 'cashReceived',
  PettyCashEntryKind.cashIssued: 'cashIssued',
  PettyCashEntryKind.expense: 'expense',
  PettyCashEntryKind.adjustment: 'adjustment',
};

PettyCashRow _$PettyCashRowFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('PettyCashRow', json, ($checkedConvert) {
  final val = PettyCashRow(
    id: $checkedConvert('id', (v) => (v as num).toInt()),
    voucherNumber: $checkedConvert('voucherNumber', (v) => v as String),
    entryDate: $checkedConvert('entryDate', (v) => DateTime.parse(v as String)),
    kind: $checkedConvert(
      'kind',
      (v) => $enumDecode(_$PettyCashEntryKindEnumMap, v),
    ),
    amount: $checkedConvert(
      'amount',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    signedAmount: $checkedConvert(
      'signedAmount',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    balanceAfter: $checkedConvert(
      'balanceAfter',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    description: $checkedConvert('description', (v) => v as String),
    createdBy: $checkedConvert('createdBy', (v) => v as String),
    referenceNumber: $checkedConvert('referenceNumber', (v) => v as String?),
    expenseId: $checkedConvert('expenseId', (v) => (v as num?)?.toInt()),
    expenseVoucherNumber: $checkedConvert(
      'expenseVoucherNumber',
      (v) => v as String?,
    ),
    handledByEmployeeName: $checkedConvert(
      'handledByEmployeeName',
      (v) => v as String?,
    ),
  );
  return val;
});

Map<String, dynamic> _$PettyCashRowToJson(PettyCashRow instance) =>
    <String, dynamic>{
      'id': instance.id,
      'voucherNumber': instance.voucherNumber,
      'entryDate': instance.entryDate.toIso8601String(),
      'kind': _$PettyCashEntryKindEnumMap[instance.kind]!,
      'amount': instance.amount.toJson(),
      'signedAmount': instance.signedAmount.toJson(),
      'balanceAfter': instance.balanceAfter.toJson(),
      'description': instance.description,
      'createdBy': instance.createdBy,
      'referenceNumber': ?instance.referenceNumber,
      'expenseId': ?instance.expenseId,
      'expenseVoucherNumber': ?instance.expenseVoucherNumber,
      'handledByEmployeeName': ?instance.handledByEmployeeName,
    };

PettyCashSnapshot _$PettyCashSnapshotFromJson(Map<String, dynamic> json) =>
    $checkedCreate('PettyCashSnapshot', json, ($checkedConvert) {
      final val = PettyCashSnapshot(
        balance: $checkedConvert(
          'balance',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        entryCount: $checkedConvert('entryCount', (v) => (v as num).toInt()),
        receivedInPeriod: $checkedConvert(
          'receivedInPeriod',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        spentInPeriod: $checkedConvert(
          'spentInPeriod',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        lastEntryAt: $checkedConvert(
          'lastEntryAt',
          (v) => v == null ? null : DateTime.parse(v as String),
        ),
      );
      return val;
    });

Map<String, dynamic> _$PettyCashSnapshotToJson(PettyCashSnapshot instance) =>
    <String, dynamic>{
      'balance': instance.balance.toJson(),
      'entryCount': instance.entryCount,
      'receivedInPeriod': instance.receivedInPeriod.toJson(),
      'spentInPeriod': instance.spentInPeriod.toJson(),
      'lastEntryAt': ?instance.lastEntryAt?.toIso8601String(),
    };

PettyCashFilter _$PettyCashFilterFromJson(Map<String, dynamic> json) =>
    $checkedCreate('PettyCashFilter', json, ($checkedConvert) {
      final val = PettyCashFilter(
        search: $checkedConvert('search', (v) => v as String? ?? ''),
        kind: $checkedConvert(
          'kind',
          (v) => $enumDecodeNullable(_$PettyCashEntryKindEnumMap, v),
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

Map<String, dynamic> _$PettyCashFilterToJson(PettyCashFilter instance) =>
    <String, dynamic>{
      'search': instance.search,
      'kind': ?_$PettyCashEntryKindEnumMap[instance.kind],
      'from': ?instance.from?.toIso8601String(),
      'to': ?instance.to?.toIso8601String(),
      'limit': instance.limit,
    };
