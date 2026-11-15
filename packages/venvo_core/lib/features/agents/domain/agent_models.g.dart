// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AgentListItem _$AgentListItemFromJson(Map<String, dynamic> json) =>
    $checkedCreate('AgentListItem', json, ($checkedConvert) {
      final val = AgentListItem(
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
        activeShopCount: $checkedConvert(
          'activeShopCount',
          (v) => (v as num).toInt(),
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
        phone: $checkedConvert('phone', (v) => v as String?),
        address: $checkedConvert('address', (v) => v as String?),
        nic: $checkedConvert('nic', (v) => v as String?),
        commissionBps: $checkedConvert(
          'commissionBps',
          (v) => (v as num?)?.toInt(),
        ),
        notes: $checkedConvert('notes', (v) => v as String?),
        locationId: $checkedConvert('locationId', (v) => (v as num?)?.toInt()),
      );
      return val;
    });

Map<String, dynamic> _$AgentListItemToJson(AgentListItem instance) =>
    <String, dynamic>{
      'id': instance.id,
      'code': instance.code,
      'name': instance.name,
      'phone': ?instance.phone,
      'address': ?instance.address,
      'nic': ?instance.nic,
      'commissionBps': ?instance.commissionBps,
      'openingBalance': instance.openingBalance.toJson(),
      'status': _$EntityStatusEnumMap[instance.status]!,
      'notes': ?instance.notes,
      'locationId': ?instance.locationId,
      'activeShopCount': instance.activeShopCount,
      'stockUnits': instance.stockUnits,
      'stockValueAtCost': instance.stockValueAtCost.toJson(),
      'billedTotal': instance.billedTotal.toJson(),
      'settledTotal': instance.settledTotal.toJson(),
      'pendingChequeTotal': instance.pendingChequeTotal.toJson(),
    };

const _$EntityStatusEnumMap = {
  EntityStatus.active: 'active',
  EntityStatus.inactive: 'inactive',
  EntityStatus.archived: 'archived',
};

AgentDraft _$AgentDraftFromJson(Map<String, dynamic> json) =>
    $checkedCreate('AgentDraft', json, ($checkedConvert) {
      final val = AgentDraft(
        name: $checkedConvert('name', (v) => v as String),
        id: $checkedConvert('id', (v) => (v as num?)?.toInt()),
        code: $checkedConvert('code', (v) => v as String?),
        phone: $checkedConvert('phone', (v) => v as String?),
        address: $checkedConvert('address', (v) => v as String?),
        nic: $checkedConvert('nic', (v) => v as String?),
        commissionBps: $checkedConvert(
          'commissionBps',
          (v) => (v as num?)?.toInt(),
        ),
        openingBalance: $checkedConvert(
          'openingBalance',
          (v) => v == null ? Money.zero : Money.fromJson((v as num).toInt()),
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

Map<String, dynamic> _$AgentDraftToJson(AgentDraft instance) =>
    <String, dynamic>{
      'id': ?instance.id,
      'code': ?instance.code,
      'name': instance.name,
      'phone': ?instance.phone,
      'address': ?instance.address,
      'nic': ?instance.nic,
      'commissionBps': ?instance.commissionBps,
      'openingBalance': instance.openingBalance.toJson(),
      'status': _$EntityStatusEnumMap[instance.status]!,
      'notes': ?instance.notes,
    };

AgentFilter _$AgentFilterFromJson(Map<String, dynamic> json) =>
    $checkedCreate('AgentFilter', json, ($checkedConvert) {
      final val = AgentFilter(
        search: $checkedConvert('search', (v) => v as String? ?? ''),
        includeInactive: $checkedConvert(
          'includeInactive',
          (v) => v as bool? ?? false,
        ),
        includeArchived: $checkedConvert(
          'includeArchived',
          (v) => v as bool? ?? false,
        ),
        owingOnly: $checkedConvert('owingOnly', (v) => v as bool? ?? false),
      );
      return val;
    });

Map<String, dynamic> _$AgentFilterToJson(AgentFilter instance) =>
    <String, dynamic>{
      'search': instance.search,
      'includeInactive': instance.includeInactive,
      'includeArchived': instance.includeArchived,
      'owingOnly': instance.owingOnly,
    };
