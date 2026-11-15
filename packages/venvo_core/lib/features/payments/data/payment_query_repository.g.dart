// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'payment_query_repository.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PaymentTotalsSnapshot _$PaymentTotalsSnapshotFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('PaymentTotalsSnapshot', json, ($checkedConvert) {
  final val = PaymentTotalsSnapshot(
    count: $checkedConvert('count', (v) => (v as num).toInt()),
    clearedIn: $checkedConvert(
      'clearedIn',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    clearedOut: $checkedConvert(
      'clearedOut',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    pending: $checkedConvert(
      'pending',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    bounced: $checkedConvert(
      'bounced',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    advances: $checkedConvert(
      'advances',
      (v) => Money.fromJson((v as num).toInt()),
    ),
  );
  return val;
});

Map<String, dynamic> _$PaymentTotalsSnapshotToJson(
  PaymentTotalsSnapshot instance,
) => <String, dynamic>{
  'count': instance.count,
  'clearedIn': instance.clearedIn.toJson(),
  'clearedOut': instance.clearedOut.toJson(),
  'pending': instance.pending.toJson(),
  'bounced': instance.bounced.toJson(),
  'advances': instance.advances.toJson(),
};

ChequeTotalsSnapshot _$ChequeTotalsSnapshotFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('ChequeTotalsSnapshot', json, ($checkedConvert) {
  final val = ChequeTotalsSnapshot(
    count: $checkedConvert('count', (v) => (v as num).toInt()),
    outstanding: $checkedConvert(
      'outstanding',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    cleared: $checkedConvert(
      'cleared',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    bounced: $checkedConvert(
      'bounced',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    bankableCount: $checkedConvert('bankableCount', (v) => (v as num).toInt()),
    postDatedCount: $checkedConvert(
      'postDatedCount',
      (v) => (v as num).toInt(),
    ),
  );
  return val;
});

Map<String, dynamic> _$ChequeTotalsSnapshotToJson(
  ChequeTotalsSnapshot instance,
) => <String, dynamic>{
  'count': instance.count,
  'outstanding': instance.outstanding.toJson(),
  'cleared': instance.cleared.toJson(),
  'bounced': instance.bounced.toJson(),
  'bankableCount': instance.bankableCount,
  'postDatedCount': instance.postDatedCount,
};
