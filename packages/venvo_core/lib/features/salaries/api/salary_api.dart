import '../../../core/api/api_client.dart';
import '../../../core/api/api_decode.dart';
import '../../../core/api/revision_bus.dart';
import '../../../core/enums/app_enums.dart';
import '../../../core/errors/failures.dart';
import '../../../core/utils/money.dart';
import '../../authentication/domain/authenticated_user.dart';
import '../domain/salary_models.dart';

/// Payroll writes over HTTP. Mirrors `SalaryService`.
class SalaryApi {
  const SalaryApi(this._client);

  final ApiClient _client;

  /// Payroll touches the accounts and the employee list, where each person's
  /// outstanding advance is shown.
  static const Set<ApiTopic> _topics = {ApiTopic.finance, ApiTopic.employees};

  /// Works out what a salary would come to, without creating it.
  ///
  /// A POST because it sends a draft, but it writes nothing — it is what the
  /// payroll form shows while somebody is still filling it in.
  Future<SalaryComputation> compute(SalaryDraft draft) async {
    final json = await _client.post(
      '/api/v1/salaries/compute',
      body: draft.toJson(),
    );
    return SalaryComputation.fromJson(_object(json, 'computation'));
  }

  Future<int> createSalary(AuthenticatedUser actor, SalaryDraft draft) async {
    final json = await _client.post(
      '/api/v1/salaries',
      body: draft.toJson(),
      bumps: _topics,
    );
    return decodeId(json);
  }

  /// Approves it. The liability is posted now, before any money moves.
  Future<void> approveSalary(
    AuthenticatedUser actor, {
    required int salaryId,
  }) async {
    await _client.post('/api/v1/salaries/$salaryId/approve', bumps: _topics);
  }

  /// Pays it. Omitting [amount] pays whatever is still outstanding.
  Future<int> paySalary(
    AuthenticatedUser actor, {
    required int salaryId,
    Money? amount,
    PaymentMethod method = PaymentMethod.cash,
    DateTime? paymentDate,
    String? referenceNumber,
    String? notes,
  }) async {
    final json = await _client.post(
      '/api/v1/salaries/$salaryId/pay',
      body: {
        if (amount != null) 'amount': amount.toJson(),
        'method': method.name,
        if (paymentDate != null)
          'paymentDate': paymentDate.toUtc().toIso8601String(),
        if (referenceNumber != null) 'referenceNumber': referenceNumber,
        if (notes != null) 'notes': notes,
      },
      bumps: {..._topics, ApiTopic.payments},
    );
    final paymentId = json['paymentId'];
    if (paymentId is int) return paymentId;
    throw StorageFailure(
      'The server sent a reply this version cannot read.',
      details: 'Expected an integer "paymentId".',
    );
  }

  Future<void> cancelSalary(
    AuthenticatedUser actor, {
    required int salaryId,
    required String reason,
  }) async {
    await _client.post(
      '/api/v1/salaries/$salaryId/cancel',
      body: {'reason': reason},
      bumps: {..._topics, ApiTopic.payments},
    );
  }

  /// Advances money against a future salary. It becomes a receivable from the
  /// employee, recovered when payroll is next run for them.
  Future<int> recordAdvance(
    AuthenticatedUser actor, {
    required int employeeId,
    required Money amount,
    PaymentMethod method = PaymentMethod.cash,
    DateTime? advanceDate,
    String? notes,
  }) async {
    final json = await _client.post(
      '/api/v1/advances',
      body: {
        'employeeId': employeeId,
        'amount': amount.toJson(),
        'method': method.name,
        if (advanceDate != null)
          'advanceDate': advanceDate.toUtc().toIso8601String(),
        if (notes != null) 'notes': notes,
      },
      bumps: _topics,
    );
    return decodeId(json);
  }

  Future<Money> outstandingAdvances(int employeeId) async {
    final json = await _client.get(
      '/api/v1/employees/$employeeId/outstanding-advances',
    );
    return _money(json, 'outstanding');
  }
}

/// Payroll reads over HTTP. Mirrors `SalaryQueryRepository`.
class SalaryQueryApi {
  const SalaryQueryApi(this._client);

  final ApiClient _client;

  Stream<List<SalarySummary>> watchSalaries(SalaryFilter filter) =>
      _client.watch({ApiTopic.finance}, () async {
        final json = await _client.get(
          '/api/v1/salaries',
          query: _query(filter),
        );
        return decodeList(json, 'salaries', SalarySummary.fromJson);
      });

  Future<SalaryDetail> salaryDetail(int salaryId) async {
    final json = await _client.get('/api/v1/salaries/$salaryId');
    return SalaryDetail.fromJson(_object(json, 'salary'));
  }

  Future<SalaryTotals> totals(SalaryFilter filter) async {
    final json = await _client.get(
      '/api/v1/salaries/totals',
      query: _query(filter),
    );
    return SalaryTotals.fromJson(_object(json, 'totals'));
  }

  Stream<List<EmployeeAdvanceRow>> watchAdvances({
    int? employeeId,
    bool outstandingOnly = true,
  }) => _client.watch({ApiTopic.finance, ApiTopic.employees}, () async {
    final json = await _client.get(
      '/api/v1/advances',
      query: {'employeeId': employeeId, 'outstandingOnly': outstandingOnly},
    );
    return decodeList(json, 'advances', EmployeeAdvanceRow.fromJson);
  });

  /// The months payroll has been run for, for a period picker.
  Future<List<({int year, int month, int count})>> periods() async {
    final json = await _client.get('/api/v1/salaries/periods');
    final raw = json['periods'];
    if (raw is! List) {
      throw StorageFailure(
        'The server sent a reply this version cannot read.',
        details: 'Expected a list under "periods".',
      );
    }
    return [
      for (final entry in raw.cast<Map<String, Object?>>())
        (
          year: entry['year']! as int,
          month: entry['month']! as int,
          count: entry['count']! as int,
        ),
    ];
  }

  static Map<String, Object?> _query(SalaryFilter filter) => {
    if (filter.search.trim().isNotEmpty) 'search': filter.search.trim(),
    'employeeId': filter.employeeId,
    'periodYear': filter.periodYear,
    'periodMonth': filter.periodMonth,
    'status': filter.status?.name,
    'unpaidOnly': filter.unpaidOnly,
    'limit': filter.limit,
  };
}

Map<String, dynamic> _object(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is Map<String, dynamic>) return value;
  throw StorageFailure(
    'The server sent a reply this version cannot read.',
    details: 'Expected an object under "$key", got ${value.runtimeType}.',
  );
}

Money _money(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) return Money(value);
  throw StorageFailure(
    'The server sent a reply this version cannot read.',
    details: 'Expected integer minor units under "$key".',
  );
}
