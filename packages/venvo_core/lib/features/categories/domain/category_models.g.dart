// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'category_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CategoryListItem _$CategoryListItemFromJson(Map<String, dynamic> json) =>
    $checkedCreate('CategoryListItem', json, ($checkedConvert) {
      final val = CategoryListItem(
        id: $checkedConvert('id', (v) => (v as num).toInt()),
        name: $checkedConvert('name', (v) => v as String),
        parentId: $checkedConvert('parentId', (v) => (v as num?)?.toInt()),
        parentName: $checkedConvert('parentName', (v) => v as String?),
        sortOrder: $checkedConvert('sortOrder', (v) => (v as num).toInt()),
        status: $checkedConvert(
          'status',
          (v) => $enumDecode(_$EntityStatusEnumMap, v),
        ),
        activeProductCount: $checkedConvert(
          'activeProductCount',
          (v) => (v as num).toInt(),
        ),
        totalProductCount: $checkedConvert(
          'totalProductCount',
          (v) => (v as num).toInt(),
        ),
        description: $checkedConvert('description', (v) => v as String?),
      );
      return val;
    });

Map<String, dynamic> _$CategoryListItemToJson(CategoryListItem instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'parentId': ?instance.parentId,
      'parentName': ?instance.parentName,
      'sortOrder': instance.sortOrder,
      'status': _$EntityStatusEnumMap[instance.status]!,
      'activeProductCount': instance.activeProductCount,
      'totalProductCount': instance.totalProductCount,
      'description': ?instance.description,
    };

const _$EntityStatusEnumMap = {
  EntityStatus.active: 'active',
  EntityStatus.inactive: 'inactive',
  EntityStatus.archived: 'archived',
};

CategoryDraft _$CategoryDraftFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('CategoryDraft', json, ($checkedConvert) {
  final val = CategoryDraft(
    name: $checkedConvert('name', (v) => v as String),
    id: $checkedConvert('id', (v) => (v as num?)?.toInt()),
    description: $checkedConvert('description', (v) => v as String?),
    parentId: $checkedConvert('parentId', (v) => (v as num?)?.toInt()),
    sortOrder: $checkedConvert('sortOrder', (v) => (v as num?)?.toInt() ?? 0),
    status: $checkedConvert(
      'status',
      (v) =>
          $enumDecodeNullable(_$EntityStatusEnumMap, v) ?? EntityStatus.active,
    ),
  );
  return val;
});

Map<String, dynamic> _$CategoryDraftToJson(CategoryDraft instance) =>
    <String, dynamic>{
      'id': ?instance.id,
      'name': instance.name,
      'description': ?instance.description,
      'parentId': ?instance.parentId,
      'sortOrder': instance.sortOrder,
      'status': _$EntityStatusEnumMap[instance.status]!,
    };
