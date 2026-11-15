import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/features/inventory/data/stock_count_repository.dart';
import 'package:venvo_core/features/inventory/data/stock_ledger_service.dart';
import 'package:venvo_core/features/inventory/data/stock_query_repository.dart';
import 'package:venvo_core/features/inventory/domain/stock_models.dart';

import '../auth/auth_middleware.dart';
import '../http/json_body.dart';
import '../http/path_id.dart';
import '../http/query_params.dart';
import '../http/responses.dart';

/// Stock: what is where, how it moved, and the reconciliation counts.
///
/// The writes go through [StockLedgerService.postMovement], which posts the
/// paired, signed ledger rows inside one transaction and refuses a route that
/// does not balance. None of that is reimplemented here and none of it can be
/// bypassed by calling this API: `postMovement` checks the permission for the
/// document type itself, and the negative-stock override needs both
/// `stock.negative_override` **and** a written reason.
Router stockRoutes({
  required StockQueryRepository queries,
  required StockLedgerService ledger,
  required StockCountRepository counts,
}) {
  final router = Router();

  // ---- reads -------------------------------------------------------------

  router.get('/stock', (Request request) async {
    requirePermission(request, Permissions.stockView, action: 'view stock');
    final query = QueryParams.of(request);
    final rows = await queries
        .watchProductStock(
          StockOverviewFilter(
            search: query.string('search'),
            categoryId: query.optionalInt('categoryId'),
            lowStockOnly: query.boolean('lowStockOnly'),
            hideZeroStock: query.boolean('hideZeroStock', fallback: true),
          ),
        )
        .first;
    return Api.ok({'stock': rows.map((r) => r.toJson()).toList()});
  });

  router.get('/stock/ledger', (Request request) async {
    requirePermission(request, Permissions.stockView, action: 'view stock');
    final query = QueryParams.of(request);
    final rows = await queries
        .watchLedger(
          StockLedgerFilter(
            search: query.string('search'),
            productId: query.optionalInt('productId'),
            locationId: query.optionalInt('locationId'),
            from: query.optionalUtcDate('from'),
            to: query.optionalUtcDate('to'),
            includeVirtualLocations: query.boolean('includeVirtualLocations'),
            limit: query.optionalInt('limit') ?? 500,
          ),
        )
        .first;
    return Api.ok({'entries': rows.map((r) => r.toJson()).toList()});
  });

  router.get('/stock/documents', (Request request) async {
    requirePermission(request, Permissions.stockView, action: 'view stock');
    final query = QueryParams.of(request);
    final rows = await queries
        .watchDocuments(
          StockDocumentFilter(
            search: query.string('search'),
            // Repeated: ?type=warehouseToAgent&type=agentToShop
            types: query.enumSet('type', StockDocumentType.values),
            status: query.has('status')
                ? query.enumValue(
                    'status',
                    StockDocumentStatus.values,
                    fallback: StockDocumentStatus.values.first,
                  )
                : null,
            agentId: query.optionalInt('agentId'),
            shopId: query.optionalInt('shopId'),
            locationId: query.optionalInt('locationId'),
            from: query.optionalUtcDate('from'),
            to: query.optionalUtcDate('to'),
            limit: query.optionalInt('limit') ?? 300,
          ),
        )
        .first;
    return Api.ok({'documents': rows.map((r) => r.toJson()).toList()});
  });

  router.get('/stock/documents/<id>', (Request request, String id) async {
    requirePermission(request, Permissions.stockView, action: 'view stock');
    final detail = await queries.documentDetail(pathId(id));
    return Api.ok({'document': detail.toJson()});
  });

  router.get('/stock/locations/<id>', (Request request, String id) async {
    requirePermission(request, Permissions.stockView, action: 'view stock');
    final query = QueryParams.of(request);
    final rows = await queries
        .watchLocationStock(
          pathId(id),
          search: query.string('search'),
          hideZero: query.boolean('hideZero', fallback: true),
        )
        .first;
    return Api.ok({'balances': rows.map((r) => r.toJson()).toList()});
  });

  router.get('/stock/balance', (Request request) async {
    requirePermission(request, Permissions.stockView, action: 'view stock');
    final query = QueryParams.of(request);
    final quantity = await ledger.balanceOf(
      locationId: query.requireInt('locationId'),
      productId: query.requireInt('productId'),
    );
    return Api.ok({'quantity': quantity});
  });

  /// Replays the ledger for one product at one location and reports whether
  /// the cached balance agrees.
  ///
  /// This is the check that makes "the ledger is the authority and
  /// `stock_balances` is only a cache" verifiable rather than merely claimed.
  router.get('/stock/verify', (Request request) async {
    requirePermission(
      request,
      Permissions.stockReconcile,
      action: 'verify stock balances',
    );
    final query = QueryParams.of(request);
    final result = await ledger.verifyBalance(
      locationId: query.requireInt('locationId'),
      productId: query.requireInt('productId'),
    );
    return Api.ok({
      'cached': result.cached,
      'fromLedger': result.fromLedger,
      'matches': result.matches,
    });
  });

  /// Products whose signed ledger rows do not sum to zero across all
  /// locations. An empty list is the expected answer; anything else is a bug
  /// worth finding, because double-entry stock must always net to nothing.
  router.get('/stock/unbalanced', (Request request) async {
    requirePermission(
      request,
      Permissions.stockReconcile,
      action: 'verify stock balances',
    );
    final rows = await ledger.findUnbalancedProducts();
    return Api.ok({
      'products': [
        for (final row in rows)
          {'productId': row.productId, 'netDelta': row.netDelta},
      ],
    });
  });

  // ---- movements ---------------------------------------------------------

  router.post('/stock/movements', (Request request) async {
    final body = await JsonBody.read(request);
    final result = await ledger.postMovement(
      request.session.user,
      body.decode(StockMovementRequest.fromJson),
    );
    return Api.created({'movement': result.toJson()});
  });

  /// Cancels a posted movement by reversing it.
  ///
  /// Nothing is edited or deleted: the original document stays and a
  /// compensating pair of ledger rows is posted, which is what keeps a
  /// completed transaction from being quietly rewritten.
  router.post('/stock/movements/<id>/cancel', (
    Request request,
    String id,
  ) async {
    final body = await JsonBody.read(request);
    final result = await ledger.cancelMovement(
      request.session.user,
      transactionId: pathId(id),
      reason: body.requireString('reason', maxLength: 500),
    );
    return Api.ok({'movement': result.toJson()});
  });

  // ---- reconciliation counts --------------------------------------------

  router.get('/stock/counts', (Request request) async {
    requirePermission(
      request,
      Permissions.stockReconcile,
      action: 'view stock counts',
    );
    final sheets = await counts
        .watchCounts(
          locationId: QueryParams.of(request).optionalInt('locationId'),
        )
        .first;
    return Api.ok({'counts': sheets.map((s) => s.toJson()).toList()});
  });

  router.post('/stock/counts', (Request request) async {
    final body = await JsonBody.read(request);
    final id = await counts.createCount(
      request.session.user,
      locationId: body.requireInt('locationId'),
      includeZeroStock: body.boolean('includeZeroStock'),
      notes: body.optionalString('notes', maxLength: 500),
    );
    return Api.created({'id': id});
  });

  router.get('/stock/counts/<id>', (Request request, String id) async {
    requirePermission(
      request,
      Permissions.stockReconcile,
      action: 'view stock counts',
    );
    final sheet = await counts.loadCount(pathId(id));
    return Api.ok({'count': sheet.toJson()});
  });

  /// Records counted quantities. A null value means "not counted yet", which
  /// is a different fact from a counted zero and is preserved as such.
  router.put('/stock/counts/<id>/quantities', (
    Request request,
    String id,
  ) async {
    final body = await JsonBody.read(request);
    await counts.saveCountedQuantities(
      request.session.user,
      countId: pathId(id),
      countedByProductId: body.requireNullableIntMap('counted'),
    );
    return Api.noContent();
  });

  /// Posts the count: every variance becomes a real stock adjustment through
  /// the ledger, so the correction is itself auditable.
  router.post('/stock/counts/<id>/post', (Request request, String id) async {
    final body = await JsonBody.read(request);
    final movements = await counts.postCount(
      request.session.user,
      countId: pathId(id),
      reason: body.optionalString('reason', maxLength: 500),
    );
    return Api.ok({'movements': movements.map((m) => m.toJson()).toList()});
  });

  router.post('/stock/counts/<id>/discard', (Request request, String id) async {
    await counts.discardCount(request.session.user, pathId(id));
    return Api.noContent();
  });

  router.get('/stock/counts/<id>/variance', (Request request, String id) async {
    requirePermission(
      request,
      Permissions.stockReconcile,
      action: 'view stock counts',
    );
    final variance = await counts.varianceValue(pathId(id));
    return Api.ok({'variance': variance.toJson()});
  });

  return router;
}
