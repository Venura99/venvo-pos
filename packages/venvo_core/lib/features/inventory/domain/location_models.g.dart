// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'location_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LocationListItem _$LocationListItemFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('LocationListItem', json, ($checkedConvert) {
  final val = LocationListItem(
    id: $checkedConvert('id', (v) => (v as num).toInt()),
    code: $checkedConvert('code', (v) => v as String),
    name: $checkedConvert('name', (v) => v as String),
    kind: $checkedConvert('kind', (v) => $enumDecode(_$LocationKindEnumMap, v)),
    isActive: $checkedConvert('isActive', (v) => v as bool),
    productLines: $checkedConvert('productLines', (v) => (v as num).toInt()),
    totalUnits: $checkedConvert('totalUnits', (v) => (v as num).toInt()),
    stockValueAtCost: $checkedConvert(
      'stockValueAtCost',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    agentId: $checkedConvert('agentId', (v) => (v as num?)?.toInt()),
    shopId: $checkedConvert('shopId', (v) => (v as num?)?.toInt()),
    ownerName: $checkedConvert('ownerName', (v) => v as String?),
  );
  return val;
});

Map<String, dynamic> _$LocationListItemToJson(LocationListItem instance) =>
    <String, dynamic>{
      'id': instance.id,
      'code': instance.code,
      'name': instance.name,
      'kind': _$LocationKindEnumMap[instance.kind]!,
      'isActive': instance.isActive,
      'productLines': instance.productLines,
      'totalUnits': instance.totalUnits,
      'stockValueAtCost': instance.stockValueAtCost.toJson(),
      'agentId': ?instance.agentId,
      'shopId': ?instance.shopId,
      'ownerName': ?instance.ownerName,
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
