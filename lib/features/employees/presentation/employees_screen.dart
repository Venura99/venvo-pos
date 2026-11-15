import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/employees/api/employee_api.dart';
import 'package:venvo_core/features/employees/domain/employee_models.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/app_data_table.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/feedback_views.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/status_pill.dart';
import '../../authentication/presentation/auth_controller.dart';
import 'employee_form.dart';

final employeeRepositoryProvider = Provider<EmployeeApi>(
  (ref) => EmployeeApi(ref.watch(apiClientProvider)),
);

final employeeFilterProvider = StateProvider<EmployeeFilter>(
  (ref) => const EmployeeFilter(),
);

final employeesProvider = StreamProvider<List<EmployeeListItem>>((ref) {
  return ref
      .watch(employeeRepositoryProvider)
      .watchEmployees(ref.watch(employeeFilterProvider));
});

/// Active employees, for the pickers on expense and salary documents.
final selectableEmployeesProvider = FutureProvider((ref) {
  // Re-resolved whenever the list changes, so a newly added employee is
  // immediately selectable.
  ref.watch(employeesProvider);
  return ref.watch(employeeRepositoryProvider).selectableEmployees();
});

final employeeDesignationsProvider = StreamProvider<List<String>>((ref) {
  return ref.watch(employeeRepositoryProvider).watchDesignations();
});

class EmployeesScreen extends ConsumerWidget {
  const EmployeesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (!(user?.can(Permissions.employeesView) ?? false)) {
      return const PageScaffold(
        title: 'Employees',
        child: EmptyState(
          icon: Icons.lock_outline,
          title: 'You do not have access to employees',
        ),
      );
    }

    final canManage = user?.can(Permissions.employeesManage) ?? false;
    final employees = ref.watch(employeesProvider);
    final filter = ref.watch(employeeFilterProvider);
    final designations =
        ref.watch(employeeDesignationsProvider).valueOrNull ?? const [];
    final today = ref.watch(clockProvider).nowUtc();

    return PageScaffold(
      title: 'Employees',
      description:
          'Staff records feed the salary and expense modules. Advances given '
          'and salaries still owed are shown here.',
      scrollable: false,
      actions: [
        if (canManage)
          FilledButton.icon(
            onPressed: () => _openForm(context, ref, null),
            icon: const Icon(Icons.person_add_alt_outlined, size: 18),
            label: const Text('Add employee'),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AppSearchField(
                hintText: 'Search name, code, phone or designation',
                width: 340,
                onChanged: (value) => ref
                    .read(employeeFilterProvider.notifier)
                    .update((state) => state.copyWith(search: value)),
              ),
              if (designations.isNotEmpty)
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<String?>(
                    initialValue: filter.designation,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Designation'),
                    items: [
                      const DropdownMenuItem<String?>(child: Text('All')),
                      for (final designation in designations)
                        DropdownMenuItem<String?>(
                          value: designation,
                          child: Text(designation),
                        ),
                    ],
                    onChanged: (value) => ref
                        .read(employeeFilterProvider.notifier)
                        .update(
                          (state) => value == null
                              ? state.copyWith(clearDesignation: true)
                              : state.copyWith(designation: value),
                        ),
                  ),
                ),
              FilterChip(
                selected: filter.includeInactive,
                label: const Text('Include inactive'),
                onSelected: (value) => ref
                    .read(employeeFilterProvider.notifier)
                    .update((state) => state.copyWith(includeInactive: value)),
              ),
              FilterChip(
                selected: filter.includeArchived,
                label: const Text('Include archived'),
                onSelected: (value) => ref
                    .read(employeeFilterProvider.notifier)
                    .update((state) => state.copyWith(includeArchived: value)),
              ),
            ],
          ),
          AppSpacing.gapLg,
          Expanded(
            child: AsyncValueView<List<EmployeeListItem>>(
              value: employees,
              builder: (context, data) => SectionCard(
                padding: EdgeInsets.zero,
                fillHeight: true,
                child: AppDataTable<EmployeeListItem>(
                  rows: data,
                  minWidth: 1020,
                  onRowTap: canManage
                      ? (employee) => _openForm(context, ref, employee)
                      : null,
                  empty: EmptyState(
                    icon: Icons.groups_outlined,
                    title: filter.hasAnyFilter
                        ? 'No employees match these filters'
                        : 'No employees yet',
                    message: filter.hasAnyFilter
                        ? null
                        : 'Add your staff so expenses and salaries can be '
                              'recorded against them.',
                    action: canManage && !filter.hasAnyFilter
                        ? FilledButton.icon(
                            onPressed: () => _openForm(context, ref, null),
                            icon: const Icon(
                              Icons.person_add_alt_outlined,
                              size: 18,
                            ),
                            label: const Text('Add employee'),
                          )
                        : null,
                  ),
                  columns: [
                    AppTableColumn<EmployeeListItem>(
                      label: 'Employee',
                      flex: 3,
                      cell: (context, row) => TableTwoLineCell(
                        primary: row.name,
                        secondary: row.phone == null
                            ? row.code
                            : '${row.code} · ${row.phone}',
                      ),
                    ),
                    AppTableColumn<EmployeeListItem>(
                      label: 'Designation',
                      flex: 2,
                      cell: (context, row) => TableTextCell(
                        row.designation ?? '—',
                        muted: row.designation == null,
                      ),
                    ),
                    AppTableColumn<EmployeeListItem>(
                      label: 'Joined',
                      width: 130,
                      cell: (context, row) {
                        if (row.joiningDate == null) {
                          return const TableTextCell('—', muted: true);
                        }
                        final years = row.yearsOfService(today);
                        return TableTwoLineCell(
                          primary: DateFormat(
                            'd MMM yyyy',
                          ).format(row.joiningDate!.toLocal()),
                          secondary: years == null
                              ? ''
                              : years == 1
                              ? '1 year'
                              : '$years years',
                        );
                      },
                    ),
                    AppTableColumn<EmployeeListItem>(
                      label: 'Basic salary',
                      width: 120,
                      numeric: true,
                      cell: (context, row) =>
                          TableTextCell(row.basicSalary.plain),
                    ),
                    AppTableColumn<EmployeeListItem>(
                      label: 'Advances due',
                      width: 120,
                      numeric: true,
                      tooltip:
                          'Advances given and not yet recovered from a '
                          'salary',
                      cell: (context, row) => Text(
                        row.outstandingAdvances.isZero
                            ? '—'
                            : row.outstandingAdvances.plain,
                        style: context.text.bodyMedium?.copyWith(
                          color: row.outstandingAdvances.isZero
                              ? context.colors.onSurfaceVariant
                              : context.statusColors.warning,
                        ),
                      ),
                    ),
                    AppTableColumn<EmployeeListItem>(
                      label: 'Salary owed',
                      width: 115,
                      numeric: true,
                      tooltip: 'Approved salaries not yet fully paid',
                      cell: (context, row) => Text(
                        row.unpaidSalaryTotal.isZero
                            ? '—'
                            : row.unpaidSalaryTotal.plain,
                        style: context.text.bodyMedium?.copyWith(
                          color: row.unpaidSalaryTotal.isZero
                              ? context.colors.onSurfaceVariant
                              : context.statusColors.danger,
                        ),
                      ),
                    ),
                    AppTableColumn<EmployeeListItem>(
                      label: 'Status',
                      width: 100,
                      cell: (context, row) => StatusPill.entity(row.status),
                    ),
                    AppTableColumn<EmployeeListItem>(
                      label: '',
                      width: 56,
                      cell: (context, row) => canManage
                          ? _RowMenu(employee: row)
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AppSpacing.gapSm,
          _SummaryBar(employees: employees.valueOrNull ?? const []),
        ],
      ),
    );
  }

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref,
    EmployeeListItem? existing,
  ) async {
    final saved = await EmployeeFormDialog.show(context, existing: existing);
    if (saved && context.mounted) {
      showSuccessSnackBar(
        context,
        existing == null ? 'Employee added.' : 'Employee saved.',
      );
    }
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.employees});

  final List<EmployeeListItem> employees;

  @override
  Widget build(BuildContext context) {
    if (employees.isEmpty) return const SizedBox.shrink();

    final payroll = employees
        .where((e) => e.isActive)
        .map((e) => e.basicSalary)
        .sum;
    final advances = employees.map((e) => e.outstandingAdvances).sum;
    final owed = employees.map((e) => e.unpaidSalaryTotal).sum;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Wrap(
        spacing: AppSpacing.xl,
        runSpacing: AppSpacing.xs,
        children: [
          Text(
            employees.length == 1
                ? '1 employee'
                : '${employees.length} employees',
            style: context.text.bodySmall,
          ),
          Text(
            'Monthly basic payroll ${payroll.formatted()}',
            style: context.text.bodySmall,
          ),
          if (!advances.isZero)
            Text(
              'Advances outstanding ${advances.formatted()}',
              style: context.text.bodySmall?.copyWith(
                color: context.statusColors.warning,
              ),
            ),
          if (!owed.isZero)
            Text(
              'Salary owed ${owed.formatted()}',
              style: context.text.bodySmall?.copyWith(
                color: context.statusColors.danger,
              ),
            ),
        ],
      ),
    );
  }
}

class _RowMenu extends ConsumerWidget {
  const _RowMenu({required this.employee});

  final EmployeeListItem employee;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Actions',
      icon: const Icon(Icons.more_horiz, size: 18),
      onSelected: (value) => _handle(context, ref, value),
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'edit', child: Text('Edit')),
        const PopupMenuDivider(),
        if (employee.isArchived)
          const PopupMenuItem(value: 'restore', child: Text('Restore'))
        else
          const PopupMenuItem(value: 'archive', child: Text('Archive')),
      ],
    );
  }

  Future<void> _handle(
    BuildContext context,
    WidgetRef ref,
    String action,
  ) async {
    final repository = ref.read(employeeRepositoryProvider);
    final actor = ref.read(requireCurrentUserProvider);

    try {
      switch (action) {
        case 'edit':
          await EmployeeFormDialog.show(context, existing: employee);
        case 'archive':
          final confirmed = await ConfirmDialog.show(
            context,
            title: 'Archive ${employee.name}?',
            message: employee.hasOpenBalances
                ? 'They still have open balances. Archiving is allowed so a '
                      'departure can be recorded, and the balances stay on the '
                      'record.'
                : 'They will not be offered on new vouchers. Their salary '
                      'history is kept.',
            details: [
              if (!employee.outstandingAdvances.isZero)
                'Advances not recovered: ${employee.outstandingAdvances}',
              if (!employee.unpaidSalaryTotal.isZero)
                'Salary still owed: ${employee.unpaidSalaryTotal}',
              '${employee.salaryRecordCount} salary record(s)',
            ],
            confirmLabel: 'Archive',
            isDestructive: employee.hasOpenBalances,
            icon: Icons.archive_outlined,
          );
          if (!confirmed) return;
          await repository.archive(actor, employee.id);
          if (context.mounted) {
            showSuccessSnackBar(context, 'Employee archived.');
          }
        case 'restore':
          await repository.restore(actor, employee.id);
          if (context.mounted) {
            showSuccessSnackBar(context, 'Employee restored.');
          }
      }
    } catch (error) {
      if (context.mounted) showFailureSnackBar(context, error);
    }
  }
}
