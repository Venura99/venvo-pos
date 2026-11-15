import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:venvo_core/core/constants/app_constants.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/inventory/domain/location_models.dart';

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
import 'location_providers.dart';

/// Warehouses and every other place stock can sit.
///
/// Agent and shop locations appear here but are maintained from the agent and
/// shop screens, because they exist only as long as their party does. Only
/// warehouses can be created or renamed here.
class LocationsScreen extends ConsumerWidget {
  const LocationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (!(user?.can(Permissions.stockView) ?? false)) {
      return const PageScaffold(
        title: 'Warehouses & Locations',
        child: EmptyState(
          icon: Icons.lock_outline,
          title: 'You do not have access to stock locations',
        ),
      );
    }

    final canManage = user?.can(Permissions.stockAdjust) ?? false;
    final locations = ref.watch(locationsProvider);
    final showVirtual = ref.watch(showVirtualLocationsProvider);

    return PageScaffold(
      title: 'Warehouses & Locations',
      description:
          'Every place stock can sit. Agent and shop locations are created '
          'and maintained with their agent or shop; warehouses are managed '
          'here.',
      scrollable: false,
      actions: [
        if (canManage)
          FilledButton.icon(
            onPressed: () => _addWarehouse(context, ref),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add warehouse'),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              FilterChip(
                selected: showVirtual,
                label: const Text('Show virtual counterparties'),
                avatar: const Icon(Icons.hub_outlined, size: 16),
                onSelected: (value) =>
                    ref.read(showVirtualLocationsProvider.notifier).state =
                        value,
              ),
              AppSpacing.hGapLg,
              Expanded(
                child: Text(
                  showVirtual
                      ? 'Virtual locations hold no real goods. They are the '
                            'counterparty on every movement, which is what makes '
                            'the ledger balance to zero.'
                      : '',
                  style: context.text.bodySmall,
                ),
              ),
            ],
          ),
          AppSpacing.gapLg,
          Expanded(
            child: AsyncValueView<List<LocationListItem>>(
              value: locations,
              builder: (context, data) => SectionCard(
                padding: EdgeInsets.zero,
                fillHeight: true,
                child: AppDataTable<LocationListItem>(
                  rows: data,
                  minWidth: 980,
                  empty: const EmptyState(
                    icon: Icons.warehouse_outlined,
                    title: 'No locations',
                    message:
                        'The main warehouse is created automatically, so this '
                        'should not happen. Restore a backup if it does.',
                  ),
                  columns: [
                    AppTableColumn<LocationListItem>(
                      label: 'Location',
                      flex: 3,
                      cell: (context, row) => TableTwoLineCell(
                        primary: row.name,
                        secondary: row.code,
                      ),
                    ),
                    AppTableColumn<LocationListItem>(
                      label: 'Kind',
                      flex: 2,
                      cell: (context, row) => Tooltip(
                        message: locationKindExplanation(row.kind),
                        child: TableTextCell(
                          locationKindLabel(row.kind),
                          muted: row.isVirtual,
                        ),
                      ),
                    ),
                    AppTableColumn<LocationListItem>(
                      label: 'Products',
                      width: 90,
                      numeric: true,
                      tooltip: 'Distinct products with a non-zero balance',
                      cell: (context, row) =>
                          TableTextCell('${row.productLines}'),
                    ),
                    AppTableColumn<LocationListItem>(
                      label: 'Units',
                      width: 100,
                      numeric: true,
                      cell: (context, row) => Text(
                        '${row.totalUnits}',
                        style: context.text.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: row.hasNegativeStock
                              ? context.statusColors.danger
                              : null,
                        ),
                      ),
                    ),
                    AppTableColumn<LocationListItem>(
                      label: 'Value at cost',
                      width: 130,
                      numeric: true,
                      cell: (context, row) => TableTextCell(
                        row.isVirtual ? '—' : row.stockValueAtCost.plain,
                        muted: row.isVirtual,
                      ),
                    ),
                    AppTableColumn<LocationListItem>(
                      label: 'Status',
                      width: 110,
                      cell: (context, row) => row.isActive
                          ? const StatusPill('Active', tone: StatusTone.success)
                          : const StatusPill('Inactive'),
                    ),
                    AppTableColumn<LocationListItem>(
                      label: '',
                      width: 56,
                      cell: (context, row) =>
                          canManage && row.kind == LocationKind.warehouse
                          ? _WarehouseMenu(location: row)
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AppSpacing.gapSm,
          _SummaryBar(locations: locations.valueOrNull ?? const []),
        ],
      ),
    );
  }

  Future<void> _addWarehouse(BuildContext context, WidgetRef ref) async {
    final nameController = TextEditingController();

    final saved = await AppFormDialog.show(
      context,
      title: 'Add warehouse',
      subtitle:
          'A second warehouse can receive and hold stock like the main '
          'one. Its code is allocated automatically.',
      submitLabel: 'Add warehouse',
      child: AppTextField(
        controller: nameController,
        label: 'Warehouse name',
        isRequired: true,
        autofocus: true,
        maxLength: 180,
        textCapitalization: TextCapitalization.words,
      ),
      onSubmit: () => ref
          .read(locationRepositoryProvider)
          .createWarehouse(
            ref.read(requireCurrentUserProvider),
            name: nameController.text,
          ),
    );

    nameController.dispose();
    if (saved && context.mounted) {
      showSuccessSnackBar(context, 'Warehouse added.');
    }
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.locations});

  final List<LocationListItem> locations;

  @override
  Widget build(BuildContext context) {
    if (locations.isEmpty) return const SizedBox.shrink();

    final real = locations.where((l) => !l.isVirtual).toList();
    final totalValue = real.map((l) => l.stockValueAtCost).sum;
    final negative = real.where((l) => l.hasNegativeStock).length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Wrap(
        spacing: AppSpacing.xl,
        runSpacing: AppSpacing.xs,
        children: [
          Text(
            '${real.length} real location(s)',
            style: context.text.bodySmall,
          ),
          Text(
            'Stock value at cost ${totalValue.formatted()}',
            style: context.text.bodySmall,
          ),
          if (negative > 0)
            Text(
              '$negative location(s) with negative stock — investigate these',
              style: context.text.bodySmall?.copyWith(
                color: context.statusColors.danger,
              ),
            ),
        ],
      ),
    );
  }
}

class _WarehouseMenu extends ConsumerWidget {
  const _WarehouseMenu({required this.location});

  final LocationListItem location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMain = location.code == AppConstants.mainWarehouseCode;

    return PopupMenuButton<String>(
      tooltip: 'Actions',
      icon: const Icon(Icons.more_horiz, size: 18),
      onSelected: (value) => _handle(context, ref, value),
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'rename', child: Text('Rename')),
        if (!isMain)
          if (location.isActive)
            const PopupMenuItem(value: 'deactivate', child: Text('Deactivate'))
          else
            const PopupMenuItem(value: 'activate', child: Text('Activate')),
      ],
    );
  }

  Future<void> _handle(
    BuildContext context,
    WidgetRef ref,
    String action,
  ) async {
    final repository = ref.read(locationRepositoryProvider);
    final actor = ref.read(requireCurrentUserProvider);

    try {
      switch (action) {
        case 'rename':
          final controller = TextEditingController(text: location.name);
          final saved = await AppFormDialog.show(
            context,
            title: 'Rename warehouse',
            submitLabel: 'Rename',
            child: AppTextField(
              controller: controller,
              label: 'Warehouse name',
              isRequired: true,
              autofocus: true,
              maxLength: 180,
            ),
            onSubmit: () => repository.renameWarehouse(
              actor,
              locationId: location.id,
              name: controller.text,
            ),
          );
          controller.dispose();
          if (saved && context.mounted) {
            showSuccessSnackBar(context, 'Warehouse renamed.');
          }
        case 'deactivate':
          final confirmed = await ConfirmDialog.show(
            context,
            title: 'Deactivate ${location.name}?',
            message:
                'It will not be offered as a source or destination on new '
                'documents. Its history is kept.',
            confirmLabel: 'Deactivate',
            icon: Icons.block_outlined,
          );
          if (!confirmed) return;
          await repository.setWarehouseActive(
            actor,
            locationId: location.id,
            isActive: false,
          );
          if (context.mounted) {
            showSuccessSnackBar(context, 'Warehouse deactivated.');
          }
        case 'activate':
          await repository.setWarehouseActive(
            actor,
            locationId: location.id,
            isActive: true,
          );
          if (context.mounted) {
            showSuccessSnackBar(context, 'Warehouse activated.');
          }
      }
    } catch (error) {
      if (context.mounted) showFailureSnackBar(context, error);
    }
  }
}
