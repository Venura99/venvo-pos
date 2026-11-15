import '../../../core/enums/app_enums.dart';
import '../../../core/utils/money.dart';
import 'package:json_annotation/json_annotation.dart';

part 'salary_models.g.dart';

/// A salary being computed for one employee and one month.
@JsonSerializable()
class SalaryDraft {
  const SalaryDraft({
    required this.employeeId,
    required this.periodYear,
    required this.periodMonth,
    required this.basicSalary,
    this.allowances = Money.zero,
    this.bonus = Money.zero,
    this.deductions = Money.zero,
    this.recoverAdvances = true,
    this.advanceRecoveryCap,
    this.notes,
  });

  final int employeeId;
  final int periodYear;
  final int periodMonth;

  final Money basicSalary;
  final Money allowances;
  final Money bonus;

  /// Anything withheld that is not an advance recovery: unpaid leave, a fine,
  /// a statutory deduction.
  final Money deductions;

  /// Whether outstanding advances are taken out of this salary.
  final bool recoverAdvances;

  /// Caps the advance recovery, for letting an employee pay one back over
  /// several months instead of all at once. Null recovers as much as the
  /// salary can stand.
  final Money? advanceRecoveryCap;

  final String? notes;

  /// Pay before any advance is recovered.
  Money get earned => basicSalary + allowances + bonus - deductions;

  factory SalaryDraft.fromJson(Map<String, dynamic> json) =>
      _$SalaryDraftFromJson(json);

  Map<String, dynamic> toJson() => _$SalaryDraftToJson(this);
}

/// What a salary would come to, before anything is written.
///
/// The form shows this as the figures are typed, and the service computes it
/// the same way when it posts, so what was previewed is what gets recorded.
@JsonSerializable()
class SalaryComputation {
  const SalaryComputation({
    required this.earned,
    required this.outstandingAdvances,
    required this.advanceRecovered,
    required this.net,
  });

  final Money earned;

  /// Advances the employee owed before this salary.
  final Money outstandingAdvances;

  /// How much of that is being taken out of this one.
  final Money advanceRecovered;

  /// `earned - advanceRecovered`.
  final Money net;

  Money get advancesRemaining => outstandingAdvances - advanceRecovered;

  bool get recoversAnything => advanceRecovered.isPositive;

  /// True when the advance is larger than the pay, so only part of it can be
  /// recovered this month.
  bool get isPartialRecovery =>
      outstandingAdvances.isPositive && advancesRemaining.isPositive;

  factory SalaryComputation.fromJson(Map<String, dynamic> json) =>
      _$SalaryComputationFromJson(json);

  Map<String, dynamic> toJson() => _$SalaryComputationToJson(this);
}

/// A salary as the register lists it.
@JsonSerializable()
class SalarySummary {
  const SalarySummary({
    required this.id,
    required this.voucherNumber,
    required this.employeeId,
    required this.employeeName,
    required this.employeeCode,
    required this.periodYear,
    required this.periodMonth,
    required this.basicSalary,
    required this.allowances,
    required this.bonus,
    required this.deductions,
    required this.advanceDeducted,
    required this.netSalary,
    required this.paid,
    required this.status,
    required this.createdBy,
    this.designation,
    this.approvedBy,
    this.notes,
  });

  final int id;
  final String voucherNumber;
  final int employeeId;
  final String employeeName;
  final String employeeCode;
  final int periodYear;
  final int periodMonth;

  final Money basicSalary;
  final Money allowances;
  final Money bonus;
  final Money deductions;
  final Money advanceDeducted;
  final Money netSalary;

  /// Paid so far, which may be less than [netSalary].
  final Money paid;

  final SalaryStatus status;
  final String createdBy;
  final String? designation;
  final String? approvedBy;
  final String? notes;

  Money get earned => basicSalary + allowances + bonus - deductions;

  Money get outstanding {
    final left = netSalary - paid;
    return left.isPositive ? left : Money.zero;
  }

  bool get isDraft => status == SalaryStatus.draft;
  bool get isCancelled => status == SalaryStatus.cancelled;
  bool get isApproved =>
      status == SalaryStatus.approved ||
      status == SalaryStatus.partiallyPaid ||
      status == SalaryStatus.paid;
  bool get isFullyPaid => status == SalaryStatus.paid;

  bool get canBePaid => isApproved && outstanding.isPositive;

  /// A salary can be withdrawn while nothing has been handed over.
  bool get canBeCancelled => !isCancelled && paid.isZero;

  String get periodLabel => '${_monthName(periodMonth)} $periodYear';

  factory SalarySummary.fromJson(Map<String, dynamic> json) =>
      _$SalarySummaryFromJson(json);

  Map<String, dynamic> toJson() => _$SalarySummaryToJson(this);
}

/// One payment against a salary.
@JsonSerializable()
class SalaryPaymentRow {
  const SalaryPaymentRow({
    required this.id,
    required this.paymentDate,
    required this.amount,
    required this.method,
    required this.createdBy,
    this.referenceNumber,
    this.notes,
  });

  final int id;
  final DateTime paymentDate;
  final Money amount;
  final PaymentMethod method;
  final String createdBy;
  final String? referenceNumber;
  final String? notes;

  factory SalaryPaymentRow.fromJson(Map<String, dynamic> json) =>
      _$SalaryPaymentRowFromJson(json);

  Map<String, dynamic> toJson() => _$SalaryPaymentRowToJson(this);
}

/// A salary with its payments, for viewing or printing a slip.
@JsonSerializable()
class SalaryDetail {
  const SalaryDetail({
    required this.summary,
    required this.payments,
    required this.outstandingAdvances,
  });

  final SalarySummary summary;
  final List<SalaryPaymentRow> payments;

  /// What the employee still owes in advances after this salary.
  final Money outstandingAdvances;

  factory SalaryDetail.fromJson(Map<String, dynamic> json) =>
      _$SalaryDetailFromJson(json);

  Map<String, dynamic> toJson() => _$SalaryDetailToJson(this);
}

/// An advance given to an employee.
@JsonSerializable()
class EmployeeAdvanceRow {
  const EmployeeAdvanceRow({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.advanceDate,
    required this.amount,
    required this.recovered,
    required this.method,
    required this.createdBy,
    this.notes,
  });

  final int id;
  final int employeeId;
  final String employeeName;
  final DateTime advanceDate;
  final Money amount;

  /// Taken back out of salaries so far.
  final Money recovered;

  final PaymentMethod method;
  final String createdBy;
  final String? notes;

  Money get outstanding {
    final left = amount - recovered;
    return left.isPositive ? left : Money.zero;
  }

  bool get isSettled => outstanding.isZero;

  factory EmployeeAdvanceRow.fromJson(Map<String, dynamic> json) =>
      _$EmployeeAdvanceRowFromJson(json);

  Map<String, dynamic> toJson() => _$EmployeeAdvanceRowToJson(this);
}

/// Headline figures over the salary register.
@JsonSerializable()
class SalaryTotals {
  const SalaryTotals({
    required this.count,
    required this.earned,
    required this.advanceRecovered,
    required this.net,
    required this.paid,
    required this.outstanding,
    required this.draftCount,
  });

  static const SalaryTotals empty = SalaryTotals(
    count: 0,
    earned: Money.zero,
    advanceRecovered: Money.zero,
    net: Money.zero,
    paid: Money.zero,
    outstanding: Money.zero,
    draftCount: 0,
  );

  final int count;
  final Money earned;
  final Money advanceRecovered;
  final Money net;
  final Money paid;
  final Money outstanding;

  /// Salaries computed but not yet approved, which are not a liability yet.
  final int draftCount;

  factory SalaryTotals.fromJson(Map<String, dynamic> json) =>
      _$SalaryTotalsFromJson(json);

  Map<String, dynamic> toJson() => _$SalaryTotalsToJson(this);
}

/// How the salary register is narrowed.
@JsonSerializable()
class SalaryFilter {
  const SalaryFilter({
    this.search = '',
    this.employeeId,
    this.periodYear,
    this.periodMonth,
    this.status,
    this.unpaidOnly = false,
    this.limit = 300,
  });

  final String search;
  final int? employeeId;
  final int? periodYear;
  final int? periodMonth;
  final SalaryStatus? status;
  final bool unpaidOnly;
  final int limit;

  bool get hasAnyFilter =>
      search.trim().isNotEmpty ||
      employeeId != null ||
      periodYear != null ||
      periodMonth != null ||
      status != null ||
      unpaidOnly;

  SalaryFilter copyWith({
    String? search,
    int? employeeId,
    bool clearEmployee = false,
    int? periodYear,
    bool clearYear = false,
    int? periodMonth,
    bool clearMonth = false,
    SalaryStatus? status,
    bool clearStatus = false,
    bool? unpaidOnly,
    int? limit,
  }) {
    return SalaryFilter(
      search: search ?? this.search,
      employeeId: clearEmployee ? null : (employeeId ?? this.employeeId),
      periodYear: clearYear ? null : (periodYear ?? this.periodYear),
      periodMonth: clearMonth ? null : (periodMonth ?? this.periodMonth),
      status: clearStatus ? null : (status ?? this.status),
      unpaidOnly: unpaidOnly ?? this.unpaidOnly,
      limit: limit ?? this.limit,
    );
  }

  factory SalaryFilter.fromJson(Map<String, dynamic> json) =>
      _$SalaryFilterFromJson(json);

  Map<String, dynamic> toJson() => _$SalaryFilterToJson(this);
}

String salaryStatusLabel(SalaryStatus status) => switch (status) {
  SalaryStatus.draft => 'Draft',
  SalaryStatus.approved => 'Approved',
  SalaryStatus.partiallyPaid => 'Part paid',
  SalaryStatus.paid => 'Paid',
  SalaryStatus.cancelled => 'Cancelled',
};

String _monthName(int month) => switch (month) {
  1 => 'January',
  2 => 'February',
  3 => 'March',
  4 => 'April',
  5 => 'May',
  6 => 'June',
  7 => 'July',
  8 => 'August',
  9 => 'September',
  10 => 'October',
  11 => 'November',
  12 => 'December',
  _ => 'Month $month',
};

String salaryMonthName(int month) => _monthName(month);
