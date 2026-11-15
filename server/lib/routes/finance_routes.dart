import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/features/finance/data/financial_ledger_service.dart';

import '../auth/auth_middleware.dart';
import '../http/query_params.dart';
import '../http/responses.dart';

/// Reads over the financial journal.
///
/// Only reads for now: the postings all happen as a side effect of the
/// operation that caused them — an invoice, a payment, a stock movement — and
/// a route that let a client write directly into the journal would be a way to
/// put the accounts out of step with the business. Expenses, petty cash and
/// salaries each post through their own service and get their own endpoints.
Router financeRoutes({required FinancialLedgerService finance}) {
  final router = Router();

  router.get('/finance/trial-balance', (Request request) async {
    requirePermission(
      request,
      Permissions.financialLedgerView,
      action: 'view the financial ledger',
    );
    final query = QueryParams.of(request);
    final balance = await finance.trialBalance(
      from: query.optionalUtcDate('from'),
      to: query.optionalUtcDate('to'),
    );
    return Api.ok({'trialBalance': balance.toJson()});
  });

  /// Journal batches whose debits and credits do not agree.
  ///
  /// An empty list is the only acceptable answer. `post()` refuses an
  /// unbalanced batch, so anything here means a bug has written one another
  /// way — and a profit figure taken from an unbalanced journal is fiction.
  /// This is the financial twin of `/stock/unbalanced`.
  router.get('/finance/unbalanced-batches', (Request request) async {
    requirePermission(
      request,
      Permissions.financialLedgerView,
      action: 'view the financial ledger',
    );
    final batches = await finance.findUnbalancedBatches();
    return Api.ok({'batches': batches.map((b) => b.toJson()).toList()});
  });

  router.get('/finance/balance', (Request request) async {
    requirePermission(
      request,
      Permissions.financialLedgerView,
      action: 'view the financial ledger',
    );
    final query = QueryParams.of(request);
    final code = query.requireString('account');
    final balance = await finance.balanceOf(
      code,
      from: query.optionalUtcDate('from'),
      to: query.optionalUtcDate('to'),
    );
    return Api.ok({'account': code, 'balance': balance.toJson()});
  });

  router.get('/finance/profit-and-loss', (Request request) async {
    requirePermission(
      request,
      Permissions.reportsFinancial,
      action: 'view financial reports',
    );
    final query = QueryParams.of(request);
    final statement = await finance.profitAndLoss(
      from: query.optionalUtcDate('from'),
      to: query.optionalUtcDate('to'),
    );
    return Api.ok({'profitAndLoss': statement.toJson()});
  });

  return router;
}
