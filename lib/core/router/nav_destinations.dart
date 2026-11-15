import 'package:flutter/material.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/features/authentication/domain/authenticated_user.dart';

/// Route paths, in one place so no screen hardcodes a string.
class Routes {
  const Routes._();

  static const String firstRun = '/setup';
  static const String signIn = '/sign-in';
  static const String changePassword = '/change-password';

  static const String dashboard = '/';

  // Operations
  static const String stockTransfers = '/transfers';
  static const String shopSupply = '/shop-supply';
  static const String retailSales = '/retail-sales';
  static const String returns = '/returns';

  // Inventory
  static const String stockOverview = '/stock';
  static const String openingStock = '/stock/opening';
  static const String stockAdjustments = '/stock/adjustments';
  static const String stockReconciliation = '/stock/reconciliation';
  static const String stockMovements = '/stock/movements';

  // Master data
  static const String products = '/products';
  static const String categories = '/categories';
  static const String agents = '/agents';
  static const String shops = '/shops';
  static const String employees = '/employees';
  static const String locations = '/locations';

  // Money
  static const String invoices = '/invoices';
  static const String payments = '/payments';
  static const String cheques = '/cheques';
  static const String creditNotes = '/credit-notes';
  static const String expenses = '/expenses';
  static const String pettyCash = '/petty-cash';
  static const String salaries = '/salaries';
  static const String financialLedger = '/ledger';

  static const String reports = '/reports';

  // System
  static const String users = '/users';
  static const String settings = '/settings';
  static const String backup = '/backup';
  static const String auditLog = '/audit';
}

/// One item in the sidebar.
class NavDestination {
  const NavDestination({
    required this.label,
    required this.path,
    required this.icon,
    required this.selectedIcon,
    this.permission,
    this.availableFromPhase = 1,
  });

  final String label;
  final String path;
  final IconData icon;
  final IconData selectedIcon;

  /// Permission required to see the item at all. Null means everyone.
  final String? permission;

  /// Development phase the screen lands in. Items from a later phase are
  /// visible but open an honest "not built yet" page rather than pretending to
  /// work, so the shape of the finished product is visible from day one.
  final int availableFromPhase;

  bool isVisibleTo(AuthenticatedUser user) =>
      permission == null || user.can(permission!);
}

/// A labelled group of sidebar items.
class NavSection {
  const NavSection({required this.title, required this.destinations});

  final String title;
  final List<NavDestination> destinations;
}

/// The phase currently implemented. Destinations above this show the planned
/// state page.
const int kImplementedThroughPhase = 8;

/// The application's navigation, in the order a wholesale operator works:
/// what happened today, then goods, then the people and places, then money,
/// then reporting, then administration.
const List<NavSection> kNavSections = [
  NavSection(
    title: 'Overview',
    destinations: [
      NavDestination(
        label: 'Dashboard',
        path: Routes.dashboard,
        icon: Icons.dashboard_outlined,
        selectedIcon: Icons.dashboard,
      ),
    ],
  ),
  NavSection(
    title: 'Operations',
    destinations: [
      NavDestination(
        label: 'Stock Transfers',
        path: Routes.stockTransfers,
        icon: Icons.local_shipping_outlined,
        selectedIcon: Icons.local_shipping,
        permission: Permissions.stockTransfer,
        availableFromPhase: 3,
      ),
      NavDestination(
        label: 'Shop Supply',
        path: Routes.shopSupply,
        icon: Icons.store_mall_directory_outlined,
        selectedIcon: Icons.store_mall_directory,
        permission: Permissions.invoiceCreate,
        availableFromPhase: 3,
      ),
      NavDestination(
        label: 'Retail Sales',
        path: Routes.retailSales,
        icon: Icons.point_of_sale_outlined,
        selectedIcon: Icons.point_of_sale,
        permission: Permissions.retailSaleRecord,
        availableFromPhase: 4,
      ),
      NavDestination(
        label: 'Returns',
        path: Routes.returns,
        icon: Icons.assignment_return_outlined,
        selectedIcon: Icons.assignment_return,
        permission: Permissions.returnView,
        availableFromPhase: 5,
      ),
    ],
  ),
  NavSection(
    title: 'Inventory',
    destinations: [
      NavDestination(
        label: 'Stock Overview',
        path: Routes.stockOverview,
        icon: Icons.inventory_2_outlined,
        selectedIcon: Icons.inventory_2,
        permission: Permissions.stockView,
        availableFromPhase: 3,
      ),
      NavDestination(
        label: 'Opening Stock',
        path: Routes.openingStock,
        icon: Icons.playlist_add_outlined,
        selectedIcon: Icons.playlist_add,
        permission: Permissions.stockOpening,
        availableFromPhase: 3,
      ),
      NavDestination(
        label: 'Adjustments',
        path: Routes.stockAdjustments,
        icon: Icons.tune_outlined,
        selectedIcon: Icons.tune,
        permission: Permissions.stockAdjust,
        availableFromPhase: 3,
      ),
      NavDestination(
        label: 'Reconciliation',
        path: Routes.stockReconciliation,
        icon: Icons.fact_check_outlined,
        selectedIcon: Icons.fact_check,
        permission: Permissions.stockReconcile,
        availableFromPhase: 3,
      ),
      NavDestination(
        label: 'Stock Movements',
        path: Routes.stockMovements,
        icon: Icons.swap_vert_outlined,
        selectedIcon: Icons.swap_vert,
        permission: Permissions.stockView,
        availableFromPhase: 3,
      ),
    ],
  ),
  NavSection(
    title: 'Master Data',
    destinations: [
      NavDestination(
        label: 'Products',
        path: Routes.products,
        icon: Icons.category_outlined,
        selectedIcon: Icons.category,
        permission: Permissions.productsView,
        availableFromPhase: 2,
      ),
      NavDestination(
        label: 'Categories',
        path: Routes.categories,
        icon: Icons.folder_outlined,
        selectedIcon: Icons.folder,
        permission: Permissions.productsView,
        availableFromPhase: 2,
      ),
      NavDestination(
        label: 'Agents',
        path: Routes.agents,
        icon: Icons.badge_outlined,
        selectedIcon: Icons.badge,
        permission: Permissions.agentsView,
        availableFromPhase: 2,
      ),
      NavDestination(
        label: 'Shops',
        path: Routes.shops,
        icon: Icons.storefront_outlined,
        selectedIcon: Icons.storefront,
        permission: Permissions.shopsView,
        availableFromPhase: 2,
      ),
      NavDestination(
        label: 'Employees',
        path: Routes.employees,
        icon: Icons.groups_outlined,
        selectedIcon: Icons.groups,
        permission: Permissions.employeesView,
        availableFromPhase: 2,
      ),
      NavDestination(
        label: 'Warehouses',
        path: Routes.locations,
        icon: Icons.warehouse_outlined,
        selectedIcon: Icons.warehouse,
        permission: Permissions.stockView,
        availableFromPhase: 2,
      ),
    ],
  ),
  NavSection(
    title: 'Money',
    destinations: [
      NavDestination(
        label: 'Invoices',
        path: Routes.invoices,
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long,
        permission: Permissions.invoiceView,
        availableFromPhase: 4,
      ),
      NavDestination(
        label: 'Payments',
        path: Routes.payments,
        icon: Icons.payments_outlined,
        selectedIcon: Icons.payments,
        permission: Permissions.paymentView,
        availableFromPhase: 4,
      ),
      NavDestination(
        label: 'Cheques',
        path: Routes.cheques,
        icon: Icons.account_balance_outlined,
        selectedIcon: Icons.account_balance,
        permission: Permissions.chequeManage,
        availableFromPhase: 4,
      ),
      NavDestination(
        label: 'Credit Notes',
        path: Routes.creditNotes,
        icon: Icons.request_quote_outlined,
        selectedIcon: Icons.request_quote,
        permission: Permissions.returnView,
        availableFromPhase: 5,
      ),
      NavDestination(
        label: 'Expenses',
        path: Routes.expenses,
        icon: Icons.receipt_outlined,
        selectedIcon: Icons.receipt,
        permission: Permissions.expenseView,
        availableFromPhase: 6,
      ),
      NavDestination(
        label: 'Petty Cash',
        path: Routes.pettyCash,
        icon: Icons.savings_outlined,
        selectedIcon: Icons.savings,
        permission: Permissions.pettyCashView,
        availableFromPhase: 6,
      ),
      NavDestination(
        label: 'Salaries',
        path: Routes.salaries,
        icon: Icons.badge_outlined,
        selectedIcon: Icons.badge,
        permission: Permissions.salaryView,
        availableFromPhase: 6,
      ),
      NavDestination(
        label: 'Financial Ledger',
        path: Routes.financialLedger,
        icon: Icons.account_tree_outlined,
        selectedIcon: Icons.account_tree,
        permission: Permissions.financialLedgerView,
        availableFromPhase: 6,
      ),
    ],
  ),
  NavSection(
    title: 'Reporting',
    destinations: [
      NavDestination(
        label: 'Reports',
        path: Routes.reports,
        icon: Icons.insert_chart_outlined,
        selectedIcon: Icons.insert_chart,
        permission: Permissions.reportsView,
        availableFromPhase: 7,
      ),
    ],
  ),
  NavSection(
    title: 'Administration',
    destinations: [
      NavDestination(
        label: 'Users & Roles',
        path: Routes.users,
        icon: Icons.manage_accounts_outlined,
        selectedIcon: Icons.manage_accounts,
        permission: Permissions.usersManage,
      ),
      NavDestination(
        label: 'Audit Log',
        path: Routes.auditLog,
        icon: Icons.history_outlined,
        selectedIcon: Icons.history,
        permission: Permissions.auditView,
      ),
      NavDestination(
        label: 'Backups',
        path: Routes.backup,
        icon: Icons.backup_outlined,
        selectedIcon: Icons.backup,
        permission: Permissions.backupRun,
        availableFromPhase: 8,
      ),
      NavDestination(
        label: 'Settings',
        path: Routes.settings,
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
        permission: Permissions.settingsManage,
      ),
    ],
  ),
];

/// Flat list of every destination, for route generation and lookups.
final List<NavDestination> kAllDestinations = [
  for (final section in kNavSections) ...section.destinations,
];

NavDestination? destinationForPath(String path) {
  for (final destination in kAllDestinations) {
    if (destination.path == path) return destination;
  }
  return null;
}
