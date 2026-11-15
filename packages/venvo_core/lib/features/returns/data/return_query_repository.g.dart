// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'return_query_repository.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ReturnTotals _$ReturnTotalsFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ReturnTotals', json, ($checkedConvert) {
      final val = ReturnTotals(
        documentCount: $checkedConvert(
          'documentCount',
          (v) => (v as num).toInt(),
        ),
        totalUnits: $checkedConvert('totalUnits', (v) => (v as num).toInt()),
        totalValue: $checkedConvert(
          'totalValue',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        awaitingInspection: $checkedConvert(
          'awaitingInspection',
          (v) => (v as num).toInt(),
        ),
        creditedValue: $checkedConvert(
          'creditedValue',
          (v) => Money.fromJson((v as num).toInt()),
        ),
      );
      return val;
    });

Map<String, dynamic> _$ReturnTotalsToJson(ReturnTotals instance) =>
    <String, dynamic>{
      'documentCount': instance.documentCount,
      'totalUnits': instance.totalUnits,
      'totalValue': instance.totalValue.toJson(),
      'awaitingInspection': instance.awaitingInspection,
      'creditedValue': instance.creditedValue.toJson(),
    };
