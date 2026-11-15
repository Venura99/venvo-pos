import '../../../core/enums/app_enums.dart';
import 'package:json_annotation/json_annotation.dart';

part 'category_models.g.dart';

/// A category as the list screen needs it: the stored row plus the two things
/// the screen would otherwise have to query per row - its parent's name and
/// how many products point at it.
@JsonSerializable()
class CategoryListItem {
  const CategoryListItem({
    required this.id,
    required this.name,
    required this.parentId,
    required this.parentName,
    required this.sortOrder,
    required this.status,
    required this.activeProductCount,
    required this.totalProductCount,
    this.description,
  });

  final int id;
  final String name;
  final int? parentId;
  final String? parentName;
  final int sortOrder;
  final EntityStatus status;

  /// Products in this category that are themselves active. A category with
  /// active products cannot be archived.
  final int activeProductCount;
  final int totalProductCount;
  final String? description;

  bool get isArchived => status == EntityStatus.archived;

  /// Name with its parent prefixed, for display in a picker where the bare
  /// name would be ambiguous.
  String get qualifiedName => parentName == null ? name : '$parentName / $name';

  factory CategoryListItem.fromJson(Map<String, dynamic> json) =>
      _$CategoryListItemFromJson(json);

  Map<String, dynamic> toJson() => _$CategoryListItemToJson(this);
}

/// Input for creating or updating a category. Created by the form, validated
/// and consumed by the repository.
@JsonSerializable()
class CategoryDraft {
  const CategoryDraft({
    required this.name,
    this.id,
    this.description,
    this.parentId,
    this.sortOrder = 0,
    this.status = EntityStatus.active,
  });

  /// Null when creating.
  final int? id;
  final String name;
  final String? description;
  final int? parentId;
  final int sortOrder;
  final EntityStatus status;

  bool get isNew => id == null;

  factory CategoryDraft.fromJson(Map<String, dynamic> json) =>
      _$CategoryDraftFromJson(json);

  Map<String, dynamic> toJson() => _$CategoryDraftToJson(this);
}
