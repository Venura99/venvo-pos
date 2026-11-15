import '../../../core/enums/app_enums.dart';
import '../../../core/utils/money.dart';
import 'package:json_annotation/json_annotation.dart';

part 'location_models.g.dart';

/// An inventory location with what it currently holds.
@JsonSerializable()
class LocationListItem {
  const LocationListItem({
    required this.id,
    required this.code,
    required this.name,
    required this.kind,
    required this.isActive,
    required this.productLines,
    required this.totalUnits,
    required this.stockValueAtCost,
    this.agentId,
    this.shopId,
    this.ownerName,
  });

  final int id;
  final String code;
  final String name;
  final LocationKind kind;
  final bool isActive;

  /// Distinct products with a non-zero balance here.
  final int productLines;
  final int totalUnits;
  final Money stockValueAtCost;

  final int? agentId;
  final int? shopId;

  /// The agent or shop this location belongs to, when it belongs to one.
  final String? ownerName;

  bool get isVirtual => kind.isVirtual;

  /// True when the location exists because a party exists, so it cannot be
  /// renamed or removed on its own.
  bool get isPartyOwned => agentId != null || shopId != null;

  /// A real location with a negative balance means something was posted that
  /// should not have been; it is surfaced rather than hidden.
  bool get hasNegativeStock => !isVirtual && totalUnits < 0;

  factory LocationListItem.fromJson(Map<String, dynamic> json) =>
      _$LocationListItemFromJson(json);

  Map<String, dynamic> toJson() => _$LocationListItemToJson(this);
}

/// Human label for a location kind.
String locationKindLabel(LocationKind kind) => switch (kind) {
  LocationKind.warehouse => 'Warehouse',
  LocationKind.agent => 'Agent',
  LocationKind.shop => 'Shop',
  LocationKind.damaged => 'Damaged / quarantine',
  LocationKind.supplier => 'Suppliers (virtual)',
  LocationKind.customer => 'Customers (virtual)',
  LocationKind.adjustment => 'Adjustments (virtual)',
  LocationKind.inTransit => 'In transit (virtual)',
};

/// Why the virtual locations exist, shown on the locations screen so nobody
/// mistakes them for places with real goods in them.
String locationKindExplanation(LocationKind kind) => switch (kind) {
  LocationKind.warehouse => 'Your own stock, before it goes out to an agent.',
  LocationKind.agent => 'Stock an agent is holding.',
  LocationKind.shop => 'Stock sitting in a retail shop.',
  LocationKind.damaged => 'Damaged or defective goods held back from sale.',
  LocationKind.supplier =>
    'The counterparty for goods bought in. Its balance is the mirror '
        'image of everything ever purchased.',
  LocationKind.customer => 'The counterparty for goods sold to end customers.',
  LocationKind.adjustment =>
    'The counterparty for stock-take variances and authorised '
        'corrections.',
  LocationKind.inTransit =>
    'Goods dispatched but not yet received at the other end, and returns '
        'waiting to be inspected.',
};
