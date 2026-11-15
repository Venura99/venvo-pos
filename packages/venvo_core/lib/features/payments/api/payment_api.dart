import '../../../core/api/api_client.dart';
import '../../../core/api/api_decode.dart';
import '../../../core/api/revision_bus.dart';
import '../../../core/errors/failures.dart';
import '../../../core/utils/money.dart';
import '../../authentication/domain/authenticated_user.dart';
import '../data/payment_query_repository.dart';
import '../domain/payment_models.dart';

/// Collections, allocations and the cheque lifecycle over HTTP.
/// Mirrors `PaymentService`.
class PaymentApi {
  const PaymentApi(this._client);

  final ApiClient _client;

  /// Every topic a settlement touches. A collection changes the invoice
  /// register, the party balances and the accounts at once.
  static const Set<ApiTopic> _settlementTopics = {
    ApiTopic.payments,
    ApiTopic.invoices,
    ApiTopic.finance,
    ApiTopic.agents,
    ApiTopic.shops,
  };

  Future<PaymentResult> recordPayment(
    AuthenticatedUser actor,
    PaymentRequest request,
  ) async {
    final json = await _client.post(
      '/api/v1/payments',
      body: request.toJson(),
      bumps: _settlementTopics,
    );
    return PaymentResult.fromJson(_object(json, 'payment'));
  }

  Future<void> allocate(
    AuthenticatedUser actor, {
    required int paymentId,
    required List<PaymentAllocationRequest> allocations,
  }) async {
    await _client.post(
      '/api/v1/payments/$paymentId/allocations',
      body: {
        'allocations': [for (final a in allocations) a.toJson()],
      },
      bumps: _settlementTopics,
    );
  }

  /// Withdraws an allocation. Omitting [amount] releases all of it.
  Future<void> releaseAllocation(
    AuthenticatedUser actor, {
    required int paymentId,
    required int invoiceId,
    Money? amount,
    String? reason,
  }) async {
    await _client.post(
      '/api/v1/payments/$paymentId/allocations/$invoiceId/release',
      body: {
        if (amount != null) 'amount': amount.toJson(),
        if (reason != null) 'reason': reason,
      },
      bumps: _settlementTopics,
    );
  }

  Future<Money> releaseAllocationsForInvoice({
    required AuthenticatedUser actor,
    required int invoiceId,
    required String reason,
  }) async {
    final json = await _client.post(
      '/api/v1/invoices/$invoiceId/allocations/release',
      body: {'reason': reason},
      bumps: _settlementTopics,
    );
    return _money(json, 'released');
  }

  Future<void> cancelPayment(
    AuthenticatedUser actor, {
    required int paymentId,
    required String reason,
  }) async {
    await _client.post(
      '/api/v1/payments/$paymentId/cancel',
      body: {'reason': reason},
      bumps: _settlementTopics,
    );
  }

  // ---- cheques -----------------------------------------------------------

  Future<void> depositCheque(
    AuthenticatedUser actor, {
    required int chequeId,
    DateTime? depositedOn,
  }) async {
    await _client.post(
      '/api/v1/cheques/$chequeId/deposit',
      body: {
        if (depositedOn != null)
          'depositedOn': depositedOn.toUtc().toIso8601String(),
      },
      bumps: _settlementTopics,
    );
  }

  /// The money has arrived. This is the point the journal entry is posted —
  /// not when the cheque was taken in.
  Future<void> clearCheque(
    AuthenticatedUser actor, {
    required int chequeId,
    DateTime? clearedOn,
  }) async {
    await _client.post(
      '/api/v1/cheques/$chequeId/clear',
      body: {
        if (clearedOn != null) 'clearedOn': clearedOn.toUtc().toIso8601String(),
      },
      bumps: _settlementTopics,
    );
  }

  Future<void> bounceCheque(
    AuthenticatedUser actor, {
    required int chequeId,
    required String reason,
    Money bounceCharge = Money.zero,
    DateTime? bouncedOn,
  }) async {
    await _client.post(
      '/api/v1/cheques/$chequeId/bounce',
      body: {
        'reason': reason,
        'bounceCharge': bounceCharge.toJson(),
        if (bouncedOn != null) 'bouncedOn': bouncedOn.toUtc().toIso8601String(),
      },
      bumps: _settlementTopics,
    );
  }

  Future<void> linkReplacementPayment(
    AuthenticatedUser actor, {
    required int chequeId,
    required int replacementPaymentId,
  }) async {
    await _client.post(
      '/api/v1/cheques/$chequeId/replacement',
      body: {'replacementPaymentId': replacementPaymentId},
      bumps: _settlementTopics,
    );
  }

  // ---- settlement position ----------------------------------------------

  /// What is still owed on an invoice, counting **cleared money only**.
  Future<Money> outstandingOf(int invoiceId) async =>
      _money(await _settlement(invoiceId), 'outstanding');

  /// What may still be *applied* to an invoice, counting pending payments as
  /// well — a cheque banked but not yet cleared.
  ///
  /// Smaller than [outstandingOf] once a cheque is in flight, and that gap is
  /// the point: allocating against the outstanding figure while a payment is
  /// pending would apply the same debt twice.
  Future<Money> allocatableRemaining(int invoiceId) async =>
      _money(await _settlement(invoiceId), 'allocatableRemaining');

  Future<Map<String, Object?>> _settlement(int invoiceId) =>
      _client.get('/api/v1/invoices/$invoiceId/settlement');

  Future<List<AllocatableInvoice>> allocatableInvoices({
    int? agentId,
    int? shopId,
  }) async {
    final json = await _client.get(
      '/api/v1/payments/allocatable',
      query: {'agentId': agentId, 'shopId': shopId},
    );
    return decodeList(json, 'invoices', AllocatableInvoice.fromJson);
  }

  /// Money received that has not been applied to any invoice.
  Future<Money> advanceBalance({int? agentId, int? shopId}) async {
    final json = await _client.get(
      '/api/v1/payments/advance-balance',
      query: {'agentId': agentId, 'shopId': shopId},
    );
    return _money(json, 'advance');
  }
}

/// Payment reads over HTTP. Mirrors `PaymentQueryRepository`.
class PaymentQueryApi {
  const PaymentQueryApi(this._client);

  final ApiClient _client;

  Stream<List<PaymentSummary>> watchPayments(PaymentFilter filter) =>
      _client.watch({ApiTopic.payments, ApiTopic.invoices}, () async {
        final json = await _client.get(
          '/api/v1/payments',
          query: _paymentQuery(filter),
        );
        return decodeList(json, 'payments', PaymentSummary.fromJson);
      });

  Stream<List<ChequeSummary>> watchCheques(ChequeFilter filter) =>
      _client.watch({ApiTopic.payments}, () async {
        final json = await _client.get(
          '/api/v1/cheques',
          query: _chequeQuery(filter),
        );
        return decodeList(json, 'cheques', ChequeSummary.fromJson);
      });

  Future<PaymentTotalsSnapshot> paymentTotals(PaymentFilter filter) async {
    final json = await _client.get(
      '/api/v1/payments/totals',
      query: _paymentQuery(filter),
    );
    return PaymentTotalsSnapshot.fromJson(_object(json, 'totals'));
  }

  Future<ChequeTotalsSnapshot> chequeTotals(ChequeFilter filter) async {
    final json = await _client.get(
      '/api/v1/cheques/totals',
      query: _chequeQuery(filter),
    );
    return ChequeTotalsSnapshot.fromJson(_object(json, 'totals'));
  }

  static Map<String, Object?> _paymentQuery(PaymentFilter filter) => {
    if (filter.search.trim().isNotEmpty) 'search': filter.search.trim(),
    'direction': filter.direction?.name,
    'method': filter.method?.name,
    'status': filter.status?.name,
    'agentId': filter.agentId,
    'shopId': filter.shopId,
    'from': filter.from,
    'to': filter.to,
    'advancesOnly': filter.advancesOnly,
    'limit': filter.limit,
  };

  static Map<String, Object?> _chequeQuery(ChequeFilter filter) => {
    if (filter.search.trim().isNotEmpty) 'search': filter.search.trim(),
    'status': filter.statuses.map((s) => s.name),
    'from': filter.from,
    'to': filter.to,
    'bankableOnly': filter.bankableOnly,
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
    details:
        'Expected integer minor units under "$key", '
        'got ${value.runtimeType}.',
  );
}
