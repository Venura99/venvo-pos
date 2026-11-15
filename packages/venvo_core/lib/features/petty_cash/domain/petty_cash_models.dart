import '../../../core/enums/app_enums.dart';
import '../../../core/utils/money.dart';
import 'package:json_annotation/json_annotation.dart';

part 'petty_cash_models.g.dart';

/// A petty cash movement being recorded.
@JsonSerializable()
class PettyCashDraft {
  const PettyCashDraft({
    required this.kind,
    required this.amount,
    required this.description,
    this.entryDate,
    this.referenceNumber,
    this.handledByEmployeeId,
    this.adjustmentAddsToFloat = false,
  });

  final PettyCashEntryKind kind;

  /// Always positive. [kind] decides which way the float moves.
  final Money amount;

  final String description;
  final DateTime? entryDate;
  final String? referenceNumber;
  final int? handledByEmployeeId;

  /// Only read when [kind] is an adjustment, where the direction is the whole
  /// point: cash counted over adds to the float, cash counted short takes
  /// from it. Every other kind has a fixed direction.
  final bool adjustmentAddsToFloat;

  /// Which way this entry moves the float.
  bool get addsToFloat => kind == PettyCashEntryKind.adjustment
      ? adjustmentAddsToFloat
      : pettyCashKindAddsToFloat(kind);

  factory PettyCashDraft.fromJson(Map<String, dynamic> json) =>
      _$PettyCashDraftFromJson(json);

  Map<String, dynamic> toJson() => _$PettyCashDraftToJson(this);
}

/// One row of the petty cash book.
@JsonSerializable()
class PettyCashRow {
  const PettyCashRow({
    required this.id,
    required this.voucherNumber,
    required this.entryDate,
    required this.kind,
    required this.amount,
    required this.signedAmount,
    required this.balanceAfter,
    required this.description,
    required this.createdBy,
    this.referenceNumber,
    this.expenseId,
    this.expenseVoucherNumber,
    this.handledByEmployeeName,
  });

  final int id;
  final String voucherNumber;
  final DateTime entryDate;
  final PettyCashEntryKind kind;
  final Money amount;

  /// Effect on the float: negative where cash left it.
  final Money signedAmount;

  /// The float immediately after this entry, as it was recorded at the time.
  final Money balanceAfter;

  final String description;
  final String createdBy;
  final String? referenceNumber;

  /// Set when this entry is the cash side of an expense.
  final int? expenseId;
  final String? expenseVoucherNumber;

  final String? handledByEmployeeName;

  bool get isInflow => signedAmount.isPositive;
  bool get isExpense => kind == PettyCashEntryKind.expense;

  factory PettyCashRow.fromJson(Map<String, dynamic> json) =>
      _$PettyCashRowFromJson(json);

  Map<String, dynamic> toJson() => _$PettyCashRowToJson(this);
}

/// The state of the float, with the day's movement.
@JsonSerializable()
class PettyCashSnapshot {
  const PettyCashSnapshot({
    required this.balance,
    required this.entryCount,
    required this.receivedInPeriod,
    required this.spentInPeriod,
    this.lastEntryAt,
  });

  static const PettyCashSnapshot empty = PettyCashSnapshot(
    balance: Money.zero,
    entryCount: 0,
    receivedInPeriod: Money.zero,
    spentInPeriod: Money.zero,
  );

  /// The float as it stands now, whatever period is being viewed.
  final Money balance;

  final int entryCount;
  final Money receivedInPeriod;

  /// Cash that left the float, as a positive figure.
  final Money spentInPeriod;

  final DateTime? lastEntryAt;

  Money get netInPeriod => receivedInPeriod - spentInPeriod;

  bool get isEmpty => balance.isZero && entryCount == 0;

  factory PettyCashSnapshot.fromJson(Map<String, dynamic> json) =>
      _$PettyCashSnapshotFromJson(json);

  Map<String, dynamic> toJson() => _$PettyCashSnapshotToJson(this);
}

/// How the petty cash book is narrowed.
@JsonSerializable()
class PettyCashFilter {
  const PettyCashFilter({
    this.search = '',
    this.kind,
    this.from,
    this.to,
    this.limit = 300,
  });

  final String search;
  final PettyCashEntryKind? kind;
  final DateTime? from;
  final DateTime? to;
  final int limit;

  bool get hasAnyFilter =>
      search.trim().isNotEmpty || kind != null || from != null || to != null;

  PettyCashFilter copyWith({
    String? search,
    PettyCashEntryKind? kind,
    bool clearKind = false,
    DateTime? from,
    bool clearFrom = false,
    DateTime? to,
    bool clearTo = false,
    int? limit,
  }) {
    return PettyCashFilter(
      search: search ?? this.search,
      kind: clearKind ? null : (kind ?? this.kind),
      from: clearFrom ? null : (from ?? this.from),
      to: clearTo ? null : (to ?? this.to),
      limit: limit ?? this.limit,
    );
  }

  factory PettyCashFilter.fromJson(Map<String, dynamic> json) =>
      _$PettyCashFilterFromJson(json);

  Map<String, dynamic> toJson() => _$PettyCashFilterToJson(this);
}

String pettyCashKindLabel(PettyCashEntryKind kind) => switch (kind) {
  PettyCashEntryKind.opening => 'Opening float',
  PettyCashEntryKind.cashReceived => 'Cash into float',
  PettyCashEntryKind.cashIssued => 'Cash out of float',
  PettyCashEntryKind.expense => 'Expense paid',
  PettyCashEntryKind.adjustment => 'Adjustment',
};

/// Which way each fixed kind moves the float. Kept in one place so the sign
/// can never be decided differently in two places.
///
/// An adjustment is not here on purpose: its direction comes from the entry
/// itself, through [PettyCashDraft.addsToFloat].
bool pettyCashKindAddsToFloat(PettyCashEntryKind kind) => switch (kind) {
  PettyCashEntryKind.opening || PettyCashEntryKind.cashReceived => true,
  PettyCashEntryKind.cashIssued || PettyCashEntryKind.expense => false,
  PettyCashEntryKind.adjustment => throw ArgumentError(
    'An adjustment carries its own direction; read '
    'PettyCashDraft.addsToFloat instead.',
  ),
};
