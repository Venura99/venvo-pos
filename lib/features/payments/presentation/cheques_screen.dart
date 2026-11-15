import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/payments/domain/payment_models.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/app_data_table.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/feedback_views.dart';
import '../../../core/widgets/form_dialog.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/status_pill.dart';
import '../../authentication/presentation/auth_controller.dart';
import 'cheque_photo.dart';
import 'payment_providers.dart';

/// The cheque register and its lifecycle.
///
/// This screen exists because a cheque is not money. It tracks each one from
/// received, through banked, to cleared or bounced - and the figures in the
/// summary bar keep those apart so nobody treats a drawer full of cheques as
/// cash in hand.
class ChequesScreen extends ConsumerWidget {
  const ChequesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (!(user?.can(Permissions.chequeManage) ?? false)) {
      return const PageScaffold(
        title: 'Cheques',
        child: EmptyState(
          icon: Icons.lock_outline,
          title: 'You do not have access to the cheque register',
          message: 'Ask an administrator for the "Manage cheques" permission.',
        ),
      );
    }

    final cheques = ref.watch(chequesProvider);
    final filter = ref.watch(chequeFilterProvider);
    final now = ref.watch(clockProvider).nowUtc();

    return PageScaffold(
      title: 'Cheques',
      description:
          'A cheque is a promise until it clears. Nothing here counts towards '
          'cash or reduces a balance until it is cleared.',
      scrollable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Filters(filter: filter),
          AppSpacing.gapLg,
          Expanded(
            child: AsyncValueView<List<ChequeSummary>>(
              value: cheques,
              builder: (context, rows) => SectionCard(
                padding: EdgeInsets.zero,
                fillHeight: true,
                child: AppDataTable<ChequeSummary>(
                  rows: rows,
                  minWidth: 1180,
                  empty: EmptyState(
                    icon: Icons.account_balance_outlined,
                    title: filter.hasAnyFilter
                        ? 'No cheques match these filters'
                        : 'No cheques yet',
                    message: filter.hasAnyFilter
                        ? null
                        : 'Cheques appear here as soon as one is taken on a '
                              'payment.',
                  ),
                  columns: [
                    AppTableColumn<ChequeSummary>(
                      label: 'Cheque',
                      width: 150,
                      cell: (context, row) => TableTwoLineCell(
                        primary: row.chequeNumber,
                        secondary: row.branchName == null
                            ? row.bankName
                            : '${row.bankName} · ${row.branchName}',
                      ),
                    ),
                    AppTableColumn<ChequeSummary>(
                      label: 'Party',
                      flex: 3,
                      cell: (context, row) => TableTwoLineCell(
                        primary: row.partyName,
                        secondary: row.invoiceNumbers.isEmpty
                            ? 'on account · ${row.receiptNumber}'
                            : row.invoiceNumbers.join(', '),
                      ),
                    ),
                    AppTableColumn<ChequeSummary>(
                      label: 'Cheque date',
                      width: 135,
                      tooltip: 'A cheque cannot be banked before this date',
                      cell: (context, row) => row.isPostDated(now)
                          ? TableTwoLineCell(
                              primary: DateFormat(
                                'd MMM yyyy',
                              ).format(row.chequeDate.toLocal()),
                              secondary: 'post-dated',
                            )
                          : TableTextCell(
                              DateFormat(
                                'd MMM yyyy',
                              ).format(row.chequeDate.toLocal()),
                            ),
                    ),
                    AppTableColumn<ChequeSummary>(
                      label: 'Amount',
                      width: 120,
                      numeric: true,
                      cell: (context, row) => Text(
                        row.amount.plain,
                        style: context.text.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          decoration: row.isBounced
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                    AppTableColumn<ChequeSummary>(
                      label: 'Progress',
                      flex: 2,
                      cell: (context, row) =>
                          _ProgressCell(cheque: row, now: now),
                    ),
                    AppTableColumn<ChequeSummary>(
                      label: 'Status',
                      width: 125,
                      cell: (context, row) => StatusPill.cheque(row.status),
                    ),
                    AppTableColumn<ChequeSummary>(
                      label: '',
                      width: 56,
                      cell: (context, row) => _RowMenu(cheque: row, now: now),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AppSpacing.gapSm,
          const _SummaryBar(),
        ],
      ),
    );
  }
}

class _ProgressCell extends StatelessWidget {
  const _ProgressCell({required this.cheque, required this.now});

  final ChequeSummary cheque;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    if (cheque.isBounced) {
      return Text(
        cheque.bounceReason ?? 'Returned unpaid',
        style: context.text.bodySmall?.copyWith(
          color: context.statusColors.danger,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }
    if (cheque.isCleared) {
      return TableTextCell(
        cheque.clearedAt == null
            ? 'Cleared'
            : 'Cleared ${DateFormat('d MMM').format(cheque.clearedAt!.toLocal())}',
        muted: true,
      );
    }
    if (cheque.status == ChequeStatus.deposited) {
      final days = cheque.daysSinceDeposit(now);
      return TableTextCell(
        days == null ? 'In clearing' : 'In clearing for $days day(s)',
        muted: true,
      );
    }
    if (cheque.isPostDated(now)) {
      final days = cheque.chequeDate.difference(now).inDays + 1;
      return TableTextCell('Bankable in $days day(s)', muted: true);
    }
    return Text(
      'Ready to bank',
      style: context.text.bodySmall?.copyWith(
        color: context.statusColors.warning,
      ),
    );
  }
}

class _Filters extends ConsumerWidget {
  const _Filters({required this.filter});

  final ChequeFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(chequeFilterProvider.notifier);

    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AppSearchField(
          hintText: 'Search cheque number, bank or party',
          width: 320,
          onChanged: (value) =>
              notifier.update((state) => state.copyWith(search: value)),
        ),
        for (final status in const [
          ChequeStatus.pending,
          ChequeStatus.deposited,
          ChequeStatus.cleared,
          ChequeStatus.bounced,
        ])
          FilterChip(
            selected: filter.statuses.contains(status),
            label: Text(chequeStatusLabel(status)),
            onSelected: (selected) => notifier.update((state) {
              final next = {...state.statuses};
              if (selected) {
                next.add(status);
              } else {
                next.remove(status);
              }
              return state.copyWith(statuses: next);
            }),
          ),
        FilterChip(
          selected: filter.bankableOnly,
          label: const Text('Ready to bank'),
          avatar: const Icon(Icons.account_balance_outlined, size: 16),
          onSelected: (value) =>
              notifier.update((state) => state.copyWith(bankableOnly: value)),
        ),
        if (filter.hasAnyFilter)
          TextButton.icon(
            onPressed: () => notifier.state = const ChequeFilter(),
            icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
            label: const Text('Clear filters'),
          ),
      ],
    );
  }
}

class _SummaryBar extends ConsumerWidget {
  const _SummaryBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totals = ref.watch(chequeTotalsProvider).valueOrNull;
    if (totals == null || totals.count == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Wrap(
        spacing: AppSpacing.xl,
        runSpacing: AppSpacing.xs,
        children: [
          Text('${totals.count} cheque(s)', style: context.text.bodySmall),
          Text(
            'Not yet cleared ${totals.outstanding.formatted()}',
            style: context.text.bodySmall?.copyWith(
              color: context.statusColors.warning,
            ),
          ),
          Text(
            'Cleared ${totals.cleared.formatted()}',
            style: context.text.bodySmall?.copyWith(
              color: context.statusColors.success,
            ),
          ),
          if (!totals.bounced.isZero)
            Text(
              'Bounced ${totals.bounced.formatted()}',
              style: context.text.bodySmall?.copyWith(
                color: context.statusColors.danger,
              ),
            ),
          if (totals.bankableCount > 0)
            Text(
              '${totals.bankableCount} ready to bank',
              style: context.text.bodySmall,
            ),
          if (totals.postDatedCount > 0)
            Text(
              '${totals.postDatedCount} post-dated',
              style: context.text.bodySmall,
            ),
        ],
      ),
    );
  }
}

class _RowMenu extends ConsumerWidget {
  const _RowMenu({required this.cheque, required this.now});

  final ChequeSummary cheque;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Actions',
      icon: const Icon(Icons.more_horiz, size: 18),
      onSelected: (value) async {
        switch (value) {
          case 'deposit':
            await _deposit(context, ref);
          case 'clear':
            await _clear(context, ref);
          case 'bounce':
            await _bounce(context, ref);
          case 'photos':
            await ChequePhotosDialog.show(
              context,
              chequeId: cheque.id,
              title: 'Cheque ${cheque.chequeNumber} · ${cheque.partyName}',
              canAttach: true,
            );
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'photos',
          child: Text('Photo and reminders'),
        ),
        const PopupMenuDivider(),
        if (cheque.status == ChequeStatus.pending)
          PopupMenuItem(
            value: 'deposit',
            enabled: !cheque.isPostDated(now),
            child: Text(
              cheque.isPostDated(now) ? 'Bank it (post-dated)' : 'Bank it',
            ),
          ),
        if (cheque.isOutstanding)
          const PopupMenuItem(value: 'clear', child: Text('Mark as cleared')),
        if (cheque.status != ChequeStatus.bounced &&
            cheque.status != ChequeStatus.cancelled) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'bounce', child: Text('Record a bounce')),
        ],
      ],
    );
  }

  Future<void> _deposit(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(paymentServiceProvider)
          .depositCheque(
            ref.read(requireCurrentUserProvider),
            chequeId: cheque.id,
          );
      if (context.mounted) {
        showSuccessSnackBar(
          context,
          'Cheque ${cheque.chequeNumber} banked. It is in clearing, not yet '
          'cash.',
        );
      }
    } catch (error) {
      if (context.mounted) showFailureSnackBar(context, error);
    }
  }

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Mark cheque ${cheque.chequeNumber} as cleared?',
      message:
          'This is the point at which the money becomes real. Whatever this '
          'cheque was applied to will be settled by it.',
      details: [
        '${cheque.partyName} · ${cheque.amount.formatted()}',
        if (cheque.invoiceNumbers.isNotEmpty)
          'Applied to ${cheque.invoiceNumbers.join(', ')}',
      ],
      confirmLabel: 'Mark as cleared',
      icon: Icons.check_circle_outline,
    );
    if (!confirmed) return;

    try {
      await ref
          .read(paymentServiceProvider)
          .clearCheque(
            ref.read(requireCurrentUserProvider),
            chequeId: cheque.id,
          );
      if (context.mounted) {
        showSuccessSnackBar(context, 'Cheque cleared and the money credited.');
      }
    } catch (error) {
      if (context.mounted) showFailureSnackBar(context, error);
    }
  }

  Future<void> _bounce(BuildContext context, WidgetRef ref) async {
    final reasonController = TextEditingController();
    final chargeController = TextEditingController();

    final bounced = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AppFormDialog(
        title: 'Cheque ${cheque.chequeNumber} bounced',
        subtitle:
            'Nothing is deleted. The payment stops counting as cleared, so '
            'whatever it had settled is owed again on its own.',
        submitLabel: 'Record the bounce',
        width: 540,
        onSubmit: () => ref
            .read(paymentServiceProvider)
            .bounceCheque(
              ref.read(requireCurrentUserProvider),
              chequeId: cheque.id,
              reason: reasonController.text,
              bounceCharge: Money.tryParse(chargeController.text) ?? Money.zero,
            ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(
              controller: reasonController,
              label: 'Reason',
              isRequired: true,
              autofocus: true,
              maxLength: 300,
              hintText: 'Insufficient funds',
            ),
            AppSpacing.gapLg,
            AppMoneyField(
              controller: chargeController,
              label: 'Bank charge',
              helperText: 'Recorded on the cheque for recovery. Optional.',
            ),
            if (cheque.invoiceNumbers.isNotEmpty) ...[
              AppSpacing.gapLg,
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: context.statusColors.warningContainer,
                  borderRadius: AppRadii.smAll,
                ),
                child: Text(
                  '${cheque.amount.formatted()} will be owed again on '
                  '${cheque.invoiceNumbers.join(', ')}.',
                  style: context.text.bodySmall?.copyWith(
                    color: context.statusColors.onWarningContainer,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    reasonController.dispose();
    chargeController.dispose();
    if ((bounced ?? false) && context.mounted) {
      showSuccessSnackBar(context, 'Bounce recorded.');
    }
  }
}
