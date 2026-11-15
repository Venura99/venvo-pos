import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/payments/domain/payment_models.dart';
import 'package:venvo_core/features/salaries/domain/salary_models.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/app_data_table.dart';
import '../../../core/widgets/feedback_views.dart';
import '../../../core/widgets/form_dialog.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/status_pill.dart';
import '../../authentication/presentation/auth_controller.dart';
import '../../employees/presentation/employees_screen.dart';
import 'salary_detail_dialog.dart';
import 'salary_providers.dart';

/// Monthly salaries, with the advances they recover.
///
/// Outstanding advances are shown on the same screen because they are the
/// thing most easily got wrong: an advance is money the employee owes back,
/// and forgetting to recover it means paying the same month twice.
class SalariesScreen extends ConsumerWidget {
  const SalariesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (!(user?.can(Permissions.salaryView) ?? false)) {
      return const PageScaffold(
        title: 'Salaries',
        child: EmptyState(
          icon: Icons.lock_outline,
          title: 'You do not have access to salaries',
        ),
      );
    }

    final canManage = user?.can(Permissions.salaryManage) ?? false;

    return PageScaffold(
      title: 'Salaries',
      description:
          'A salary is computed as a draft, approved to become payable, then '
          'paid in one go or in parts. An advance is recovered by deduction '
          'at approval, so the wage is counted as a cost exactly once.',
      scrollable: false,
      actions: [
        if (canManage) ...[
          OutlinedButton.icon(
            onPressed: () => _newAdvance(context),
            icon: const Icon(Icons.payments_outlined, size: 18),
            label: const Text('Give an advance'),
          ),
          FilledButton.icon(
            onPressed: () => _newSalary(context),
            icon: const Icon(Icons.calculate_outlined, size: 18),
            label: const Text('Compute a salary'),
          ),
        ],
      ],
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AdvancesBanner(),
          _Filters(),
          AppSpacing.gapLg,
          Expanded(child: _SalaryTable()),
          AppSpacing.gapSm,
          _SummaryBar(),
        ],
      ),
    );
  }

  Future<void> _newSalary(BuildContext context) async {
    final created = await SalaryFormDialog.show(context);
    if (created && context.mounted) {
      showSuccessSnackBar(
        context,
        'Salary computed as a draft. Approve it to make it payable.',
      );
    }
  }

  Future<void> _newAdvance(BuildContext context) async {
    final given = await AdvanceFormDialog.show(context);
    if (given && context.mounted) {
      showSuccessSnackBar(context, 'Advance recorded.');
    }
  }
}

class _AdvancesBanner extends ConsumerWidget {
  const _AdvancesBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final advances =
        ref.watch(outstandingAdvancesProvider(null)).valueOrNull ?? const [];
    if (advances.isEmpty) return const SizedBox.shrink();

    final total = advances.map((row) => row.outstanding).sum;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: SectionCard(
        title:
            '${total.formatted()} of advances outstanding '
            'across ${advances.map((a) => a.employeeId).toSet().length} '
            'employee(s)',
        subtitle:
            'Money the business is owed back. It is recovered from a salary '
            'by deduction, oldest advance first.',
        leading: Icon(
          Icons.account_balance_wallet_outlined,
          color: context.statusColors.info,
        ),
        child: Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xs,
          children: [
            for (final row in advances.take(8))
              Chip(
                label: Text(
                  '${row.employeeName} · ${row.outstanding.formatted()}',
                ),
                visualDensity: VisualDensity.compact,
              ),
            if (advances.length > 8)
              Chip(
                label: Text('and ${advances.length - 8} more'),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ),
    );
  }
}

class _Filters extends ConsumerWidget {
  const _Filters();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(salaryFilterProvider);
    final notifier = ref.read(salaryFilterProvider.notifier);
    final employees =
        ref.watch(selectableEmployeesProvider).valueOrNull ?? const [];
    final periods = ref.watch(salaryPeriodsProvider).valueOrNull ?? const [];

    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AppSearchField(
          hintText: 'Search voucher or employee',
          width: 300,
          onChanged: (value) =>
              notifier.update((state) => state.copyWith(search: value)),
        ),
        SizedBox(
          width: 210,
          child: DropdownButtonFormField<int?>(
            initialValue: filter.employeeId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Employee'),
            items: [
              const DropdownMenuItem<int?>(child: Text('Everybody')),
              for (final employee in employees)
                DropdownMenuItem<int?>(
                  value: employee.id,
                  child: Text(employee.name),
                ),
            ],
            onChanged: (value) => notifier.update(
              (state) => value == null
                  ? state.copyWith(clearEmployee: true)
                  : state.copyWith(employeeId: value),
            ),
          ),
        ),
        SizedBox(
          width: 190,
          child: DropdownButtonFormField<String?>(
            initialValue:
                filter.periodYear == null || filter.periodMonth == null
                ? null
                : '${filter.periodYear}-${filter.periodMonth}',
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Period'),
            items: [
              const DropdownMenuItem<String?>(child: Text('All periods')),
              for (final period in periods)
                DropdownMenuItem<String?>(
                  value: '${period.year}-${period.month}',
                  child: Text(
                    '${salaryMonthName(period.month)} ${period.year}'
                    ' (${period.count})',
                  ),
                ),
            ],
            onChanged: (value) {
              if (value == null) {
                notifier.update(
                  (state) => state.copyWith(clearYear: true, clearMonth: true),
                );
                return;
              }
              final parts = value.split('-');
              notifier.update(
                (state) => state.copyWith(
                  periodYear: int.parse(parts[0]),
                  periodMonth: int.parse(parts[1]),
                ),
              );
            },
          ),
        ),
        SizedBox(
          width: 170,
          child: DropdownButtonFormField<SalaryStatus?>(
            initialValue: filter.status,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Status'),
            items: [
              const DropdownMenuItem<SalaryStatus?>(child: Text('Any status')),
              for (final status in SalaryStatus.values)
                DropdownMenuItem<SalaryStatus?>(
                  value: status,
                  child: Text(salaryStatusLabel(status)),
                ),
            ],
            onChanged: (value) => notifier.update(
              (state) => value == null
                  ? state.copyWith(clearStatus: true)
                  : state.copyWith(status: value),
            ),
          ),
        ),
        FilterChip(
          selected: filter.unpaidOnly,
          label: const Text('Still owed'),
          avatar: const Icon(Icons.schedule, size: 16),
          onSelected: (value) =>
              notifier.update((state) => state.copyWith(unpaidOnly: value)),
        ),
        if (filter.hasAnyFilter)
          TextButton.icon(
            onPressed: () => notifier.state = const SalaryFilter(),
            icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
            label: const Text('Clear filters'),
          ),
      ],
    );
  }
}

class _SalaryTable extends ConsumerWidget {
  const _SalaryTable();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salaries = ref.watch(salariesProvider);
    final filter = ref.watch(salaryFilterProvider);

    return AsyncValueView<List<SalarySummary>>(
      value: salaries,
      builder: (context, rows) => SectionCard(
        padding: EdgeInsets.zero,
        fillHeight: true,
        child: AppDataTable<SalarySummary>(
          rows: rows,
          minWidth: 1240,
          onRowTap: (row) => showSalaryDetail(context, ref, row.id),
          empty: EmptyState(
            icon: Icons.badge_outlined,
            title: filter.hasAnyFilter
                ? 'No salaries match these filters'
                : 'No salaries computed yet',
            message: filter.hasAnyFilter
                ? null
                : 'Compute a salary for a month, check it, then approve it.',
          ),
          columns: [
            AppTableColumn<SalarySummary>(
              label: 'Voucher',
              width: 150,
              cell: (context, row) => TableTwoLineCell(
                primary: row.voucherNumber,
                secondary: row.periodLabel,
              ),
            ),
            AppTableColumn<SalarySummary>(
              label: 'Employee',
              flex: 3,
              cell: (context, row) => TableTwoLineCell(
                primary: row.employeeName,
                secondary: row.designation ?? row.employeeCode,
              ),
            ),
            AppTableColumn<SalarySummary>(
              label: 'Earned',
              width: 120,
              numeric: true,
              cell: (context, row) => TableTextCell(row.earned.plain),
            ),
            AppTableColumn<SalarySummary>(
              label: 'Advance',
              width: 115,
              numeric: true,
              cell: (context, row) => Text(
                row.advanceDeducted.isZero ? '—' : row.advanceDeducted.plain,
                textAlign: TextAlign.right,
                style: context.text.bodyMedium?.copyWith(
                  color: row.advanceDeducted.isZero
                      ? context.colors.onSurfaceVariant
                      : context.statusColors.info,
                ),
              ),
            ),
            AppTableColumn<SalarySummary>(
              label: 'Net',
              width: 125,
              numeric: true,
              cell: (context, row) => Text(
                row.netSalary.plain,
                textAlign: TextAlign.right,
                style: context.text.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  decoration: row.isCancelled
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
            ),
            AppTableColumn<SalarySummary>(
              label: 'Paid',
              width: 120,
              numeric: true,
              cell: (context, row) =>
                  TableTextCell(row.paid.isZero ? '—' : row.paid.plain),
            ),
            AppTableColumn<SalarySummary>(
              label: 'Still owed',
              width: 120,
              numeric: true,
              cell: (context, row) => Text(
                row.outstanding.isZero ? '—' : row.outstanding.plain,
                textAlign: TextAlign.right,
                style: context.text.bodyMedium?.copyWith(
                  color: row.outstanding.isPositive
                      ? context.statusColors.warning
                      : null,
                ),
              ),
            ),
            AppTableColumn<SalarySummary>(
              label: 'Status',
              width: 120,
              cell: (context, row) => StatusPill(
                salaryStatusLabel(row.status),
                tone: switch (row.status) {
                  SalaryStatus.draft => StatusTone.neutral,
                  SalaryStatus.approved => StatusTone.info,
                  SalaryStatus.partiallyPaid => StatusTone.warning,
                  SalaryStatus.paid => StatusTone.success,
                  SalaryStatus.cancelled => StatusTone.danger,
                },
              ),
            ),
            AppTableColumn<SalarySummary>(
              label: '',
              width: 56,
              cell: (context, row) => _RowMenu(salary: row),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryBar extends ConsumerWidget {
  const _SummaryBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totals = ref.watch(salaryTotalsProvider).valueOrNull;
    if (totals == null) return const SizedBox.shrink();
    if (totals.count == 0 && totals.draftCount == 0) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Wrap(
        spacing: AppSpacing.xl,
        runSpacing: AppSpacing.xs,
        children: [
          Text('${totals.count} approved', style: context.text.bodySmall),
          if (totals.draftCount > 0)
            Text(
              '${totals.draftCount} draft(s), not yet payable',
              style: context.text.bodySmall,
            ),
          Text(
            'Wage bill ${totals.earned.formatted()}',
            style: context.text.bodySmall,
          ),
          if (!totals.advanceRecovered.isZero)
            Text(
              'Advances recovered ${totals.advanceRecovered.formatted()}',
              style: context.text.bodySmall?.copyWith(
                color: context.statusColors.info,
              ),
            ),
          Text(
            'Paid ${totals.paid.formatted()}',
            style: context.text.bodySmall,
          ),
          Text(
            'Still owed ${totals.outstanding.formatted()}',
            style: context.text.bodySmall?.copyWith(
              color: totals.outstanding.isPositive
                  ? context.statusColors.warning
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _RowMenu extends ConsumerWidget {
  const _RowMenu({required this.salary});

  final SalarySummary salary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage =
        ref.watch(currentUserProvider)?.can(Permissions.salaryManage) ?? false;

    return PopupMenuButton<String>(
      tooltip: 'Actions',
      icon: const Icon(Icons.more_horiz, size: 18),
      onSelected: (value) async {
        switch (value) {
          case 'view':
            await showSalaryDetail(context, ref, salary.id);
          case 'approve':
            await confirmAndApproveSalary(context, ref, salary);
          case 'pay':
            await showSalaryPaymentDialog(context, ref, salary);
          case 'cancel':
            await confirmAndCancelSalary(context, ref, salary);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'view', child: Text('View salary slip')),
        if (canManage && salary.isDraft)
          const PopupMenuItem(value: 'approve', child: Text('Approve')),
        if (canManage && salary.canBePaid)
          const PopupMenuItem(value: 'pay', child: Text('Pay')),
        if (canManage && salary.canBeCancelled) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'cancel', child: Text('Cancel salary')),
        ],
      ],
    );
  }
}

/// Computes a salary for one employee and month.
class SalaryFormDialog extends ConsumerStatefulWidget {
  const SalaryFormDialog({super.key});

  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const SalaryFormDialog(),
    );
    return result ?? false;
  }

  @override
  ConsumerState<SalaryFormDialog> createState() => _SalaryFormDialogState();
}

class _SalaryFormDialogState extends ConsumerState<SalaryFormDialog> {
  final _basic = TextEditingController();
  final _allowances = TextEditingController();
  final _bonus = TextEditingController();
  final _deductions = TextEditingController();
  final _cap = TextEditingController();
  final _notes = TextEditingController();

  int? _employeeId;
  late int _year;
  late int _month;
  bool _recoverAdvances = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
  }

  @override
  void dispose() {
    _basic.dispose();
    _allowances.dispose();
    _bonus.dispose();
    _deductions.dispose();
    _cap.dispose();
    _notes.dispose();
    super.dispose();
  }

  Money get _earned {
    final basic = Money.tryParse(_basic.text) ?? Money.zero;
    final allowances = Money.tryParse(_allowances.text) ?? Money.zero;
    final bonus = Money.tryParse(_bonus.text) ?? Money.zero;
    final deductions = Money.tryParse(_deductions.text) ?? Money.zero;
    return basic + allowances + bonus - deductions;
  }

  @override
  Widget build(BuildContext context) {
    final employees =
        ref.watch(selectableEmployeesProvider).valueOrNull ?? const [];
    final owed = _employeeId == null
        ? Money.zero
        : ref.watch(employeeAdvanceBalanceProvider(_employeeId!)).valueOrNull ??
              Money.zero;

    // The same arithmetic the service will apply, shown live so the figure on
    // screen is the figure that gets recorded.
    final earned = _earned;
    var recovery = Money.zero;
    if (_recoverAdvances && owed.isPositive && earned.isPositive) {
      recovery = owed < earned ? owed : earned;
      final cap = Money.tryParse(_cap.text);
      if (cap != null && cap.isPositive && cap < recovery) recovery = cap;
    }
    final net = earned - recovery;

    return AppFormDialog(
      title: 'Compute a salary',
      subtitle:
          'Saved as a draft. Nothing is owed and nothing is posted until it '
          'is approved.',
      submitLabel: 'Save the draft',
      width: 680,
      onSubmit: _submit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          FormSection(
            title: 'Who and when',
            children: [
              FormRow(
                children: [
                  AppDropdownField<int>(
                    label: 'Employee',
                    isRequired: true,
                    value: _employeeId,
                    items: [
                      for (final employee in employees)
                        DropdownMenuItem(
                          value: employee.id,
                          child: Text(
                            '${employee.name}'
                            '${employee.designation == null ? '' : ' · ${employee.designation}'}',
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(() {
                      _employeeId = value;
                      // The employee's standing basic salary is the usual
                      // starting point.
                      final employee = employees
                          .where((e) => e.id == value)
                          .firstOrNull;
                      if (employee != null && _basic.text.trim().isEmpty) {
                        final basic = Money(employee.basicSalaryCents);
                        if (!basic.isZero) {
                          _basic.text = (basic.cents / Money.minorPerMajor)
                              .toStringAsFixed(2);
                        }
                      }
                    }),
                  ),
                  AppDropdownField<int>(
                    label: 'Month',
                    isRequired: true,
                    value: _month,
                    items: [
                      for (var month = 1; month <= 12; month++)
                        DropdownMenuItem(
                          value: month,
                          child: Text(salaryMonthName(month)),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _month = value ?? _month),
                  ),
                  AppDropdownField<int>(
                    label: 'Year',
                    isRequired: true,
                    value: _year,
                    items: [
                      for (
                        var year = DateTime.now().year - 2;
                        year <= DateTime.now().year + 1;
                        year++
                      )
                        DropdownMenuItem(value: year, child: Text('$year')),
                    ],
                    onChanged: (value) =>
                        setState(() => _year = value ?? _year),
                  ),
                ],
              ),
            ],
          ),
          AppSpacing.gapLg,
          FormSection(
            title: 'The pay',
            children: [
              FormRow(
                children: [
                  AppMoneyField(
                    controller: _basic,
                    label: 'Basic',
                    isRequired: true,
                    allowZero: false,
                    onChanged: (_) => setState(() {}),
                  ),
                  AppMoneyField(
                    controller: _allowances,
                    label: 'Allowances',
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
              FormRow(
                children: [
                  AppMoneyField(
                    controller: _bonus,
                    label: 'Bonus',
                    onChanged: (_) => setState(() {}),
                  ),
                  AppMoneyField(
                    controller: _deductions,
                    label: 'Deductions',
                    helperText: 'Unpaid leave, fines, statutory deductions.',
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
            ],
          ),
          if (owed.isPositive) ...[
            AppSpacing.gapLg,
            FormSection(
              title: 'Advances outstanding: ${owed.formatted()}',
              description:
                  'Recovered by deduction from this salary, oldest advance '
                  'first. Cap it to spread the recovery over several months.',
              children: [
                SwitchListTile(
                  value: _recoverAdvances,
                  onChanged: (value) =>
                      setState(() => _recoverAdvances = value),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Recover advances from this salary'),
                ),
                if (_recoverAdvances)
                  AppMoneyField(
                    controller: _cap,
                    label: 'Recover at most',
                    helperText:
                        'Leave empty to recover as much as this salary can '
                        'stand.',
                    onChanged: (_) => setState(() {}),
                  ),
              ],
            ),
          ],
          AppSpacing.gapLg,
          _Preview(earned: earned, recovery: recovery, net: net, owed: owed),
          AppSpacing.gapLg,
          AppTextField(
            controller: _notes,
            label: 'Notes',
            maxLines: 2,
            maxLength: 1000,
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final employeeId = _employeeId;
    if (employeeId == null) {
      throw const FormatException('Choose an employee.');
    }
    final basic = Money.tryParse(_basic.text);
    if (basic == null || !basic.isPositive) {
      throw const FormatException('Enter the basic salary.');
    }

    final cap = Money.tryParse(_cap.text);
    await ref
        .read(salaryServiceProvider)
        .createSalary(
          ref.read(requireCurrentUserProvider),
          SalaryDraft(
            employeeId: employeeId,
            periodYear: _year,
            periodMonth: _month,
            basicSalary: basic,
            allowances: Money.tryParse(_allowances.text) ?? Money.zero,
            bonus: Money.tryParse(_bonus.text) ?? Money.zero,
            deductions: Money.tryParse(_deductions.text) ?? Money.zero,
            recoverAdvances: _recoverAdvances,
            advanceRecoveryCap: cap != null && cap.isPositive ? cap : null,
            notes: _notes.text,
          ),
        );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({
    required this.earned,
    required this.recovery,
    required this.net,
    required this.owed,
  });

  final Money earned;
  final Money recovery;
  final Money net;
  final Money owed;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _line(context, 'Earned', earned),
          if (recovery.isPositive)
            _line(context, 'Less advance recovered', -recovery),
          const Divider(),
          _line(context, 'Net salary', net, emphasise: true),
          if (owed.isPositive && (owed - recovery).isPositive)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                '${(owed - recovery).formatted()} of advances will still be '
                'outstanding after this salary.',
                style: context.text.bodySmall?.copyWith(
                  color: context.statusColors.info,
                ),
              ),
            ),
          if (net.isZero && earned.isPositive)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'The whole salary goes to the advance, so the employee takes '
                'home nothing this month.',
                style: context.text.bodySmall?.copyWith(
                  color: context.statusColors.warning,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _line(
    BuildContext context,
    String label,
    Money amount, {
    bool emphasise = false,
  }) {
    final style = emphasise
        ? context.text.titleMedium
        : context.text.bodyMedium;
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

/// Records an advance to an employee.
class AdvanceFormDialog extends ConsumerStatefulWidget {
  const AdvanceFormDialog({super.key});

  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AdvanceFormDialog(),
    );
    return result ?? false;
  }

  @override
  ConsumerState<AdvanceFormDialog> createState() => _AdvanceFormDialogState();
}

class _AdvanceFormDialogState extends ConsumerState<AdvanceFormDialog> {
  final _amount = TextEditingController();
  final _notes = TextEditingController();

  int? _employeeId;
  PaymentMethod _method = PaymentMethod.cash;
  DateTime? _date;

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final employees =
        ref.watch(selectableEmployeesProvider).valueOrNull ?? const [];
    final owed = _employeeId == null
        ? null
        : ref.watch(employeeAdvanceBalanceProvider(_employeeId!)).valueOrNull;

    return AppFormDialog(
      title: 'Give an advance',
      subtitle:
          'An advance is money the employee owes back, not a wage cost. It is '
          'recovered from a later salary by deduction.',
      submitLabel: 'Record the advance',
      width: 560,
      onSubmit: _submit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppDropdownField<int>(
            label: 'Employee',
            isRequired: true,
            value: _employeeId,
            helperText: owed == null || owed.isZero
                ? null
                : 'Already owes ${owed.formatted()} in advances.',
            items: [
              for (final employee in employees)
                DropdownMenuItem(
                  value: employee.id,
                  child: Text(employee.name),
                ),
            ],
            onChanged: (value) => setState(() => _employeeId = value),
          ),
          AppSpacing.gapLg,
          FormRow(
            children: [
              AppMoneyField(
                controller: _amount,
                label: 'Amount',
                isRequired: true,
                allowZero: false,
              ),
              AppDropdownField<PaymentMethod>(
                label: 'Paid by',
                isRequired: true,
                value: _method,
                items: [
                  for (final method in const [
                    PaymentMethod.cash,
                    PaymentMethod.bankTransfer,
                  ])
                    DropdownMenuItem(
                      value: method,
                      child: Text(paymentMethodLabel(method)),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _method = value ?? _method),
              ),
            ],
          ),
          AppSpacing.gapLg,
          AppDateField(
            label: 'Date',
            value: _date ?? DateTime.now(),
            onChanged: (value) => setState(() => _date = value),
          ),
          AppSpacing.gapLg,
          AppTextField(
            controller: _notes,
            label: 'Notes',
            maxLength: 500,
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final employeeId = _employeeId;
    if (employeeId == null) {
      throw const FormatException('Choose an employee.');
    }
    final amount = Money.tryParse(_amount.text);
    if (amount == null || !amount.isPositive) {
      throw const FormatException('Enter the amount.');
    }

    await ref
        .read(salaryServiceProvider)
        .recordAdvance(
          ref.read(requireCurrentUserProvider),
          employeeId: employeeId,
          amount: amount,
          method: _method,
          advanceDate: _date,
          notes: _notes.text,
        );
  }
}

/// Approves a draft salary, which is what makes it payable.
Future<void> confirmAndApproveSalary(
  BuildContext context,
  WidgetRef ref,
  SalarySummary salary,
) async {
  final approved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AppFormDialog(
      title: 'Approve ${salary.voucherNumber}?',
      subtitle:
          '${salary.netSalary.formatted()} becomes payable to '
          '${salary.employeeName}'
          '${salary.advanceDeducted.isZero ? '' : ', and '
                    '${salary.advanceDeducted.formatted()} of advances is '
                    'recovered by deduction'}.',
      submitLabel: 'Approve it',
      onSubmit: () => ref
          .read(salaryServiceProvider)
          .approveSalary(
            ref.read(requireCurrentUserProvider),
            salaryId: salary.id,
          ),
      child: Text(
        'The wage becomes an expense now, not when it is paid. Paying it '
        'later settles the debt rather than creating a second cost.',
        style: context.text.bodySmall,
      ),
    ),
  );

  if ((approved ?? false) && context.mounted) {
    showSuccessSnackBar(context, '${salary.voucherNumber} approved.');
  }
}

/// Pays a salary, in full or in part.
Future<void> showSalaryPaymentDialog(
  BuildContext context,
  WidgetRef ref,
  SalarySummary salary,
) async {
  final amountController = TextEditingController(
    text: (salary.outstanding.cents / Money.minorPerMajor).toStringAsFixed(2),
  );
  final referenceController = TextEditingController();
  var method = PaymentMethod.cash;
  DateTime? date;

  final paid = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AppFormDialog(
        title: 'Pay ${salary.voucherNumber}',
        subtitle:
            '${salary.outstanding.formatted()} is outstanding to '
            '${salary.employeeName}. A part payment leaves the rest owed.',
        submitLabel: 'Record the payment',
        onSubmit: () async {
          final amount = Money.tryParse(amountController.text);
          if (amount == null || !amount.isPositive) {
            throw const FormatException('Enter the amount paid.');
          }
          await ref
              .read(salaryServiceProvider)
              .paySalary(
                ref.read(requireCurrentUserProvider),
                salaryId: salary.id,
                amount: amount,
                method: method,
                paymentDate: date,
                referenceNumber: referenceController.text,
              );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AppMoneyField(
              controller: amountController,
              label: 'Amount',
              isRequired: true,
              allowZero: false,
              autofocus: true,
            ),
            AppSpacing.gapLg,
            FormRow(
              children: [
                AppDropdownField<PaymentMethod>(
                  label: 'Paid by',
                  isRequired: true,
                  value: method,
                  items: [
                    for (final option in const [
                      PaymentMethod.cash,
                      PaymentMethod.bankTransfer,
                      PaymentMethod.cheque,
                    ])
                      DropdownMenuItem(
                        value: option,
                        child: Text(paymentMethodLabel(option)),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => method = value ?? method),
                ),
                AppDateField(
                  label: 'Date',
                  value: date ?? DateTime.now(),
                  onChanged: (value) => setState(() => date = value),
                ),
              ],
            ),
            AppSpacing.gapLg,
            AppTextField(
              controller: referenceController,
              label: 'Reference',
              maxLength: 64,
            ),
          ],
        ),
      ),
    ),
  );

  amountController.dispose();
  referenceController.dispose();
  if ((paid ?? false) && context.mounted) {
    showSuccessSnackBar(context, 'Salary payment recorded.');
  }
}

/// Cancels a salary that has not been paid.
Future<void> confirmAndCancelSalary(
  BuildContext context,
  WidgetRef ref,
  SalarySummary salary,
) async {
  final reasonController = TextEditingController();

  final cancelled = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AppFormDialog(
      title: 'Cancel ${salary.voucherNumber}?',
      subtitle: salary.advanceDeducted.isZero
          ? 'The salary is kept and marked cancelled.'
          : 'The salary is kept and marked cancelled, and the '
                '${salary.advanceDeducted.formatted()} of advances it '
                'recovered goes back to being outstanding.',
      submitLabel: 'Cancel the salary',
      onSubmit: () => ref
          .read(salaryServiceProvider)
          .cancelSalary(
            ref.read(requireCurrentUserProvider),
            salaryId: salary.id,
            reason: reasonController.text,
          ),
      child: AppTextField(
        controller: reasonController,
        label: 'Reason',
        isRequired: true,
        autofocus: true,
        maxLines: 2,
        maxLength: 500,
      ),
    ),
  );

  reasonController.dispose();
  if ((cancelled ?? false) && context.mounted) {
    showSuccessSnackBar(context, '${salary.voucherNumber} cancelled.');
  }
}
