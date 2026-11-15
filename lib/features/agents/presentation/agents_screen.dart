import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/agents/api/agent_api.dart';
import 'package:venvo_core/features/agents/domain/agent_models.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/app_data_table.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/feedback_views.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/status_pill.dart';
import '../../authentication/presentation/auth_controller.dart';
import 'agent_form.dart';

final agentRepositoryProvider = Provider<AgentApi>(
  (ref) => AgentApi(ref.watch(apiClientProvider)),
);

final agentFilterProvider = StateProvider<AgentFilter>(
  (ref) => const AgentFilter(),
);

final agentsProvider = StreamProvider<List<AgentListItem>>((ref) {
  return ref
      .watch(agentRepositoryProvider)
      .watchAgents(ref.watch(agentFilterProvider));
});

/// Active agents, for the shop form's agent picker and later for documents.
final selectableAgentsProvider = FutureProvider((ref) {
  // Re-resolved whenever the agent list changes, so a newly added agent is
  // immediately assignable.
  ref.watch(agentsProvider);
  return ref.watch(agentRepositoryProvider).selectableAgents();
});

class AgentsScreen extends ConsumerWidget {
  const AgentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (!(user?.can(Permissions.agentsView) ?? false)) {
      return const PageScaffold(
        title: 'Agents',
        child: EmptyState(
          icon: Icons.lock_outline,
          title: 'You do not have access to agents',
        ),
      );
    }

    final canManage = user?.can(Permissions.agentsManage) ?? false;
    final agents = ref.watch(agentsProvider);
    final filter = ref.watch(agentFilterProvider);
    final rows = agents.valueOrNull ?? const <AgentListItem>[];

    return PageScaffold(
      title: 'Agents',
      description:
          'Each agent holds their own stock and carries their own balance. '
          'A stock location is created for every agent automatically.',
      scrollable: false,
      actions: [
        if (canManage)
          FilledButton.icon(
            onPressed: () => _openForm(context, ref, null),
            icon: const Icon(Icons.person_add_outlined, size: 18),
            label: const Text('Add agent'),
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
                hintText: 'Search name, code, phone or NIC',
                width: 320,
                onChanged: (value) => ref
                    .read(agentFilterProvider.notifier)
                    .update((state) => state.copyWith(search: value)),
              ),
              FilterChip(
                selected: filter.owingOnly,
                label: const Text('Owing money'),
                onSelected: (value) => ref
                    .read(agentFilterProvider.notifier)
                    .update((state) => state.copyWith(owingOnly: value)),
              ),
              FilterChip(
                selected: filter.includeInactive,
                label: const Text('Include inactive'),
                onSelected: (value) => ref
                    .read(agentFilterProvider.notifier)
                    .update((state) => state.copyWith(includeInactive: value)),
              ),
              FilterChip(
                selected: filter.includeArchived,
                label: const Text('Include archived'),
                onSelected: (value) => ref
                    .read(agentFilterProvider.notifier)
                    .update((state) => state.copyWith(includeArchived: value)),
              ),
            ],
          ),
          AppSpacing.gapLg,
          Expanded(
            child: AsyncValueView<List<AgentListItem>>(
              value: agents,
              builder: (context, data) => SectionCard(
                padding: EdgeInsets.zero,
                fillHeight: true,
                child: AppDataTable<AgentListItem>(
                  rows: data,
                  minWidth: 1100,
                  onRowTap: canManage
                      ? (agent) => _openForm(context, ref, agent)
                      : null,
                  empty: EmptyState(
                    icon: Icons.badge_outlined,
                    title: filter.hasAnyFilter
                        ? 'No agents match these filters'
                        : 'No agents yet',
                    message: filter.hasAnyFilter
                        ? null
                        : 'Add the agents you distribute through. Each one '
                              'gets a stock location so you can transfer goods '
                              'to them.',
                    action: canManage && !filter.hasAnyFilter
                        ? FilledButton.icon(
                            onPressed: () => _openForm(context, ref, null),
                            icon: const Icon(
                              Icons.person_add_outlined,
                              size: 18,
                            ),
                            label: const Text('Add agent'),
                          )
                        : null,
                  ),
                  columns: [
                    AppTableColumn<AgentListItem>(
                      label: 'Agent',
                      flex: 3,
                      cell: (context, row) => TableTwoLineCell(
                        primary: row.name,
                        secondary: row.phone == null
                            ? row.code
                            : '${row.code} · ${row.phone}',
                      ),
                    ),
                    AppTableColumn<AgentListItem>(
                      label: 'Shops',
                      width: 80,
                      numeric: true,
                      tooltip: 'Active shops this agent serves',
                      cell: (context, row) =>
                          TableTextCell('${row.activeShopCount}'),
                    ),
                    AppTableColumn<AgentListItem>(
                      label: 'Stock units',
                      width: 110,
                      numeric: true,
                      tooltip: 'Units the agent is currently holding',
                      cell: (context, row) =>
                          TableTextCell('${row.stockUnits}'),
                    ),
                    AppTableColumn<AgentListItem>(
                      label: 'Stock value',
                      width: 120,
                      numeric: true,
                      cell: (context, row) =>
                          TableTextCell(row.stockValueAtCost.plain),
                    ),
                    AppTableColumn<AgentListItem>(
                      label: 'Commission',
                      width: 100,
                      numeric: true,
                      cell: (context, row) => TableTextCell(
                        row.commissionBps == null
                            ? '—'
                            : formatBps(row.commissionBps!),
                        muted: row.commissionBps == null,
                      ),
                    ),
                    AppTableColumn<AgentListItem>(
                      label: 'Outstanding',
                      width: 130,
                      numeric: true,
                      tooltip:
                          'Opening balance plus invoices, less cleared '
                          'money and credit notes',
                      cell: (context, row) => Text(
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
                    ),
                    AppTableColumn<AgentListItem>(
                      label: 'Cheques pending',
                      width: 130,
                      numeric: true,
                      tooltip: 'Received but not cleared, so not yet settled',
                      cell: (context, row) => TableTextCell(
                        row.pendingChequeTotal.isZero
                            ? '—'
                            : row.pendingChequeTotal.plain,
                        muted: row.pendingChequeTotal.isZero,
                      ),
                    ),
                    AppTableColumn<AgentListItem>(
                      label: 'Status',
                      width: 100,
                      cell: (context, row) => StatusPill.entity(row.status),
                    ),
                    AppTableColumn<AgentListItem>(
                      label: '',
                      width: 56,
                      cell: (context, row) => canManage
                          ? _RowMenu(agent: row)
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AppSpacing.gapSm,
          _SummaryBar(agents: rows),
        ],
      ),
    );
  }

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref,
    AgentListItem? existing,
  ) async {
    final saved = await AgentFormDialog.show(context, existing: existing);
    if (saved && context.mounted) {
      showSuccessSnackBar(
        context,
        existing == null
            ? 'Agent added, with a stock location ready for transfers.'
            : 'Agent saved.',
      );
    }
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.agents});

  final List<AgentListItem> agents;

  @override
  Widget build(BuildContext context) {
    if (agents.isEmpty) return const SizedBox.shrink();

    final outstanding = agents.map((a) => a.outstandingBalance).sum;
    final stockValue = agents.map((a) => a.stockValueAtCost).sum;
    final pendingCheques = agents.map((a) => a.pendingChequeTotal).sum;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Wrap(
        spacing: AppSpacing.xl,
        runSpacing: AppSpacing.xs,
        children: [
          Text(
            agents.length == 1 ? '1 agent' : '${agents.length} agents',
            style: context.text.bodySmall,
          ),
          Text(
            'Stock with agents ${stockValue.formatted()}',
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
          if (!pendingCheques.isZero)
            Text(
              'Cheques pending ${pendingCheques.formatted()}',
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
  const _RowMenu({required this.agent});

  final AgentListItem agent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Actions',
      icon: const Icon(Icons.more_horiz, size: 18),
      onSelected: (value) => _handle(context, ref, value),
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'edit', child: Text('Edit')),
        const PopupMenuDivider(),
        if (agent.isArchived)
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
    final repository = ref.read(agentRepositoryProvider);
    final actor = ref.read(requireCurrentUserProvider);

    try {
      switch (action) {
        case 'edit':
          await AgentFormDialog.show(context, existing: agent);
        case 'archive':
          final confirmed = await ConfirmDialog.show(
            context,
            title: 'Archive ${agent.name}?',
            message:
                'They will not be offered on new transfers. Every past '
                'document, payment and balance is kept exactly as it is.',
            details: [
              'Stock held: ${agent.stockUnits} unit(s)',
              'Active shops: ${agent.activeShopCount}',
              'Outstanding: ${agent.outstandingBalance.formatted()}',
            ],
            confirmLabel: 'Archive',
            icon: Icons.archive_outlined,
          );
          if (!confirmed) return;
          await repository.archive(actor, agent.id);
          if (context.mounted) showSuccessSnackBar(context, 'Agent archived.');
        case 'restore':
          await repository.restore(actor, agent.id);
          if (context.mounted) showSuccessSnackBar(context, 'Agent restored.');
      }
    } catch (error) {
      if (context.mounted) showFailureSnackBar(context, error);
    }
  }
}
