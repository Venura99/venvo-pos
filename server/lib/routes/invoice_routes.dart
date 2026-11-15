import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/errors/failures.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/invoices/data/invoice_query_repository.dart';
import 'package:venvo_core/features/invoices/data/invoice_service.dart';
import 'package:venvo_core/features/invoices/domain/invoice_models.dart';

import '../auth/auth_middleware.dart';
import '../http/json_body.dart';
import '../http/path_id.dart';
import '../http/query_params.dart';
import '../http/responses.dart';

/// Billing.
///
/// [InvoiceService] does the work: it posts the invoice, its lines, the
/// receivable and the balanced journal entry — and, where the request says so,
/// the stock movement — inside **one** transaction. The discount ceilings and
/// the credit-limit warning are enforced there too. None of that is repeated
/// here, and none of it can be skipped by calling this API instead of the
/// desktop build.
Router invoiceRoutes({
  required InvoiceService invoices,
  required InvoiceQueryRepository queries,
}) {
  final router = Router();

  InvoiceFilter filterFrom(Request request) {
    final query = QueryParams.of(request);
    return InvoiceFilter(
      search: query.string('search'),
      kinds: query.enumSet('kind', InvoiceKind.values),
      status: query.has('status')
          ? query.enumValue(
              'status',
              InvoiceStatus.values,
              fallback: InvoiceStatus.values.first,
            )
          : null,
      settlement: query.has('settlement')
          ? query.enumValue(
              'settlement',
              PaymentSettlementStatus.values,
              fallback: PaymentSettlementStatus.values.first,
            )
          : null,
      agentId: query.optionalInt('agentId'),
      shopId: query.optionalInt('shopId'),
      from: query.optionalUtcDate('from'),
      to: query.optionalUtcDate('to'),
      unpaidOnly: query.boolean('unpaidOnly'),
      overdueOnly: query.boolean('overdueOnly'),
      limit: query.optionalInt('limit') ?? 300,
    );
  }

  // ---- reads -------------------------------------------------------------

  router.get('/invoices', (Request request) async {
    requirePermission(
      request,
      Permissions.invoiceView,
      action: 'view invoices',
    );
    final rows = await queries.watchInvoices(filterFrom(request)).first;
    return Api.ok({'invoices': rows.map((r) => r.toJson()).toList()});
  });

  // Registered before `/invoices/<id>`: shelf_router matches in the order
  // routes are added, so a literal segment has to come first or it would be
  // read as an invoice id.
  router.get('/invoices/totals', (Request request) async {
    requirePermission(
      request,
      Permissions.invoiceView,
      action: 'view invoices',
    );
    final totals = await queries.totals(filterFrom(request));
    return Api.ok({'totals': totals.toJson()});
  });

  /// Stock that has been delivered but not yet billed.
  ///
  /// This is the queue that keeps "goods moved" and "money is owed" separate:
  /// a transfer is posted when the lorry leaves, and billing it is a second,
  /// deliberate step.
  router.get('/invoices/unbilled-deliveries', (Request request) async {
    requirePermission(
      request,
      Permissions.invoiceView,
      action: 'view invoices',
    );
    final rows = await queries.watchUnbilledDeliveries().first;
    return Api.ok({'deliveries': rows.map((r) => r.toJson()).toList()});
  });

  router.get('/invoices/<id>', (Request request, String id) async {
    requirePermission(
      request,
      Permissions.invoiceView,
      action: 'view invoices',
    );
    final detail = await queries.invoiceDetail(pathId(id));
    return Api.ok({'invoice': detail.toJson()});
  });

  // ---- writes ------------------------------------------------------------

  router.post('/invoices', (Request request) async {
    final body = await JsonBody.read(request);
    final result = await invoices.postInvoice(
      request.session.user,
      body.decode(InvoiceRequest.fromJson),
    );
    return Api.created({'invoice': result.toJson()});
  });

  /// Bills a delivery that was already posted.
  ///
  /// The lines and prices come from the delivery note, so what is billed is
  /// what was actually sent.
  router.post('/invoices/from-delivery', (Request request) async {
    final body = await JsonBody.read(request);
    final result = await invoices.billDelivery(
      request.session.user,
      stockTransactionId: body.requireInt('stockTransactionId'),
      invoiceDate: body.optionalUtcDate('invoiceDate'),
      dueDate: body.optionalUtcDate('dueDate'),
      invoiceDiscountType: body.has('invoiceDiscountType')
          ? body.enumValue('invoiceDiscountType', DiscountType.values)
          : DiscountType.none,
      invoiceDiscountValue: body.optionalInt('invoiceDiscountValue') ?? 0,
      discountReason: body.optionalString('discountReason', maxLength: 500),
      notes: body.optionalString('notes', maxLength: 1000),
      payment: body.decodeOptional('payment', ImmediatePayment.fromJson),
      priceOverrides: _priceOverrides(body),
    );
    return Api.created({'invoice': result.toJson()});
  });

  /// Cancels an invoice. The receivable is released and the journal entry
  /// reversed.
  ///
  /// `reverseStockMovement` decides whether the goods come back, and defaults
  /// to **false** — cancelling a bill is not the same as un-shipping. Set it
  /// only when the goods really are coming back, because reversing a delivery
  /// that already happened invents stock the warehouse does not have.
  ///
  /// It has no effect on an invoice that billed a separately posted delivery:
  /// that movement is not this invoice's to undo.
  router.post('/invoices/<id>/cancel', (Request request, String id) async {
    final body = await JsonBody.read(request);
    final result = await invoices.cancelInvoice(
      request.session.user,
      invoiceId: pathId(id),
      reason: body.requireString('reason', maxLength: 500),
      reverseStockMovement: body.boolean('reverseStockMovement'),
    );
    return Api.ok({'cancellation': result.toJson()});
  });

  return router;
}

/// Prices agreed at billing time that differ from the delivery note, keyed by
/// product id and in minor units. Absent means "bill what the note says".
///
/// A null price is refused rather than skipped: an override with no value is
/// a mistake in the request, and guessing would bill the wrong amount.
Map<int, Money>? _priceOverrides(JsonBody body) {
  if (!body.has('priceOverrides')) return null;
  final raw = body.requireNullableIntMap('priceOverrides');
  return {
    for (final entry in raw.entries)
      entry.key: Money(
        entry.value ??
            (throw ValidationFailure(
              'priceOverrides["${entry.key}"] has no price.',
              field: 'priceOverrides',
            )),
      ),
  };
}
