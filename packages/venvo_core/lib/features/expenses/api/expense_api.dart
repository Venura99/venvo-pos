import '../../../core/api/api_client.dart';
import '../../../core/api/api_decode.dart';
import '../../../core/api/revision_bus.dart';
import '../../../core/errors/failures.dart';
import '../../../core/utils/money.dart';
import '../../authentication/domain/authenticated_user.dart';
import '../domain/expense_models.dart';

/// Expense writes over HTTP. Mirrors `ExpenseService`.
class ExpenseApi {
  const ExpenseApi(this._client);

  final ApiClient _client;

  Future<int> postExpense(AuthenticatedUser actor, ExpenseDraft draft) async {
    final json = await _client.post(
      '/api/v1/expenses',
      body: draft.toJson(),
      // An expense paid from the float moves petty cash in the same
      // transaction, so both views are stale either way.
      bumps: {ApiTopic.finance},
    );
    return decodeId(json);
  }

  Future<void> cancelExpense(
    AuthenticatedUser actor, {
    required int expenseId,
    required String reason,
  }) async {
    await _client.post(
      '/api/v1/expenses/$expenseId/cancel',
      body: {'reason': reason},
      bumps: {ApiTopic.finance},
    );
  }

  Future<int> createCategory(
    AuthenticatedUser actor, {
    required String name,
    String? code,
  }) async {
    final json = await _client.post(
      '/api/v1/expense-categories',
      body: {'name': name, if (code != null) 'code': code},
      bumps: {ApiTopic.finance},
    );
    return decodeId(json);
  }

  Future<void> archiveCategory(
    AuthenticatedUser actor, {
    required int categoryId,
  }) async {
    await _client.post(
      '/api/v1/expense-categories/$categoryId/archive',
      bumps: {ApiTopic.finance},
    );
  }
}

/// Expense reads over HTTP. Mirrors `ExpenseQueryRepository`.
class ExpenseQueryApi {
  const ExpenseQueryApi(this._client);

  final ApiClient _client;

  Stream<List<ExpenseSummary>> watchExpenses(ExpenseFilter filter) =>
      _client.watch({ApiTopic.finance}, () async {
        final json = await _client.get(
          '/api/v1/expenses',
          query: _query(filter),
        );
        return decodeList(json, 'expenses', ExpenseSummary.fromJson);
      });

  Future<ExpenseTotals> totals(ExpenseFilter filter) async {
    final json = await _client.get(
      '/api/v1/expenses/totals',
      query: _query(filter),
    );
    return ExpenseTotals.fromJson(_object(json, 'totals'));
  }

  Stream<List<ExpenseCategorySummary>> watchCategories({
    bool includeArchived = false,
  }) => _client.watch({ApiTopic.finance}, () async {
    final json = await _client.get(
      '/api/v1/expense-categories',
      query: {'includeArchived': includeArchived},
    );
    return decodeList(json, 'categories', ExpenseCategorySummary.fromJson);
  });

  /// Spend per day, for the trend on the expenses screen.
  Future<List<({DateTime day, Money total, int count})>> dailyTotals({
    DateTime? from,
    DateTime? to,
  }) async {
    final json = await _client.get(
      '/api/v1/expenses/daily-totals',
      query: {'from': from, 'to': to},
    );
    final raw = json['days'];
    if (raw is! List) {
      throw StorageFailure(
        'The server sent a reply this version cannot read.',
        details: 'Expected a list under "days".',
      );
    }
    return [
      for (final entry in raw.cast<Map<String, Object?>>())
        (
          day: DateTime.parse(entry['day']! as String),
          total: Money(entry['total']! as int),
          count: entry['count']! as int,
        ),
    ];
  }

  static Map<String, Object?> _query(ExpenseFilter filter) => {
    if (filter.search.trim().isNotEmpty) 'search': filter.search.trim(),
    'categoryId': filter.categoryId,
    'paymentMethod': filter.paymentMethod?.name,
    'status': filter.status?.name,
    'pettyCashOnly': filter.pettyCashOnly,
    'from': filter.from,
    'to': filter.to,
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
