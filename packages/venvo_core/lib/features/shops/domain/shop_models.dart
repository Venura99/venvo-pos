import '../../../core/enums/app_enums.dart';
import '../../../core/utils/money.dart';
import 'package:json_annotation/json_annotation.dart';

part 'shop_models.g.dart';

/// A shop with the figures the list screen shows.
@JsonSerializable()
class ShopListItem {
  const ShopListItem({
    required this.id,
    required this.code,
    required this.name,
    required this.openingBalance,
    required this.status,
    required this.stockUnits,
    required this.stockValueAtCost,
    required this.billedTotal,
    required this.settledTotal,
    required this.pendingChequeTotal,
    required this.retailSalesTotal,
    this.ownerName,
    this.phone,
    this.address,
    this.assignedAgentId,
    this.assignedAgentName,
    this.creditLimit,
    this.notes,
    this.locationId,
  });

  final int id;
  final String code;
  final String name;
  final String? ownerName;
  final String? phone;
  final String? address;

  /// The agent currently responsible for this shop. Reassigning changes only
  /// this pointer: every past document keeps the agent it was created with.
  final int? assignedAgentId;
  final String? assignedAgentName;

  final Money openingBalance;

  /// Optional ceiling on what the shop may owe. Null means no limit.
  final Money? creditLimit;

  final EntityStatus status;
  final String? notes;
  final int? locationId;

  final int stockUnits;
  final Money stockValueAtCost;

  /// Wholesale invoices raised on this shop.
  final Money billedTotal;

  /// Settled by cleared payments and posted credit notes only.
  final Money settledTotal;
  final Money pendingChequeTotal;

  /// What the shop has sold to end customers. Recorded separately from the
  /// wholesale supply that stocked it, and never added to it.
  final Money retailSalesTotal;

  bool get isActive => status == EntityStatus.active;
  bool get isArchived => status == EntityStatus.archived;
  bool get hasAgent => assignedAgentId != null;

  Money get outstandingBalance => openingBalance + billedTotal - settledTotal;

  bool get owesMoney => outstandingBalance.isPositive;
  bool get isInCredit => outstandingBalance.isNegative;

  /// True when the shop owes more than its credit limit allows.
  bool get isOverCreditLimit {
    final limit = creditLimit;
    if (limit == null || limit.isZero) return false;
    return outstandingBalance > limit;
  }

  /// How much more the shop may be supplied on credit, or null when there is
  /// no limit set.
  Money? get availableCredit {
    final limit = creditLimit;
    if (limit == null || limit.isZero) return null;
    final remaining = limit - outstandingBalance;
    return remaining.isNegative ? Money.zero : remaining;
  }

  factory ShopListItem.fromJson(Map<String, dynamic> json) =>
      _$ShopListItemFromJson(json);

  Map<String, dynamic> toJson() => _$ShopListItemToJson(this);
}

/// Input for creating or updating a shop.
@JsonSerializable()
class ShopDraft {
  const ShopDraft({
    required this.name,
    this.id,
    this.code,
    this.ownerName,
    this.phone,
    this.address,
    this.assignedAgentId,
    this.openingBalance = Money.zero,
    this.creditLimit,
    this.status = EntityStatus.active,
    this.notes,
  });

  final int? id;

  /// Leave null or empty to have a code allocated automatically.
  final String? code;
  final String name;
  final String? ownerName;
  final String? phone;
  final String? address;
  final int? assignedAgentId;
  final Money openingBalance;
  final Money? creditLimit;
  final EntityStatus status;
  final String? notes;

  bool get isNew => id == null;

  factory ShopDraft.fromJson(Map<String, dynamic> json) =>
      _$ShopDraftFromJson(json);

  Map<String, dynamic> toJson() => _$ShopDraftToJson(this);
}

/// How the shop list is narrowed.
@JsonSerializable()
class ShopFilter {
  const ShopFilter({
    this.search = '',
    this.agentId,
    this.includeInactive = false,
    this.includeArchived = false,
    this.owingOnly = false,
    this.overCreditLimitOnly = false,
    this.unassignedOnly = false,
  });

  final String search;
  final int? agentId;
  final bool includeInactive;
  final bool includeArchived;
  final bool owingOnly;
  final bool overCreditLimitOnly;

  /// Shops with no agent responsible for them, which need attention.
  final bool unassignedOnly;

  bool get hasAnyFilter =>
      search.trim().isNotEmpty ||
      agentId != null ||
      owingOnly ||
      overCreditLimitOnly ||
      unassignedOnly;

  ShopFilter copyWith({
    String? search,
    int? agentId,
    bool clearAgent = false,
    bool? includeInactive,
    bool? includeArchived,
    bool? owingOnly,
    bool? overCreditLimitOnly,
    bool? unassignedOnly,
  }) {
    return ShopFilter(
      search: search ?? this.search,
      agentId: clearAgent ? null : (agentId ?? this.agentId),
      includeInactive: includeInactive ?? this.includeInactive,
      includeArchived: includeArchived ?? this.includeArchived,
      owingOnly: owingOnly ?? this.owingOnly,
      overCreditLimitOnly: overCreditLimitOnly ?? this.overCreditLimitOnly,
      unassignedOnly: unassignedOnly ?? this.unassignedOnly,
    );
  }

  factory ShopFilter.fromJson(Map<String, dynamic> json) =>
      _$ShopFilterFromJson(json);

  Map<String, dynamic> toJson() => _$ShopFilterToJson(this);
}
