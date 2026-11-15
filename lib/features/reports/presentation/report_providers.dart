import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:venvo_core/features/reports/api/report_api.dart';
import 'package:venvo_core/features/reports/data/report_export_service.dart';
import 'package:venvo_core/features/reports/domain/report_catalogue.dart';
import 'package:venvo_core/features/reports/domain/report_models.dart';

import '../../../core/providers/core_providers.dart';
import '../../authentication/presentation/auth_controller.dart';
import '../../invoices/presentation/invoice_providers.dart';

final reportRepositoryProvider = Provider<ReportApi>(
  (ref) => ReportApi(ref.watch(apiClientProvider)),
);

final reportExportServiceProvider = FutureProvider<ReportExportService>((
  ref,
) async {
  return ReportExportService(
    business: await ref.watch(businessIdentityProvider.future),
  );
});

/// The reports this user is allowed to see.
///
/// A report is a view over data that is already permission-controlled, so each
/// one mirrors the module it reads: somebody who cannot see salaries does not
/// get a salary report either.
final visibleReportsProvider = Provider<List<ReportDefinition>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];
  return kReports
      .where((report) => user.can(report.permission))
      .toList(growable: false);
});

final selectedReportIdProvider = StateProvider<String?>((ref) => null);

/// The report currently open, defaulting to the first one this user can see.
final selectedReportProvider = Provider<ReportDefinition?>((ref) {
  final visible = ref.watch(visibleReportsProvider);
  if (visible.isEmpty) return null;
  final chosen = ref.watch(selectedReportIdProvider);
  if (chosen == null) return visible.first;
  return visible.where((report) => report.id == chosen).firstOrNull ??
      visible.first;
});

final reportFilterProvider = StateProvider<ReportFilter>(
  (ref) => const ReportFilter(),
);

/// The open report, run.
final reportResultProvider = FutureProvider<ReportResult?>((ref) async {
  final definition = ref.watch(selectedReportProvider);
  if (definition == null) return null;
  return ref
      .watch(reportRepositoryProvider)
      .run(definition, ref.watch(reportFilterProvider));
});
