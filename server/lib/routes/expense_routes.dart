import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/features/expenses/data/expense_query_repository.dart';
import 'package:venvo_core/features/expenses/data/expense_service.dart';
import 'package:venvo_core/features/expenses/domain/expense_models.dart';

import '../auth/auth_middleware.dart';
import '../http/json_body.dart';
import '../http/path_id.dart';
import '../http/query_params.dart';
import '../http/responses.dart';

/// Operating expenses and their categories.
///
/// An expense posts its own journal entry, and one marked `fromPettyCash`
/// also writes the petty cash entry that pays for it — both inside the same
/// transaction as the expense itself, so the float and the expense can never
/// disagree.
Router expenseRoutes({
  required ExpenseService expenses,
  required ExpenseQueryRepository queries,
}) {
  final router = Router();

  ExpenseFilter filterFrom(Request request) {
    final query = QueryParams.of(request);
    return ExpenseFilter(
      search: query.string('search'),
      categoryId: query.optionalInt('categoryId'),
      paymentMethod: query.has('paymentMethod')
          ? query.enumValue(
              'paymentMethod',
              PaymentMethod.values,
              fallback: PaymentMethod.values.first,
            )
          : null,
      status: query.has('status')
          ? query.enumValue(
              'status',
              InvoiceStatus.values,
              fallback: InvoiceStatus.values.first,
            )
          : null,
      pettyCashOnly: query.boolean('pettyCashOnly'),
      from: query.optionalUtcDate('from'),
      to: query.optionalUtcDate('to'),
      limit: query.optionalInt('limit') ?? 300,
    );
  }

  router.get('/expenses', (Request request) async {
    requirePermission(
      request,
      Permissions.expenseView,
      action: 'view expenses',
    );
    final rows = await queries.watchExpenses(filterFrom(request)).first;
    return Api.ok({'expenses': rows.map((r) => r.toJson()).toList()});
  });

  router.get('/expenses/totals', (Request request) async {
    requirePermission(
      request,
      Permissions.expenseView,
      action: 'view expenses',
    );
    final totals = await queries.totals(filterFrom(request));
    return Api.ok({'totals': totals.toJson()});
  });

  /// Spend per day, for the trend on the expenses screen.
  router.get('/expenses/daily-totals', (Request request) async {
    requirePermission(
      request,
      Permissions.expenseView,
      action: 'view expenses',
    );
    final query = QueryParams.of(request);
    final rows = await queries.dailyTotals(
      from: query.optionalUtcDate('from'),
      to: query.optionalUtcDate('to'),
    );
    return Api.ok({
      'days': [
        for (final row in rows)
          {
            'day': row.day.toUtc().toIso8601String(),
            'total': row.total.toJson(),
            'count': row.count,
          },
      ],
    });
  });

  router.post('/expenses', (Request request) async {
    final body = await JsonBody.read(request);
    final id = await expenses.postExpense(
      request.session.user,
      body.decode(ExpenseDraft.fromJson),
    );
    return Api.created({'id': id});
  });

  router.post('/expenses/<id>/cancel', (Request request, String id) async {
    final body = await JsonBody.read(request);
    await expenses.cancelExpense(
      request.session.user,
      expenseId: pathId(id),
      reason: body.requireString('reason', maxLength: 500),
    );
    return Api.noContent();
  });

  // ---- categories --------------------------------------------------------

  router.get('/expense-categories', (Request request) async {
    requirePermission(
      request,
      Permissions.expenseView,
      action: 'view expenses',
    );
    final rows = await queries
        .watchCategories(
          includeArchived: QueryParams.of(request).boolean('includeArchived'),
        )
        .first;
    return Api.ok({'categories': rows.map((r) => r.toJson()).toList()});
  });

  router.post('/expense-categories', (Request request) async {
    final body = await JsonBody.read(request);
    final id = await expenses.createCategory(
      request.session.user,
      name: body.requireString('name', maxLength: 120),
      code: body.optionalString('code', maxLength: 32),
    );
    return Api.created({'id': id});
  });

  router.post('/expense-categories/<id>/archive', (
    Request request,
    String id,
  ) async {
    await expenses.archiveCategory(
      request.session.user,
      categoryId: pathId(id),
    );
    return Api.noContent();
  });

  return router;
}
