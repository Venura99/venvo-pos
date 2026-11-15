import '../../../core/api/api_client.dart';
import '../../../core/api/api_decode.dart';
import '../../../core/api/revision_bus.dart';
import '../../../core/errors/failures.dart';
import '../domain/report_models.dart';

/// The reports, over HTTP.
///
/// `ReportRepository` runs 18 hand-written SQL queries. None of that moves to
/// the client: a report is asked for by id with a filter, and the rows come
/// back already typed — money as integer minor units, dates as instants — so
/// the table, the PDF and the CSV all format from the same values, which is
/// what they did locally.
class ReportApi {
  const ReportApi(this._client);

  final ApiClient _client;

  /// The reports this user may run.
  ///
  /// Comes from the server rather than the client's own copy of the
  /// catalogue, so the list is filtered by the caller's permissions and a
  /// client cannot show a report it would be refused.
  Future<List<ReportDefinition>> catalogue() async {
    final json = await _client.get('/api/v1/reports');
    return decodeList(json, 'reports', ReportDefinition.fromJson);
  }

  Future<ReportResult> run(
    ReportDefinition definition,
    ReportFilter filter,
  ) async {
    final json = await _client.get(
      '/api/v1/reports/${definition.id}',
      query: {
        'from': filter.from,
        'to': filter.to,
        'agentId': filter.agentId,
        'shopId': filter.shopId,
        'productId': filter.productId,
        'categoryId': filter.categoryId,
        'employeeId': filter.employeeId,
        'locationId': filter.locationId,
        'limit': filter.limit,
      },
    );
    final result = json['result'];
    if (result is! Map<String, dynamic>) {
      throw StorageFailure(
        'The server sent a reply this version cannot read.',
        details: 'Expected an object under "result".',
      );
    }
    return ReportResult.fromJson(result);
  }

  /// Re-runs [definition] whenever anything it could be reporting on changes.
  ///
  /// Deliberately broad: a report draws on several areas at once, and the
  /// cost of re-running one the user is looking at is far smaller than the
  /// cost of showing them a figure that is no longer true.
  Stream<ReportResult> watch(
    ReportDefinition definition,
    ReportFilter filter,
  ) => _client.watch(const {
    ApiTopic.stock,
    ApiTopic.invoices,
    ApiTopic.payments,
    ApiTopic.returns,
    ApiTopic.finance,
  }, () => run(definition, filter));
}
