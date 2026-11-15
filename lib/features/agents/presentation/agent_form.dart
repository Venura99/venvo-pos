import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/features/agents/domain/agent_models.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/form_dialog.dart';
import '../../../core/widgets/form_fields.dart';
import '../../authentication/presentation/auth_controller.dart';
import 'agents_screen.dart';

/// Create/edit form for an agent.
///
/// Saving a new agent also creates the stock location that agent holds goods
/// in; the form says so, because that location is what warehouse transfers
/// will target.
class AgentFormDialog extends ConsumerStatefulWidget {
  const AgentFormDialog({super.key, this.existing});

  final AgentListItem? existing;

  static Future<bool> show(
    BuildContext context, {
    AgentListItem? existing,
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AgentFormDialog(existing: existing),
    );
    return saved ?? false;
  }

  @override
  ConsumerState<AgentFormDialog> createState() => _AgentFormDialogState();
}

class _AgentFormDialogState extends ConsumerState<AgentFormDialog> {
  late final TextEditingController _code;
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _nic;
  late final TextEditingController _address;
  late final TextEditingController _commission;
  late final TextEditingController _openingBalance;
  late final TextEditingController _notes;
  late EntityStatus _status;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;

    _code = TextEditingController(text: existing?.code ?? '');
    _name = TextEditingController(text: existing?.name ?? '');
    _phone = TextEditingController(text: existing?.phone ?? '');
    _nic = TextEditingController(text: existing?.nic ?? '');
    _address = TextEditingController(text: existing?.address ?? '');
    _notes = TextEditingController(text: existing?.notes ?? '');
    _commission = TextEditingController();
    if (existing?.commissionBps != null) {
      AppPercentField.setBps(_commission, existing!.commissionBps!);
    }
    _openingBalance = TextEditingController();
    if (existing != null) {
      AppMoneyField.setValue(_openingBalance, existing.openingBalance);
    }
    _status = existing?.status ?? EntityStatus.active;
  }

  @override
  void dispose() {
    for (final controller in [
      _code,
      _name,
      _phone,
      _nic,
      _address,
      _commission,
      _openingBalance,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final repository = ref.read(agentRepositoryProvider);
    final actor = ref.read(requireCurrentUserProvider);

    final draft = AgentDraft(
      id: widget.existing?.id,
      code: _code.text,
      name: _name.text,
      phone: _phone.text,
      nic: _nic.text,
      address: _address.text,
      commissionBps: AppPercentField.bpsOf(_commission),
      openingBalance: AppMoneyField.valueOrZero(_openingBalance),
      status: _status,
      notes: _notes.text,
    );

    if (draft.isNew) {
      await repository.create(actor, draft);
    } else {
      await repository.update(actor, draft);
    }
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    final hasTransactions = existing != null && !existing.billedTotal.isZero;

    return AppFormDialog(
      title: existing == null ? 'Add agent' : 'Edit agent',
      subtitle: existing == null
          ? 'A stock location is created for the agent automatically.'
          : 'Outstanding balance ${existing.outstandingBalance.formatted()}',
      submitLabel: existing == null ? 'Add agent' : 'Save changes',
      width: 620,
      onSubmit: _submit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          FormSection(
            title: 'Identity',
            children: [
              FormRow(
                children: [
                  AppTextField(
                    controller: _name,
                    label: 'Agent name',
                    isRequired: true,
                    autofocus: true,
                    maxLength: 180,
                    textCapitalization: TextCapitalization.words,
                  ),
                  AppTextField(
                    controller: _code,
                    label: 'Agent code',
                    maxLength: 24,
                    helperText: existing == null
                        ? 'Leave empty to allocate one'
                        : 'Used on documents',
                  ),
                ],
              ),
              AppSpacing.gapLg,
              FormRow(
                children: [
                  AppTextField(
                    controller: _phone,
                    label: 'Contact number',
                    maxLength: 32,
                  ),
                  AppTextField(
                    controller: _nic,
                    label: 'NIC',
                    maxLength: 24,
                    helperText: 'Optional',
                  ),
                ],
              ),
              AppSpacing.gapLg,
              AppTextField(
                controller: _address,
                label: 'Address',
                maxLines: 2,
                maxLength: 500,
              ),
            ],
          ),
          AppSpacing.gapXl,
          FormSection(
            title: 'Commercial terms',
            children: [
              FormRow(
                children: [
                  AppPercentField(
                    controller: _commission,
                    label: 'Commission',
                    helperText: 'Optional',
                  ),
                  AppMoneyField(
                    controller: _openingBalance,
                    label: 'Opening balance',
                    helperText: hasTransactions
                        ? 'Changing this changes what the agent owes'
                        : 'What the agent owed before going live',
                    enabled: !hasTransactions || existing.isActive,
                  ),
                ],
              ),
              if (hasTransactions) ...[
                AppSpacing.gapMd,
                _BalanceNote(agent: existing),
              ],
            ],
          ),
          AppSpacing.gapXl,
          FormSection(
            title: 'Notes',
            children: [
              AppTextField(
                controller: _notes,
                label: 'Notes',
                maxLines: 3,
                maxLength: 1000,
              ),
            ],
          ),
          if (existing != null) ...[
            AppSpacing.gapLg,
            SwitchListTile(
              value: _status == EntityStatus.active,
              onChanged: (isActive) => setState(() {
                _status = isActive
                    ? EntityStatus.active
                    : EntityStatus.inactive;
              }),
              title: const Text('Active'),
              subtitle: const Text(
                'An inactive agent is not offered on new transfers. Their '
                'stock, history and balance are untouched.',
              ),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ],
      ),
    );
  }
}

/// Explains how the outstanding balance is made up, so the opening balance
/// field is not mistaken for the whole story.
class _BalanceNote extends StatelessWidget {
  const _BalanceNote({required this.agent});

  final AgentListItem agent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: AppRadii.smAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _line(context, 'Opening balance', agent.openingBalance.formatted()),
          _line(context, 'Invoiced since', agent.billedTotal.formatted()),
          _line(
            context,
            'Settled (cleared money and credit notes)',
            '− ${agent.settledTotal.formatted()}',
          ),
          const Divider(height: AppSpacing.lg),
          _line(
            context,
            'Outstanding',
            agent.outstandingBalance.formatted(),
            bold: true,
          ),
          if (!agent.pendingChequeTotal.isZero) ...[
            AppSpacing.gapXs,
            Text(
              'Plus ${agent.pendingChequeTotal.formatted()} in cheques that '
              'have not cleared. Those do not reduce the balance until they '
              'clear.',
              style: context.text.bodySmall?.copyWith(
                color: context.statusColors.warning,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _line(
    BuildContext context,
    String label,
    String value, {
    bool bold = false,
  }) {
    final style = context.text.bodySmall?.copyWith(
      fontWeight: bold ? FontWeight.w700 : null,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}
