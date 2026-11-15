import '../../../core/utils/money.dart';
import 'package:json_annotation/json_annotation.dart';

part 'report_models.g.dart';

/// What a column holds, which decides how it is formatted on screen, in a PDF
/// and in a CSV - once, in one place, rather than three times.
enum ReportValueKind { text, money, integer, date, month, percent }

/// One cell of a report.
///
/// Values are kept typed rather than pre-formatted because the three outputs
/// want them differently: a table right-aligns money, a PDF prints it with a
/// thousands separator, and a CSV has to hand a spreadsheet something it will
/// read back as a number.
// Built through the private constructor: the public ones are each a single
// named kind, and the generated code lives in this file's `part`, so it can
// reach `_` while nothing outside can.
@JsonSerializable(constructor: '_')
class ReportValue {
  const ReportValue._({
    required this.kind,
    this.text,
    this.money,
    this.number,
    this.date,
    this.bps,
  });

  const ReportValue.text(String value)
    : this._(kind: ReportValueKind.text, text: value);

  const ReportValue.money(Money value)
    : this._(kind: ReportValueKind.money, money: value);

  const ReportValue.integer(int value)
    : this._(kind: ReportValueKind.integer, number: value);

  const ReportValue.date(DateTime value)
    : this._(kind: ReportValueKind.date, date: value);

  /// A whole month, printed as "November 2026".
  const ReportValue.month(DateTime value)
    : this._(kind: ReportValueKind.month, date: value);

  /// A percentage in basis points, so 12.5% stays exact.
  const ReportValue.percent(int value)
    : this._(kind: ReportValueKind.percent, bps: value);

  static const ReportValue empty = ReportValue._(kind: ReportValueKind.text);

  final ReportValueKind kind;
  final String? text;
  final Money? money;
  final int? number;
  final DateTime? date;
  final int? bps;

  bool get isEmpty =>
      text == null &&
      money == null &&
      number == null &&
      date == null &&
      bps == null;

  bool get isNumeric =>
      kind == ReportValueKind.money ||
      kind == ReportValueKind.integer ||
      kind == ReportValueKind.percent;

  /// True when the figure should be shown in the "this is bad" colour.
  bool get isNegative =>
      (money?.isNegative ?? false) || (number != null && number! < 0);

  factory ReportValue.fromJson(Map<String, dynamic> json) =>
      _$ReportValueFromJson(json);

  Map<String, dynamic> toJson() => _$ReportValueToJson(this);
}

/// One column of a report.
@JsonSerializable()
class ReportColumn {
  const ReportColumn({
    required this.label,
    required this.kind,
    this.width,
    this.flex = 1,
    this.totalled = false,
  });

  /// A money column that is summed in the totals row.
  const ReportColumn.money(
    this.label, {
    this.width = 130,
    this.flex = 1,
    this.totalled = true,
  }) : kind = ReportValueKind.money;

  /// A whole-number column that is summed in the totals row.
  const ReportColumn.integer(
    this.label, {
    this.width = 100,
    this.flex = 1,
    this.totalled = true,
  }) : kind = ReportValueKind.integer;

  const ReportColumn.text(this.label, {this.width, this.flex = 1})
    : kind = ReportValueKind.text,
      totalled = false;

  final String label;
  final ReportValueKind kind;
  final double? width;
  final int flex;

  /// Whether the totals row adds this column up. A quantity or an amount is
  /// worth totalling; an average cost or a margin is not, because the sum of
  /// percentages means nothing.
  final bool totalled;

  bool get isNumeric =>
      kind == ReportValueKind.money ||
      kind == ReportValueKind.integer ||
      kind == ReportValueKind.percent;

  factory ReportColumn.fromJson(Map<String, dynamic> json) =>
      _$ReportColumnFromJson(json);

  Map<String, dynamic> toJson() => _$ReportColumnToJson(this);
}

/// One row of a report.
@JsonSerializable()
class ReportRow {
  const ReportRow(this.values, {this.emphasise = false, this.id});

  final List<ReportValue> values;

  /// A subtotal or a group line, shown in bold.
  final bool emphasise;

  /// The record behind the row, where there is one, so a report can be a way
  /// into the detail rather than a dead end.
  final int? id;

  factory ReportRow.fromJson(Map<String, dynamic> json) =>
      _$ReportRowFromJson(json);

  Map<String, dynamic> toJson() => _$ReportRowToJson(this);
}

/// A caveat printed under a report.
///
/// Reports carry their own definitions with them: a collections figure that
/// counts only cleared money has to say so on the page, or somebody will read
/// it as "money received" and be wrong.
@JsonSerializable()
class ReportNote {
  const ReportNote(this.text);

  final String text;

  factory ReportNote.fromJson(Map<String, dynamic> json) =>
      _$ReportNoteFromJson(json);

  Map<String, dynamic> toJson() => _$ReportNoteToJson(this);
}

/// A report, run.
@JsonSerializable()
class ReportResult {
  const ReportResult({
    required this.title,
    required this.columns,
    required this.rows,
    required this.generatedAt,
    required this.filter,
    this.totals,
    this.notes = const [],
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<ReportColumn> columns;
  final List<ReportRow> rows;

  /// The totals row, where the report has one.
  final List<ReportValue>? totals;

  final List<ReportNote> notes;
  final DateTime generatedAt;
  final ReportFilter filter;

  bool get isEmpty => rows.isEmpty;

  /// Sums every column marked [ReportColumn.totalled], for a report that has
  /// not computed its own totals row.
  static List<ReportValue> sumColumns(
    List<ReportColumn> columns,
    List<ReportRow> rows,
  ) {
    return [
      for (var index = 0; index < columns.length; index++)
        if (!columns[index].totalled)
          ReportValue.empty
        else if (columns[index].kind == ReportValueKind.money)
          ReportValue.money(
            rows
                .where((row) => !row.emphasise)
                .map(
                  (row) => index < row.values.length
                      ? (row.values[index].money ?? Money.zero)
                      : Money.zero,
                )
                .sum,
          )
        else
          ReportValue.integer(
            rows
                .where((row) => !row.emphasise)
                .fold(
                  0,
                  (total, row) =>
                      total +
                      (index < row.values.length
                          ? (row.values[index].number ?? 0)
                          : 0),
                ),
          ),
    ];
  }

  factory ReportResult.fromJson(Map<String, dynamic> json) =>
      _$ReportResultFromJson(json);

  Map<String, dynamic> toJson() => _$ReportResultToJson(this);
}

/// Which report, and over what.
///
/// One filter type for all eighteen: each report reads the fields it cares
/// about and ignores the rest, so the screen can keep the period while the
/// user moves between reports.
@JsonSerializable()
class ReportFilter {
  const ReportFilter({
    this.from,
    this.to,
    this.agentId,
    this.shopId,
    this.productId,
    this.categoryId,
    this.employeeId,
    this.locationId,
    this.limit = 2000,
  });

  final DateTime? from;
  final DateTime? to;
  final int? agentId;
  final int? shopId;
  final int? productId;
  final int? categoryId;
  final int? employeeId;
  final int? locationId;

  /// A guard rather than a feature: a report over a decade of data should not
  /// try to render a hundred thousand rows.
  final int limit;

  bool get hasPeriod => from != null || to != null;

  bool get hasAnyFilter =>
      hasPeriod ||
      agentId != null ||
      shopId != null ||
      productId != null ||
      categoryId != null ||
      employeeId != null ||
      locationId != null;

  ReportFilter copyWith({
    DateTime? from,
    bool clearFrom = false,
    DateTime? to,
    bool clearTo = false,
    int? agentId,
    bool clearAgent = false,
    int? shopId,
    bool clearShop = false,
    int? productId,
    bool clearProduct = false,
    int? categoryId,
    bool clearCategory = false,
    int? employeeId,
    bool clearEmployee = false,
    int? locationId,
    bool clearLocation = false,
    int? limit,
  }) {
    return ReportFilter(
      from: clearFrom ? null : (from ?? this.from),
      to: clearTo ? null : (to ?? this.to),
      agentId: clearAgent ? null : (agentId ?? this.agentId),
      shopId: clearShop ? null : (shopId ?? this.shopId),
      productId: clearProduct ? null : (productId ?? this.productId),
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      employeeId: clearEmployee ? null : (employeeId ?? this.employeeId),
      locationId: clearLocation ? null : (locationId ?? this.locationId),
      limit: limit ?? this.limit,
    );
  }

  factory ReportFilter.fromJson(Map<String, dynamic> json) =>
      _$ReportFilterFromJson(json);

  Map<String, dynamic> toJson() => _$ReportFilterToJson(this);
}

/// Which filters a report offers, so the screen shows the ones that apply and
/// hides the ones that would do nothing.
enum ReportFilterField {
  period,
  agent,
  shop,
  product,
  category,
  employee,
  location,
}

/// The groups the report list is organised into.
enum ReportGroup { sales, stock, money, finance }

/// One of the eighteen reports.
@JsonSerializable()
class ReportDefinition {
  const ReportDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.group,
    required this.permission,
    this.filters = const {ReportFilterField.period},
  });

  /// Stable identifier, used as the export filename and to remember which
  /// report was last open.
  final String id;

  final String title;
  final String description;
  final ReportGroup group;

  /// What a user needs in order to see it. A report is a view over data that
  /// is already permission-controlled, so this mirrors the module it reads.
  final String permission;

  final Set<ReportFilterField> filters;

  bool offers(ReportFilterField field) => filters.contains(field);

  factory ReportDefinition.fromJson(Map<String, dynamic> json) =>
      _$ReportDefinitionFromJson(json);

  Map<String, dynamic> toJson() => _$ReportDefinitionToJson(this);
}

String reportGroupLabel(ReportGroup group) => switch (group) {
  ReportGroup.sales => 'Sales',
  ReportGroup.stock => 'Stock',
  ReportGroup.money => 'Money',
  ReportGroup.finance => 'Finance',
};
