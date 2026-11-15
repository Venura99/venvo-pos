import '../../../core/api/api_client.dart';
import '../../../core/api/api_decode.dart';
import '../../../core/api/revision_bus.dart';
import '../../../core/errors/failures.dart';
import '../../../core/utils/money.dart';
import '../../authentication/domain/authenticated_user.dart';
import '../data/return_query_repository.dart';
import '../domain/return_models.dart';

/// Returns and credit notes over HTTP. Mirrors `ReturnService`.
class ReturnApi {
  const ReturnApi(this._client);

  final ApiClient _client;

  /// Everything a return or a credit note can move. Returns touch stock, the
  /// invoice register (a credit changes what is owed) and the accounts.
  static const Set<ApiTopic> _topics = {
    ApiTopic.returns,
    ApiTopic.stock,
    ApiTopic.invoices,
    ApiTopic.finance,
    ApiTopic.agents,
    ApiTopic.shops,
  };

  Future<ReturnPostResult> postReturn(
    AuthenticatedUser actor,
    ReturnDraft draft,
  ) async {
    final json = await _client.post(
      '/api/v1/returns',
      body: draft.toJson(),
      bumps: _topics,
    );
    return ReturnPostResult.fromJson(_object(json, 'return'));
  }

  Future<InspectionResult> recordInspection(
    AuthenticatedUser actor,
    InspectionRequest request,
  ) async {
    final json = await _client.post(
      '/api/v1/returns/${request.returnId}/inspection',
      body: request.toJson(),
      bumps: _topics,
    );
    return InspectionResult.fromJson(_object(json, 'inspection'));
  }

  Future<void> cancelReturn(
    AuthenticatedUser actor, {
    required int returnId,
    required String reason,
  }) async {
    await _client.post(
      '/api/v1/returns/$returnId/cancel',
      body: {'reason': reason},
      bumps: _topics,
    );
  }

  /// Issues a credit note. Omitting [amount] credits the full creditable
  /// value: the accepted and damaged goods at the price actually charged.
  /// Scrapped goods are worth nothing and are never credited.
  Future<int> issueCreditNote(
    AuthenticatedUser actor, {
    required int returnId,
    Money? amount,
    String? reason,
    String? notes,
    DateTime? issueDate,
  }) async {
    final json = await _client.post(
      '/api/v1/returns/$returnId/credit-note',
      body: {
        if (amount != null) 'amount': amount.toJson(),
        if (reason != null) 'reason': reason,
        if (notes != null) 'notes': notes,
        if (issueDate != null) 'issueDate': issueDate.toUtc().toIso8601String(),
      },
      bumps: _topics,
    );
    return decodeId(json);
  }

  Future<void> applyToInvoice(
    AuthenticatedUser actor, {
    required int creditNoteId,
    required int invoiceId,
    required Money amount,
  }) async {
    await _client.post(
      '/api/v1/credit-notes/$creditNoteId/apply',
      body: {'invoiceId': invoiceId, 'amount': amount.toJson()},
      bumps: _topics,
    );
  }

  Future<void> withdrawApplication(
    AuthenticatedUser actor, {
    required int applicationId,
    required String reason,
  }) async {
    await _client.post(
      '/api/v1/credit-note-applications/$applicationId/withdraw',
      body: {'reason': reason},
      bumps: _topics,
    );
  }

  Future<void> cancelCreditNote(
    AuthenticatedUser actor, {
    required int creditNoteId,
    required String reason,
  }) async {
    await _client.post(
      '/api/v1/credit-notes/$creditNoteId/cancel',
      body: {'reason': reason},
      bumps: _topics,
    );
  }

  /// What is still returnable on an invoice: billed, less what has come back.
  Future<List<ReturnableInvoiceLine>> returnableLines(int invoiceId) async {
    final json = await _client.get(
      '/api/v1/invoices/$invoiceId/returnable-lines',
    );
    return decodeList(json, 'lines', ReturnableInvoiceLine.fromJson);
  }
}

/// Return reads over HTTP. Mirrors `ReturnQueryRepository`.
class ReturnQueryApi {
  const ReturnQueryApi(this._client);

  final ApiClient _client;

  Stream<List<ReturnSummary>> watchReturns(ReturnFilter filter) =>
      _client.watch({ApiTopic.returns, ApiTopic.stock}, () async {
        final json = await _client.get(
          '/api/v1/returns',
          query: _returnQuery(filter),
        );
        return decodeList(json, 'returns', ReturnSummary.fromJson);
      });

  Future<ReturnDetail> returnDetail(int returnId) async {
    final json = await _client.get('/api/v1/returns/$returnId');
    return ReturnDetail.fromJson(_object(json, 'return'));
  }

  Future<ReturnTotals> returnTotals(ReturnFilter filter) async {
    final json = await _client.get(
      '/api/v1/returns/totals',
      query: _returnQuery(filter),
    );
    return ReturnTotals.fromJson(_object(json, 'totals'));
  }

  Stream<List<CreditNoteSummary>> watchCreditNotes(CreditNoteFilter filter) =>
      _client.watch({ApiTopic.returns, ApiTopic.invoices}, () async {
        final json = await _client.get(
          '/api/v1/credit-notes',
          query: _creditQuery(filter),
        );
        return decodeList(json, 'creditNotes', CreditNoteSummary.fromJson);
      });

  Future<CreditNoteDetail> creditNoteDetail(int creditNoteId) async {
    final json = await _client.get('/api/v1/credit-notes/$creditNoteId');
    return CreditNoteDetail.fromJson(_object(json, 'creditNote'));
  }

  /// Credit a party holds and has not used.
  Future<Money> availableCredit({int? agentId, int? shopId}) async {
    final json = await _client.get(
      '/api/v1/credit-notes/available',
      query: {'agentId': agentId, 'shopId': shopId},
    );
    final available = json['available'];
    if (available is int) return Money(available);
    throw StorageFailure(
      'The server sent a reply this version cannot read.',
      details: 'Expected integer minor units, got ${available.runtimeType}.',
    );
  }

  static Map<String, Object?> _returnQuery(ReturnFilter filter) => {
    if (filter.search.trim().isNotEmpty) 'search': filter.search.trim(),
    'route': filter.routes.map((r) => r.name),
    'status': filter.status?.name,
    'reason': filter.reason?.name,
    'agentId': filter.agentId,
    'shopId': filter.shopId,
    'pendingInspectionOnly': filter.pendingInspectionOnly,
    'from': filter.from,
    'to': filter.to,
    'limit': filter.limit,
  };

  static Map<String, Object?> _creditQuery(CreditNoteFilter filter) => {
    if (filter.search.trim().isNotEmpty) 'search': filter.search.trim(),
    'status': filter.status?.name,
    'agentId': filter.agentId,
    'shopId': filter.shopId,
    'withRemainingOnly': filter.withRemainingOnly,
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
