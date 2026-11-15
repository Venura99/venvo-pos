import '../../../core/api/api_client.dart';
import '../../../core/api/revision_bus.dart';
import '../../../core/errors/failures.dart';
import '../domain/dashboard_snapshot.dart';

/// The dashboard, over HTTP. Mirrors `DashboardRepository`.
///
/// Every figure in the snapshot is computed from the ledgers when the request
/// arrives. None is a stored total somebody has to remember to update, which
/// is why the dashboard cannot drift away from the transactions underneath it.
class DashboardApi {
  const DashboardApi(this._client);

  final ApiClient _client;

  Future<DashboardSnapshot> load() async {
    final json = await _client.get('/api/v1/dashboard');
    final snapshot = json['dashboard'];
    if (snapshot is! Map<String, dynamic>) {
      throw StorageFailure(
        'The server sent a reply this version cannot read.',
        details: 'Expected an object under "dashboard".',
      );
    }
    return DashboardSnapshot.fromJson(snapshot);
  }

  /// Reloads whenever anything the dashboard counts changes.
  Stream<DashboardSnapshot> watch() => _client.watch(const {
    ApiTopic.stock,
    ApiTopic.invoices,
    ApiTopic.payments,
    ApiTopic.returns,
    ApiTopic.finance,
  }, load);
}
