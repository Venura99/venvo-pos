import '../../../core/enums/app_enums.dart';
import '../../../core/utils/money.dart';
import 'package:json_annotation/json_annotation.dart';

part 'product_models.g.dart';

/// A product as the catalogue screen needs it: the stored row, its category
/// name, and the stock it currently has across the business.
@JsonSerializable()
class ProductListItem {
  const ProductListItem({
    required this.id,
    required this.sku,
    required this.name,
    required this.categoryId,
    required this.categoryName,
    required this.unitOfMeasure,
    required this.unitsPerPack,
    required this.costPrice,
    required this.wholesalePrice,
    required this.retailPrice,
    required this.reorderLevel,
    required this.status,
    required this.warehouseQuantity,
    required this.agentQuantity,
    required this.shopQuantity,
    required this.damagedQuantity,
    this.barcode,
    this.brand,
    this.description,
    this.notes,
  });

  final int id;
  final String sku;
  final String name;
  final String? barcode;
  final int categoryId;
  final String categoryName;
  final String? brand;
  final String? description;
  final UnitOfMeasure unitOfMeasure;
  final int unitsPerPack;
  final Money costPrice;
  final Money wholesalePrice;
  final Money retailPrice;
  final int reorderLevel;
  final EntityStatus status;
  final String? notes;

  final int warehouseQuantity;
  final int agentQuantity;
  final int shopQuantity;

  /// Held in the quarantine location. Deliberately excluded from
  /// [sellableQuantity]: damaged goods are not stock that can be sold.
  final int damagedQuantity;

  bool get isActive => status == EntityStatus.active;
  bool get isArchived => status == EntityStatus.archived;

  /// Everything the business can still sell, wherever it sits.
  int get sellableQuantity => warehouseQuantity + agentQuantity + shopQuantity;

  /// True when the product is at or below its reorder level. A reorder level
  /// of zero means the product is not tracked for reordering.
  bool get isLowStock => reorderLevel > 0 && sellableQuantity <= reorderLevel;

  /// Value of the sellable stock at cost.
  Money get stockValueAtCost => costPrice * sellableQuantity;

  /// Margin on a wholesale sale, which may be negative if the product is
  /// being sold below cost.
  Money get wholesaleMargin => wholesalePrice - costPrice;

  /// Margin as basis points of the wholesale price, for display.
  int get wholesaleMarginBps =>
      wholesalePrice.isZero ? 0 : wholesaleMargin.bpsOf(wholesalePrice);

  bool get sellsBelowCost =>
      !wholesalePrice.isZero && wholesalePrice < costPrice;

  factory ProductListItem.fromJson(Map<String, dynamic> json) =>
      _$ProductListItemFromJson(json);

  Map<String, dynamic> toJson() => _$ProductListItemToJson(this);
}

/// Input for creating or updating a product.
@JsonSerializable()
class ProductDraft {
  const ProductDraft({
    required this.sku,
    required this.name,
    required this.categoryId,
    this.id,
    this.barcode,
    this.brand,
    this.description,
    this.unitOfMeasure = UnitOfMeasure.piece,
    this.unitsPerPack = 1,
    this.costPrice = Money.zero,
    this.wholesalePrice = Money.zero,
    this.retailPrice = Money.zero,
    this.reorderLevel = 0,
    this.status = EntityStatus.active,
    this.notes,
  });

  final int? id;
  final String sku;
  final String name;
  final String? barcode;
  final int categoryId;
  final String? brand;
  final String? description;
  final UnitOfMeasure unitOfMeasure;
  final int unitsPerPack;
  final Money costPrice;
  final Money wholesalePrice;
  final Money retailPrice;
  final int reorderLevel;
  final EntityStatus status;
  final String? notes;

  bool get isNew => id == null;

  factory ProductDraft.fromJson(Map<String, dynamic> json) =>
      _$ProductDraftFromJson(json);

  Map<String, dynamic> toJson() => _$ProductDraftToJson(this);
}

/// How the catalogue list is narrowed. Applied in SQL so the indexes are used
/// rather than loading the whole catalogue and filtering in memory.
@JsonSerializable()
class ProductFilter {
  const ProductFilter({
    this.search = '',
    this.categoryId,
    this.brand,
    this.includeInactive = false,
    this.includeArchived = false,
    this.lowStockOnly = false,
    this.sortKey = ProductSortKey.name,
    this.sortAscending = true,
  });

  final String search;
  final int? categoryId;
  final String? brand;
  final bool includeInactive;
  final bool includeArchived;
  final bool lowStockOnly;
  final ProductSortKey sortKey;
  final bool sortAscending;

  bool get hasAnyFilter =>
      search.trim().isNotEmpty ||
      categoryId != null ||
      brand != null ||
      lowStockOnly;

  ProductFilter copyWith({
    String? search,
    int? categoryId,
    bool clearCategory = false,
    String? brand,
    bool clearBrand = false,
    bool? includeInactive,
    bool? includeArchived,
    bool? lowStockOnly,
    ProductSortKey? sortKey,
    bool? sortAscending,
  }) {
    return ProductFilter(
      search: search ?? this.search,
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      brand: clearBrand ? null : (brand ?? this.brand),
      includeInactive: includeInactive ?? this.includeInactive,
      includeArchived: includeArchived ?? this.includeArchived,
      lowStockOnly: lowStockOnly ?? this.lowStockOnly,
      sortKey: sortKey ?? this.sortKey,
      sortAscending: sortAscending ?? this.sortAscending,
    );
  }

  /// Toggles between ascending and descending when the same column is clicked
  /// again, and resets to ascending for a new column.
  ProductFilter withSort(ProductSortKey key) {
    return copyWith(
      sortKey: key,
      sortAscending: sortKey == key ? !sortAscending : true,
    );
  }

  factory ProductFilter.fromJson(Map<String, dynamic> json) =>
      _$ProductFilterFromJson(json);

  Map<String, dynamic> toJson() => _$ProductFilterToJson(this);
}

enum ProductSortKey {
  name('name'),
  sku('sku'),
  category('category'),
  costPrice('cost'),
  wholesalePrice('wholesale'),
  retailPrice('retail'),
  stock('stock');

  const ProductSortKey(this.id);

  /// Stable identifier used as the table column's sort key.
  final String id;

  static ProductSortKey? fromId(String id) {
    for (final key in values) {
      if (key.id == id) return key;
    }
    return null;
  }
}

/// Where a product's stock sits, for the "cannot archive" explanation and for
/// the product detail panel.
@JsonSerializable()
class ProductStockAtLocation {
  const ProductStockAtLocation({
    required this.locationName,
    required this.locationKind,
    required this.quantity,
  });

  final String locationName;
  final LocationKind locationKind;
  final int quantity;

  factory ProductStockAtLocation.fromJson(Map<String, dynamic> json) =>
      _$ProductStockAtLocationFromJson(json);

  Map<String, dynamic> toJson() => _$ProductStockAtLocationToJson(this);
}

/// Human label for a unit of measure.
String unitOfMeasureLabel(UnitOfMeasure unit) => switch (unit) {
  UnitOfMeasure.piece => 'Piece',
  UnitOfMeasure.pack => 'Pack',
  UnitOfMeasure.box => 'Box',
  UnitOfMeasure.dozen => 'Dozen',
  UnitOfMeasure.set => 'Set',
  UnitOfMeasure.pair => 'Pair',
  UnitOfMeasure.meter => 'Meter',
  UnitOfMeasure.kilogram => 'Kilogram',
};
