import '../../../core/api/api_client.dart';
import '../../../core/api/api_decode.dart';
import '../../../core/api/revision_bus.dart';
import '../../../core/errors/failures.dart';
import '../../../core/utils/money.dart';
import '../domain/finance_models.dart';

/// Reads over the financial journal. Mirrors the read half of
/// `FinancialLedgerService`.
///
/// There is no write half here on purpose. Journal entries are posted as a
/// consequence of the operation that caused them — an invoice, a cleared
/// cheque, a stock movement — and a client able to write into the journal
/// directly would be a way to put the accounts out of step with the business.
class FinanceApi {
  const FinanceApi(this._client);

  final ApiClient _client;

  Future<TrialBalance> trialBalance({DateTime? from, DateTime? to}) async {
    final json = await _client.get(
      '/api/v1/finance/trial-balance',
      query: {'from': from, 'to': to},
    );
    return TrialBalance.fromJson(_object(json, 'trialBalance'));
  }

  /// Batches whose debits and credits disagree. Should always be empty.
  Future<List<UnbalancedBatch>> findUnbalancedBatches() async {
    final json = await _client.get('/api/v1/finance/unbalanced-batches');
    return decodeList(json, 'batches', UnbalancedBatch.fromJson);
  }

  Future<Money> balanceOf(
    String accountCode, {
    DateTime? from,
    DateTime? to,
  }) async {
    final json = await _client.get(
      '/api/v1/finance/balance',
      query: {'account': accountCode, 'from': from, 'to': to},
    );
    final balance = json['balance'];
    if (balance is int) return Money(balance);
    throw StorageFailure(
      'The server sent a reply this version cannot read.',
      details: 'Expected integer minor units, got ${balance.runtimeType}.',
    );
  }

  Future<ProfitAndLoss> profitAndLoss({DateTime? from, DateTime? to}) async {
    final json = await _client.get(
      '/api/v1/finance/profit-and-loss',
      query: {'from': from, 'to': to},
    );
    return ProfitAndLoss.fromJson(_object(json, 'profitAndLoss'));
  }

  /// Journal entries, newest first.
  Stream<List<JournalRow>> watchEntries(FinancialLedgerFilter filter) =>
      _client.watch(
        {
          ApiTopic.finance,
          ApiTopic.invoices,
          ApiTopic.payments,
          ApiTopic.stock,
          ApiTopic.returns,
        },
        () async {
          final json = await _client.get(
            '/api/v1/finance/entries',
            query: {
              if (filter.search.trim().isNotEmpty)
                'search': filter.search.trim(),
              'account': filter.accountCode,
              'sourceKind': filter.sourceKind?.name,
              'from': filter.from,
              'to': filter.to,
              'limit': filter.limit,
            },
          );
          return decodeList(json, 'entries', JournalRow.fromJson);
        },
      );

  /// Re-reads the trial balance whenever anything that posts to the journal
  /// changes.
  Stream<TrialBalance> watchTrialBalance({DateTime? from, DateTime? to}) =>
      _client.watch({
        ApiTopic.finance,
        ApiTopic.invoices,
        ApiTopic.payments,
        ApiTopic.stock,
      }, () => trialBalance(from: from, to: to));
}

Map<String, dynamic> _object(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is Map<String, dynamic>) return value;
  throw StorageFailure(
    'The server sent a reply this version cannot read.',
    details: 'Expected an object under "$key", got ${value.runtimeType}.',
  );
}
