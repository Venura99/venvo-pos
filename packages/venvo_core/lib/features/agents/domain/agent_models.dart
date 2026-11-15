import '../../../core/enums/app_enums.dart';
import '../../../core/utils/money.dart';
import 'package:json_annotation/json_annotation.dart';

part 'agent_models.g.dart';

/// An agent with the figures the list screen shows: how many shops they
/// serve, what stock they are holding and what they owe.
@JsonSerializable()
class AgentListItem {
  const AgentListItem({
    required this.id,
    required this.code,
    required this.name,
    required this.openingBalance,
    required this.status,
    required this.activeShopCount,
    required this.stockUnits,
    required this.stockValueAtCost,
    required this.billedTotal,
    required this.settledTotal,
    required this.pendingChequeTotal,
    this.phone,
    this.address,
    this.nic,
    this.commissionBps,
    this.notes,
    this.locationId,
  });

  final int id;
  final String code;
  final String name;
  final String? phone;
  final String? address;
  final String? nic;

  /// Commission rate in basis points; null when the agent has none.
  final int? commissionBps;

  /// Receivable carried in from before the system went live.
  final Money openingBalance;
  final EntityStatus status;
  final String? notes;

  /// The agent's own stock location.
  final int? locationId;

  final int activeShopCount;
  final int stockUnits;
  final Money stockValueAtCost;

  /// Total of posted invoices raised on this agent.
  final Money billedTotal;

  /// Settled by *cleared* payments and applied credit notes only.
  final Money settledTotal;

  /// Received as cheques that have not cleared. Not settlement.
  final Money pendingChequeTotal;

  bool get isActive => status == EntityStatus.active;
  bool get isArchived => status == EntityStatus.archived;

  /// What the agent owes: the opening balance plus what has been billed, less
  /// what cleared money and credit notes have settled.
  Money get outstandingBalance => openingBalance + billedTotal - settledTotal;

  bool get owesMoney => outstandingBalance.isPositive;

  /// True when the agent has paid more than they were billed, which is an
  /// advance rather than an error.
  bool get isInCredit => outstandingBalance.isNegative;

  factory AgentListItem.fromJson(Map<String, dynamic> json) =>
      _$AgentListItemFromJson(json);

  Map<String, dynamic> toJson() => _$AgentListItemToJson(this);
}

/// Input for creating or updating an agent.
@JsonSerializable()
class AgentDraft {
  const AgentDraft({
    required this.name,
    this.id,
    this.code,
    this.phone,
    this.address,
    this.nic,
    this.commissionBps,
    this.openingBalance = Money.zero,
    this.status = EntityStatus.active,
    this.notes,
  });

  final int? id;

  /// Leave null or empty to have a code allocated automatically.
  final String? code;
  final String name;
  final String? phone;
  final String? address;
  final String? nic;
  final int? commissionBps;
  final Money openingBalance;
  final EntityStatus status;
  final String? notes;

  bool get isNew => id == null;

  factory AgentDraft.fromJson(Map<String, dynamic> json) =>
      _$AgentDraftFromJson(json);

  Map<String, dynamic> toJson() => _$AgentDraftToJson(this);
}

/// How the agent list is narrowed.
@JsonSerializable()
class AgentFilter {
  const AgentFilter({
    this.search = '',
    this.includeInactive = false,
    this.includeArchived = false,
    this.owingOnly = false,
  });

  final String search;
  final bool includeInactive;
  final bool includeArchived;

  /// Only agents with an outstanding balance.
  final bool owingOnly;

  bool get hasAnyFilter => search.trim().isNotEmpty || owingOnly;

  AgentFilter copyWith({
    String? search,
    bool? includeInactive,
    bool? includeArchived,
    bool? owingOnly,
  }) {
    return AgentFilter(
      search: search ?? this.search,
      includeInactive: includeInactive ?? this.includeInactive,
      includeArchived: includeArchived ?? this.includeArchived,
      owingOnly: owingOnly ?? this.owingOnly,
    );
  }

  factory AgentFilter.fromJson(Map<String, dynamic> json) =>
      _$AgentFilterFromJson(json);

  Map<String, dynamic> toJson() => _$AgentFilterToJson(this);
}
