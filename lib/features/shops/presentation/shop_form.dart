import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:venvo_core/core/database/app_database.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/features/shops/domain/shop_models.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/form_dialog.dart';
import '../../../core/widgets/form_fields.dart';
import '../../authentication/presentation/auth_controller.dart';
import 'shops_screen.dart';

/// Create/edit form for a shop.
///
/// The agent assignment can be changed here, but a change is recorded as a
/// reassignment in its own right, because it affects which agent is
/// responsible for the shop from now on without touching any past document.
class ShopFormDialog extends ConsumerStatefulWidget {
  const ShopFormDialog({super.key, required this.agents, this.existing});

  final ShopListItem? existing;
  final List<Agent> agents;

  static Future<bool> show(
    BuildContext context, {
    required List<Agent> agents,
    ShopListItem? existing,
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ShopFormDialog(agents: agents, existing: existing),
    );
    return saved ?? false;
  }

  @override
  ConsumerState<ShopFormDialog> createState() => _ShopFormDialogState();
}

class _ShopFormDialogState extends ConsumerState<ShopFormDialog> {
  late final TextEditingController _code;
  late final TextEditingController _name;
  late final TextEditingController _ownerName;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  late final TextEditingController _openingBalance;
  late final TextEditingController _creditLimit;
  late final TextEditingController _notes;
  int? _agentId;
  late EntityStatus _status;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;

    _code = TextEditingController(text: existing?.code ?? '');
    _name = TextEditingController(text: existing?.name ?? '');
    _ownerName = TextEditingController(text: existing?.ownerName ?? '');
    _phone = TextEditingController(text: existing?.phone ?? '');
    _address = TextEditingController(text: existing?.address ?? '');
    _notes = TextEditingController(text: existing?.notes ?? '');

    _openingBalance = TextEditingController();
    if (existing != null) {
      AppMoneyField.setValue(_openingBalance, existing.openingBalance);
    }
    _creditLimit = TextEditingController();
    if (existing?.creditLimit != null) {
      AppMoneyField.setValue(_creditLimit, existing!.creditLimit!);
    }

    _agentId =
        existing?.assignedAgentId ??
        (widget.agents.length == 1 ? widget.agents.first.id : null);
    _status = existing?.status ?? EntityStatus.active;
  }

  @override
  void dispose() {
    for (final controller in [
      _code,
      _name,
      _ownerName,
      _phone,
      _address,
      _openingBalance,
      _creditLimit,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final repository = ref.read(shopRepositoryProvider);
    final actor = ref.read(requireCurrentUserProvider);
    final limit = AppMoneyField.valueOf(_creditLimit);

    final draft = ShopDraft(
      id: widget.existing?.id,
      code: _code.text,
      name: _name.text,
      ownerName: _ownerName.text,
      phone: _phone.text,
      address: _address.text,
      assignedAgentId: _agentId,
      openingBalance: AppMoneyField.valueOrZero(_openingBalance),
      creditLimit: limit,
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
    final agentChanged =
        existing != null && _agentId != existing.assignedAgentId;

    return AppFormDialog(
      title: existing == null ? 'Add shop' : 'Edit shop',
      subtitle: existing == null
          ? 'A stock location is created for the shop automatically.'
          : 'Outstanding balance ${existing.outstandingBalance.formatted()}',
      submitLabel: existing == null ? 'Add shop' : 'Save changes',
      width: 640,
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
                    label: 'Shop name',
                    isRequired: true,
                    autofocus: true,
                    maxLength: 180,
                    textCapitalization: TextCapitalization.words,
                  ),
                  AppTextField(
                    controller: _code,
                    label: 'Shop code',
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
                    controller: _ownerName,
                    label: 'Owner name',
                    maxLength: 180,
                    textCapitalization: TextCapitalization.words,
                  ),
                  AppTextField(
                    controller: _phone,
                    label: 'Contact number',
                    maxLength: 32,
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
            title: 'Agent',
            description:
                'The agent responsible for supplying this shop from now on. '
                'Past documents keep the agent they were created with.',
            children: [
              AppDropdownField<int?>(
                value: _agentId,
                label: 'Assigned agent',
                items: [
                  const DropdownMenuItem<int?>(child: Text('Not assigned')),
                  for (final agent in widget.agents)
                    DropdownMenuItem<int?>(
                      value: agent.id,
                      child: Text('${agent.name} (${agent.code})'),
                    ),
                ],
                onChanged: (value) => setState(() => _agentId = value),
              ),
              if (agentChanged) ...[
                AppSpacing.gapMd,
                _InfoNote(
                  icon: Icons.swap_horiz,
                  message: existing.assignedAgentName == null
                      ? 'This shop will be assigned to an agent. Nothing '
                            'already recorded changes.'
                      : 'This shop will move from '
                            '${existing.assignedAgentName} to the agent you '
                            'selected. Every invoice, transfer and payment '
                            'already recorded keeps its original agent.',
                ),
              ],
              if (widget.agents.isEmpty) ...[
                AppSpacing.gapMd,
                const _InfoNote(
                  icon: Icons.info_outline,
                  message:
                      'There are no active agents yet. You can add the shop '
                      'now and assign an agent later.',
                ),
              ],
            ],
          ),
          AppSpacing.gapXl,
          FormSection(
            title: 'Credit terms',
            children: [
              FormRow(
                children: [
                  AppMoneyField(
                    controller: _openingBalance,
                    label: 'Opening balance',
                    helperText: hasTransactions
                        ? 'Changing this changes what the shop owes'
                        : 'What the shop owed before going live',
                  ),
                  AppMoneyField(
                    controller: _creditLimit,
                    label: 'Credit limit',
                    helperText: 'Leave empty for no limit',
                  ),
                ],
              ),
              if (existing != null && existing.isOverCreditLimit) ...[
                AppSpacing.gapMd,
                _InfoNote(
                  icon: Icons.warning_amber_outlined,
                  isWarning: true,
                  message:
                      'This shop already owes '
                      '${existing.outstandingBalance.formatted()}, which is '
                      'over its limit of '
                      '${existing.creditLimit!.formatted()}.',
                ),
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
                'An inactive shop is not offered on new supply documents. Its '
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

class _InfoNote extends StatelessWidget {
  const _InfoNote({
    required this.icon,
    required this.message,
    this.isWarning = false,
  });

  final IconData icon;
  final String message;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    final colors = context.statusColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isWarning
            ? colors.warningContainer
            : colors.infoContainer.withValues(alpha: 0.6),
        borderRadius: AppRadii.smAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 16,
            color: isWarning
                ? colors.onWarningContainer
                : colors.onInfoContainer,
          ),
          AppSpacing.hGapSm,
          Expanded(
            child: Text(
              message,
              style: context.text.bodySmall?.copyWith(
                color: isWarning
                    ? colors.onWarningContainer
                    : colors.onInfoContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
