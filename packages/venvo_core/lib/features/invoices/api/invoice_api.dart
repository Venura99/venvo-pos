import '../../../core/api/api_client.dart';
import '../../../core/api/api_decode.dart';
import '../../../core/api/revision_bus.dart';
import '../../../core/enums/app_enums.dart';
import '../../../core/errors/failures.dart';
import '../../../core/utils/money.dart';
import '../../authentication/domain/authenticated_user.dart';
import '../data/invoice_query_repository.dart';
import '../data/invoice_service.dart';
import '../domain/invoice_models.dart';

/// Billing writes over HTTP. Mirrors `InvoiceService`.
class InvoiceApi {
  const InvoiceApi(this._client);

  final ApiClient _client;

  /// The invoice, its lines, the receivable, the journal entry and — where
  /// the request says so — the stock movement are all posted on the server in
  /// one transaction. Either all of it happened or none of it did; there is no
  /// state in which goods have left and nothing is owed.
  Future<InvoicePostResult> postInvoice(
    AuthenticatedUser actor,
    InvoiceRequest request,
  ) async {
    final json = await _client.post(
      '/api/v1/invoices',
      body: request.toJson(),
      bumps: {
        ApiTopic.invoices,
        ApiTopic.stock,
        ApiTopic.payments,
        ApiTopic.finance,
        // Balances on the agent and shop lists move with a new receivable.
        ApiTopic.agents,
        ApiTopic.shops,
      },
    );
    return InvoicePostResult.fromJson(_object(json, 'invoice'));
  }

  Future<InvoicePostResult> billDelivery(
    AuthenticatedUser actor, {
    required int stockTransactionId,
    DateTime? invoiceDate,
    DateTime? dueDate,
    DiscountType invoiceDiscountType = DiscountType.none,
    int invoiceDiscountValue = 0,
    String? discountReason,
    String? notes,
    ImmediatePayment? payment,
    Map<int, Money>? priceOverrides,
  }) async {
    final json = await _client.post(
      '/api/v1/invoices/from-delivery',
      body: {
        'stockTransactionId': stockTransactionId,
        if (invoiceDate != null)
          'invoiceDate': invoiceDate.toUtc().toIso8601String(),
        if (dueDate != null) 'dueDate': dueDate.toUtc().toIso8601String(),
        'invoiceDiscountType': invoiceDiscountType.name,
        'invoiceDiscountValue': invoiceDiscountValue,
        if (discountReason != null && discountReason.trim().isNotEmpty)
          'discountReason': discountReason.trim(),
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        if (payment != null) 'payment': payment.toJson(),
        // JSON object keys are text; the server parses them back to ids.
        if (priceOverrides != null)
          'priceOverrides': {
            for (final entry in priceOverrides.entries)
              '${entry.key}': entry.value.toJson(),
          },
      },
      bumps: {
        ApiTopic.invoices,
        ApiTopic.payments,
        ApiTopic.finance,
        ApiTopic.agents,
        ApiTopic.shops,
      },
    );
    return InvoicePostResult.fromJson(_object(json, 'invoice'));
  }

  /// Cancels an invoice.
  ///
  /// [reverseStockMovement] decides whether the goods come back and defaults
  /// to false, matching `InvoiceService`. Cancelling a bill is not
  /// un-shipping, and reversing a delivery that already happened would invent
  /// stock the warehouse does not have.
  Future<InvoiceCancelResult> cancelInvoice(
    AuthenticatedUser actor, {
    required int invoiceId,
    required String reason,
    bool reverseStockMovement = false,
  }) async {
    final json = await _client.post(
      '/api/v1/invoices/$invoiceId/cancel',
      body: {'reason': reason, 'reverseStockMovement': reverseStockMovement},
      bumps: {
        ApiTopic.invoices,
        ApiTopic.stock,
        ApiTopic.payments,
        ApiTopic.finance,
        ApiTopic.agents,
        ApiTopic.shops,
      },
    );
    return InvoiceCancelResult.fromJson(_object(json, 'cancellation'));
  }
}

/// Billing reads over HTTP. Mirrors `InvoiceQueryRepository`.
class InvoiceQueryApi {
  const InvoiceQueryApi(this._client);

  final ApiClient _client;

  /// Payments are watched too: an invoice's settlement status changes when a
  /// collection is applied to it, with nothing about the invoice itself
  /// having changed.
  Stream<List<InvoiceSummary>> watchInvoices(InvoiceFilter filter) =>
      _client.watch({ApiTopic.invoices, ApiTopic.payments}, () async {
        final json = await _client.get(
          '/api/v1/invoices',
          query: _query(filter),
        );
        return decodeList(json, 'invoices', InvoiceSummary.fromJson);
      });

  Future<InvoiceDetail> invoiceDetail(int invoiceId) async {
    final json = await _client.get('/api/v1/invoices/$invoiceId');
    return InvoiceDetail.fromJson(_object(json, 'invoice'));
  }

  /// Goods delivered but not yet billed.
  Stream<List<UnbilledDelivery>> watchUnbilledDeliveries() =>
      _client.watch({ApiTopic.invoices, ApiTopic.stock}, () async {
        final json = await _client.get('/api/v1/invoices/unbilled-deliveries');
        return decodeList(json, 'deliveries', UnbilledDelivery.fromJson);
      });

  Future<InvoiceTotalsSnapshot> totals(InvoiceFilter filter) async {
    final json = await _client.get(
      '/api/v1/invoices/totals',
      query: _query(filter),
    );
    return InvoiceTotalsSnapshot.fromJson(_object(json, 'totals'));
  }

  static Map<String, Object?> _query(InvoiceFilter filter) => {
    if (filter.search.trim().isNotEmpty) 'search': filter.search.trim(),
    'kind': filter.kinds.map((k) => k.name),
    'status': filter.status?.name,
    'settlement': filter.settlement?.name,
    'agentId': filter.agentId,
    'shopId': filter.shopId,
    'from': filter.from,
    'to': filter.to,
    'unpaidOnly': filter.unpaidOnly,
    'overdueOnly': filter.overdueOnly,
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
