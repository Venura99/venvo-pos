// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shop_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ShopListItem _$ShopListItemFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ShopListItem', json, ($checkedConvert) {
      final val = ShopListItem(
        id: $checkedConvert('id', (v) => (v as num).toInt()),
        code: $checkedConvert('code', (v) => v as String),
        name: $checkedConvert('name', (v) => v as String),
        openingBalance: $checkedConvert(
          'openingBalance',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        status: $checkedConvert(
          'status',
          (v) => $enumDecode(_$EntityStatusEnumMap, v),
        ),
        stockUnits: $checkedConvert('stockUnits', (v) => (v as num).toInt()),
        stockValueAtCost: $checkedConvert(
          'stockValueAtCost',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        billedTotal: $checkedConvert(
          'billedTotal',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        settledTotal: $checkedConvert(
          'settledTotal',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        pendingChequeTotal: $checkedConvert(
          'pendingChequeTotal',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        retailSalesTotal: $checkedConvert(
          'retailSalesTotal',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        ownerName: $checkedConvert('ownerName', (v) => v as String?),
        phone: $checkedConvert('phone', (v) => v as String?),
        address: $checkedConvert('address', (v) => v as String?),
        assignedAgentId: $checkedConvert(
          'assignedAgentId',
          (v) => (v as num?)?.toInt(),
        ),
        assignedAgentName: $checkedConvert(
          'assignedAgentName',
          (v) => v as String?,
        ),
        creditLimit: $checkedConvert(
          'creditLimit',
          (v) => v == null ? null : Money.fromJson((v as num).toInt()),
        ),
        notes: $checkedConvert('notes', (v) => v as String?),
        locationId: $checkedConvert('locationId', (v) => (v as num?)?.toInt()),
      );
      return val;
    });

Map<String, dynamic> _$ShopListItemToJson(ShopListItem instance) =>
    <String, dynamic>{
      'id': instance.id,
      'code': instance.code,
      'name': instance.name,
      'ownerName': ?instance.ownerName,
      'phone': ?instance.phone,
      'address': ?instance.address,
      'assignedAgentId': ?instance.assignedAgentId,
      'assignedAgentName': ?instance.assignedAgentName,
      'openingBalance': instance.openingBalance.toJson(),
      'creditLimit': ?instance.creditLimit?.toJson(),
      'status': _$EntityStatusEnumMap[instance.status]!,
      'notes': ?instance.notes,
      'locationId': ?instance.locationId,
      'stockUnits': instance.stockUnits,
      'stockValueAtCost': instance.stockValueAtCost.toJson(),
      'billedTotal': instance.billedTotal.toJson(),
      'settledTotal': instance.settledTotal.toJson(),
      'pendingChequeTotal': instance.pendingChequeTotal.toJson(),
      'retailSalesTotal': instance.retailSalesTotal.toJson(),
    };

const _$EntityStatusEnumMap = {
  EntityStatus.active: 'active',
  EntityStatus.inactive: 'inactive',
  EntityStatus.archived: 'archived',
};

ShopDraft _$ShopDraftFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ShopDraft', json, ($checkedConvert) {
      final val = ShopDraft(
        name: $checkedConvert('name', (v) => v as String),
        id: $checkedConvert('id', (v) => (v as num?)?.toInt()),
        code: $checkedConvert('code', (v) => v as String?),
        ownerName: $checkedConvert('ownerName', (v) => v as String?),
        phone: $checkedConvert('phone', (v) => v as String?),
        address: $checkedConvert('address', (v) => v as String?),
        assignedAgentId: $checkedConvert(
          'assignedAgentId',
          (v) => (v as num?)?.toInt(),
        ),
        openingBalance: $checkedConvert(
          'openingBalance',
          (v) => v == null ? Money.zero : Money.fromJson((v as num).toInt()),
        ),
        creditLimit: $checkedConvert(
          'creditLimit',
          (v) => v == null ? null : Money.fromJson((v as num).toInt()),
        ),
        status: $checkedConvert(
          'status',
          (v) =>
              $enumDecodeNullable(_$EntityStatusEnumMap, v) ??
              EntityStatus.active,
        ),
        notes: $checkedConvert('notes', (v) => v as String?),
      );
      return val;
    });

Map<String, dynamic> _$ShopDraftToJson(ShopDraft instance) => <String, dynamic>{
  'id': ?instance.id,
  'code': ?instance.code,
  'name': instance.name,
  'ownerName': ?instance.ownerName,
  'phone': ?instance.phone,
  'address': ?instance.address,
  'assignedAgentId': ?instance.assignedAgentId,
  'openingBalance': instance.openingBalance.toJson(),
  'creditLimit': ?instance.creditLimit?.toJson(),
  'status': _$EntityStatusEnumMap[instance.status]!,
  'notes': ?instance.notes,
};

ShopFilter _$ShopFilterFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ShopFilter', json, ($checkedConvert) {
      final val = ShopFilter(
        search: $checkedConvert('search', (v) => v as String? ?? ''),
        agentId: $checkedConvert('agentId', (v) => (v as num?)?.toInt()),
        includeInactive: $checkedConvert(
          'includeInactive',
          (v) => v as bool? ?? false,
        ),
        includeArchived: $checkedConvert(
          'includeArchived',
          (v) => v as bool? ?? false,
        ),
        owingOnly: $checkedConvert('owingOnly', (v) => v as bool? ?? false),
        overCreditLimitOnly: $checkedConvert(
          'overCreditLimitOnly',
          (v) => v as bool? ?? false,
        ),
        unassignedOnly: $checkedConvert(
          'unassignedOnly',
          (v) => v as bool? ?? false,
        ),
      );
      return val;
    });

Map<String, dynamic> _$ShopFilterToJson(ShopFilter instance) =>
    <String, dynamic>{
      'search': instance.search,
      'agentId': ?instance.agentId,
      'includeInactive': instance.includeInactive,
      'includeArchived': instance.includeArchived,
      'owingOnly': instance.owingOnly,
      'overCreditLimitOnly': instance.overCreditLimitOnly,
      'unassignedOnly': instance.unassignedOnly,
    };
