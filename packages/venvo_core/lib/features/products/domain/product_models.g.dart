// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'product_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProductListItem _$ProductListItemFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('ProductListItem', json, ($checkedConvert) {
  final val = ProductListItem(
    id: $checkedConvert('id', (v) => (v as num).toInt()),
    sku: $checkedConvert('sku', (v) => v as String),
    name: $checkedConvert('name', (v) => v as String),
    categoryId: $checkedConvert('categoryId', (v) => (v as num).toInt()),
    categoryName: $checkedConvert('categoryName', (v) => v as String),
    unitOfMeasure: $checkedConvert(
      'unitOfMeasure',
      (v) => $enumDecode(_$UnitOfMeasureEnumMap, v),
    ),
    unitsPerPack: $checkedConvert('unitsPerPack', (v) => (v as num).toInt()),
    costPrice: $checkedConvert(
      'costPrice',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    wholesalePrice: $checkedConvert(
      'wholesalePrice',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    retailPrice: $checkedConvert(
      'retailPrice',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    reorderLevel: $checkedConvert('reorderLevel', (v) => (v as num).toInt()),
    status: $checkedConvert(
      'status',
      (v) => $enumDecode(_$EntityStatusEnumMap, v),
    ),
    warehouseQuantity: $checkedConvert(
      'warehouseQuantity',
      (v) => (v as num).toInt(),
    ),
    agentQuantity: $checkedConvert('agentQuantity', (v) => (v as num).toInt()),
    shopQuantity: $checkedConvert('shopQuantity', (v) => (v as num).toInt()),
    damagedQuantity: $checkedConvert(
      'damagedQuantity',
      (v) => (v as num).toInt(),
    ),
    barcode: $checkedConvert('barcode', (v) => v as String?),
    brand: $checkedConvert('brand', (v) => v as String?),
    description: $checkedConvert('description', (v) => v as String?),
    notes: $checkedConvert('notes', (v) => v as String?),
  );
  return val;
});

Map<String, dynamic> _$ProductListItemToJson(ProductListItem instance) =>
    <String, dynamic>{
      'id': instance.id,
      'sku': instance.sku,
      'name': instance.name,
      'barcode': ?instance.barcode,
      'categoryId': instance.categoryId,
      'categoryName': instance.categoryName,
      'brand': ?instance.brand,
      'description': ?instance.description,
      'unitOfMeasure': _$UnitOfMeasureEnumMap[instance.unitOfMeasure]!,
      'unitsPerPack': instance.unitsPerPack,
      'costPrice': instance.costPrice.toJson(),
      'wholesalePrice': instance.wholesalePrice.toJson(),
      'retailPrice': instance.retailPrice.toJson(),
      'reorderLevel': instance.reorderLevel,
      'status': _$EntityStatusEnumMap[instance.status]!,
      'notes': ?instance.notes,
      'warehouseQuantity': instance.warehouseQuantity,
      'agentQuantity': instance.agentQuantity,
      'shopQuantity': instance.shopQuantity,
      'damagedQuantity': instance.damagedQuantity,
    };

const _$UnitOfMeasureEnumMap = {
  UnitOfMeasure.piece: 'piece',
  UnitOfMeasure.pack: 'pack',
  UnitOfMeasure.box: 'box',
  UnitOfMeasure.dozen: 'dozen',
  UnitOfMeasure.set: 'set',
  UnitOfMeasure.pair: 'pair',
  UnitOfMeasure.meter: 'meter',
  UnitOfMeasure.kilogram: 'kilogram',
};

const _$EntityStatusEnumMap = {
  EntityStatus.active: 'active',
  EntityStatus.inactive: 'inactive',
  EntityStatus.archived: 'archived',
};

ProductDraft _$ProductDraftFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('ProductDraft', json, ($checkedConvert) {
  final val = ProductDraft(
    sku: $checkedConvert('sku', (v) => v as String),
    name: $checkedConvert('name', (v) => v as String),
    categoryId: $checkedConvert('categoryId', (v) => (v as num).toInt()),
    id: $checkedConvert('id', (v) => (v as num?)?.toInt()),
    barcode: $checkedConvert('barcode', (v) => v as String?),
    brand: $checkedConvert('brand', (v) => v as String?),
    description: $checkedConvert('description', (v) => v as String?),
    unitOfMeasure: $checkedConvert(
      'unitOfMeasure',
      (v) =>
          $enumDecodeNullable(_$UnitOfMeasureEnumMap, v) ?? UnitOfMeasure.piece,
    ),
    unitsPerPack: $checkedConvert(
      'unitsPerPack',
      (v) => (v as num?)?.toInt() ?? 1,
    ),
    costPrice: $checkedConvert(
      'costPrice',
      (v) => v == null ? Money.zero : Money.fromJson((v as num).toInt()),
    ),
    wholesalePrice: $checkedConvert(
      'wholesalePrice',
      (v) => v == null ? Money.zero : Money.fromJson((v as num).toInt()),
    ),
    retailPrice: $checkedConvert(
      'retailPrice',
      (v) => v == null ? Money.zero : Money.fromJson((v as num).toInt()),
    ),
    reorderLevel: $checkedConvert(
      'reorderLevel',
      (v) => (v as num?)?.toInt() ?? 0,
    ),
    status: $checkedConvert(
      'status',
      (v) =>
          $enumDecodeNullable(_$EntityStatusEnumMap, v) ?? EntityStatus.active,
    ),
    notes: $checkedConvert('notes', (v) => v as String?),
  );
  return val;
});

Map<String, dynamic> _$ProductDraftToJson(ProductDraft instance) =>
    <String, dynamic>{
      'id': ?instance.id,
      'sku': instance.sku,
      'name': instance.name,
      'barcode': ?instance.barcode,
      'categoryId': instance.categoryId,
      'brand': ?instance.brand,
      'description': ?instance.description,
      'unitOfMeasure': _$UnitOfMeasureEnumMap[instance.unitOfMeasure]!,
      'unitsPerPack': instance.unitsPerPack,
      'costPrice': instance.costPrice.toJson(),
      'wholesalePrice': instance.wholesalePrice.toJson(),
      'retailPrice': instance.retailPrice.toJson(),
      'reorderLevel': instance.reorderLevel,
      'status': _$EntityStatusEnumMap[instance.status]!,
      'notes': ?instance.notes,
    };

ProductFilter _$ProductFilterFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('ProductFilter', json, ($checkedConvert) {
  final val = ProductFilter(
    search: $checkedConvert('search', (v) => v as String? ?? ''),
    categoryId: $checkedConvert('categoryId', (v) => (v as num?)?.toInt()),
    brand: $checkedConvert('brand', (v) => v as String?),
    includeInactive: $checkedConvert(
      'includeInactive',
      (v) => v as bool? ?? false,
    ),
    includeArchived: $checkedConvert(
      'includeArchived',
      (v) => v as bool? ?? false,
    ),
    lowStockOnly: $checkedConvert('lowStockOnly', (v) => v as bool? ?? false),
    sortKey: $checkedConvert(
      'sortKey',
      (v) =>
          $enumDecodeNullable(_$ProductSortKeyEnumMap, v) ??
          ProductSortKey.name,
    ),
    sortAscending: $checkedConvert('sortAscending', (v) => v as bool? ?? true),
  );
  return val;
});

Map<String, dynamic> _$ProductFilterToJson(ProductFilter instance) =>
    <String, dynamic>{
      'search': instance.search,
      'categoryId': ?instance.categoryId,
      'brand': ?instance.brand,
      'includeInactive': instance.includeInactive,
      'includeArchived': instance.includeArchived,
      'lowStockOnly': instance.lowStockOnly,
      'sortKey': _$ProductSortKeyEnumMap[instance.sortKey]!,
      'sortAscending': instance.sortAscending,
    };

const _$ProductSortKeyEnumMap = {
  ProductSortKey.name: 'name',
  ProductSortKey.sku: 'sku',
  ProductSortKey.category: 'category',
  ProductSortKey.costPrice: 'costPrice',
  ProductSortKey.wholesalePrice: 'wholesalePrice',
  ProductSortKey.retailPrice: 'retailPrice',
  ProductSortKey.stock: 'stock',
};

ProductStockAtLocation _$ProductStockAtLocationFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('ProductStockAtLocation', json, ($checkedConvert) {
  final val = ProductStockAtLocation(
    locationName: $checkedConvert('locationName', (v) => v as String),
    locationKind: $checkedConvert(
      'locationKind',
      (v) => $enumDecode(_$LocationKindEnumMap, v),
    ),
    quantity: $checkedConvert('quantity', (v) => (v as num).toInt()),
  );
  return val;
});

Map<String, dynamic> _$ProductStockAtLocationToJson(
  ProductStockAtLocation instance,
) => <String, dynamic>{
  'locationName': instance.locationName,
  'locationKind': _$LocationKindEnumMap[instance.locationKind]!,
  'quantity': instance.quantity,
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
