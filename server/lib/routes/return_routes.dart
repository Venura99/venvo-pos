import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/errors/failures.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/returns/data/return_query_repository.dart';
import 'package:venvo_core/features/returns/data/return_service.dart';
import 'package:venvo_core/features/returns/domain/return_models.dart';

import '../auth/auth_middleware.dart';
import '../http/json_body.dart';
import '../http/path_id.dart';
import '../http/query_params.dart';
import '../http/responses.dart';

/// Goods coming back, and the credit raised for them.
///
/// [ReturnService] keeps the parts that are easy to get wrong: a return moves
/// along a **two-leg route** through an in-transit location rather than
/// teleporting from a shop to an agent, inspection splits the quantity into
/// accepted, damaged and scrapped, and the credit note is worth the accepted
/// and damaged goods at the price actually charged — after any
/// proportional share of an invoice-level discount. None of that is repeated
/// here.
Router returnRoutes({
  required ReturnService returns,
  required ReturnQueryRepository queries,
}) {
  final router = Router();

  ReturnFilter returnFilterFrom(Request request) {
    final query = QueryParams.of(request);
    return ReturnFilter(
      search: query.string('search'),
      routes: query.enumSet('route', ReturnRoute.values),
      status: query.has('status')
          ? query.enumValue(
              'status',
              ReturnStatus.values,
              fallback: ReturnStatus.values.first,
            )
          : null,
      reason: query.has('reason')
          ? query.enumValue(
              'reason',
              ReturnReason.values,
              fallback: ReturnReason.values.first,
            )
          : null,
      agentId: query.optionalInt('agentId'),
      shopId: query.optionalInt('shopId'),
      pendingInspectionOnly: query.boolean('pendingInspectionOnly'),
      from: query.optionalUtcDate('from'),
      to: query.optionalUtcDate('to'),
      limit: query.optionalInt('limit') ?? 300,
    );
  }

  CreditNoteFilter creditFilterFrom(Request request) {
    final query = QueryParams.of(request);
    return CreditNoteFilter(
      search: query.string('search'),
      status: query.has('status')
          ? query.enumValue(
              'status',
              InvoiceStatus.values,
              fallback: InvoiceStatus.values.first,
            )
          : null,
      agentId: query.optionalInt('agentId'),
      shopId: query.optionalInt('shopId'),
      withRemainingOnly: query.boolean('withRemainingOnly'),
      from: query.optionalUtcDate('from'),
      to: query.optionalUtcDate('to'),
      limit: query.optionalInt('limit') ?? 300,
    );
  }

  // ---- returns -----------------------------------------------------------

  router.get('/returns', (Request request) async {
    requirePermission(request, Permissions.returnView, action: 'view returns');
    final rows = await queries.watchReturns(returnFilterFrom(request)).first;
    return Api.ok({'returns': rows.map((r) => r.toJson()).toList()});
  });

  // Before `/returns/<id>`: a literal segment has to be registered first or
  // it would be read as a return id.
  router.get('/returns/totals', (Request request) async {
    requirePermission(request, Permissions.returnView, action: 'view returns');
    final totals = await queries.returnTotals(returnFilterFrom(request));
    return Api.ok({'totals': totals.toJson()});
  });

  router.get('/returns/<id>', (Request request, String id) async {
    requirePermission(request, Permissions.returnView, action: 'view returns');
    final detail = await queries.returnDetail(pathId(id));
    return Api.ok({'return': detail.toJson()});
  });

  /// Lines on an invoice that can still be returned — what was billed, less
  /// what has already come back.
  router.get('/invoices/<id>/returnable-lines', (
    Request request,
    String id,
  ) async {
    requirePermission(request, Permissions.returnView, action: 'view returns');
    final lines = await returns.returnableLines(pathId(id));
    return Api.ok({'lines': lines.map((l) => l.toJson()).toList()});
  });

  /// Records goods coming back.
  ///
  /// A `shopToWarehouse` route bypasses the agent and needs
  /// `return.direct_to_warehouse` on top of the usual permission; that check
  /// is inside the service.
  router.post('/returns', (Request request) async {
    final body = await JsonBody.read(request);
    final result = await returns.postReturn(
      request.session.user,
      body.decode(ReturnDraft.fromJson),
    );
    return Api.created({'return': result.toJson()});
  });

  /// Records what the goods were actually worth on arrival.
  ///
  /// Every returned unit has to be accounted for as accepted, damaged or
  /// scrapped — the service refuses a decision that does not add up to the
  /// quantity returned, which is what stops stock quietly disappearing
  /// between the shop and the warehouse.
  router.post('/returns/<id>/inspection', (Request request, String id) async {
    final body = await JsonBody.read(request);
    final inspection = body.decode(InspectionRequest.fromJson);
    final returnId = pathId(id);
    if (inspection.returnId != returnId) {
      throw ValidationFailure(
        'The return id in the body (${inspection.returnId}) does not match '
        'the one in the address ($returnId).',
        field: 'returnId',
      );
    }
    final result = await returns.recordInspection(
      request.session.user,
      inspection,
    );
    return Api.ok({'inspection': result.toJson()});
  });

  router.post('/returns/<id>/cancel', (Request request, String id) async {
    final body = await JsonBody.read(request);
    await returns.cancelReturn(
      request.session.user,
      returnId: pathId(id),
      reason: body.requireString('reason', maxLength: 500),
    );
    return Api.noContent();
  });

  /// Issues a credit note against an inspected return.
  ///
  /// `amount` is optional and in minor units: omitting it credits the full
  /// creditable value, which is the accepted and damaged goods at the price
  /// actually charged. Scrapped goods are worth nothing and are not credited.
  router.post('/returns/<id>/credit-note', (Request request, String id) async {
    final body = await JsonBody.read(request);
    final amount = body.optionalInt('amount');
    final creditNoteId = await returns.issueCreditNote(
      request.session.user,
      returnId: pathId(id),
      amount: amount == null ? null : Money(amount),
      reason: body.optionalString('reason', maxLength: 300),
      notes: body.optionalString('notes', maxLength: 500),
      issueDate: body.optionalUtcDate('issueDate'),
    );
    return Api.created({'id': creditNoteId});
  });

  // ---- credit notes ------------------------------------------------------

  router.get('/credit-notes', (Request request) async {
    requirePermission(
      request,
      Permissions.returnView,
      action: 'view credit notes',
    );
    final rows = await queries
        .watchCreditNotes(creditFilterFrom(request))
        .first;
    return Api.ok({'creditNotes': rows.map((r) => r.toJson()).toList()});
  });

  /// Credit a party holds and has not yet used. Registered before
  /// `/credit-notes/<id>`.
  router.get('/credit-notes/available', (Request request) async {
    requirePermission(
      request,
      Permissions.returnView,
      action: 'view credit notes',
    );
    final query = QueryParams.of(request);
    final available = await queries.availableCredit(
      agentId: query.optionalInt('agentId'),
      shopId: query.optionalInt('shopId'),
    );
    return Api.ok({'available': available.toJson()});
  });

  router.get('/credit-notes/<id>', (Request request, String id) async {
    requirePermission(
      request,
      Permissions.returnView,
      action: 'view credit notes',
    );
    final detail = await queries.creditNoteDetail(pathId(id));
    return Api.ok({'creditNote': detail.toJson()});
  });

  /// Applies credit to an invoice. The amount is required and in minor units:
  /// a credit note is often spread across several invoices.
  router.post('/credit-notes/<id>/apply', (Request request, String id) async {
    final body = await JsonBody.read(request);
    await returns.applyToInvoice(
      request.session.user,
      creditNoteId: pathId(id),
      invoiceId: body.requireInt('invoiceId'),
      amount: Money(body.requireInt('amount')),
    );
    return Api.noContent();
  });

  router.post('/credit-notes/<id>/cancel', (Request request, String id) async {
    final body = await JsonBody.read(request);
    await returns.cancelCreditNote(
      request.session.user,
      creditNoteId: pathId(id),
      reason: body.requireString('reason', maxLength: 500),
    );
    return Api.noContent();
  });

  /// Takes an application back off an invoice, returning the credit to the
  /// note's unused balance.
  router.post('/credit-note-applications/<id>/withdraw', (
    Request request,
    String id,
  ) async {
    final body = await JsonBody.read(request);
    await returns.withdrawApplication(
      request.session.user,
      applicationId: pathId(id),
      reason: body.requireString('reason', maxLength: 300),
    );
    return Api.noContent();
  });

  return router;
}
