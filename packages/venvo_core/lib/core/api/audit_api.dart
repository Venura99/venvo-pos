import '../database/app_database.dart';
import '../enums/app_enums.dart';
import 'api_client.dart';
import 'api_decode.dart';
import 'revision_bus.dart';

/// The audit trail, over HTTP.
///
/// Read-only, and there is no write method here or endpoint behind one. Audit
/// entries are written as a side effect of the operations being recorded; a
/// trail a client can add to, edit or delete is not a trail. The one way to
/// put something in it is to do the thing it records.
class AuditApi {
  const AuditApi(this._client);

  final ApiClient _client;

  Future<List<AuditLog>> entries({
    AuditAction? action,
    String search = '',
    int limit = 200,
  }) async {
    final json = await _client.get(
      '/api/v1/audit',
      query: {
        'action': action?.name,
        if (search.trim().isNotEmpty) 'search': search.trim(),
        'limit': limit,
      },
    );
    return decodeList(json, 'entries', AuditLog.fromJson);
  }

  /// Re-reads the trail when anything that writes to it happens.
  Stream<List<AuditLog>> watch({
    AuditAction? action,
    String search = '',
    int limit = 200,
  }) => _client.watch(const {
    ApiTopic.stock,
    ApiTopic.invoices,
    ApiTopic.payments,
    ApiTopic.returns,
    ApiTopic.finance,
    ApiTopic.users,
    ApiTopic.products,
    ApiTopic.agents,
    ApiTopic.shops,
    ApiTopic.employees,
    ApiTopic.settings,
  }, () => entries(action: action, search: search, limit: limit));
}
