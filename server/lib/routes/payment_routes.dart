import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/payments/data/payment_query_repository.dart';
import 'package:venvo_core/features/payments/data/payment_service.dart';
import 'package:venvo_core/features/payments/domain/payment_models.dart';

import '../auth/auth_middleware.dart';
import '../http/json_body.dart';
import '../http/path_id.dart';
import '../http/query_params.dart';
import '../http/responses.dart';

/// Collections, allocations and the cheque lifecycle.
///
/// [PaymentService] owns the hard parts and keeps them: a payment is posted
/// with its allocations in one transaction, the journal entry is written only
/// when the money is actually *cleared*, and a bounced cheque reverses what a
/// clearance had posted. All of that stays where it is tested.
Router paymentRoutes({
  required PaymentService payments,
  required PaymentQueryRepository queries,
}) {
  final router = Router();

  PaymentFilter paymentFilterFrom(Request request) {
    final query = QueryParams.of(request);
    return PaymentFilter(
      search: query.string('search'),
      direction: query.has('direction')
          ? query.enumValue(
              'direction',
              PaymentDirection.values,
              fallback: PaymentDirection.values.first,
            )
          : null,
      method: query.has('method')
          ? query.enumValue(
              'method',
              PaymentMethod.values,
              fallback: PaymentMethod.values.first,
            )
          : null,
      status: query.has('status')
          ? query.enumValue(
              'status',
              PaymentStatus.values,
              fallback: PaymentStatus.values.first,
            )
          : null,
      agentId: query.optionalInt('agentId'),
      shopId: query.optionalInt('shopId'),
      from: query.optionalUtcDate('from'),
      to: query.optionalUtcDate('to'),
      advancesOnly: query.boolean('advancesOnly'),
      limit: query.optionalInt('limit') ?? 300,
    );
  }

  // ---- payments ----------------------------------------------------------

  router.get('/payments', (Request request) async {
    requirePermission(
      request,
      Permissions.paymentView,
      action: 'view payments',
    );
    final rows = await queries.watchPayments(paymentFilterFrom(request)).first;
    return Api.ok({'payments': rows.map((r) => r.toJson()).toList()});
  });

  router.get('/payments/totals', (Request request) async {
    requirePermission(
      request,
      Permissions.paymentView,
      action: 'view payments',
    );
    final totals = await queries.paymentTotals(paymentFilterFrom(request));
    return Api.ok({'totals': totals.toJson()});
  });

  /// Invoices a collection can be applied to, for one agent or one shop.
  router.get('/payments/allocatable', (Request request) async {
    requirePermission(
      request,
      Permissions.paymentView,
      action: 'view payments',
    );
    final query = QueryParams.of(request);
    final rows = await payments.allocatableInvoices(
      agentId: query.optionalInt('agentId'),
      shopId: query.optionalInt('shopId'),
    );
    return Api.ok({'invoices': rows.map((r) => r.toJson()).toList()});
  });

  /// Money received that has not been applied to any invoice yet.
  router.get('/payments/advance-balance', (Request request) async {
    requirePermission(
      request,
      Permissions.paymentView,
      action: 'view payments',
    );
    final query = QueryParams.of(request);
    final advance = await payments.advanceBalance(
      agentId: query.optionalInt('agentId'),
      shopId: query.optionalInt('shopId'),
    );
    return Api.ok({'advance': advance.toJson()});
  });

  router.post('/payments', (Request request) async {
    final body = await JsonBody.read(request);
    final result = await payments.recordPayment(
      request.session.user,
      body.decode(PaymentRequest.fromJson),
    );
    return Api.created({'payment': result.toJson()});
  });

  router.post('/payments/<id>/allocations', (Request request, String id) async {
    final body = await JsonBody.read(request);
    await payments.allocate(
      request.session.user,
      paymentId: pathId(id),
      allocations: body.decodeEach(
        'allocations',
        PaymentAllocationRequest.fromJson,
      ),
    );
    return Api.noContent();
  });

  /// Withdraws an allocation, in whole or in part.
  ///
  /// `amount` is in minor units and optional: leaving it out releases the
  /// whole allocation to that invoice.
  ///
  /// A POST rather than a DELETE because it carries a body — the amount and
  /// the reason — and a DELETE with a body is dropped or mangled by enough
  /// proxies that it is not worth the tidiness.
  router.post('/payments/<id>/allocations/<invoiceId>/release', (
    Request request,
    String id,
    String invoiceId,
  ) async {
    final body = await JsonBody.read(request);
    final amount = body.optionalInt('amount');
    await payments.releaseAllocation(
      request.session.user,
      paymentId: pathId(id),
      invoiceId: pathId(invoiceId, field: 'invoiceId'),
      amount: amount == null ? null : Money(amount),
      reason: body.optionalString('reason', maxLength: 500),
    );
    return Api.noContent();
  });

  router.post('/payments/<id>/cancel', (Request request, String id) async {
    final body = await JsonBody.read(request);
    await payments.cancelPayment(
      request.session.user,
      paymentId: pathId(id),
      reason: body.requireString('reason', maxLength: 500),
    );
    return Api.noContent();
  });

  // ---- settlement position on an invoice ---------------------------------

  /// The two settlement figures for an invoice, together and named.
  ///
  /// They are **not** the same number and conflating them is the easiest way
  /// to take money twice:
  ///
  /// * `outstanding` counts only money that has actually cleared. It is what
  ///   the business is still owed.
  /// * `allocatableRemaining` also counts payments still pending — a cheque
  ///   banked but not cleared. It is what may still be *applied* to this
  ///   invoice, and it is the smaller figure once a cheque is in flight.
  ///
  /// Allocating against `outstanding` while a cheque is pending would apply
  /// the same debt twice.
  router.get('/invoices/<id>/settlement', (Request request, String id) async {
    requirePermission(
      request,
      Permissions.paymentView,
      action: 'view payments',
    );
    final invoiceId = pathId(id);
    final outstanding = await payments.outstandingOf(invoiceId);
    final allocatable = await payments.allocatableRemaining(invoiceId);
    return Api.ok({
      'outstanding': outstanding.toJson(),
      'allocatableRemaining': allocatable.toJson(),
    });
  });

  /// Releases every allocation against one invoice. Used when an invoice is
  /// being unwound. POST, for the same reason as the single release above.
  router.post('/invoices/<id>/allocations/release', (
    Request request,
    String id,
  ) async {
    final body = await JsonBody.read(request);
    final released = await payments.releaseAllocationsForInvoice(
      actor: request.session.user,
      invoiceId: pathId(id),
      reason: body.requireString('reason', maxLength: 500),
    );
    return Api.ok({'released': released.toJson()});
  });

  // ---- cheques -----------------------------------------------------------

  ChequeFilter chequeFilterFrom(Request request) {
    final query = QueryParams.of(request);
    return ChequeFilter(
      search: query.string('search'),
      statuses: query.enumSet('status', ChequeStatus.values),
      from: query.optionalUtcDate('from'),
      to: query.optionalUtcDate('to'),
      bankableOnly: query.boolean('bankableOnly'),
      limit: query.optionalInt('limit') ?? 300,
    );
  }

  router.get('/cheques', (Request request) async {
    requirePermission(request, Permissions.paymentView, action: 'view cheques');
    final rows = await queries.watchCheques(chequeFilterFrom(request)).first;
    return Api.ok({'cheques': rows.map((r) => r.toJson()).toList()});
  });

  router.get('/cheques/totals', (Request request) async {
    requirePermission(request, Permissions.paymentView, action: 'view cheques');
    final totals = await queries.chequeTotals(chequeFilterFrom(request));
    return Api.ok({'totals': totals.toJson()});
  });

  router.post('/cheques/<id>/deposit', (Request request, String id) async {
    final body = await JsonBody.read(request);
    await payments.depositCheque(
      request.session.user,
      chequeId: pathId(id),
      depositedOn: body.optionalUtcDate('depositedOn'),
    );
    return Api.noContent();
  });

  /// The money has arrived. This is the point the journal entry is posted —
  /// not when the cheque was taken.
  router.post('/cheques/<id>/clear', (Request request, String id) async {
    final body = await JsonBody.read(request);
    await payments.clearCheque(
      request.session.user,
      chequeId: pathId(id),
      clearedOn: body.optionalUtcDate('clearedOn'),
    );
    return Api.noContent();
  });

  /// The cheque failed. Anything a clearance posted is reversed, and the bank
  /// charge is recorded against the party.
  router.post('/cheques/<id>/bounce', (Request request, String id) async {
    final body = await JsonBody.read(request);
    final charge = body.optionalInt('bounceCharge');
    await payments.bounceCheque(
      request.session.user,
      chequeId: pathId(id),
      reason: body.requireString('reason', maxLength: 300),
      bounceCharge: charge == null ? Money.zero : Money(charge),
      bouncedOn: body.optionalUtcDate('bouncedOn'),
    );
    return Api.noContent();
  });

  /// Points a bounced cheque at the payment that replaced it, so the trail
  /// from the failure to the settlement is recorded rather than inferred.
  router.post('/cheques/<id>/replacement', (Request request, String id) async {
    final body = await JsonBody.read(request);
    await payments.linkReplacementPayment(
      request.session.user,
      chequeId: pathId(id),
      replacementPaymentId: body.requireInt('replacementPaymentId'),
    );
    return Api.noContent();
  });

  return router;
}
