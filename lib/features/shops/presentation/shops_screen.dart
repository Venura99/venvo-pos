import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/database/app_database.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/shops/api/shop_api.dart';
import 'package:venvo_core/features/shops/domain/shop_models.dart';

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
import '../../agents/presentation/agents_screen.dart';
import '../../authentication/presentation/auth_controller.dart';
import 'shop_form.dart';

final shopRepositoryProvider = Provider<ShopApi>(
  (ref) => ShopApi(ref.watch(apiClientProvider)),
);

final shopFilterProvider = StateProvider<ShopFilter>(
  (ref) => const ShopFilter(),
);

final shopsProvider = StreamProvider<List<ShopListItem>>((ref) {
  return ref
      .watch(shopRepositoryProvider)
      .watchShops(ref.watch(shopFilterProvider));
});

class ShopsScreen extends ConsumerWidget {
  const ShopsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (!(user?.can(Permissions.shopsView) ?? false)) {
      return const PageScaffold(
        title: 'Shops',
        child: EmptyState(
          icon: Icons.lock_outline,
          title: 'You do not have access to shops',
        ),
      );
    }

    final canManage = user?.can(Permissions.shopsManage) ?? false;
    final shops = ref.watch(shopsProvider);
    final filter = ref.watch(shopFilterProvider);
    final agents =
        ref.watch(selectableAgentsProvider).valueOrNull ?? const <Agent>[];

    return PageScaffold(
      title: 'Shops',
      description:
          'Retail shops supplied through your agents. Each shop holds its own '
          'stock and carries its own balance.',
      scrollable: false,
      actions: [
        if (canManage)
          FilledButton.icon(
            onPressed: () => _openForm(context, ref, null),
            icon: const Icon(Icons.add_business_outlined, size: 18),
            label: const Text('Add shop'),
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
                hintText: 'Search name, code, owner or phone',
                width: 320,
                onChanged: (value) => ref
                    .read(shopFilterProvider.notifier)
                    .update((state) => state.copyWith(search: value)),
              ),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<int?>(
                  initialValue: filter.agentId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Agent'),
                  items: [
                    const DropdownMenuItem<int?>(child: Text('All agents')),
                    for (final agent in agents)
                      DropdownMenuItem<int?>(
                        value: agent.id,
                        child: Text(agent.name),
                      ),
                  ],
                  onChanged: (value) => ref
                      .read(shopFilterProvider.notifier)
                      .update(
                        (state) => value == null
                            ? state.copyWith(clearAgent: true)
                            : state.copyWith(agentId: value),
                      ),
                ),
              ),
              FilterChip(
                selected: filter.owingOnly,
                label: const Text('Owing money'),
                onSelected: (value) => ref
                    .read(shopFilterProvider.notifier)
                    .update((state) => state.copyWith(owingOnly: value)),
              ),
              FilterChip(
                selected: filter.overCreditLimitOnly,
                label: const Text('Over credit limit'),
                avatar: const Icon(Icons.credit_card_off_outlined, size: 16),
                onSelected: (value) => ref
                    .read(shopFilterProvider.notifier)
                    .update(
                      (state) => state.copyWith(overCreditLimitOnly: value),
                    ),
              ),
              FilterChip(
                selected: filter.unassignedOnly,
                label: const Text('No agent'),
                onSelected: (value) => ref
                    .read(shopFilterProvider.notifier)
                    .update((state) => state.copyWith(unassignedOnly: value)),
              ),
              FilterChip(
                selected: filter.includeInactive,
                label: const Text('Include inactive'),
                onSelected: (value) => ref
                    .read(shopFilterProvider.notifier)
                    .update((state) => state.copyWith(includeInactive: value)),
              ),
            ],
          ),
          AppSpacing.gapLg,
          Expanded(
            child: AsyncValueView<List<ShopListItem>>(
              value: shops,
              builder: (context, data) => SectionCard(
                padding: EdgeInsets.zero,
                fillHeight: true,
                child: AppDataTable<ShopListItem>(
                  rows: data,
                  minWidth: 1180,
                  onRowTap: canManage
                      ? (shop) => _openForm(context, ref, shop)
                      : null,
                  empty: EmptyState(
                    icon: Icons.storefront_outlined,
                    title: filter.hasAnyFilter
                        ? 'No shops match these filters'
                        : 'No shops yet',
                    message: filter.hasAnyFilter
                        ? null
                        : 'Add the retail shops your agents supply. Each one '
                              'gets its own stock location.',
                    action: canManage && !filter.hasAnyFilter
                        ? FilledButton.icon(
                            onPressed: () => _openForm(context, ref, null),
                            icon: const Icon(
                              Icons.add_business_outlined,
                              size: 18,
                            ),
                            label: const Text('Add shop'),
                          )
                        : null,
                  ),
                  columns: [
                    AppTableColumn<ShopListItem>(
                      label: 'Shop',
                      flex: 3,
                      cell: (context, row) => TableTwoLineCell(
                        primary: row.name,
                        secondary: row.ownerName == null
                            ? row.code
                            : '${row.code} · ${row.ownerName}',
                      ),
                    ),
                    AppTableColumn<ShopListItem>(
                      label: 'Agent',
                      flex: 2,
                      cell: (context, row) => row.hasAgent
                          ? TableTextCell(row.assignedAgentName ?? '—')
                          : const StatusPill(
                              'No agent',
                              tone: StatusTone.warning,
                            ),
                    ),
                    AppTableColumn<ShopListItem>(
                      label: 'Stock units',
                      width: 100,
                      numeric: true,
                      cell: (context, row) =>
                          TableTextCell('${row.stockUnits}'),
                    ),
                    AppTableColumn<ShopListItem>(
                      label: 'Supplied',
                      width: 120,
                      numeric: true,
                      tooltip: 'Wholesale invoices raised on this shop',
                      cell: (context, row) =>
                          TableTextCell(row.billedTotal.plain),
                    ),
                    AppTableColumn<ShopListItem>(
                      label: 'Retail sales',
                      width: 115,
                      numeric: true,
                      tooltip:
                          'What the shop sold to end customers. Recorded '
                          'separately from what you supplied it.',
                      cell: (context, row) => TableTextCell(
                        row.retailSalesTotal.isZero
                            ? '—'
                            : row.retailSalesTotal.plain,
                        muted: row.retailSalesTotal.isZero,
                      ),
                    ),
                    AppTableColumn<ShopListItem>(
                      label: 'Outstanding',
                      width: 125,
                      numeric: true,
                      cell: (context, row) => Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (row.isOverCreditLimit) ...[
                            Tooltip(
                              message:
                                  'Over the credit limit of '
                                  '${row.creditLimit!.formatted()}',
                              child: Icon(
                                Icons.credit_card_off_outlined,
                                size: 15,
                                color: context.statusColors.danger,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                          ],
                          Text(
                            row.isInCredit
                                ? '(${row.outstandingBalance.abs.plain})'
                                : row.outstandingBalance.plain,
                            style: context.text.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: row.owesMoney
                                  ? context.statusColors.danger
                                  : row.isInCredit
                                  ? context.statusColors.info
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AppTableColumn<ShopListItem>(
                      label: 'Credit limit',
                      width: 110,
                      numeric: true,
                      cell: (context, row) => TableTextCell(
                        row.creditLimit == null
                            ? 'None'
                            : row.creditLimit!.plain,
                        muted: row.creditLimit == null,
                      ),
                    ),
                    AppTableColumn<ShopListItem>(
                      label: 'Status',
                      width: 100,
                      cell: (context, row) => StatusPill.entity(row.status),
                    ),
                    AppTableColumn<ShopListItem>(
                      label: '',
                      width: 56,
                      cell: (context, row) => canManage
                          ? _RowMenu(shop: row)
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AppSpacing.gapSm,
          _SummaryBar(shops: shops.valueOrNull ?? const []),
        ],
      ),
    );
  }

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref,
    ShopListItem? existing,
  ) async {
    final agents = await ref.read(selectableAgentsProvider.future);
    if (!context.mounted) return;

    final saved = await ShopFormDialog.show(
      context,
      agents: agents,
      existing: existing,
    );
    if (saved && context.mounted) {
      showSuccessSnackBar(
        context,
        existing == null
            ? 'Shop added, with its own stock location.'
            : 'Shop saved.',
      );
    }
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.shops});

  final List<ShopListItem> shops;

  @override
  Widget build(BuildContext context) {
    if (shops.isEmpty) return const SizedBox.shrink();

    final outstanding = shops.map((s) => s.outstandingBalance).sum;
    final stockValue = shops.map((s) => s.stockValueAtCost).sum;
    final overLimit = shops.where((s) => s.isOverCreditLimit).length;
    final unassigned = shops.where((s) => !s.hasAgent).length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Wrap(
        spacing: AppSpacing.xl,
        runSpacing: AppSpacing.xs,
        children: [
          Text(
            shops.length == 1 ? '1 shop' : '${shops.length} shops',
            style: context.text.bodySmall,
          ),
          Text(
            'Stock in shops ${stockValue.formatted()}',
            style: context.text.bodySmall,
          ),
          Text(
            'Total outstanding ${outstanding.formatted()}',
            style: context.text.bodySmall?.copyWith(
              color: outstanding.isPositive
                  ? context.statusColors.danger
                  : null,
            ),
          ),
          if (overLimit > 0)
            Text(
              '$overLimit over credit limit',
              style: context.text.bodySmall?.copyWith(
                color: context.statusColors.danger,
              ),
            ),
          if (unassigned > 0)
            Text(
              '$unassigned without an agent',
              style: context.text.bodySmall?.copyWith(
                color: context.statusColors.warning,
              ),
            ),
        ],
      ),
    );
  }
}

class _RowMenu extends ConsumerWidget {
  const _RowMenu({required this.shop});

  final ShopListItem shop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Actions',
      icon: const Icon(Icons.more_horiz, size: 18),
      onSelected: (value) => _handle(context, ref, value),
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'edit', child: Text('Edit')),
        const PopupMenuItem(value: 'reassign', child: Text('Reassign agent')),
        const PopupMenuDivider(),
        if (shop.isArchived)
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
    final repository = ref.read(shopRepositoryProvider);
    final actor = ref.read(requireCurrentUserProvider);

    try {
      switch (action) {
        case 'edit':
          final agents = await ref.read(selectableAgentsProvider.future);
          if (!context.mounted) return;
          await ShopFormDialog.show(context, agents: agents, existing: shop);
        case 'reassign':
          final agents = await ref.read(selectableAgentsProvider.future);
          if (!context.mounted) return;
          await _reassign(context, ref, agents);
        case 'archive':
          final confirmed = await ConfirmDialog.show(
            context,
            title: 'Archive ${shop.name}?',
            message:
                'It will not be offered on new supply documents. Every past '
                'invoice, payment and balance is kept exactly as it is.',
            details: [
              'Stock held: ${shop.stockUnits} unit(s)',
              'Outstanding: ${shop.outstandingBalance.formatted()}',
            ],
            confirmLabel: 'Archive',
            icon: Icons.archive_outlined,
          );
          if (!confirmed) return;
          await repository.archive(actor, shop.id);
          if (context.mounted) showSuccessSnackBar(context, 'Shop archived.');
        case 'restore':
          await repository.restore(actor, shop.id);
          if (context.mounted) showSuccessSnackBar(context, 'Shop restored.');
      }
    } catch (error) {
      if (context.mounted) showFailureSnackBar(context, error);
    }
  }

  /// Dedicated reassignment flow, so the change is deliberate and carries a
  /// reason into the audit log.
  Future<void> _reassign(
    BuildContext context,
    WidgetRef ref,
    List<Agent> agents,
  ) async {
    var selectedAgentId = shop.assignedAgentId;
    final reasonController = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AppFormDialog(
          title: 'Reassign ${shop.name}',
          subtitle: shop.assignedAgentName == null
              ? 'This shop has no agent at the moment.'
              : 'Currently served by ${shop.assignedAgentName}.',
          submitLabel: 'Reassign',
          width: 520,
          onSubmit: () => ref
              .read(shopRepositoryProvider)
              .reassignAgent(
                ref.read(requireCurrentUserProvider),
                shopId: shop.id,
                agentId: selectedAgentId,
                reason: reasonController.text,
              ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              AppDropdownField<int?>(
                value: selectedAgentId,
                label: 'New agent',
                items: [
                  const DropdownMenuItem<int?>(child: Text('Not assigned')),
                  for (final agent in agents)
                    DropdownMenuItem<int?>(
                      value: agent.id,
                      child: Text('${agent.name} (${agent.code})'),
                    ),
                ],
                onChanged: (value) => setState(() => selectedAgentId = value),
              ),
              AppSpacing.gapLg,
              AppTextField(
                controller: reasonController,
                label: 'Reason',
                maxLines: 2,
                maxLength: 300,
                helperText: 'Recorded in the audit log',
              ),
              AppSpacing.gapLg,
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: context.colors.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: AppRadii.smAll,
                ),
                child: Text(
                  'Only who supplies this shop from now on changes. Every '
                  'invoice, transfer and payment already recorded keeps its '
                  'original agent, so agent-wise history and commission stay '
                  'correct for both agents.',
                  style: context.text.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    reasonController.dispose();
    if ((saved ?? false) && context.mounted) {
      showSuccessSnackBar(context, 'Shop reassigned.');
    }
  }
}
