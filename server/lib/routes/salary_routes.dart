import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/salaries/data/salary_query_repository.dart';
import 'package:venvo_core/features/salaries/data/salary_service.dart';
import 'package:venvo_core/features/salaries/domain/salary_models.dart';

import '../auth/auth_middleware.dart';
import '../http/json_body.dart';
import '../http/path_id.dart';
import '../http/query_params.dart';
import '../http/responses.dart';

/// Payroll and employee advances.
///
/// A salary moves through draft, approved and paid, and each step posts its
/// own journal entry — the liability on approval, the cash on payment. An
/// advance given earlier is recovered out of the salary, which is why
/// recording one and paying one are the same conversation.
Router salaryRoutes({
  required SalaryService salaries,
  required SalaryQueryRepository queries,
}) {
  final router = Router();

  SalaryFilter filterFrom(Request request) {
    final query = QueryParams.of(request);
    return SalaryFilter(
      search: query.string('search'),
      employeeId: query.optionalInt('employeeId'),
      periodYear: query.optionalInt('periodYear'),
      periodMonth: query.optionalInt('periodMonth'),
      status: query.has('status')
          ? query.enumValue(
              'status',
              SalaryStatus.values,
              fallback: SalaryStatus.values.first,
            )
          : null,
      unpaidOnly: query.boolean('unpaidOnly'),
      limit: query.optionalInt('limit') ?? 300,
    );
  }

  // ---- reads -------------------------------------------------------------

  router.get('/salaries', (Request request) async {
    requirePermission(request, Permissions.salaryView, action: 'view salaries');
    final rows = await queries.watchSalaries(filterFrom(request)).first;
    return Api.ok({'salaries': rows.map((r) => r.toJson()).toList()});
  });

  // Literal segments before `/salaries/<id>`.
  router.get('/salaries/totals', (Request request) async {
    requirePermission(request, Permissions.salaryView, action: 'view salaries');
    final totals = await queries.totals(filterFrom(request));
    return Api.ok({'totals': totals.toJson()});
  });

  /// The months payroll has been run for, for a period picker.
  router.get('/salaries/periods', (Request request) async {
    requirePermission(request, Permissions.salaryView, action: 'view salaries');
    final rows = await queries.periods();
    return Api.ok({
      'periods': [
        for (final row in rows)
          {'year': row.year, 'month': row.month, 'count': row.count},
      ],
    });
  });

  /// Works out what a salary would come to without creating it.
  ///
  /// A POST because it takes a draft in the body, but it writes nothing — it
  /// is what the payroll form shows while somebody is still filling it in.
  router.post('/salaries/compute', (Request request) async {
    requirePermission(request, Permissions.salaryView, action: 'view salaries');
    final body = await JsonBody.read(request);
    final computation = await salaries.compute(
      body.decode(SalaryDraft.fromJson),
    );
    return Api.ok({'computation': computation.toJson()});
  });

  router.get('/salaries/<id>', (Request request, String id) async {
    requirePermission(request, Permissions.salaryView, action: 'view salaries');
    final detail = await queries.salaryDetail(pathId(id));
    return Api.ok({'salary': detail.toJson()});
  });

  // ---- writes ------------------------------------------------------------

  router.post('/salaries', (Request request) async {
    final body = await JsonBody.read(request);
    final id = await salaries.createSalary(
      request.session.user,
      body.decode(SalaryDraft.fromJson),
    );
    return Api.created({'id': id});
  });

  /// Approves it: the liability is posted now, before any money moves.
  router.post('/salaries/<id>/approve', (Request request, String id) async {
    await salaries.approveSalary(request.session.user, salaryId: pathId(id));
    return Api.noContent();
  });

  /// Pays it, in whole or in part. `amount` is in minor units and optional:
  /// omitting it pays whatever is still outstanding.
  router.post('/salaries/<id>/pay', (Request request, String id) async {
    final body = await JsonBody.read(request);
    final amount = body.optionalInt('amount');
    final paymentId = await salaries.paySalary(
      request.session.user,
      salaryId: pathId(id),
      amount: amount == null ? null : Money(amount),
      method: body.has('method')
          ? body.enumValue('method', PaymentMethod.values)
          : PaymentMethod.cash,
      paymentDate: body.optionalUtcDate('paymentDate'),
      referenceNumber: body.optionalString('referenceNumber', maxLength: 64),
      notes: body.optionalString('notes', maxLength: 500),
    );
    return Api.created({'paymentId': paymentId});
  });

  router.post('/salaries/<id>/cancel', (Request request, String id) async {
    final body = await JsonBody.read(request);
    await salaries.cancelSalary(
      request.session.user,
      salaryId: pathId(id),
      reason: body.requireString('reason', maxLength: 500),
    );
    return Api.noContent();
  });

  // ---- advances ----------------------------------------------------------

  router.get('/advances', (Request request) async {
    requirePermission(request, Permissions.salaryView, action: 'view salaries');
    final query = QueryParams.of(request);
    final rows = await queries
        .watchAdvances(
          employeeId: query.optionalInt('employeeId'),
          outstandingOnly: query.boolean('outstandingOnly', fallback: true),
        )
        .first;
    return Api.ok({'advances': rows.map((r) => r.toJson()).toList()});
  });

  router.get('/employees/<id>/outstanding-advances', (
    Request request,
    String id,
  ) async {
    requirePermission(request, Permissions.salaryView, action: 'view salaries');
    final outstanding = await salaries.outstandingAdvances(pathId(id));
    return Api.ok({'outstanding': outstanding.toJson()});
  });

  /// Advances money against a future salary. It becomes a receivable from the
  /// employee, recovered when payroll is next run for them.
  router.post('/advances', (Request request) async {
    final body = await JsonBody.read(request);
    final id = await salaries.recordAdvance(
      request.session.user,
      employeeId: body.requireInt('employeeId'),
      amount: Money(body.requireInt('amount')),
      method: body.has('method')
          ? body.enumValue('method', PaymentMethod.values)
          : PaymentMethod.cash,
      advanceDate: body.optionalUtcDate('advanceDate'),
      notes: body.optionalString('notes', maxLength: 500),
    );
    return Api.created({'id': id});
  });

  return router;
}
