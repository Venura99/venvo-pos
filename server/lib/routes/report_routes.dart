import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/errors/failures.dart';
import 'package:venvo_core/features/reports/data/report_repository.dart';
import 'package:venvo_core/features/reports/domain/report_catalogue.dart';
import 'package:venvo_core/features/reports/domain/report_models.dart';

import '../auth/auth_middleware.dart';
import '../http/query_params.dart';
import '../http/responses.dart';

/// The 18 reports.
///
/// Authorization here is **data-driven**: every [ReportDefinition] in
/// `kReports` carries the permission needed to run it, so the catalogue a user
/// is shown and the reports they may actually run come from the same single
/// list. There is no second place to keep in step, and a new report cannot be
/// added without saying who may see it.
Router reportRoutes({required ReportRepository reports}) {
  final router = Router();

  /// The reports this user may run.
  ///
  /// Filtered rather than returned whole: a cashier should not be shown a
  /// profit and loss statement and told they are not allowed to open it.
  router.get('/reports', (Request request) async {
    requirePermission(request, Permissions.reportsView, action: 'view reports');
    final user = request.session.user;
    final allowed = kReports.where((r) => user.can(r.permission));
    return Api.ok({
      'reports': [for (final definition in allowed) definition.toJson()],
    });
  });

  router.get('/reports/<id>', (Request request, String id) async {
    final definition = kReports.where((r) => r.id == id).firstOrNull;
    if (definition == null) {
      throw NotFoundFailure(
        'There is no report called "$id".',
        details: 'Known reports: ${kReports.map((r) => r.id).join(', ')}.',
      );
    }

    // The permission comes from the definition, not from this route.
    requirePermission(
      request,
      definition.permission,
      action: 'run the ${definition.title} report',
    );

    final query = QueryParams.of(request);
    final result = await reports.run(
      definition,
      ReportFilter(
        from: query.optionalUtcDate('from'),
        to: query.optionalUtcDate('to'),
        agentId: query.optionalInt('agentId'),
        shopId: query.optionalInt('shopId'),
        productId: query.optionalInt('productId'),
        categoryId: query.optionalInt('categoryId'),
        employeeId: query.optionalInt('employeeId'),
        locationId: query.optionalInt('locationId'),
        limit: query.optionalInt('limit') ?? 500,
      ),
    );
    return Api.ok({'result': result.toJson()});
  });

  return router;
}
