import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/petty_cash/domain/petty_cash_models.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/app_data_table.dart';
import '../../../core/widgets/feedback_views.dart';
import '../../../core/widgets/form_dialog.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/kpi_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/status_pill.dart';
import '../../authentication/presentation/auth_controller.dart';
import '../../employees/presentation/employees_screen.dart';
import 'petty_cash_providers.dart';

/// The petty cash float and its book.
///
/// The float is the number that matters, so it leads. Each row carries the
/// balance as it stood after it, which is what makes the book readable as a
/// cash book rather than as a list of amounts.
class PettyCashScreen extends ConsumerWidget {
  const PettyCashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (!(user?.can(Permissions.pettyCashView) ?? false)) {
      return const PageScaffold(
        title: 'Petty Cash',
        child: EmptyState(
          icon: Icons.lock_outline,
          title: 'You do not have access to petty cash',
        ),
      );
    }

    final canManage = user?.can(Permissions.pettyCashManage) ?? false;

    return PageScaffold(
      title: 'Petty Cash',
      description:
          'The float, and every movement in and out of it. Expenses paid from '
          'the float appear here against their voucher, so the cash and the '
          'expense report always tell the same story.',
      scrollable: false,
      actions: [
        if (canManage) ...[
          OutlinedButton.icon(
            onPressed: () => _record(context, PettyCashEntryKind.cashIssued),
            icon: const Icon(Icons.north_east, size: 18),
            label: const Text('Cash out'),
          ),
          FilledButton.icon(
            onPressed: () => _record(context, PettyCashEntryKind.cashReceived),
            icon: const Icon(Icons.south_west, size: 18),
            label: const Text('Cash in'),
          ),
        ],
      ],
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FloatHeader(),
          AppSpacing.gapLg,
          _Filters(),
          AppSpacing.gapLg,
          Expanded(child: _BookTable()),
        ],
      ),
    );
  }

  Future<void> _record(BuildContext context, PettyCashEntryKind kind) async {
    final done = await PettyCashFormDialog.show(context, kind: kind);
    if (done && context.mounted) {
      showSuccessSnackBar(context, 'Petty cash entry recorded.');
    }
  }
}

class _FloatHeader extends ConsumerWidget {
  const _FloatHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(pettyCashSnapshotProvider).valueOrNull;
    final discrepancies =
        ref.watch(pettyCashDiscrepanciesProvider).valueOrNull ?? const [];
    final canManage =
        ref.watch(currentUserProvider)?.can(Permissions.pettyCashManage) ??
        false;
    final hasOpening = (snapshot?.entryCount ?? 0) > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KpiGrid(
          children: [
            KpiCard(
              label: 'Float in hand',
              value: (snapshot?.balance ?? Money.zero).formatted(),
              caption: snapshot?.lastEntryAt == null
                  ? 'No movements yet'
                  : 'Last movement '
                        '${DateFormat('d MMM yyyy').format(snapshot!.lastEntryAt!.toLocal())}',
              icon: Icons.savings_outlined,
              tone: (snapshot?.balance ?? Money.zero).isZero
                  ? StatusTone.neutral
                  : StatusTone.success,
              isLoading: snapshot == null,
            ),
            KpiCard(
              label: 'Into the float',
              value: (snapshot?.receivedInPeriod ?? Money.zero).formatted(),
              caption: 'Over the period shown',
              icon: Icons.south_west,
              isLoading: snapshot == null,
            ),
            KpiCard(
              label: 'Out of the float',
              value: (snapshot?.spentInPeriod ?? Money.zero).formatted(),
              caption: 'Expenses and cash returned',
              icon: Icons.north_east,
              tone: StatusTone.warning,
              isLoading: snapshot == null,
            ),
            KpiCard(
              label: 'Entries',
              value: '${snapshot?.entryCount ?? 0}',
              caption: 'In the period shown',
              icon: Icons.list_alt_outlined,
              isLoading: snapshot == null,
            ),
          ],
        ),
        if (!hasOpening && canManage) ...[
          AppSpacing.gapLg,
          SectionCard(
            title: 'The float has not been opened yet',
            subtitle:
                'Record the opening float once, and top it up from the cash '
                'box thereafter.',
            leading: Icon(
              Icons.play_circle_outline,
              color: context.statusColors.info,
            ),
            actions: [
              FilledButton(
                onPressed: () async {
                  final done = await PettyCashFormDialog.show(
                    context,
                    kind: PettyCashEntryKind.opening,
                  );
                  if (done && context.mounted) {
                    showSuccessSnackBar(context, 'Opening float recorded.');
                  }
                },
                child: const Text('Record the opening float'),
              ),
            ],
          ),
        ],
        if (discrepancies.isNotEmpty) ...[
          AppSpacing.gapLg,
          SectionCard(
            title:
                '${discrepancies.length} row(s) disagree with a replay of '
                'the book',
            subtitle:
                'The running balances are written with each entry and should '
                'never drift. This needs looking at before the float is '
                'trusted.',
            leading: Icon(
              Icons.error_outline,
              color: context.statusColors.danger,
            ),
            actions: [
              if (canManage)
                OutlinedButton(
                  onPressed: () => _rebuild(context, ref),
                  child: const Text('Rebuild them'),
                ),
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final row in discrepancies.take(5))
                  Text(
                    '${row.voucherNumber}: stored ${row.stored.formatted()}, '
                    'replay says ${row.replayed.formatted()}',
                    style: context.text.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _rebuild(BuildContext context, WidgetRef ref) async {
    final corrected = await ref
        .read(pettyCashServiceProvider)
        .recomputeBalances(ref.read(requireCurrentUserProvider));
    if (context.mounted) {
      showSuccessSnackBar(context, 'Rebuilt $corrected running balance(s).');
    }
  }
}

class _Filters extends ConsumerWidget {
  const _Filters();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(pettyCashFilterProvider);
    final notifier = ref.read(pettyCashFilterProvider.notifier);

    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AppSearchField(
          hintText: 'Search voucher, description or reference',
          width: 320,
          onChanged: (value) =>
              notifier.update((state) => state.copyWith(search: value)),
        ),
        SizedBox(
          width: 210,
          child: DropdownButtonFormField<PettyCashEntryKind?>(
            initialValue: filter.kind,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Kind'),
            items: [
              const DropdownMenuItem<PettyCashEntryKind?>(
                child: Text('All movements'),
              ),
              for (final kind in PettyCashEntryKind.values)
                DropdownMenuItem<PettyCashEntryKind?>(
                  value: kind,
                  child: Text(pettyCashKindLabel(kind)),
                ),
            ],
            onChanged: (value) => notifier.update(
              (state) => value == null
                  ? state.copyWith(clearKind: true)
                  : state.copyWith(kind: value),
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
        if (filter.hasAnyFilter)
          TextButton.icon(
            onPressed: () => notifier.state = const PettyCashFilter(),
            icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
            label: const Text('Clear filters'),
          ),
      ],
    );
  }
}

class _BookTable extends ConsumerWidget {
  const _BookTable();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(pettyCashEntriesProvider);
    final filter = ref.watch(pettyCashFilterProvider);

    return AsyncValueView<List<PettyCashRow>>(
      value: entries,
      builder: (context, rows) => SectionCard(
        padding: EdgeInsets.zero,
        fillHeight: true,
        child: AppDataTable<PettyCashRow>(
          rows: rows,
          minWidth: 1020,
          empty: EmptyState(
            icon: Icons.savings_outlined,
            title: filter.hasAnyFilter
                ? 'No movements match these filters'
                : 'The petty cash book is empty',
            message: filter.hasAnyFilter
                ? null
                : 'Record the opening float to start the book.',
          ),
          columns: [
            AppTableColumn<PettyCashRow>(
              label: 'Voucher',
              width: 150,
              cell: (context, row) => TableTwoLineCell(
                primary: row.voucherNumber,
                secondary: DateFormat(
                  'd MMM yyyy',
                ).format(row.entryDate.toLocal()),
              ),
            ),
            AppTableColumn<PettyCashRow>(
              label: 'Kind',
              width: 160,
              cell: (context, row) => StatusPill(
                pettyCashKindLabel(row.kind),
                tone: row.isInflow ? StatusTone.success : StatusTone.warning,
              ),
            ),
            AppTableColumn<PettyCashRow>(
              label: 'Description',
              flex: 4,
              cell: (context, row) => TableTwoLineCell(
                primary: row.description,
                secondary: row.expenseVoucherNumber == null
                    ? (row.handledByEmployeeName ?? row.referenceNumber ?? '—')
                    : 'expense ${row.expenseVoucherNumber}',
              ),
            ),
            AppTableColumn<PettyCashRow>(
              label: 'In',
              width: 120,
              numeric: true,
              cell: (context, row) => Text(
                row.isInflow ? row.amount.plain : '—',
                textAlign: TextAlign.right,
                style: context.text.bodyMedium?.copyWith(
                  color: row.isInflow ? context.statusColors.success : null,
                ),
              ),
            ),
            AppTableColumn<PettyCashRow>(
              label: 'Out',
              width: 120,
              numeric: true,
              cell: (context, row) => Text(
                row.isInflow ? '—' : row.amount.plain,
                textAlign: TextAlign.right,
                style: context.text.bodyMedium?.copyWith(
                  color: row.isInflow ? null : context.statusColors.warning,
                ),
              ),
            ),
            AppTableColumn<PettyCashRow>(
              label: 'Balance',
              width: 130,
              numeric: true,
              cell: (context, row) => Text(
                row.balanceAfter.plain,
                textAlign: TextAlign.right,
                style: context.text.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            AppTableColumn<PettyCashRow>(
              label: 'Recorded by',
              flex: 2,
              cell: (context, row) => TableTextCell(row.createdBy, muted: true),
            ),
          ],
        ),
      ),
    );
  }
}

/// Records a movement of the float.
class PettyCashFormDialog extends ConsumerStatefulWidget {
  const PettyCashFormDialog({super.key, required this.kind});

  final PettyCashEntryKind kind;

  static Future<bool> show(
    BuildContext context, {
    required PettyCashEntryKind kind,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PettyCashFormDialog(kind: kind),
    );
    return result ?? false;
  }

  @override
  ConsumerState<PettyCashFormDialog> createState() =>
      _PettyCashFormDialogState();
}

class _PettyCashFormDialogState extends ConsumerState<PettyCashFormDialog> {
  final _amount = TextEditingController();
  final _description = TextEditingController();
  final _reference = TextEditingController();

  late PettyCashEntryKind _kind = widget.kind;
  int? _handledByEmployeeId;
  bool _adjustmentAdds = false;
  DateTime? _date;

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    _reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final float = ref.watch(pettyCashBalanceProvider).valueOrNull;
    final employees =
        ref.watch(selectableEmployeesProvider).valueOrNull ?? const [];
    final isOpening = _kind == PettyCashEntryKind.opening;

    return AppFormDialog(
      title: pettyCashKindLabel(_kind),
      subtitle: float == null ? null : 'The float holds ${float.formatted()}.',
      submitLabel: 'Record it',
      width: 580,
      onSubmit: _submit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isOpening)
            AppDropdownField<PettyCashEntryKind>(
              label: 'Kind',
              isRequired: true,
              value: _kind,
              helperText: _explain(_kind),
              items: [
                for (final kind in const [
                  PettyCashEntryKind.cashReceived,
                  PettyCashEntryKind.cashIssued,
                  PettyCashEntryKind.adjustment,
                ])
                  DropdownMenuItem(
                    value: kind,
                    child: Text(pettyCashKindLabel(kind)),
                  ),
              ],
              onChanged: (value) => setState(() => _kind = value ?? _kind),
            ),
          AppSpacing.gapLg,
          FormRow(
            children: [
              AppMoneyField(
                controller: _amount,
                label: 'Amount',
                isRequired: true,
                allowZero: false,
                autofocus: true,
              ),
              AppDateField(
                label: 'Date',
                value: _date ?? DateTime.now(),
                onChanged: (value) => setState(() => _date = value),
              ),
            ],
          ),
          if (_kind == PettyCashEntryKind.adjustment)
            SwitchListTile(
              value: _adjustmentAdds,
              onChanged: (value) => setState(() => _adjustmentAdds = value),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                _adjustmentAdds
                    ? 'Cash counted over — add it to the float'
                    : 'Cash counted short — take it off the float',
              ),
              subtitle: Text(
                _adjustmentAdds
                    ? 'Recorded as a small gain.'
                    : 'Recorded as a small loss, not as a transfer.',
                style: context.text.bodySmall,
              ),
            ),
          AppSpacing.gapLg,
          AppTextField(
            controller: _description,
            label: 'Description',
            isRequired: true,
            maxLength: 500,
            maxLines: 2,
          ),
          AppSpacing.gapLg,
          FormRow(
            children: [
              AppDropdownField<int?>(
                label: 'Handled by',
                value: _handledByEmployeeId,
                items: [
                  const DropdownMenuItem<int?>(child: Text('Not recorded')),
                  for (final employee in employees)
                    DropdownMenuItem<int?>(
                      value: employee.id,
                      child: Text(employee.name),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _handledByEmployeeId = value),
              ),
              AppTextField(
                controller: _reference,
                label: 'Reference',
                maxLength: 64,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _explain(PettyCashEntryKind kind) => switch (kind) {
    PettyCashEntryKind.opening =>
      'The float is opened once; top it up afterwards.',
    PettyCashEntryKind.cashReceived =>
      'Cash moved from the cash box into the float.',
    PettyCashEntryKind.cashIssued =>
      'Cash returned from the float to the cash box.',
    PettyCashEntryKind.expense => 'Recorded by the expense itself, not here.',
    PettyCashEntryKind.adjustment =>
      'A correction after counting the box: a loss or a gain, not a transfer.',
  };

  Future<void> _submit() async {
    final amount = Money.tryParse(_amount.text);
    if (amount == null || !amount.isPositive) {
      throw const FormatException('Enter the amount.');
    }

    await ref
        .read(pettyCashServiceProvider)
        .recordEntry(
          ref.read(requireCurrentUserProvider),
          PettyCashDraft(
            kind: _kind,
            amount: amount,
            description: _description.text,
            entryDate: _date,
            referenceNumber: _reference.text,
            handledByEmployeeId: _handledByEmployeeId,
            adjustmentAddsToFloat: _adjustmentAdds,
          ),
        );
  }
}
