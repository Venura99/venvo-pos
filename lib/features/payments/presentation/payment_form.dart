import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/errors/failures.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/payments/domain/payment_models.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/feedback_views.dart';
import '../../../core/widgets/form_dialog.dart';
import '../../../core/widgets/form_fields.dart';
import '../../agents/presentation/agents_screen.dart';
import '../../authentication/presentation/auth_controller.dart';
import '../../shops/presentation/shops_screen.dart';
import 'cheque_photo.dart';
import 'payment_providers.dart';

/// Records money received, and applies it to invoices.
///
/// The allocation list offers each invoice's **allocatable** remainder, which
/// is lower than what is owed when a pending cheque has already been promised
/// against it. That is what stops the same invoice being covered twice and
/// going overpaid the moment the cheque clears.
class PaymentFormDialog extends ConsumerStatefulWidget {
  const PaymentFormDialog({
    super.key,
    this.direction = PaymentDirection.inbound,
    this.initialAgentId,
    this.initialShopId,
  });

  final PaymentDirection direction;
  final int? initialAgentId;
  final int? initialShopId;

  static Future<bool> show(
    BuildContext context, {
    PaymentDirection direction = PaymentDirection.inbound,
    int? agentId,
    int? shopId,
  }) async {
    final recorded = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PaymentFormDialog(
        direction: direction,
        initialAgentId: agentId,
        initialShopId: shopId,
      ),
    );
    return recorded ?? false;
  }

  @override
  ConsumerState<PaymentFormDialog> createState() => _PaymentFormDialogState();
}

class _PaymentFormDialogState extends ConsumerState<PaymentFormDialog> {
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _bankName = TextEditingController();
  final _chequeNumber = TextEditingController();
  final _chequeBranch = TextEditingController();
  final _payerName = TextEditingController();
  final _notes = TextEditingController();

  /// How much of the payment is applied to each invoice.
  final Map<int, TextEditingController> _allocations = {};

  PartyType _partyType = PartyType.shop;
  int? _agentId;
  int? _shopId;
  PaymentMethod _method = PaymentMethod.cash;
  DateTime? _paymentDate;
  DateTime? _chequeDate;
  PickedChequePhoto? _chequePhoto;

  @override
  void initState() {
    super.initState();
    _agentId = widget.initialAgentId;
    _shopId = widget.initialShopId;
    if (_agentId != null) _partyType = PartyType.agent;
  }

  @override
  void dispose() {
    for (final controller in [
      _amount,
      _reference,
      _bankName,
      _chequeNumber,
      _chequeBranch,
      _payerName,
      _notes,
      ..._allocations.values,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  PaymentPartySelection get _selection => PaymentPartySelection(
    agentId: _partyType == PartyType.agent ? _agentId : null,
    shopId: _partyType == PartyType.shop ? _shopId : null,
  );

  Money get _amountValue => Money.tryParse(_amount.text) ?? Money.zero;

  Money get _allocatedTotal => _allocations.values
      .map((controller) => Money.tryParse(controller.text) ?? Money.zero)
      .sum;

  TextEditingController _allocationController(int invoiceId) {
    return _allocations.putIfAbsent(invoiceId, TextEditingController.new);
  }

  /// Spreads the amount over the oldest invoices first, which is how a
  /// collector almost always wants it applied.
  void _autoApply(List<AllocatableInvoice> invoices) {
    var remaining = _amountValue;
    for (final invoice in invoices) {
      final controller = _allocationController(invoice.invoiceId);
      if (!remaining.isPositive) {
        controller.clear();
        continue;
      }
      final apply = remaining < invoice.allocatable
          ? remaining
          : invoice.allocatable;
      AppMoneyField.setValue(controller, apply);
      remaining -= apply;
    }
    setState(() {});
  }

  Future<void> _submit() async {
    final amount = _amountValue;
    if (!amount.isPositive) {
      throw const ValidationFailure('Enter the amount received.');
    }
    if (_allocatedTotal > amount) {
      throw ValidationFailure(
        'The amounts applied to invoices come to '
        '${_allocatedTotal.formatted()}, more than the payment of '
        '${amount.formatted()}.',
      );
    }

    final allocations = <PaymentAllocationRequest>[];
    for (final entry in _allocations.entries) {
      final value = Money.tryParse(entry.value.text);
      if (value == null || !value.isPositive) continue;
      allocations.add(
        PaymentAllocationRequest(invoiceId: entry.key, amount: value),
      );
    }

    // Taken now: the dialog closes once the payment is recorded, and a failed
    // photo upload still has to be reported somewhere.
    final messenger = ScaffoldMessenger.maybeOf(context);
    final errorColour = Theme.of(context).colorScheme.error;

    final result = await ref
        .read(paymentServiceProvider)
        .recordPayment(
          ref.read(requireCurrentUserProvider),
          PaymentRequest(
            direction: widget.direction,
            method: _method,
            amount: amount,
            partyType: _partyType,
            agentId: _partyType == PartyType.agent ? _agentId : null,
            shopId: _partyType == PartyType.shop ? _shopId : null,
            payerName: _payerName.text,
            paymentDate: _paymentDate,
            bankName: _bankName.text,
            referenceNumber: _reference.text,
            notes: _notes.text,
            allocations: allocations,
            cheque: _method == PaymentMethod.cheque
                ? ChequeDetails(
                    chequeNumber: _chequeNumber.text,
                    bankName: _bankName.text,
                    chequeDate: _chequeDate ?? DateTime.now().toUtc(),
                    branchName: _chequeBranch.text,
                  )
                : null,
          ),
        );

    // The payment is recorded whatever happens next. A failed upload must not
    // throw — the form would stay open and invite recording it twice — and
    // must not be swallowed either: it is reported, and the photo can be
    // attached again from the cheque register.
    final photo = _chequePhoto;
    final chequeId = result.chequeId;
    if (photo != null && chequeId != null) {
      try {
        await ref
            .read(chequeExtrasApiProvider)
            .uploadChequeImage(
              chequeId: chequeId,
              bytes: photo.bytes,
              fileName: photo.fileName,
            );
      } catch (error) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              'The payment was recorded, but the cheque photo did not upload: '
              '${ErrorView.describe(error)} Attach it again from Cheques.',
            ),
            backgroundColor: errorColour,
            showCloseIcon: true,
            duration: const Duration(seconds: 10),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final agents = ref.watch(selectableAgentsProvider).valueOrNull ?? const [];
    final shops = ref.watch(shopsProvider).valueOrNull ?? const [];
    final invoices =
        ref.watch(allocatableInvoicesProvider(_selection)).valueOrNull ??
        const <AllocatableInvoice>[];
    final advance = ref.watch(advanceBalanceProvider(_selection)).valueOrNull;

    final unapplied = _amountValue - _allocatedTotal;

    return AppFormDialog(
      title: widget.direction == PaymentDirection.inbound
          ? 'Record a payment received'
          : 'Record a payment made',
      subtitle: _method == PaymentMethod.cheque
          ? 'A cheque is recorded as pending. It does not reduce what is owed '
                'until it clears.'
          : 'Cash, bank transfers and card payments count as settled money '
                'straight away.',
      submitLabel: 'Record payment',
      width: 980,
      onSubmit: _submit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<PartyType>(
            segments: const [
              ButtonSegment(value: PartyType.shop, label: Text('From a shop')),
              ButtonSegment(
                value: PartyType.agent,
                label: Text('From an agent'),
              ),
              ButtonSegment(value: PartyType.customer, label: Text('Walk-in')),
            ],
            selected: {_partyType},
            onSelectionChanged: (selection) => setState(() {
              _partyType = selection.first;
              _allocations.clear();
            }),
          ),
          AppSpacing.gapXl,
          FormRow(
            children: [
              if (_partyType == PartyType.shop)
                AppDropdownField<int>(
                  value: _shopId,
                  label: 'Shop',
                  isRequired: true,
                  items: [
                    for (final shop in shops)
                      DropdownMenuItem<int>(
                        value: shop.id,
                        child: Text(shop.name),
                      ),
                  ],
                  onChanged: (value) => setState(() {
                    _shopId = value;
                    _allocations.clear();
                  }),
                )
              else if (_partyType == PartyType.agent)
                AppDropdownField<int>(
                  value: _agentId,
                  label: 'Agent',
                  isRequired: true,
                  items: [
                    for (final agent in agents)
                      DropdownMenuItem<int>(
                        value: agent.id,
                        child: Text(agent.name),
                      ),
                  ],
                  onChanged: (value) => setState(() {
                    _agentId = value;
                    _allocations.clear();
                  }),
                )
              else
                AppTextField(
                  controller: _payerName,
                  label: 'Received from',
                  maxLength: 180,
                ),
              AppMoneyField(
                controller: _amount,
                label: 'Amount',
                isRequired: true,
                allowZero: false,
                onChanged: (_) => setState(() {}),
              ),
              AppDateField(
                value: _paymentDate,
                label: 'Date',
                helperText: 'Defaults to today',
                onChanged: (value) => setState(() => _paymentDate = value),
                lastDate: DateTime.now(),
              ),
            ],
          ),
          AppSpacing.gapLg,
          FormRow(
            children: [
              AppDropdownField<PaymentMethod>(
                value: _method,
                label: 'Method',
                isRequired: true,
                items: [
                  for (final method in const [
                    PaymentMethod.cash,
                    PaymentMethod.bankTransfer,
                    PaymentMethod.cheque,
                    PaymentMethod.cardOrDigital,
                  ])
                    DropdownMenuItem<PaymentMethod>(
                      value: method,
                      child: Text(paymentMethodLabel(method)),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _method = value ?? PaymentMethod.cash),
              ),
              AppTextField(
                controller: _reference,
                label: 'Reference',
                maxLength: 64,
              ),
            ],
          ),
          if (_method == PaymentMethod.cheque) ...[
            AppSpacing.gapLg,
            FormRow(
              children: [
                AppTextField(
                  controller: _chequeNumber,
                  label: 'Cheque number',
                  isRequired: true,
                  maxLength: 32,
                ),
                AppTextField(
                  controller: _bankName,
                  label: 'Bank',
                  isRequired: true,
                  maxLength: 120,
                ),
                AppTextField(
                  controller: _chequeBranch,
                  label: 'Branch',
                  maxLength: 120,
                ),
                AppDateField(
                  value: _chequeDate,
                  label: 'Cheque date',
                  isRequired: true,
                  helperText: 'As written on the cheque',
                  onChanged: (value) => setState(() => _chequeDate = value),
                ),
              ],
            ),
            AppSpacing.gapMd,
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final photo = await pickChequePhoto(context);
                    if (photo != null && mounted) {
                      setState(() => _chequePhoto = photo);
                    }
                  },
                  icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                  label: Text(
                    _chequePhoto == null
                        ? 'Add a photo of the cheque'
                        : 'Change photo',
                  ),
                ),
                if (_chequePhoto != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      _chequePhoto!.fileName,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodySmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove photo',
                    onPressed: () => setState(() => _chequePhoto = null),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ],
            ),
          ] else if (_method == PaymentMethod.bankTransfer) ...[
            AppSpacing.gapLg,
            AppTextField(controller: _bankName, label: 'Bank', maxLength: 120),
          ],
          if (_selection.isChosen) ...[
            AppSpacing.gapXl,
            _AllocationPanel(
              invoices: invoices,
              controllerFor: _allocationController,
              onChanged: () => setState(() {}),
              onAutoApply: () => _autoApply(invoices),
              amount: _amountValue,
              allocated: _allocatedTotal,
              unapplied: unapplied,
              existingAdvance: advance,
              isCheque: _method == PaymentMethod.cheque,
            ),
          ],
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
}

class _AllocationPanel extends StatelessWidget {
  const _AllocationPanel({
    required this.invoices,
    required this.controllerFor,
    required this.onChanged,
    required this.onAutoApply,
    required this.amount,
    required this.allocated,
    required this.unapplied,
    required this.existingAdvance,
    required this.isCheque,
  });

  final List<AllocatableInvoice> invoices;
  final TextEditingController Function(int invoiceId) controllerFor;
  final VoidCallback onChanged;
  final VoidCallback onAutoApply;
  final Money amount;
  final Money allocated;
  final Money unapplied;
  final Money? existingAdvance;
  final bool isCheque;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: AppRadii.mdAll,
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Apply to invoices', style: context.text.titleSmall),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        invoices.isEmpty
                            ? 'This party has nothing outstanding. The money '
                                  'will be held on account.'
                            : 'Leave blank to hold the money on account. '
                                  'Oldest first is usually what you want.',
                        style: context.text.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (invoices.isNotEmpty && amount.isPositive)
                  OutlinedButton.icon(
                    onPressed: onAutoApply,
                    icon: const Icon(Icons.auto_fix_high, size: 16),
                    label: const Text('Apply oldest first'),
                  ),
              ],
            ),
          ),
          if (invoices.isNotEmpty) ...[
            const Divider(height: 1),
            _header(context),
            const Divider(height: 1),
            for (final invoice in invoices) _row(context, invoice),
          ],
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _summaryLine(context, 'Payment', amount),
                _summaryLine(context, 'Applied to invoices', allocated),
                _summaryLine(
                  context,
                  'Held on account',
                  unapplied,
                  tone: unapplied.isNegative
                      ? context.statusColors.danger
                      : unapplied.isPositive
                      ? context.statusColors.info
                      : null,
                ),
                if (existingAdvance != null && existingAdvance!.isPositive)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      'This party already has '
                      '${existingAdvance!.formatted()} held on account from '
                      'earlier payments.',
                      style: context.text.bodySmall,
                    ),
                  ),
                if (isCheque && allocated.isPositive)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      'These invoices will show the cheque as received, but '
                      'their outstanding balance will not change until it '
                      'clears.',
                      style: context.text.bodySmall?.copyWith(
                        color: context.statusColors.warning,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final style = context.text.labelSmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: context.colors.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('INVOICE', style: style)),
          SizedBox(
            width: 110,
            child: Text(
              'OUTSTANDING',
              style: style,
              textAlign: TextAlign.right,
            ),
          ),
          SizedBox(
            width: 110,
            child: Text('CAN APPLY', style: style, textAlign: TextAlign.right),
          ),
          SizedBox(
            width: 130,
            child: Text('APPLY', style: style, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, AllocatableInvoice invoice) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(invoice.invoiceNumber, style: context.text.bodyMedium),
                Text(
                  invoice.hasPendingCheques
                      ? '${DateFormat('d MMM yyyy').format(invoice.invoiceDate.toLocal())}'
                            ' · ${invoice.pendingCheques.formatted()} promised by cheque'
                      : DateFormat(
                          'd MMM yyyy',
                        ).format(invoice.invoiceDate.toLocal()),
                  style: context.text.bodySmall?.copyWith(
                    color: invoice.hasPendingCheques
                        ? context.statusColors.warning
                        : null,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 110,
            child: Text(
              invoice.outstanding.plain,
              textAlign: TextAlign.right,
              style: AppTheme.monospacedNumbers(context.text.bodyMedium),
            ),
          ),
          SizedBox(
            width: 110,
            child: Text(
              invoice.allocatable.plain,
              textAlign: TextAlign.right,
              style: AppTheme.monospacedNumbers(
                context.text.bodyMedium,
              ).copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(
            width: 130,
            child: Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sm),
              child: AppMoneyField(
                controller: controllerFor(invoice.invoiceId),
                label: '',
                onChanged: (_) => onChanged(),
                validator: (value) => value > invoice.allocatable
                    ? 'At most ${invoice.allocatable.plain}'
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryLine(
    BuildContext context,
    String label,
    Money amount, {
    Color? tone,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: context.text.bodySmall)),
          Text(
            amount.formatted(),
            style: context.text.bodySmall?.copyWith(color: tone),
          ),
        ],
      ),
    );
  }
}
