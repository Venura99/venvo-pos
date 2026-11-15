import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/payments/domain/payment_models.dart';
import 'package:venvo_core/features/salaries/domain/salary_models.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/feedback_views.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/status_pill.dart';
import '../../authentication/presentation/auth_controller.dart';
import 'salaries_screen.dart';
import 'salary_providers.dart';

/// The salary slip: what was earned, what was taken off, and what is left.
Future<void> showSalaryDetail(
  BuildContext context,
  WidgetRef ref,
  int salaryId,
) async {
  await showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: SizedBox(
        width: 680,
        child: Consumer(
          builder: (context, ref, _) => AsyncValueView<SalaryDetail>(
            value: ref.watch(salaryDetailProvider(salaryId)),
            onRetry: () => ref.invalidate(salaryDetailProvider(salaryId)),
            builder: (context, detail) => _Body(detail: detail),
          ),
        ),
      ),
    ),
  );
}

class _Body extends ConsumerWidget {
  const _Body({required this.detail});

  final SalaryDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salary = detail.summary;
    final canManage =
        ref.watch(currentUserProvider)?.can(Permissions.salaryManage) ?? false;

    return Padding(
      padding: AppSpacing.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(salary.employeeName, style: context.text.titleLarge),
                    Text(
                      '${salary.periodLabel} · ${salary.voucherNumber}'
                      '${salary.designation == null ? '' : ' · ${salary.designation}'}',
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
              StatusPill(
                salaryStatusLabel(salary.status),
                tone: switch (salary.status) {
                  SalaryStatus.draft => StatusTone.neutral,
                  SalaryStatus.approved => StatusTone.info,
                  SalaryStatus.partiallyPaid => StatusTone.warning,
                  SalaryStatus.paid => StatusTone.success,
                  SalaryStatus.cancelled => StatusTone.danger,
                },
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          AppSpacing.gapLg,
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SectionCard(
                    title: 'The slip',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _line(context, 'Basic salary', salary.basicSalary),
                        if (!salary.allowances.isZero)
                          _line(context, 'Allowances', salary.allowances),
                        if (!salary.bonus.isZero)
                          _line(context, 'Bonus', salary.bonus),
                        if (!salary.deductions.isZero)
                          _line(context, 'Deductions', -salary.deductions),
                        const Divider(),
                        _line(context, 'Earned', salary.earned),
                        if (!salary.advanceDeducted.isZero)
                          _line(
                            context,
                            'Less advance recovered',
                            -salary.advanceDeducted,
                            tone: context.statusColors.info,
                          ),
                        const Divider(),
                        _line(
                          context,
                          'Net salary',
                          salary.netSalary,
                          emphasise: true,
                        ),
                        if (!salary.paid.isZero)
                          _line(context, 'Paid so far', salary.paid),
                        if (salary.outstanding.isPositive)
                          _line(
                            context,
                            'Still owed',
                            salary.outstanding,
                            tone: context.statusColors.warning,
                          ),
                      ],
                    ),
                  ),
                  if (detail.outstandingAdvances.isPositive) ...[
                    AppSpacing.gapLg,
                    SectionCard(
                      leading: Icon(
                        Icons.account_balance_wallet_outlined,
                        color: context.statusColors.info,
                      ),
                      title:
                          '${detail.outstandingAdvances.formatted()} of '
                          'advances still outstanding',
                      subtitle:
                          'Recoverable from a later salary, oldest advance '
                          'first.',
                    ),
                  ],
                  AppSpacing.gapLg,
                  SectionCard(
                    title: detail.payments.isEmpty
                        ? 'Not paid yet'
                        : '${detail.payments.length} payment(s)',
                    child: detail.payments.isEmpty
                        ? Text(
                            salary.isDraft
                                ? 'Approve the salary to make it payable.'
                                : '${salary.outstanding.formatted()} is '
                                      'waiting to be paid.',
                            style: context.text.bodyMedium,
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final payment in detail.payments)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: AppSpacing.xs,
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 130,
                                        child: Text(
                                          DateFormat('d MMM yyyy').format(
                                            payment.paymentDate.toLocal(),
                                          ),
                                          style: context.text.bodyMedium,
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          '${paymentMethodLabel(payment.method)}'
                                          '${payment.referenceNumber == null ? '' : ' · ${payment.referenceNumber}'}'
                                          ' · ${payment.createdBy}',
                                          style: context.text.bodySmall,
                                        ),
                                      ),
                                      Text(
                                        payment.amount.plain,
                                        style: context.text.bodyMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                  ),
                  if (salary.notes != null) ...[
                    AppSpacing.gapLg,
                    SectionCard(
                      title: 'Notes',
                      child: Text(
                        salary.notes!,
                        style: context.text.bodyMedium,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          AppSpacing.gapLg,
          Row(
            children: [
              if (canManage && salary.isDraft)
                FilledButton.icon(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await confirmAndApproveSalary(context, ref, salary);
                  },
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Approve'),
                ),
              if (canManage && salary.canBePaid)
                FilledButton.icon(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await showSalaryPaymentDialog(context, ref, salary);
                  },
                  icon: const Icon(Icons.payments_outlined, size: 18),
                  label: Text('Pay ${salary.outstanding.formatted()}'),
                ),
              const Spacer(),
              if (salary.approvedBy != null)
                Text(
                  'Approved by ${salary.approvedBy}',
                  style: context.text.bodySmall,
                ),
              AppSpacing.hGapMd,
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
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
