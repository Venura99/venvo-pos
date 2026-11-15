import 'package:flutter/material.dart';

import 'package:venvo_core/core/enums/app_enums.dart';
import '../theme/design_tokens.dart';

/// Semantic tone of a status indicator, independent of the brand palette.
enum StatusTone { success, warning, danger, info, neutral }

/// Compact coloured label used in tables and headers to show document state.
/// Tone is paired with text, never colour alone, so the meaning survives for a
/// colour-blind user and in a printed report.
class StatusPill extends StatelessWidget {
  const StatusPill(
    this.label, {
    super.key,
    this.tone = StatusTone.neutral,
    this.icon,
  });

  /// Pill for a document lifecycle status.
  factory StatusPill.document(StockDocumentStatus status, {Key? key}) {
    return switch (status) {
      StockDocumentStatus.draft => StatusPill(
        'Draft',
        tone: StatusTone.neutral,
        key: key,
      ),
      StockDocumentStatus.posted => StatusPill(
        'Posted',
        tone: StatusTone.success,
        key: key,
      ),
      StockDocumentStatus.cancelled => StatusPill(
        'Cancelled',
        tone: StatusTone.danger,
        key: key,
      ),
    };
  }

  /// Pill for how much of an invoice has been settled by *cleared* money.
  factory StatusPill.settlement(PaymentSettlementStatus status, {Key? key}) {
    return switch (status) {
      PaymentSettlementStatus.unpaid => StatusPill(
        'Unpaid',
        tone: StatusTone.danger,
        key: key,
      ),
      PaymentSettlementStatus.partiallyPaid => StatusPill(
        'Part paid',
        tone: StatusTone.warning,
        key: key,
      ),
      PaymentSettlementStatus.paid => StatusPill(
        'Paid',
        tone: StatusTone.success,
        key: key,
      ),
      PaymentSettlementStatus.overpaid => StatusPill(
        'Overpaid',
        tone: StatusTone.info,
        key: key,
      ),
    };
  }

  factory StatusPill.cheque(ChequeStatus status, {Key? key}) {
    return switch (status) {
      ChequeStatus.pending => StatusPill(
        'Pending',
        tone: StatusTone.warning,
        key: key,
      ),
      ChequeStatus.deposited => StatusPill(
        'Deposited',
        tone: StatusTone.info,
        key: key,
      ),
      ChequeStatus.cleared => StatusPill(
        'Cleared',
        tone: StatusTone.success,
        key: key,
      ),
      ChequeStatus.bounced => StatusPill(
        'Bounced',
        tone: StatusTone.danger,
        key: key,
      ),
      ChequeStatus.returned => StatusPill(
        'Returned',
        tone: StatusTone.danger,
        key: key,
      ),
      ChequeStatus.cancelled => StatusPill(
        'Cancelled',
        tone: StatusTone.neutral,
        key: key,
      ),
    };
  }

  factory StatusPill.entity(EntityStatus status, {Key? key}) {
    return switch (status) {
      EntityStatus.active => StatusPill(
        'Active',
        tone: StatusTone.success,
        key: key,
      ),
      EntityStatus.inactive => StatusPill(
        'Inactive',
        tone: StatusTone.neutral,
        key: key,
      ),
      EntityStatus.archived => StatusPill(
        'Archived',
        tone: StatusTone.neutral,
        key: key,
      ),
    };
  }

  final String label;
  final StatusTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.statusColors;
    final (background, foreground) = switch (tone) {
      StatusTone.success => (
        colors.successContainer,
        colors.onSuccessContainer,
      ),
      StatusTone.warning => (
        colors.warningContainer,
        colors.onWarningContainer,
      ),
      StatusTone.danger => (colors.dangerContainer, colors.onDangerContainer),
      StatusTone.info => (colors.infoContainer, colors.onInfoContainer),
      StatusTone.neutral => (
        colors.neutralContainer,
        colors.onNeutralContainer,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: const BorderRadius.all(Radius.circular(AppRadii.pill)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(
            label,
            style: context.text.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
