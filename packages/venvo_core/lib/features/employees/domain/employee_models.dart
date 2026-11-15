import '../../../core/enums/app_enums.dart';
import '../../../core/utils/money.dart';
import 'package:json_annotation/json_annotation.dart';

part 'employee_models.g.dart';

/// An employee with the money figures the list screen shows.
@JsonSerializable()
class EmployeeListItem {
  const EmployeeListItem({
    required this.id,
    required this.code,
    required this.name,
    required this.basicSalary,
    required this.status,
    required this.outstandingAdvances,
    required this.unpaidSalaryTotal,
    required this.salaryRecordCount,
    this.phone,
    this.address,
    this.designation,
    this.joiningDate,
    this.notes,
  });

  final int id;
  final String code;
  final String name;
  final String? phone;
  final String? address;
  final String? designation;
  final DateTime? joiningDate;
  final Money basicSalary;
  final EntityStatus status;
  final String? notes;

  /// Advances given and not yet recovered from a salary.
  final Money outstandingAdvances;

  /// Approved salaries that have not been fully paid.
  final Money unpaidSalaryTotal;
  final int salaryRecordCount;

  bool get isActive => status == EntityStatus.active;
  bool get isArchived => status == EntityStatus.archived;

  /// True when the employee is owed money or owes the business money, which
  /// is worth flagging before they are archived.
  bool get hasOpenBalances =>
      !outstandingAdvances.isZero || !unpaidSalaryTotal.isZero;

  /// Completed years of service, for display.
  int? yearsOfService(DateTime asOf) {
    final joined = joiningDate;
    if (joined == null) return null;
    final years = asOf.difference(joined).inDays ~/ 365;
    return years < 0 ? 0 : years;
  }

  factory EmployeeListItem.fromJson(Map<String, dynamic> json) =>
      _$EmployeeListItemFromJson(json);

  Map<String, dynamic> toJson() => _$EmployeeListItemToJson(this);
}

/// Input for creating or updating an employee.
@JsonSerializable()
class EmployeeDraft {
  const EmployeeDraft({
    required this.name,
    this.id,
    this.code,
    this.phone,
    this.address,
    this.designation,
    this.joiningDate,
    this.basicSalary = Money.zero,
    this.status = EntityStatus.active,
    this.notes,
  });

  final int? id;

  /// Leave null or empty to have a code allocated automatically.
  final String? code;
  final String name;
  final String? phone;
  final String? address;
  final String? designation;
  final DateTime? joiningDate;
  final Money basicSalary;
  final EntityStatus status;
  final String? notes;

  bool get isNew => id == null;

  factory EmployeeDraft.fromJson(Map<String, dynamic> json) =>
      _$EmployeeDraftFromJson(json);

  Map<String, dynamic> toJson() => _$EmployeeDraftToJson(this);
}

/// How the employee list is narrowed.
@JsonSerializable()
class EmployeeFilter {
  const EmployeeFilter({
    this.search = '',
    this.designation,
    this.includeInactive = false,
    this.includeArchived = false,
  });

  final String search;
  final String? designation;
  final bool includeInactive;
  final bool includeArchived;

  bool get hasAnyFilter => search.trim().isNotEmpty || designation != null;

  EmployeeFilter copyWith({
    String? search,
    String? designation,
    bool clearDesignation = false,
    bool? includeInactive,
    bool? includeArchived,
  }) {
    return EmployeeFilter(
      search: search ?? this.search,
      designation: clearDesignation ? null : (designation ?? this.designation),
      includeInactive: includeInactive ?? this.includeInactive,
      includeArchived: includeArchived ?? this.includeArchived,
    );
  }

  factory EmployeeFilter.fromJson(Map<String, dynamic> json) =>
      _$EmployeeFilterFromJson(json);

  Map<String, dynamic> toJson() => _$EmployeeFilterToJson(this);
}
