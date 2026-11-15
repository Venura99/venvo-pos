import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/finance/domain/finance_models.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/app_data_table.dart';
import '../../../core/widgets/feedback_views.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/kpi_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/status_pill.dart';
import '../../authentication/presentation/auth_controller.dart';
import 'finance_providers.dart';

/// The double-entry journal behind every figure in the application.
///
/// Three views of the same rows: the profit and loss for the period, the
/// trial balance that proves it adds up, and the journal itself where any
/// figure can be traced back to the invoice, payment, expense or salary that
/// produced it.
class FinancialLedgerScreen extends ConsumerStatefulWidget {
  const FinancialLedgerScreen({super.key});

  @override
  ConsumerState<FinancialLedgerScreen> createState() =>
      _FinancialLedgerScreenState();
}

class _FinancialLedgerScreenState extends ConsumerState<FinancialLedgerScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (!(user?.can(Permissions.financialLedgerView) ?? false)) {
      return const PageScaffold(
        title: 'Financial Ledger',
        child: EmptyState(
          icon: Icons.lock_outline,
          title: 'You do not have access to the financial ledger',
        ),
      );
    }

    return PageScaffold(
      title: 'Financial Ledger',
      description:
          'Every business event posts a balanced batch of double-entry rows. '
          'A cheque receipt debits Cheques in Clearing, not Cash; money '
          'received but not applied to an invoice is a liability, not income. '
          'That is what stops the same money being counted twice.',
      scrollable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _UnbalancedWarning(),
          const _PeriodBar(),
          AppSpacing.gapLg,
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                value: 0,
                label: Text('Profit and loss'),
                icon: Icon(Icons.trending_up, size: 18),
              ),
              ButtonSegment(
                value: 1,
                label: Text('Trial balance'),
                icon: Icon(Icons.balance, size: 18),
              ),
              ButtonSegment(
                value: 2,
                label: Text('Journal'),
                icon: Icon(Icons.menu_book_outlined, size: 18),
              ),
            ],
            selected: {_tab},
            onSelectionChanged: (selection) =>
                setState(() => _tab = selection.first),
          ),
          AppSpacing.gapLg,
          Expanded(
            child: switch (_tab) {
              0 => const _ProfitAndLossView(),
              1 => const _TrialBalanceView(),
              _ => const _JournalView(),
            },
          ),
        ],
      ),
    );
  }
}

class _UnbalancedWarning extends ConsumerWidget {
  const _UnbalancedWarning();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final batches =
        ref.watch(unbalancedBatchesProvider).valueOrNull ?? const [];
    if (batches.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: SectionCard(
        title: '${batches.length} journal batch(es) do not balance',
        subtitle:
            'Posting makes this impossible, so something has written to the '
            'journal without going through the posting service. The figures '
            'on this screen cannot be trusted until it is resolved.',
        leading: Icon(Icons.error_outline, color: context.statusColors.danger),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final batch in batches.take(5))
              Text(
                '${batch.batchId}: debits ${batch.debits.formatted()} '
                'against credits ${batch.credits.formatted()} '
                '(out by ${batch.difference.abs.formatted()})',
                style: context.text.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

class _PeriodBar extends ConsumerWidget {
  const _PeriodBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(financePeriodProvider);
    final notifier = ref.read(financePeriodProvider.notifier);
    final now = DateTime.now();

    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 170,
          child: AppDateField(
            value: period.from,
            label: 'From',
            onChanged: (value) =>
                notifier.state = FinancePeriod(from: value, to: period.to),
          ),
        ),
        SizedBox(
          width: 170,
          child: AppDateField(
            value: period.to,
            label: 'To',
            onChanged: (value) =>
                notifier.state = FinancePeriod(from: period.from, to: value),
          ),
        ),
        OutlinedButton(
          onPressed: () => notifier.state = FinancePeriod(
            from: DateTime(now.year, now.month),
            to: DateTime(
              now.year,
              now.month + 1,
            ).subtract(const Duration(days: 1)),
          ),
          child: const Text('This month'),
        ),
        OutlinedButton(
          onPressed: () => notifier.state = FinancePeriod(
            from: DateTime(now.year),
            to: DateTime(now.year + 1).subtract(const Duration(days: 1)),
          ),
          child: const Text('This year'),
        ),
        if (period.from != null || period.to != null)
          TextButton.icon(
            onPressed: () => notifier.state = const FinancePeriod(),
            icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
            label: const Text('All time'),
          ),
      ],
    );
  }
}

class _ProfitAndLossView extends ConsumerWidget {
  const _ProfitAndLossView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncValueView<ProfitAndLoss>(
      value: ref.watch(profitAndLossProvider),
      builder: (context, report) => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KpiGrid(
              children: [
                KpiCard(
                  label: 'Revenue',
                  value: report.revenue.formatted(),
                  caption: 'Sales less discounts and returns',
                  icon: Icons.point_of_sale_outlined,
                ),
                KpiCard(
                  label: 'Gross profit',
                  value: report.grossProfit.formatted(),
                  caption: report.revenue.isZero
                      ? 'No sales in this period'
                      : '${formatBps(report.grossMarginBps)} margin',
                  icon: Icons.trending_up,
                  tone: report.grossProfit.isNegative
                      ? StatusTone.danger
                      : StatusTone.success,
                ),
                KpiCard(
                  label: 'Overheads',
                  value: report.overheads.formatted(),
                  caption: 'Expenses, salaries and write-offs',
                  icon: Icons.receipt_outlined,
                  tone: StatusTone.warning,
                ),
                KpiCard(
                  label: 'Net profit',
                  value: report.netProfit.formatted(),
                  caption: report.isProfitable
                      ? 'In profit for this period'
                      : 'At a loss for this period',
                  icon: Icons.account_balance_outlined,
                  tone: report.isProfitable
                      ? StatusTone.success
                      : StatusTone.danger,
                ),
              ],
            ),
            AppSpacing.gapLg,
            SectionCard(
              title: 'Profit and loss',
              subtitle:
                  'Read from the journal, so it agrees with the trial '
                  'balance by construction.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _line(context, 'Sales at full price', report.grossSales),
                  if (!report.discounts.isZero)
                    _line(context, 'Discounts given', -report.discounts),
                  if (!report.returns.isZero)
                    _line(context, 'Goods returned', -report.returns),
                  const Divider(),
                  _line(context, 'Revenue', report.revenue, emphasise: true),
                  AppSpacing.gapSm,
                  _line(context, 'Cost of goods sold', -report.costOfGoodsSold),
                  const Divider(),
                  _line(
                    context,
                    'Gross profit',
                    report.grossProfit,
                    emphasise: true,
                  ),
                  AppSpacing.gapSm,
                  if (!report.operatingExpenses.isZero)
                    _line(
                      context,
                      'Operating expenses',
                      -report.operatingExpenses,
                    ),
                  if (!report.salaryExpense.isZero)
                    _line(context, 'Salaries', -report.salaryExpense),
                  if (!report.stockWriteOff.isZero)
                    _line(context, 'Stock written off', -report.stockWriteOff),
                  if (!report.otherExpenses.isZero)
                    _line(context, 'Other expenses', -report.otherExpenses),
                  const Divider(),
                  _line(
                    context,
                    'Net profit',
                    report.netProfit,
                    emphasise: true,
                    tone: report.isProfitable
                        ? context.statusColors.success
                        : context.statusColors.danger,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(
    BuildContext context,
    String label,
    Money amount, {
    bool emphasise = false,
    Color? tone,
  }) {
    final style =
        (emphasise ? context.text.titleMedium : context.text.bodyMedium)
            ?.copyWith(color: tone);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs / 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(amount.formatted(), style: style),
        ],
      ),
    );
  }
}

class _TrialBalanceView extends ConsumerWidget {
  const _TrialBalanceView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncValueView<TrialBalance>(
      value: ref.watch(trialBalanceProvider),
      builder: (context, balance) => SectionCard(
        title: balance.isBalanced
            ? 'The books balance'
            : 'The books do not balance',
        subtitle:
            'Debits ${balance.totalDebits.formatted()} against credits '
            '${balance.totalCredits.formatted()}. The two agreeing is the '
            'proof that every posting balanced.',
        leading: Icon(
          balance.isBalanced ? Icons.verified_outlined : Icons.error_outline,
          color: balance.isBalanced
              ? context.statusColors.success
              : context.statusColors.danger,
        ),
        padding: EdgeInsets.zero,
        fillHeight: true,
        child: AppDataTable<TrialBalanceRow>(
          rows: balance.rows,
          minWidth: 820,
          empty: const EmptyState(
            icon: Icons.balance,
            title: 'Nothing posted in this period',
            message:
                'The journal fills up as invoices, payments, expenses and '
                'salaries are recorded.',
          ),
          columns: [
            AppTableColumn<TrialBalanceRow>(
              label: 'Account',
              flex: 4,
              cell: (context, row) => TableTwoLineCell(
                primary: row.accountName,
                secondary: row.accountCode,
              ),
            ),
            AppTableColumn<TrialBalanceRow>(
              label: 'Type',
              width: 130,
              cell: (context, row) =>
                  TableTextCell(accountTypeLabel(row.accountType), muted: true),
            ),
            AppTableColumn<TrialBalanceRow>(
              label: 'Debits',
              width: 150,
              numeric: true,
              cell: (context, row) =>
                  TableTextCell(row.debits.isZero ? '—' : row.debits.plain),
            ),
            AppTableColumn<TrialBalanceRow>(
              label: 'Credits',
              width: 150,
              numeric: true,
              cell: (context, row) =>
                  TableTextCell(row.credits.isZero ? '—' : row.credits.plain),
            ),
            AppTableColumn<TrialBalanceRow>(
              label: 'Balance',
              width: 160,
              numeric: true,
              cell: (context, row) => Text(
                row.naturalBalance.plain,
                textAlign: TextAlign.right,
                style: context.text.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: row.naturalBalance.isNegative
                      ? context.statusColors.warning
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JournalView extends ConsumerWidget {
  const _JournalView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(financialLedgerFilterProvider);
    final notifier = ref.read(financialLedgerFilterProvider.notifier);
    final balance = ref.watch(trialBalanceProvider).valueOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            AppSearchField(
              hintText: 'Search description, batch or account',
              width: 320,
              onChanged: (value) =>
                  notifier.update((state) => state.copyWith(search: value)),
            ),
            SizedBox(
              width: 240,
              child: DropdownButtonFormField<String?>(
                initialValue: filter.accountCode,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Account'),
                items: [
                  const DropdownMenuItem<String?>(child: Text('All accounts')),
                  for (final row in balance?.rows ?? const <TrialBalanceRow>[])
                    DropdownMenuItem<String?>(
                      value: row.accountCode,
                      child: Text('${row.accountCode} ${row.accountName}'),
                    ),
                ],
                onChanged: (value) => notifier.update(
                  (state) => value == null
                      ? state.copyWith(clearAccount: true)
                      : state.copyWith(accountCode: value),
                ),
              ),
            ),
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<EntityKind?>(
                initialValue: filter.sourceKind,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Caused by'),
                items: [
                  const DropdownMenuItem<EntityKind?>(child: Text('Anything')),
                  for (final kind in const [
                    EntityKind.invoice,
                    EntityKind.payment,
                    EntityKind.cheque,
                    EntityKind.creditNote,
                    EntityKind.stockDocument,
                    EntityKind.expense,
                    EntityKind.pettyCashEntry,
                    EntityKind.salary,
                    EntityKind.salaryPayment,
                    EntityKind.employeeAdvance,
                  ])
                    DropdownMenuItem<EntityKind?>(
                      value: kind,
                      child: Text(journalSourceLabel(kind)),
                    ),
                ],
                onChanged: (value) => notifier.update(
                  (state) => value == null
                      ? state.copyWith(clearSourceKind: true)
                      : state.copyWith(sourceKind: value),
                ),
              ),
            ),
            if (filter.hasAnyFilter)
              TextButton.icon(
                onPressed: () => notifier.state = const FinancialLedgerFilter(),
                icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
                label: const Text('Clear filters'),
              ),
          ],
        ),
        AppSpacing.gapLg,
        Expanded(
          child: AsyncValueView<List<JournalRow>>(
            value: ref.watch(journalProvider),
            builder: (context, rows) => SectionCard(
              padding: EdgeInsets.zero,
              fillHeight: true,
              child: AppDataTable<JournalRow>(
                rows: rows,
                minWidth: 1120,
                empty: EmptyState(
                  icon: Icons.menu_book_outlined,
                  title: filter.hasAnyFilter
                      ? 'No journal rows match these filters'
                      : 'The journal is empty',
                  message: filter.hasAnyFilter
                      ? null
                      : 'It fills up as business is recorded.',
                ),
                columns: [
                  AppTableColumn<JournalRow>(
                    label: 'Batch',
                    width: 150,
                    cell: (context, row) => TableTwoLineCell(
                      primary: row.batchId,
                      secondary: DateFormat(
                        'd MMM yyyy',
                      ).format(row.entryDate.toLocal()),
                    ),
                  ),
                  AppTableColumn<JournalRow>(
                    label: 'Account',
                    flex: 3,
                    cell: (context, row) => TableTwoLineCell(
                      primary: row.accountName,
                      secondary: row.accountCode,
                    ),
                  ),
                  AppTableColumn<JournalRow>(
                    label: 'Description',
                    flex: 4,
                    cell: (context, row) => TableTwoLineCell(
                      primary: row.description,
                      secondary: journalSourceLabel(row.sourceKind),
                    ),
                  ),
                  AppTableColumn<JournalRow>(
                    label: 'Debit',
                    width: 140,
                    numeric: true,
                    cell: (context, row) => Text(
                      row.debit.isZero ? '—' : row.debit.plain,
                      textAlign: TextAlign.right,
                      style: context.text.bodyMedium,
                    ),
                  ),
                  AppTableColumn<JournalRow>(
                    label: 'Credit',
                    width: 140,
                    numeric: true,
                    cell: (context, row) => Text(
                      row.credit.isZero ? '—' : row.credit.plain,
                      textAlign: TextAlign.right,
                      style: context.text.bodyMedium,
                    ),
                  ),
                  AppTableColumn<JournalRow>(
                    label: '',
                    width: 110,
                    cell: (context, row) => row.isReversal
                        ? const StatusPill('Reversal', tone: StatusTone.warning)
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
