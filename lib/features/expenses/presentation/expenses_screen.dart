import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/expenses/domain/expense_models.dart';
import 'package:venvo_core/features/payments/domain/payment_models.dart';

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
import '../../petty_cash/presentation/petty_cash_providers.dart';
import 'expense_providers.dart';

/// Daily expenses, with the category breakdown beside them.
///
/// The breakdown is on the same screen as the list because "what are we
/// spending it on?" is the question an expense report exists to answer, and
/// reading it off a list of vouchers is not an answer.
class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (!(user?.can(Permissions.expenseView) ?? false)) {
      return const PageScaffold(
        title: 'Expenses',
        child: EmptyState(
          icon: Icons.lock_outline,
          title: 'You do not have access to expenses',
        ),
      );
    }

    final canManage = user?.can(Permissions.expenseManage) ?? false;

    return PageScaffold(
      title: 'Expenses',
      description:
          'What the business spends, by category and by day. An expense paid '
          'out of the petty cash float reduces the float once; the cash '
          'movement is never recorded twice.',
      scrollable: false,
      actions: [
        if (canManage) ...[
          OutlinedButton.icon(
            onPressed: () => showExpenseCategoriesDialog(context),
            icon: const Icon(Icons.folder_outlined, size: 18),
            label: const Text('Categories'),
          ),
          FilledButton.icon(
            onPressed: () => _newExpense(context),
            icon: const Icon(Icons.receipt_outlined, size: 18),
            label: const Text('New expense'),
          ),
        ],
      ],
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Breakdown(),
          _Filters(),
          AppSpacing.gapLg,
          Expanded(child: _ExpenseTable()),
          AppSpacing.gapSm,
          _SummaryBar(),
        ],
      ),
    );
  }

  Future<void> _newExpense(BuildContext context) async {
    final posted = await ExpenseFormDialog.show(context);
    if (posted && context.mounted) {
      showSuccessSnackBar(context, 'Expense recorded.');
    }
  }
}

class _Breakdown extends ConsumerWidget {
  const _Breakdown();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totals = ref.watch(expenseTotalsProvider).valueOrNull;
    if (totals == null || totals.byCategory.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: SectionCard(
        title: 'Where the money went',
        subtitle:
            '${totals.total.formatted()} over ${totals.count} voucher(s)'
            '${totals.fromPettyCash.isZero ? '' : ', of which '
                      '${totals.fromPettyCash.formatted()} from petty cash'}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final row in totals.byCategory.take(8))
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(
                  children: [
                    SizedBox(
                      width: 200,
                      child: Text(
                        row.categoryName,
                        style: context.text.bodyMedium,
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: totals.total.isZero
                              ? 0
                              : row.total.cents / totals.total.cents,
                          minHeight: 8,
                          backgroundColor: context.colors.surfaceContainerHigh,
                        ),
                      ),
                    ),
                    AppSpacing.hGapMd,
                    SizedBox(
                      width: 130,
                      child: Text(
                        row.total.plain,
                        textAlign: TextAlign.right,
                        style: context.text.bodyMedium,
                      ),
                    ),
                    SizedBox(
                      width: 70,
                      child: Text(
                        formatBps(row.shareOf(totals.total)),
                        textAlign: TextAlign.right,
                        style: context.text.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            if (totals.byCategory.length > 8)
              Text(
                'and ${totals.byCategory.length - 8} more category(s).',
                style: context.text.bodySmall,
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
    final filter = ref.watch(expenseFilterProvider);
    final notifier = ref.read(expenseFilterProvider.notifier);
    final categories =
        ref.watch(expenseCategoriesProvider).valueOrNull ?? const [];

    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AppSearchField(
          hintText: 'Search voucher, description or category',
          width: 320,
          onChanged: (value) =>
              notifier.update((state) => state.copyWith(search: value)),
        ),
        SizedBox(
          width: 210,
          child: DropdownButtonFormField<int?>(
            initialValue: filter.categoryId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [
              const DropdownMenuItem<int?>(child: Text('All categories')),
              for (final category in categories)
                DropdownMenuItem<int?>(
                  value: category.id,
                  child: Text(category.name),
                ),
            ],
            onChanged: (value) => notifier.update(
              (state) => value == null
                  ? state.copyWith(clearCategory: true)
                  : state.copyWith(categoryId: value),
            ),
          ),
        ),
        SizedBox(
          width: 180,
          child: DropdownButtonFormField<PaymentMethod?>(
            initialValue: filter.paymentMethod,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Paid by'),
            items: [
              const DropdownMenuItem<PaymentMethod?>(child: Text('Any')),
              for (final method in const [
                PaymentMethod.cash,
                PaymentMethod.bankTransfer,
                PaymentMethod.cardOrDigital,
                PaymentMethod.cheque,
              ])
                DropdownMenuItem<PaymentMethod?>(
                  value: method,
                  child: Text(paymentMethodLabel(method)),
                ),
            ],
            onChanged: (value) => notifier.update(
              (state) => value == null
                  ? state.copyWith(clearMethod: true)
                  : state.copyWith(paymentMethod: value),
            ),
          ),
        ),
        SizedBox(
          width: 165,
          child: AppDateField(
            value: filter.from,
            label: 'From',
            onChanged: (value) => notifier.update(
              (state) => value == null
                  ? state.copyWith(clearFrom: true)
                  : state.copyWith(from: value),
            ),
          ),
        ),
        SizedBox(
          width: 165,
          child: AppDateField(
            value: filter.to,
            label: 'To',
            onChanged: (value) => notifier.update(
              (state) => value == null
                  ? state.copyWith(clearTo: true)
                  : state.copyWith(to: value),
            ),
          ),
        ),
        FilterChip(
          selected: filter.pettyCashOnly,
          label: const Text('From petty cash'),
          avatar: const Icon(Icons.savings_outlined, size: 16),
          onSelected: (value) =>
              notifier.update((state) => state.copyWith(pettyCashOnly: value)),
        ),
        if (filter.hasAnyFilter)
          TextButton.icon(
            onPressed: () => notifier.state = const ExpenseFilter(),
            icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
            label: const Text('Clear filters'),
          ),
      ],
    );
  }
}

class _ExpenseTable extends ConsumerWidget {
  const _ExpenseTable();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expenses = ref.watch(expensesProvider);
    final filter = ref.watch(expenseFilterProvider);

    return AsyncValueView<List<ExpenseSummary>>(
      value: expenses,
      builder: (context, rows) => SectionCard(
        padding: EdgeInsets.zero,
        fillHeight: true,
        child: AppDataTable<ExpenseSummary>(
          rows: rows,
          minWidth: 1100,
          empty: EmptyState(
            icon: Icons.receipt_outlined,
            title: filter.hasAnyFilter
                ? 'No expenses match these filters'
                : 'No expenses recorded yet',
            message: filter.hasAnyFilter
                ? null
                : 'Record what the business spends, and it shows up here and '
                      'in the profit and loss.',
          ),
          columns: [
            AppTableColumn<ExpenseSummary>(
              label: 'Voucher',
              width: 150,
              cell: (context, row) => TableTwoLineCell(
                primary: row.voucherNumber,
                secondary: DateFormat(
                  'd MMM yyyy',
                ).format(row.expenseDate.toLocal()),
              ),
            ),
            AppTableColumn<ExpenseSummary>(
              label: 'Category',
              flex: 2,
              cell: (context, row) => TableTextCell(row.categoryName),
            ),
            AppTableColumn<ExpenseSummary>(
              label: 'What for',
              flex: 4,
              cell: (context, row) => TableTwoLineCell(
                primary: row.description,
                secondary: row.paidByEmployeeName == null
                    ? (row.referenceNumber ?? '—')
                    : 'paid by ${row.paidByEmployeeName}',
              ),
            ),
            AppTableColumn<ExpenseSummary>(
              label: 'Paid by',
              width: 140,
              cell: (context, row) => TableTwoLineCell(
                primary: paymentMethodLabel(row.paymentMethod),
                secondary: row.fromPettyCash
                    ? 'petty cash ${row.pettyCashVoucherNumber}'
                    : '—',
              ),
            ),
            AppTableColumn<ExpenseSummary>(
              label: 'Amount',
              width: 130,
              numeric: true,
              cell: (context, row) => Text(
                row.amount.plain,
                textAlign: TextAlign.right,
                style: context.text.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  decoration: row.isCancelled
                      ? TextDecoration.lineThrough
                      : null,
                  color: row.isCancelled
                      ? context.colors.onSurfaceVariant
                      : null,
                ),
              ),
            ),
            AppTableColumn<ExpenseSummary>(
              label: 'Status',
              width: 110,
              cell: (context, row) => StatusPill(
                row.isCancelled ? 'Cancelled' : 'Posted',
                tone: row.isCancelled ? StatusTone.danger : StatusTone.success,
              ),
            ),
            AppTableColumn<ExpenseSummary>(
              label: '',
              width: 56,
              cell: (context, row) => _RowMenu(expense: row),
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
    final totals = ref.watch(expenseTotalsProvider).valueOrNull;
    if (totals == null || totals.count == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Wrap(
        spacing: AppSpacing.xl,
        runSpacing: AppSpacing.xs,
        children: [
          Text('${totals.count} voucher(s)', style: context.text.bodySmall),
          Text(
            'Total ${totals.total.formatted()}',
            style: context.text.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (!totals.fromPettyCash.isZero)
            Text(
              'From petty cash ${totals.fromPettyCash.formatted()}',
              style: context.text.bodySmall,
            ),
          if (totals.cancelledCount > 0)
            Text(
              '${totals.cancelledCount} cancelled, not counted',
              style: context.text.bodySmall,
            ),
        ],
      ),
    );
  }
}

class _RowMenu extends ConsumerWidget {
  const _RowMenu({required this.expense});

  final ExpenseSummary expense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage =
        ref.watch(currentUserProvider)?.can(Permissions.expenseManage) ?? false;
    if (!canManage || !expense.canBeCancelled) {
      return const SizedBox.shrink();
    }

    return PopupMenuButton<String>(
      tooltip: 'Actions',
      icon: const Icon(Icons.more_horiz, size: 18),
      onSelected: (value) async {
        if (value == 'cancel') {
          await _confirmAndCancel(context, ref, expense);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'cancel', child: Text('Cancel expense')),
      ],
    );
  }
}

Future<void> _confirmAndCancel(
  BuildContext context,
  WidgetRef ref,
  ExpenseSummary expense,
) async {
  final reasonController = TextEditingController();

  final cancelled = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AppFormDialog(
      title: 'Cancel ${expense.voucherNumber}?',
      subtitle: expense.fromPettyCash
          ? 'The voucher is kept and marked cancelled, and the money goes '
                'back into the petty cash float as its own entry.'
          : 'The voucher is kept and marked cancelled, and the accounting is '
                'taken back out.',
      submitLabel: 'Cancel the expense',
      onSubmit: () => ref
          .read(expenseServiceProvider)
          .cancelExpense(
            ref.read(requireCurrentUserProvider),
            expenseId: expense.id,
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
    showSuccessSnackBar(context, '${expense.voucherNumber} cancelled.');
  }
}

/// Records an expense.
class ExpenseFormDialog extends ConsumerStatefulWidget {
  const ExpenseFormDialog({super.key});

  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const ExpenseFormDialog(),
    );
    return result ?? false;
  }

  @override
  ConsumerState<ExpenseFormDialog> createState() => _ExpenseFormDialogState();
}

class _ExpenseFormDialogState extends ConsumerState<ExpenseFormDialog> {
  final _amount = TextEditingController();
  final _description = TextEditingController();
  final _reference = TextEditingController();
  final _notes = TextEditingController();

  int? _categoryId;
  int? _paidByEmployeeId;
  PaymentMethod _method = PaymentMethod.cash;
  bool _fromPettyCash = false;
  DateTime? _date;

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories =
        ref.watch(expenseCategoriesProvider).valueOrNull ?? const [];
    final employees =
        ref.watch(selectableEmployeesProvider).valueOrNull ?? const [];
    final float = ref.watch(pettyCashBalanceProvider).valueOrNull;

    return AppFormDialog(
      title: 'New expense',
      subtitle:
          'Posted straight away. There is no draft to forget about, and the '
          'accounting is written in the same breath.',
      submitLabel: 'Record the expense',
      width: 640,
      onSubmit: _submit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          FormSection(
            title: 'What was spent',
            children: [
              FormRow(
                children: [
                  AppDropdownField<int>(
                    label: 'Category',
                    isRequired: true,
                    value: _categoryId,
                    items: [
                      for (final category in categories)
                        DropdownMenuItem(
                          value: category.id,
                          child: Text(category.name),
                        ),
                    ],
                    onChanged: (value) => setState(() => _categoryId = value),
                  ),
                  AppMoneyField(
                    controller: _amount,
                    label: 'Amount',
                    isRequired: true,
                    allowZero: false,
                  ),
                ],
              ),
              AppTextField(
                controller: _description,
                label: 'What for',
                isRequired: true,
                maxLength: 500,
                maxLines: 2,
              ),
            ],
          ),
          AppSpacing.gapLg,
          FormSection(
            title: 'How it was paid',
            children: [
              FormRow(
                children: [
                  AppDropdownField<PaymentMethod>(
                    label: 'Method',
                    isRequired: true,
                    value: _method,
                    items: [
                      for (final method in const [
                        PaymentMethod.cash,
                        PaymentMethod.bankTransfer,
                        PaymentMethod.cardOrDigital,
                        PaymentMethod.cheque,
                      ])
                        DropdownMenuItem(
                          value: method,
                          child: Text(paymentMethodLabel(method)),
                        ),
                    ],
                    onChanged: (value) => setState(() {
                      _method = value ?? _method;
                      if (_method != PaymentMethod.cash) {
                        _fromPettyCash = false;
                      }
                    }),
                  ),
                  AppDateField(
                    label: 'Date',
                    value: _date ?? DateTime.now(),
                    onChanged: (value) => setState(() => _date = value),
                  ),
                ],
              ),
              if (_method == PaymentMethod.cash)
                CheckboxListTile(
                  value: _fromPettyCash,
                  onChanged: (value) =>
                      setState(() => _fromPettyCash = value ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Paid out of the petty cash float'),
                  subtitle: Text(
                    float == null
                        ? 'The float is reduced by one linked entry.'
                        : 'The float holds ${float.formatted()}. It is '
                              'reduced by one linked entry, so the cash is '
                              'not counted twice.',
                    style: context.text.bodySmall,
                  ),
                ),
              FormRow(
                children: [
                  AppDropdownField<int?>(
                    label: 'Spent by',
                    value: _paidByEmployeeId,
                    items: [
                      const DropdownMenuItem<int?>(child: Text('Not recorded')),
                      for (final employee in employees)
                        DropdownMenuItem<int?>(
                          value: employee.id,
                          child: Text(employee.name),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _paidByEmployeeId = value),
                  ),
                  AppTextField(
                    controller: _reference,
                    label: 'Reference',
                    maxLength: 64,
                    helperText: 'Bill number, cheque number, anything.',
                  ),
                ],
              ),
              AppTextField(
                controller: _notes,
                label: 'Notes',
                maxLines: 2,
                maxLength: 1000,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final categoryId = _categoryId;
    if (categoryId == null) {
      throw const FormatException('Choose a category.');
    }
    final amount = Money.tryParse(_amount.text);
    if (amount == null || !amount.isPositive) {
      throw const FormatException('Enter the amount spent.');
    }

    await ref
        .read(expenseServiceProvider)
        .postExpense(
          ref.read(requireCurrentUserProvider),
          ExpenseDraft(
            categoryId: categoryId,
            description: _description.text,
            amount: amount,
            paymentMethod: _method,
            expenseDate: _date,
            paidByEmployeeId: _paidByEmployeeId,
            referenceNumber: _reference.text,
            fromPettyCash: _fromPettyCash,
            notes: _notes.text,
          ),
        );
  }
}

/// Maintains the list of expense categories.
Future<void> showExpenseCategoriesDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (context) =>
        const Dialog(child: SizedBox(width: 640, child: _CategoriesBody())),
  );
}

class _CategoriesBody extends ConsumerStatefulWidget {
  const _CategoriesBody();

  @override
  ConsumerState<_CategoriesBody> createState() => _CategoriesBodyState();
}

class _CategoriesBodyState extends ConsumerState<_CategoriesBody> {
  final _name = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories =
        ref.watch(allExpenseCategoriesProvider).valueOrNull ?? const [];
    final canManage =
        ref.watch(currentUserProvider)?.can(Permissions.expenseManage) ?? false;

    return Padding(
      padding: AppSpacing.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Expense categories',
                  style: context.text.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          Text(
            'An archived category keeps its history: existing vouchers still '
            'show it, but nothing new can be booked against it.',
            style: context.text.bodySmall,
          ),
          AppSpacing.gapLg,
          if (_error != null) ...[
            Text(
              _error!,
              style: context.text.bodySmall?.copyWith(
                color: context.statusColors.danger,
              ),
            ),
            AppSpacing.gapSm,
          ],
          if (canManage)
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    controller: _name,
                    label: 'Add a category',
                    maxLength: 120,
                  ),
                ),
                AppSpacing.hGapMd,
                FilledButton(
                  onPressed: _busy ? null : _add,
                  child: const Text('Add'),
                ),
              ],
            ),
          AppSpacing.gapLg,
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: categories.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final category = categories[index];
                return ListTile(
                  dense: true,
                  title: Text(category.name),
                  subtitle: Text(
                    '${category.code}'
                    '${category.expenseCount == 0 ? '' : ' · '
                              '${category.expenseCount} voucher(s), '
                              '${category.total.formatted()}'}',
                  ),
                  trailing: category.isArchived
                      ? const StatusPill('Archived', tone: StatusTone.neutral)
                      : category.isSystem
                      ? const StatusPill('Standard', tone: StatusTone.info)
                      : canManage
                      ? TextButton(
                          onPressed: _busy ? null : () => _archive(category.id),
                          child: const Text('Archive'),
                        )
                      : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _add() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(expenseServiceProvider)
          .createCategory(
            ref.read(requireCurrentUserProvider),
            name: _name.text,
          );
      _name.clear();
    } catch (error) {
      setState(() => _error = ErrorView.describe(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _archive(int categoryId) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(expenseServiceProvider)
          .archiveCategory(
            ref.read(requireCurrentUserProvider),
            categoryId: categoryId,
          );
    } catch (error) {
      setState(() => _error = ErrorView.describe(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
