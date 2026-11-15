// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'employee_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

EmployeeListItem _$EmployeeListItemFromJson(Map<String, dynamic> json) =>
    $checkedCreate('EmployeeListItem', json, ($checkedConvert) {
      final val = EmployeeListItem(
        id: $checkedConvert('id', (v) => (v as num).toInt()),
        code: $checkedConvert('code', (v) => v as String),
        name: $checkedConvert('name', (v) => v as String),
        basicSalary: $checkedConvert(
          'basicSalary',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        status: $checkedConvert(
          'status',
          (v) => $enumDecode(_$EntityStatusEnumMap, v),
        ),
        outstandingAdvances: $checkedConvert(
          'outstandingAdvances',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        unpaidSalaryTotal: $checkedConvert(
          'unpaidSalaryTotal',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        salaryRecordCount: $checkedConvert(
          'salaryRecordCount',
          (v) => (v as num).toInt(),
        ),
        phone: $checkedConvert('phone', (v) => v as String?),
        address: $checkedConvert('address', (v) => v as String?),
        designation: $checkedConvert('designation', (v) => v as String?),
        joiningDate: $checkedConvert(
          'joiningDate',
          (v) => v == null ? null : DateTime.parse(v as String),
        ),
        notes: $checkedConvert('notes', (v) => v as String?),
      );
      return val;
    });

Map<String, dynamic> _$EmployeeListItemToJson(EmployeeListItem instance) =>
    <String, dynamic>{
      'id': instance.id,
      'code': instance.code,
      'name': instance.name,
      'phone': ?instance.phone,
      'address': ?instance.address,
      'designation': ?instance.designation,
      'joiningDate': ?instance.joiningDate?.toIso8601String(),
      'basicSalary': instance.basicSalary.toJson(),
      'status': _$EntityStatusEnumMap[instance.status]!,
      'notes': ?instance.notes,
      'outstandingAdvances': instance.outstandingAdvances.toJson(),
      'unpaidSalaryTotal': instance.unpaidSalaryTotal.toJson(),
      'salaryRecordCount': instance.salaryRecordCount,
    };

const _$EntityStatusEnumMap = {
  EntityStatus.active: 'active',
  EntityStatus.inactive: 'inactive',
  EntityStatus.archived: 'archived',
};

EmployeeDraft _$EmployeeDraftFromJson(Map<String, dynamic> json) =>
    $checkedCreate('EmployeeDraft', json, ($checkedConvert) {
      final val = EmployeeDraft(
        name: $checkedConvert('name', (v) => v as String),
        id: $checkedConvert('id', (v) => (v as num?)?.toInt()),
        code: $checkedConvert('code', (v) => v as String?),
        phone: $checkedConvert('phone', (v) => v as String?),
        address: $checkedConvert('address', (v) => v as String?),
        designation: $checkedConvert('designation', (v) => v as String?),
        joiningDate: $checkedConvert(
          'joiningDate',
          (v) => v == null ? null : DateTime.parse(v as String),
        ),
        basicSalary: $checkedConvert(
          'basicSalary',
          (v) => v == null ? Money.zero : Money.fromJson((v as num).toInt()),
        ),
        status: $checkedConvert(
          'status',
          (v) =>
              $enumDecodeNullable(_$EntityStatusEnumMap, v) ??
              EntityStatus.active,
        ),
        notes: $checkedConvert('notes', (v) => v as String?),
      );
      return val;
    });

Map<String, dynamic> _$EmployeeDraftToJson(EmployeeDraft instance) =>
    <String, dynamic>{
      'id': ?instance.id,
      'code': ?instance.code,
      'name': instance.name,
      'phone': ?instance.phone,
      'address': ?instance.address,
      'designation': ?instance.designation,
      'joiningDate': ?instance.joiningDate?.toIso8601String(),
      'basicSalary': instance.basicSalary.toJson(),
      'status': _$EntityStatusEnumMap[instance.status]!,
      'notes': ?instance.notes,
    };

EmployeeFilter _$EmployeeFilterFromJson(Map<String, dynamic> json) =>
    $checkedCreate('EmployeeFilter', json, ($checkedConvert) {
      final val = EmployeeFilter(
        search: $checkedConvert('search', (v) => v as String? ?? ''),
        designation: $checkedConvert('designation', (v) => v as String?),
        includeInactive: $checkedConvert(
          'includeInactive',
          (v) => v as bool? ?? false,
        ),
        includeArchived: $checkedConvert(
          'includeArchived',
          (v) => v as bool? ?? false,
        ),
      );
      return val;
    });

Map<String, dynamic> _$EmployeeFilterToJson(EmployeeFilter instance) =>
    <String, dynamic>{
      'search': instance.search,
      'designation': ?instance.designation,
      'includeInactive': instance.includeInactive,
      'includeArchived': instance.includeArchived,
    };
