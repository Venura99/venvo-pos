import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/agents/presentation/agents_screen.dart';
import '../../features/authentication/presentation/auth_controller.dart';
import '../../features/authentication/presentation/sign_in_screen.dart';
import '../../features/authentication/presentation/users_screen.dart';
import '../../features/backup/presentation/backup_screen.dart';
import '../../features/categories/presentation/categories_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/employees/presentation/employees_screen.dart';
import '../../features/expenses/presentation/expenses_screen.dart';
import '../../features/finance/presentation/financial_ledger_screen.dart';
import '../../features/inventory/presentation/locations_screen.dart';
import '../../features/inventory/presentation/stock_movements_screen.dart';
import '../../features/inventory/presentation/stock_overview_screen.dart';
import '../../features/inventory/presentation/stock_reconciliation_screen.dart';
import '../../features/invoices/presentation/invoices_screen.dart';
import '../../features/payments/presentation/cheques_screen.dart';
import '../../features/payments/presentation/payments_screen.dart';
import '../../features/petty_cash/presentation/petty_cash_screen.dart';
import '../../features/products/presentation/products_screen.dart';
import '../../features/reports/presentation/reports_screen.dart';
import '../../features/returns/presentation/credit_notes_screen.dart';
import '../../features/returns/presentation/returns_screen.dart';
import '../../features/salaries/presentation/salaries_screen.dart';
import '../../features/settings/presentation/audit_log_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/shops/presentation/shops_screen.dart';
import '../../features/stock_transfers/presentation/transfers_screen.dart';
import '../widgets/app_shell.dart';
import '../widgets/planned_module_page.dart';
import 'nav_destinations.dart';

/// Application routing.
///
/// Three gates are applied, in order, before any business screen renders:
/// a database with no users goes to first-run setup, a visitor with no session
/// goes to sign-in, and a user whose password was reset goes to the
/// change-password screen. Everything else renders inside [AppShell].
final routerProvider = Provider<GoRouter>((ref) {
  // GoRouter needs a Listenable to re-evaluate redirects. Rebuilding the
  // router itself on every auth change would throw away navigation state, so a
  // notifier is nudged instead.
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.dashboard,
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final location = state.matchedLocation;

      if (auth.needsFirstRun) {
        return location == Routes.firstRun ? null : Routes.firstRun;
      }
      if (!auth.isSignedIn) {
        return location == Routes.signIn ? null : Routes.signIn;
      }
      if (auth.mustChangePassword) {
        return location == Routes.changePassword ? null : Routes.changePassword;
      }
      // Signed in: keep them out of the pre-auth screens.
      if (location == Routes.signIn || location == Routes.firstRun) {
        return Routes.dashboard;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.firstRun,
        builder: (context, state) => const FirstRunScreen(),
      ),
      GoRoute(
        path: Routes.signIn,
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: Routes.changePassword,
        builder: (context, state) => const ChangePasswordScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          for (final destination in kAllDestinations)
            GoRoute(
              path: destination.path,
              pageBuilder: (context, state) => NoTransitionPage(
                key: ValueKey(destination.path),
                child: screenForDestination(destination),
              ),
            ),
        ],
      ),
    ],
    errorBuilder: (context, state) => _RouteNotFound(location: state.uri.path),
  );
});

/// Maps a navigation destination to its screen. Destinations whose module is
/// scheduled for a later phase get an honest placeholder rather than a
/// half-working screen.
Widget screenForDestination(NavDestination destination) {
  if (destination.availableFromPhase > kImplementedThroughPhase) {
    final plan = _plannedModules[destination.path];
    return PlannedModulePage(
      title: destination.label,
      phase: destination.availableFromPhase,
      summary: plan?.summary ?? 'This module is scheduled for a later phase.',
      capabilities: plan?.capabilities ?? const [],
    );
  }

  return switch (destination.path) {
    Routes.dashboard => const DashboardScreen(),
    Routes.stockTransfers => const StockDocumentRegisterScreen.transfers(),
    Routes.shopSupply => const StockDocumentRegisterScreen.shopSupply(),
    Routes.openingStock => const StockDocumentRegisterScreen.openingStock(),
    Routes.stockAdjustments => const StockDocumentRegisterScreen.adjustments(),
    Routes.stockOverview => const StockOverviewScreen(),
    Routes.stockMovements => const StockMovementsScreen(),
    Routes.stockReconciliation => const StockReconciliationScreen(),
    Routes.invoices => const InvoicesScreen(),
    Routes.payments => const PaymentsScreen(),
    Routes.cheques => const ChequesScreen(),
    Routes.retailSales => const InvoicesScreen.retailSales(),
    Routes.returns => const ReturnsScreen(),
    Routes.creditNotes => const CreditNotesScreen(),
    Routes.expenses => const ExpensesScreen(),
    Routes.pettyCash => const PettyCashScreen(),
    Routes.salaries => const SalariesScreen(),
    Routes.financialLedger => const FinancialLedgerScreen(),
    Routes.reports => const ReportsScreen(),
    Routes.backup => const BackupScreen(),
    Routes.products => const ProductsScreen(),
    Routes.categories => const CategoriesScreen(),
    Routes.agents => const AgentsScreen(),
    Routes.shops => const ShopsScreen(),
    Routes.employees => const EmployeesScreen(),
    Routes.locations => const LocationsScreen(),
    Routes.users => const UsersScreen(),
    Routes.auditLog => const AuditLogScreen(),
    Routes.settings => const SettingsScreen(),
    _ => PlannedModulePage(
      title: destination.label,
      phase: destination.availableFromPhase,
      summary: 'This screen has not been wired up yet.',
    ),
  };
}

class _PlannedModule {
  const _PlannedModule({required this.summary, required this.capabilities});

  final String summary;
  final List<String> capabilities;
}

/// What each pending module will do, so the placeholder is informative rather
/// than an apology.
const Map<String, _PlannedModule> _plannedModules = {};

class _RouteNotFound extends StatelessWidget {
  const _RouteNotFound({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.explore_off_outlined, size: 40),
            const SizedBox(height: 16),
            Text('No screen at $location'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => GoRouter.of(context).go(Routes.dashboard),
              child: const Text('Back to dashboard'),
            ),
          ],
        ),
      ),
    );
  }
}
