// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'salary_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SalaryDraft _$SalaryDraftFromJson(Map<String, dynamic> json) =>
    $checkedCreate('SalaryDraft', json, ($checkedConvert) {
      final val = SalaryDraft(
        employeeId: $checkedConvert('employeeId', (v) => (v as num).toInt()),
        periodYear: $checkedConvert('periodYear', (v) => (v as num).toInt()),
        periodMonth: $checkedConvert('periodMonth', (v) => (v as num).toInt()),
        basicSalary: $checkedConvert(
          'basicSalary',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        allowances: $checkedConvert(
          'allowances',
          (v) => v == null ? Money.zero : Money.fromJson((v as num).toInt()),
        ),
        bonus: $checkedConvert(
          'bonus',
          (v) => v == null ? Money.zero : Money.fromJson((v as num).toInt()),
        ),
        deductions: $checkedConvert(
          'deductions',
          (v) => v == null ? Money.zero : Money.fromJson((v as num).toInt()),
        ),
        recoverAdvances: $checkedConvert(
          'recoverAdvances',
          (v) => v as bool? ?? true,
        ),
        advanceRecoveryCap: $checkedConvert(
          'advanceRecoveryCap',
          (v) => v == null ? null : Money.fromJson((v as num).toInt()),
        ),
        notes: $checkedConvert('notes', (v) => v as String?),
      );
      return val;
    });

Map<String, dynamic> _$SalaryDraftToJson(SalaryDraft instance) =>
    <String, dynamic>{
      'employeeId': instance.employeeId,
      'periodYear': instance.periodYear,
      'periodMonth': instance.periodMonth,
      'basicSalary': instance.basicSalary.toJson(),
      'allowances': instance.allowances.toJson(),
      'bonus': instance.bonus.toJson(),
      'deductions': instance.deductions.toJson(),
      'recoverAdvances': instance.recoverAdvances,
      'advanceRecoveryCap': ?instance.advanceRecoveryCap?.toJson(),
      'notes': ?instance.notes,
    };

SalaryComputation _$SalaryComputationFromJson(Map<String, dynamic> json) =>
    $checkedCreate('SalaryComputation', json, ($checkedConvert) {
      final val = SalaryComputation(
        earned: $checkedConvert(
          'earned',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        outstandingAdvances: $checkedConvert(
          'outstandingAdvances',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        advanceRecovered: $checkedConvert(
          'advanceRecovered',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        net: $checkedConvert('net', (v) => Money.fromJson((v as num).toInt())),
      );
      return val;
    });

Map<String, dynamic> _$SalaryComputationToJson(SalaryComputation instance) =>
    <String, dynamic>{
      'earned': instance.earned.toJson(),
      'outstandingAdvances': instance.outstandingAdvances.toJson(),
      'advanceRecovered': instance.advanceRecovered.toJson(),
      'net': instance.net.toJson(),
    };

SalarySummary _$SalarySummaryFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('SalarySummary', json, ($checkedConvert) {
  final val = SalarySummary(
    id: $checkedConvert('id', (v) => (v as num).toInt()),
    voucherNumber: $checkedConvert('voucherNumber', (v) => v as String),
    employeeId: $checkedConvert('employeeId', (v) => (v as num).toInt()),
    employeeName: $checkedConvert('employeeName', (v) => v as String),
    employeeCode: $checkedConvert('employeeCode', (v) => v as String),
    periodYear: $checkedConvert('periodYear', (v) => (v as num).toInt()),
    periodMonth: $checkedConvert('periodMonth', (v) => (v as num).toInt()),
    basicSalary: $checkedConvert(
      'basicSalary',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    allowances: $checkedConvert(
      'allowances',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    bonus: $checkedConvert('bonus', (v) => Money.fromJson((v as num).toInt())),
    deductions: $checkedConvert(
      'deductions',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    advanceDeducted: $checkedConvert(
      'advanceDeducted',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    netSalary: $checkedConvert(
      'netSalary',
      (v) => Money.fromJson((v as num).toInt()),
    ),
    paid: $checkedConvert('paid', (v) => Money.fromJson((v as num).toInt())),
    status: $checkedConvert(
      'status',
      (v) => $enumDecode(_$SalaryStatusEnumMap, v),
    ),
    createdBy: $checkedConvert('createdBy', (v) => v as String),
    designation: $checkedConvert('designation', (v) => v as String?),
    approvedBy: $checkedConvert('approvedBy', (v) => v as String?),
    notes: $checkedConvert('notes', (v) => v as String?),
  );
  return val;
});

Map<String, dynamic> _$SalarySummaryToJson(SalarySummary instance) =>
    <String, dynamic>{
      'id': instance.id,
      'voucherNumber': instance.voucherNumber,
      'employeeId': instance.employeeId,
      'employeeName': instance.employeeName,
      'employeeCode': instance.employeeCode,
      'periodYear': instance.periodYear,
      'periodMonth': instance.periodMonth,
      'basicSalary': instance.basicSalary.toJson(),
      'allowances': instance.allowances.toJson(),
      'bonus': instance.bonus.toJson(),
      'deductions': instance.deductions.toJson(),
      'advanceDeducted': instance.advanceDeducted.toJson(),
      'netSalary': instance.netSalary.toJson(),
      'paid': instance.paid.toJson(),
      'status': _$SalaryStatusEnumMap[instance.status]!,
      'createdBy': instance.createdBy,
      'designation': ?instance.designation,
      'approvedBy': ?instance.approvedBy,
      'notes': ?instance.notes,
    };

const _$SalaryStatusEnumMap = {
  SalaryStatus.draft: 'draft',
  SalaryStatus.approved: 'approved',
  SalaryStatus.partiallyPaid: 'partiallyPaid',
  SalaryStatus.paid: 'paid',
  SalaryStatus.cancelled: 'cancelled',
};

SalaryPaymentRow _$SalaryPaymentRowFromJson(Map<String, dynamic> json) =>
    $checkedCreate('SalaryPaymentRow', json, ($checkedConvert) {
      final val = SalaryPaymentRow(
        id: $checkedConvert('id', (v) => (v as num).toInt()),
        paymentDate: $checkedConvert(
          'paymentDate',
          (v) => DateTime.parse(v as String),
        ),
        amount: $checkedConvert(
          'amount',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        method: $checkedConvert(
          'method',
          (v) => $enumDecode(_$PaymentMethodEnumMap, v),
        ),
        createdBy: $checkedConvert('createdBy', (v) => v as String),
        referenceNumber: $checkedConvert(
          'referenceNumber',
          (v) => v as String?,
        ),
        notes: $checkedConvert('notes', (v) => v as String?),
      );
      return val;
    });

Map<String, dynamic> _$SalaryPaymentRowToJson(SalaryPaymentRow instance) =>
    <String, dynamic>{
      'id': instance.id,
      'paymentDate': instance.paymentDate.toIso8601String(),
      'amount': instance.amount.toJson(),
      'method': _$PaymentMethodEnumMap[instance.method]!,
      'createdBy': instance.createdBy,
      'referenceNumber': ?instance.referenceNumber,
      'notes': ?instance.notes,
    };

const _$PaymentMethodEnumMap = {
  PaymentMethod.cash: 'cash',
  PaymentMethod.bankTransfer: 'bankTransfer',
  PaymentMethod.cheque: 'cheque',
  PaymentMethod.cardOrDigital: 'cardOrDigital',
  PaymentMethod.creditNote: 'creditNote',
  PaymentMethod.openingBalance: 'openingBalance',
};

SalaryDetail _$SalaryDetailFromJson(Map<String, dynamic> json) =>
    $checkedCreate('SalaryDetail', json, ($checkedConvert) {
      final val = SalaryDetail(
        summary: $checkedConvert(
          'summary',
          (v) => SalarySummary.fromJson(v as Map<String, dynamic>),
        ),
        payments: $checkedConvert(
          'payments',
          (v) => (v as List<dynamic>)
              .map((e) => SalaryPaymentRow.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
        outstandingAdvances: $checkedConvert(
          'outstandingAdvances',
          (v) => Money.fromJson((v as num).toInt()),
        ),
      );
      return val;
    });

Map<String, dynamic> _$SalaryDetailToJson(SalaryDetail instance) =>
    <String, dynamic>{
      'summary': instance.summary.toJson(),
      'payments': instance.payments.map((e) => e.toJson()).toList(),
      'outstandingAdvances': instance.outstandingAdvances.toJson(),
    };

EmployeeAdvanceRow _$EmployeeAdvanceRowFromJson(Map<String, dynamic> json) =>
    $checkedCreate('EmployeeAdvanceRow', json, ($checkedConvert) {
      final val = EmployeeAdvanceRow(
        id: $checkedConvert('id', (v) => (v as num).toInt()),
        employeeId: $checkedConvert('employeeId', (v) => (v as num).toInt()),
        employeeName: $checkedConvert('employeeName', (v) => v as String),
        advanceDate: $checkedConvert(
          'advanceDate',
          (v) => DateTime.parse(v as String),
        ),
        amount: $checkedConvert(
          'amount',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        recovered: $checkedConvert(
          'recovered',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        method: $checkedConvert(
          'method',
          (v) => $enumDecode(_$PaymentMethodEnumMap, v),
        ),
        createdBy: $checkedConvert('createdBy', (v) => v as String),
        notes: $checkedConvert('notes', (v) => v as String?),
      );
      return val;
    });

Map<String, dynamic> _$EmployeeAdvanceRowToJson(EmployeeAdvanceRow instance) =>
    <String, dynamic>{
      'id': instance.id,
      'employeeId': instance.employeeId,
      'employeeName': instance.employeeName,
      'advanceDate': instance.advanceDate.toIso8601String(),
      'amount': instance.amount.toJson(),
      'recovered': instance.recovered.toJson(),
      'method': _$PaymentMethodEnumMap[instance.method]!,
      'createdBy': instance.createdBy,
      'notes': ?instance.notes,
    };

SalaryTotals _$SalaryTotalsFromJson(Map<String, dynamic> json) =>
    $checkedCreate('SalaryTotals', json, ($checkedConvert) {
      final val = SalaryTotals(
        count: $checkedConvert('count', (v) => (v as num).toInt()),
        earned: $checkedConvert(
          'earned',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        advanceRecovered: $checkedConvert(
          'advanceRecovered',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        net: $checkedConvert('net', (v) => Money.fromJson((v as num).toInt())),
        paid: $checkedConvert(
          'paid',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        outstanding: $checkedConvert(
          'outstanding',
          (v) => Money.fromJson((v as num).toInt()),
        ),
        draftCount: $checkedConvert('draftCount', (v) => (v as num).toInt()),
      );
      return val;
    });

Map<String, dynamic> _$SalaryTotalsToJson(SalaryTotals instance) =>
    <String, dynamic>{
      'count': instance.count,
      'earned': instance.earned.toJson(),
      'advanceRecovered': instance.advanceRecovered.toJson(),
      'net': instance.net.toJson(),
      'paid': instance.paid.toJson(),
      'outstanding': instance.outstanding.toJson(),
      'draftCount': instance.draftCount,
    };

SalaryFilter _$SalaryFilterFromJson(Map<String, dynamic> json) =>
    $checkedCreate('SalaryFilter', json, ($checkedConvert) {
      final val = SalaryFilter(
        search: $checkedConvert('search', (v) => v as String? ?? ''),
        employeeId: $checkedConvert('employeeId', (v) => (v as num?)?.toInt()),
        periodYear: $checkedConvert('periodYear', (v) => (v as num?)?.toInt()),
        periodMonth: $checkedConvert(
          'periodMonth',
          (v) => (v as num?)?.toInt(),
        ),
        status: $checkedConvert(
          'status',
          (v) => $enumDecodeNullable(_$SalaryStatusEnumMap, v),
        ),
        unpaidOnly: $checkedConvert('unpaidOnly', (v) => v as bool? ?? false),
        limit: $checkedConvert('limit', (v) => (v as num?)?.toInt() ?? 300),
      );
      return val;
    });

Map<String, dynamic> _$SalaryFilterToJson(SalaryFilter instance) =>
    <String, dynamic>{
      'search': instance.search,
      'employeeId': ?instance.employeeId,
      'periodYear': ?instance.periodYear,
      'periodMonth': ?instance.periodMonth,
      'status': ?_$SalaryStatusEnumMap[instance.status],
      'unpaidOnly': instance.unpaidOnly,
      'limit': instance.limit,
    };
