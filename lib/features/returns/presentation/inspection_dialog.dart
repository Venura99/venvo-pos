import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/returns/domain/return_models.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/feedback_views.dart';
import '../../../core/widgets/form_dialog.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/status_pill.dart';
import '../../authentication/presentation/auth_controller.dart';
import 'return_providers.dart';

/// Records the inspection of a return.
///
/// Every returned unit has to be put somewhere: back into stock, into the
/// damaged store, or written off. The dialog will not submit until each line
/// adds up to exactly what came back, because a unit left unaccounted for
/// would stay in transit where no stock report would ever show it.
Future<void> showInspectionDialog(
  BuildContext context,
  WidgetRef ref,
  ReturnSummary document,
) async {
  final detail = await ref.read(returnDetailProvider(document.id).future);
  if (!context.mounted) return;

  final inspected = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _InspectionDialog(detail: detail),
  );

  if ((inspected ?? false) && context.mounted) {
    showSuccessSnackBar(
      context,
      '${document.returnNumber} inspected. The goods have left transit.',
    );
  }
}

class _InspectionDialog extends ConsumerStatefulWidget {
  const _InspectionDialog({required this.detail});

  final ReturnDetail detail;

  @override
  ConsumerState<_InspectionDialog> createState() => _InspectionDialogState();
}

class _InspectionDialogState extends ConsumerState<_InspectionDialog> {
  final _decisions = <int, _LineDecision>{};
  final _notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    for (final line in widget.detail.lines) {
      // Everything good until somebody says otherwise: the common case is a
      // return that is simply accepted, and an inspector should not have to
      // retype the quantity to say so.
      _decisions[line.id] = _LineDecision(accepted: line.quantity);
    }
  }

  @override
  void dispose() {
    for (final decision in _decisions.values) {
      decision.dispose();
    }
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail;
    final destination = detail.summary.toLocationName;

    return AppFormDialog(
      title: 'Inspect ${detail.summary.returnNumber}',
      subtitle:
          'Accepted goods go into "$destination". Damaged goods go to the '
          'quarantine store and are still credited. Scrapped goods leave the '
          'business and are never credited.',
      submitLabel: 'Record the inspection',
      width: 860,
      onSubmit: _submit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Header(),
          for (final line in detail.lines)
            _LineRow(
              line: line,
              decision: _decisions[line.id]!,
              onChanged: () => setState(() {}),
            ),
          const Divider(),
          _Totals(lines: detail.lines, decisions: _decisions),
          AppSpacing.gapLg,
          AppTextField(
            controller: _notes,
            label: 'Inspection notes',
            maxLines: 2,
            maxLength: 500,
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    for (final line in widget.detail.lines) {
      final decision = _decisions[line.id]!;
      if (decision.total != line.quantity) {
        throw FormatException(
          '"${line.productName}" came back with ${line.quantity} unit(s), '
          'but ${decision.total} were accounted for. Accepted, damaged and '
          'scrapped must add up to what was returned.',
        );
      }
    }

    await ref
        .read(returnServiceProvider)
        .recordInspection(
          ref.read(requireCurrentUserProvider),
          InspectionRequest(
            returnId: widget.detail.summary.id,
            notes: _notes.text,
            decisions: [
              for (final line in widget.detail.lines)
                InspectionDecision(
                  returnItemId: line.id,
                  acceptedQuantity: _decisions[line.id]!.accepted,
                  damagedQuantity: _decisions[line.id]!.damaged,
                  scrappedQuantity: _decisions[line.id]!.scrapped,
                  note: _decisions[line.id]!.note.text,
                ),
            ],
          ),
        );
  }
}

/// One line's split, held as controllers so the arithmetic can be shown live.
class _LineDecision {
  _LineDecision({required int accepted}) {
    acceptedField.text = accepted.toString();
  }

  final TextEditingController acceptedField = TextEditingController();
  final TextEditingController damagedField = TextEditingController();
  final TextEditingController scrappedField = TextEditingController();
  final TextEditingController note = TextEditingController();

  int get accepted => _value(acceptedField);
  int get damaged => _value(damagedField);
  int get scrapped => _value(scrappedField);

  int get total => accepted + damaged + scrapped;

  static int _value(TextEditingController controller) =>
      int.tryParse(controller.text.trim()) ?? 0;

  void dispose() {
    acceptedField.dispose();
    damagedField.dispose();
    scrappedField.dispose();
    note.dispose();
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Widget label(String text, double width) => SizedBox(
      width: width,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: context.text.labelSmall?.copyWith(
          color: context.colors.onSurfaceVariant,
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          const Expanded(child: SizedBox.shrink()),
          label('Back', 70),
          label('Accept', 110),
          label('Damaged', 110),
          label('Scrap', 110),
        ],
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.line,
    required this.decision,
    required this.onChanged,
  });

  final ReturnLineView line;
  final _LineDecision decision;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final balanced = decision.total == line.quantity;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.productName,
                        style: context.text.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${line.sku} · ${line.unitPrice.formatted()} each',
                        style: context.text.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: 70,
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: Text(
                    '${line.quantity}',
                    textAlign: TextAlign.center,
                    style: context.text.bodyLarge,
                  ),
                ),
              ),
              _QuantityBox(
                controller: decision.acceptedField,
                label: 'Accept',
                maximum: line.quantity,
                onChanged: onChanged,
              ),
              _QuantityBox(
                controller: decision.damagedField,
                label: 'Damaged',
                maximum: line.quantity,
                onChanged: onChanged,
              ),
              _QuantityBox(
                controller: decision.scrappedField,
                label: 'Scrap',
                maximum: line.quantity,
                onChanged: onChanged,
              ),
            ],
          ),
          if (!balanced)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                decision.total > line.quantity
                    ? 'That is ${decision.total - line.quantity} more than '
                          'came back.'
                    : '${line.quantity - decision.total} unit(s) still '
                          'unaccounted for.',
                style: context.text.bodySmall?.copyWith(
                  color: context.statusColors.danger,
                ),
              ),
            ),
          if (decision.damaged > 0 || decision.scrapped > 0)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: AppTextField(
                controller: decision.note,
                label: 'What is wrong with them',
                maxLength: 500,
              ),
            ),
        ],
      ),
    );
  }
}

class _QuantityBox extends StatelessWidget {
  const _QuantityBox({
    required this.controller,
    required this.label,
    required this.maximum,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final int maximum;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 110,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: AppIntField(
          controller: controller,
          label: label,
          minimum: 0,
          maximum: maximum,
          onChanged: (_) => onChanged(),
        ),
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.lines, required this.decisions});

  final List<ReturnLineView> lines;
  final Map<int, _LineDecision> decisions;

  @override
  Widget build(BuildContext context) {
    var accepted = 0;
    var damaged = 0;
    var scrapped = 0;
    var creditable = Money.zero;

    for (final line in lines) {
      final decision = decisions[line.id]!;
      accepted += decision.accepted;
      damaged += decision.damaged;
      scrapped += decision.scrapped;
      creditable += line.unitPrice * (decision.accepted + decision.damaged);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Wrap(
        spacing: AppSpacing.lg,
        runSpacing: AppSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          StatusPill('$accepted back into stock', tone: StatusTone.success),
          StatusPill('$damaged to quarantine', tone: StatusTone.warning),
          StatusPill('$scrapped written off', tone: StatusTone.danger),
          Text(
            'Creditable after inspection ${creditable.formatted()}',
            style: context.text.bodySmall?.copyWith(
              color: context.statusColors.info,
            ),
          ),
        ],
      ),
    );
  }
}
