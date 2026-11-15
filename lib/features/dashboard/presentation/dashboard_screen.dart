import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:venvo_core/features/dashboard/api/dashboard_api.dart';
import 'package:venvo_core/features/dashboard/domain/dashboard_snapshot.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/router/nav_destinations.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/feedback_views.dart';
import '../../../core/widgets/kpi_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/status_pill.dart';
import '../../authentication/presentation/auth_controller.dart';

final dashboardRepositoryProvider = Provider<DashboardApi>(
  (ref) => DashboardApi(ref.watch(apiClientProvider)),
);

/// Re-reads every figure on demand. Kept as a FutureProvider rather than a
/// stream so the whole dashboard is one consistent read.
final dashboardSnapshotProvider = FutureProvider<DashboardSnapshot>((ref) {
  return ref.watch(dashboardRepositoryProvider).load();
});

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(dashboardSnapshotProvider);
    final user = ref.watch(currentUserProvider);

    return PageScaffold(
      title:
          'Good ${_partOfDay(ref)}, ${user?.fullName.split(' ').first ?? ''}',
      description:
          'Everything below is read live from this computer. '
          'Nothing is estimated.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(dashboardSnapshotProvider),
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Refresh'),
        ),
      ],
      child: AsyncValueView<DashboardSnapshot>(
        value: snapshot,
        onRetry: () => ref.invalidate(dashboardSnapshotProvider),
        builder: (context, data) => _DashboardBody(data: data),
      ),
    );
  }

  String _partOfDay(WidgetRef ref) {
    final hour = ref.read(clockProvider).nowUtc().toLocal().hour;
    if (hour < 12) return 'morning';
    if (hour < 17) return 'afternoon';
    return 'evening';
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.data});

  final DashboardSnapshot data;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (data.isEmptyBusiness) ...[
          const _GettingStartedCard(),
          AppSpacing.gapXl,
        ],
        Text('Today', style: context.text.titleMedium),
        AppSpacing.gapMd,
        KpiGrid(
          children: [
            KpiCard(
              label: 'Sales today',
              value: data.todaysSales.formatted(),
              caption: 'Posted invoices dated today',
              icon: Icons.trending_up,
              tone: StatusTone.info,
            ),
            KpiCard(
              label: 'Collections today',
              value: data.todaysCollections.formatted(),
              caption: 'Cleared money only',
              icon: Icons.payments_outlined,
              tone: StatusTone.success,
            ),
            KpiCard(
              label: 'Expenses today',
              value: data.todaysExpenses.formatted(),
              caption: 'Posted expense vouchers',
              icon: Icons.receipt_outlined,
              tone: StatusTone.warning,
            ),
            KpiCard(
              label: 'Pending cheques',
              value: data.pendingChequeTotal.formatted(),
              caption: data.pendingChequeCount == 1
                  ? '1 cheque not yet cleared'
                  : '${data.pendingChequeCount} cheques not yet cleared',
              icon: Icons.account_balance_outlined,
              tone: data.pendingChequeCount > 0
                  ? StatusTone.warning
                  : StatusTone.neutral,
            ),
          ],
        ),
        AppSpacing.gapXl,
        Text('Money owed to us', style: context.text.titleMedium),
        AppSpacing.gapMd,
        KpiGrid(
          children: [
            KpiCard(
              label: 'Total receivable',
              value: data.totalReceivable.formatted(),
              caption: 'Including opening balances',
              icon: Icons.account_balance_wallet_outlined,
              tone: data.totalReceivable.isPositive
                  ? StatusTone.danger
                  : StatusTone.neutral,
            ),
            KpiCard(
              label: 'From agents',
              value: data.receivableFromAgents.formatted(),
              caption: '${data.activeAgentCount} active agent(s)',
              icon: Icons.badge_outlined,
            ),
            KpiCard(
              label: 'From shops',
              value: data.receivableFromShops.formatted(),
              caption: '${data.activeShopCount} active shop(s)',
              icon: Icons.storefront_outlined,
            ),
            KpiCard(
              label: 'Unallocated advances',
              value: data.unallocatedAdvances.formatted(),
              caption: 'Received but not applied to an invoice',
              icon: Icons.savings_outlined,
              tone: data.unallocatedAdvances.isPositive
                  ? StatusTone.info
                  : StatusTone.neutral,
            ),
          ],
        ),
        AppSpacing.gapXl,
        Text('Stock on hand', style: context.text.titleMedium),
        AppSpacing.gapMd,
        KpiGrid(
          children: [
            KpiCard(
              label: 'Warehouse stock value',
              value: data.warehouseStockValue.formatted(),
              caption: 'At weighted average cost',
              icon: Icons.warehouse_outlined,
            ),
            KpiCard(
              label: 'Agent stock value',
              value: data.agentStockValue.formatted(),
              caption: 'Held by agents',
              icon: Icons.local_shipping_outlined,
            ),
            KpiCard(
              label: 'Shop stock value',
              value: data.shopStockValue.formatted(),
              caption: 'Held by shops',
              icon: Icons.storefront_outlined,
            ),
            KpiCard(
              label: 'Low stock products',
              value: data.lowStockCount.toString(),
              caption: 'At or below reorder level',
              icon: Icons.warning_amber_outlined,
              tone: data.lowStockCount > 0
                  ? StatusTone.warning
                  : StatusTone.success,
            ),
          ],
        ),
        AppSpacing.gapXl,
        Text(
          'This month (${DateFormat('MMMM yyyy').format(data.generatedAt.toLocal())})',
          style: context.text.titleMedium,
        ),
        AppSpacing.gapMd,
        KpiGrid(
          children: [
            KpiCard(
              label: 'Sales',
              value: data.monthSales.formatted(),
              icon: Icons.insert_chart_outlined,
              tone: StatusTone.info,
            ),
            KpiCard(
              label: 'Estimated gross profit',
              value: data.monthGrossProfit.formatted(),
              caption: 'Net sales less snapshotted cost',
              icon: Icons.show_chart,
              tone: data.monthGrossProfit.isNegative
                  ? StatusTone.danger
                  : StatusTone.success,
            ),
            KpiCard(
              label: 'Expenses',
              value: data.monthExpenses.formatted(),
              icon: Icons.receipt_long_outlined,
              tone: StatusTone.warning,
            ),
            KpiCard(
              label: 'Net profit',
              value: data.monthNetProfit.formatted(),
              caption: 'From the journal, after every expense',
              icon: Icons.account_balance_wallet_outlined,
              tone: data.monthNetProfit.isNegative
                  ? StatusTone.danger
                  : StatusTone.success,
            ),
          ],
        ),
        AppSpacing.gapXl,
        Text('Needs attention', style: context.text.titleMedium),
        AppSpacing.gapMd,
        KpiGrid(
          children: [
            KpiCard(
              label: 'Returns to inspect',
              value: '${data.returnsAwaitingInspection}',
              caption: data.hasInspectionBacklog
                  ? '${data.returnsAwaitingInspectionUnits} unit(s) in '
                        'transit, neither sellable nor creditable'
                  : 'Nothing waiting',
              icon: Icons.pending_actions_outlined,
              tone: data.hasInspectionBacklog
                  ? StatusTone.warning
                  : StatusTone.neutral,
            ),
            KpiCard(
              label: 'Credit owed to parties',
              value: data.unappliedCreditNotes.formatted(),
              caption: 'Posted credit notes not yet applied',
              icon: Icons.request_quote_outlined,
              tone: data.unappliedCreditNotes.isPositive
                  ? StatusTone.info
                  : StatusTone.neutral,
            ),
            KpiCard(
              label: 'Salaries owed',
              value: data.unpaidSalaries.formatted(),
              caption: 'Approved but not yet paid in full',
              icon: Icons.badge_outlined,
              tone: data.unpaidSalaries.isPositive
                  ? StatusTone.warning
                  : StatusTone.neutral,
            ),
            KpiCard(
              label: 'Damaged stock value',
              value: data.damagedStockValue.formatted(),
              caption: 'In quarantine, owned but not sellable',
              icon: Icons.report_problem_outlined,
              tone: data.damagedStockValue.isPositive
                  ? StatusTone.danger
                  : StatusTone.neutral,
            ),
          ],
        ),
        AppSpacing.gapXl,
        Text('Cash and advances', style: context.text.titleMedium),
        AppSpacing.gapMd,
        KpiGrid(
          children: [
            KpiCard(
              label: 'Petty cash float',
              value: data.pettyCashFloat.formatted(),
              caption: 'In the box now',
              icon: Icons.savings_outlined,
              tone: StatusTone.neutral,
            ),
            KpiCard(
              label: 'Employee advances',
              value: data.outstandingEmployeeAdvances.formatted(),
              caption: 'Recoverable from later salaries',
              icon: Icons.account_balance_wallet_outlined,
              tone: data.outstandingEmployeeAdvances.isPositive
                  ? StatusTone.info
                  : StatusTone.neutral,
            ),
            KpiCard(
              label: 'Unapplied receipts',
              value: data.unallocatedAdvances.formatted(),
              caption: 'Money held but not put against an invoice',
              icon: Icons.inbox_outlined,
              tone: StatusTone.neutral,
            ),
            KpiCard(
              label: 'Shop retail sales',
              value: data.monthRetailSales.formatted(),
              caption:
                  'This month, reported apart from the wholesale supply that '
                  'stocked them',
              icon: Icons.point_of_sale_outlined,
              tone: StatusTone.neutral,
            ),
          ],
        ),
        AppSpacing.gapXl,
        Text(
          'Figures read at '
          '${DateFormat('d MMM yyyy, HH:mm:ss').format(data.generatedAt.toLocal())}',
          style: context.text.bodySmall,
        ),
      ],
    );
  }
}

/// Shown while the database has no master data yet, so a new installation is
/// not a blank screen with nothing to do.
class _GettingStartedCard extends StatelessWidget {
  const _GettingStartedCard();

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Set up your business',
      subtitle:
          'The database is ready and empty. These are the next steps, in order.',
      leading: Icon(Icons.flag_outlined, color: context.colors.primary),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Step(
            index: 1,
            title: 'Record your business details',
            detail: 'Name, address and phone number, which print on invoices.',
            actionLabel: 'Open settings',
            onPressed: () => context.go(Routes.settings),
          ),
          _Step(
            index: 2,
            title: 'Add product categories',
            detail: 'Group the catalogue: chargers, cables, audio, power.',
            actionLabel: 'Open categories',
            onPressed: () => context.go(Routes.categories),
          ),
          _Step(
            index: 3,
            title: 'Add your products and their prices',
            detail: 'Cost, wholesale and selling price, plus reorder levels.',
            actionLabel: 'Open products',
            onPressed: () => context.go(Routes.products),
          ),
          _Step(
            index: 4,
            title: 'Add your agents',
            detail: 'Each agent gets their own stock location automatically.',
            actionLabel: 'Open agents',
            onPressed: () => context.go(Routes.agents),
          ),
          _Step(
            index: 5,
            title: 'Add the shops each agent supplies',
            detail: 'Shops also get their own stock location.',
            actionLabel: 'Open shops',
            onPressed: () => context.go(Routes.shops),
          ),
          const _Step(
            index: 6,
            title: 'Enter opening warehouse stock',
            detail:
                'Recorded as an opening stock document so the ledger balances '
                'from the first day.',
            phase: 3,
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.index,
    required this.title,
    required this.detail,
    this.actionLabel,
    this.onPressed,
    this.phase,
  });

  final int index;
  final String title;
  final String detail;
  final String? actionLabel;
  final VoidCallback? onPressed;
  final int? phase;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 24,
            width: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.colors.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$index',
              style: context.text.labelSmall?.copyWith(
                color: context.colors.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: context.text.titleSmall),
                const SizedBox(height: AppSpacing.xxs),
                Text(detail, style: context.text.bodySmall),
              ],
            ),
          ),
          AppSpacing.hGapMd,
          if (onPressed != null)
            OutlinedButton(onPressed: onPressed, child: Text(actionLabel!))
          else if (phase != null)
            StatusPill('Phase $phase', tone: StatusTone.neutral),
        ],
      ),
    );
  }
}
