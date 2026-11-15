import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/features/petty_cash/data/petty_cash_service.dart';
import 'package:venvo_core/features/petty_cash/domain/petty_cash_models.dart';

import '../auth/auth_middleware.dart';
import '../http/json_body.dart';
import '../http/query_params.dart';
import '../http/responses.dart';

/// The petty cash float.
///
/// Every entry carries a signed amount and a running balance, so the float is
/// the sum of its movements rather than a number somebody keeps up to date.
/// `/recompute` rebuilds those running balances from the entries, which is
/// what makes the claim checkable.
Router pettyCashRoutes({required PettyCashService pettyCash}) {
  final router = Router();

  PettyCashFilter filterFrom(Request request) {
    final query = QueryParams.of(request);
    return PettyCashFilter(
      search: query.string('search'),
      kind: query.has('kind')
          ? query.enumValue(
              'kind',
              PettyCashEntryKind.values,
              fallback: PettyCashEntryKind.values.first,
            )
          : null,
      from: query.optionalUtcDate('from'),
      to: query.optionalUtcDate('to'),
      limit: query.optionalInt('limit') ?? 300,
    );
  }

  router.get('/petty-cash', (Request request) async {
    requirePermission(
      request,
      Permissions.pettyCashView,
      action: 'view petty cash',
    );
    final rows = await pettyCash.watchEntries(filterFrom(request)).first;
    return Api.ok({'entries': rows.map((r) => r.toJson()).toList()});
  });

  router.get('/petty-cash/snapshot', (Request request) async {
    requirePermission(
      request,
      Permissions.pettyCashView,
      action: 'view petty cash',
    );
    final snapshot = await pettyCash.snapshot(filterFrom(request));
    return Api.ok({'snapshot': snapshot.toJson()});
  });

  /// The float as it stands, or as it stood at `asOf`.
  router.get('/petty-cash/float', (Request request) async {
    requirePermission(
      request,
      Permissions.pettyCashView,
      action: 'view petty cash',
    );
    final balance = await pettyCash.floatBalance(
      asOf: QueryParams.of(request).optionalUtcDate('asOf'),
    );
    return Api.ok({'float': balance.toJson()});
  });

  /// Entries whose stored running balance disagrees with a replay of the
  /// book. An empty list is the expected answer.
  router.get('/petty-cash/discrepancies', (Request request) async {
    requirePermission(
      request,
      Permissions.pettyCashView,
      action: 'view petty cash',
    );
    final rows = await pettyCash.findBalanceDiscrepancies();
    return Api.ok({
      'discrepancies': [
        for (final row in rows)
          {
            'voucherNumber': row.voucherNumber,
            'stored': row.stored.toJson(),
            'replayed': row.replayed.toJson(),
          },
      ],
    });
  });

  router.post('/petty-cash', (Request request) async {
    final body = await JsonBody.read(request);
    final id = await pettyCash.recordEntry(
      request.session.user,
      body.decode(PettyCashDraft.fromJson),
    );
    return Api.created({'id': id});
  });

  /// Replays the entries and rewrites each running balance.
  ///
  /// Returns how many rows it changed — zero is the expected answer, and
  /// anything else is worth looking into rather than celebrating.
  router.post('/petty-cash/recompute', (Request request) async {
    final changed = await pettyCash.recomputeBalances(request.session.user);
    return Api.ok({'rowsChanged': changed});
  });

  return router;
}
