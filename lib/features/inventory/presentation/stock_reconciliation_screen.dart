import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/features/inventory/domain/stock_models.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/feedback_views.dart';
import '../../../core/widgets/form_dialog.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/status_pill.dart';
import '../../authentication/presentation/auth_controller.dart';
import 'stock_providers.dart';

/// Physical stock counts and the variances they produce.
///
/// The system's quantities are captured when the sheet is opened, so a
/// movement posted while the count is being taken cannot silently change the
/// variance. Posting turns the differences into adjustment documents through
/// the adjustment counterparty.
class StockReconciliationScreen extends ConsumerWidget {
  const StockReconciliationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (!(user?.can(Permissions.stockReconcile) ?? false)) {
      return const PageScaffold(
        title: 'Stock Reconciliation',
        child: EmptyState(
          icon: Icons.lock_outline,
          title: 'You do not have access to reconciliation',
          message: 'Ask an administrator for the "Reconcile stock" permission.',
        ),
      );
    }

    final counts = ref.watch(stockCountsProvider);
    final selected = ref.watch(selectedStockCountProvider);

    return PageScaffold(
      title: 'Stock Reconciliation',
      description:
          'Count what is physically there, compare it with what the system '
          'believes, and post the difference as an adjustment.',
      scrollable: false,
      actions: [
        FilledButton.icon(
          onPressed: () => _startCount(context, ref),
          icon: const Icon(Icons.fact_check_outlined, size: 18),
          label: const Text('Start a count'),
        ),
      ],
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 330,
            child: AsyncValueView<List<StockCountSheet>>(
              value: counts,
              builder: (context, rows) => _CountList(counts: rows),
            ),
          ),
          AppSpacing.hGapLg,
          Expanded(
            child: AsyncValueView<StockCountSheet?>(
              value: selected,
              builder: (context, sheet) => sheet == null
                  ? const SectionCard(
                      child: EmptyState(
                        icon: Icons.fact_check_outlined,
                        title: 'No count selected',
                        message:
                            'Start a count, or pick one from the list to '
                            'enter what you found.',
                      ),
                    )
                  : _CountSheetView(sheet: sheet),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startCount(BuildContext context, WidgetRef ref) async {
    final locations = ref
        .read(stockLocationsProvider)
        .where(
          (location) => location.kind.isStockHolding && !location.isVirtual,
        )
        .toList();
    if (locations.isEmpty) return;

    var locationId = locations.first.id;
    var includeZero = false;
    final notesController = TextEditingController();

    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AppFormDialog(
          title: 'Start a stock count',
          subtitle:
              'The system quantities are captured now, so later movements '
              'cannot change the variance behind your back.',
          submitLabel: 'Open the count sheet',
          width: 520,
          onSubmit: () async {
            final countId = await ref
                .read(stockCountRepositoryProvider)
                .createCount(
                  ref.read(requireCurrentUserProvider),
                  locationId: locationId,
                  includeZeroStock: includeZero,
                  notes: notesController.text,
                );
            ref.read(selectedStockCountIdProvider.notifier).state = countId;
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              AppDropdownField<int>(
                value: locationId,
                label: 'Location to count',
                isRequired: true,
                items: [
                  for (final location in locations)
                    DropdownMenuItem<int>(
                      value: location.id,
                      child: Text(location.name),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => locationId = value ?? locationId),
              ),
              AppSpacing.gapLg,
              SwitchListTile(
                value: includeZero,
                onChanged: (value) => setState(() => includeZero = value),
                title: const Text('Include products with no stock recorded'),
                subtitle: const Text(
                  'A full stock-take needs these: a product the system thinks '
                  'it has none of may well be on the shelf.',
                ),
                contentPadding: EdgeInsets.zero,
              ),
              AppSpacing.gapLg,
              AppTextField(
                controller: notesController,
                label: 'Notes',
                maxLines: 2,
                maxLength: 1000,
              ),
            ],
          ),
        ),
      ),
    );

    notesController.dispose();
    if ((created ?? false) && context.mounted) {
      showSuccessSnackBar(context, 'Count sheet opened.');
    }
  }
}

class _CountList extends ConsumerWidget {
  const _CountList({required this.counts});

  final List<StockCountSheet> counts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedStockCountIdProvider);

    return SectionCard(
      title: 'Counts',
      padding: EdgeInsets.zero,
      fillHeight: true,
      child: counts.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Text('No counts yet.'),
            )
          : ListView.separated(
              itemCount: counts.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final sheet = counts[index];
                return ListTile(
                  dense: true,
                  selected: sheet.id == selectedId,
                  title: Text(sheet.documentNumber),
                  subtitle: Text(
                    '${sheet.locationName}\n'
                    '${DateFormat('d MMM yyyy, HH:mm').format(sheet.countDate.toLocal())}',
                  ),
                  isThreeLine: true,
                  trailing: StatusPill.document(sheet.status),
                  onTap: () =>
                      ref.read(selectedStockCountIdProvider.notifier).state =
                          sheet.id,
                );
              },
            ),
    );
  }
}

class _CountSheetView extends ConsumerStatefulWidget {
  const _CountSheetView({required this.sheet});

  final StockCountSheet sheet;

  @override
  ConsumerState<_CountSheetView> createState() => _CountSheetViewState();
}

class _CountSheetViewState extends ConsumerState<_CountSheetView> {
  final Map<int, TextEditingController> _controllers = {};
  String _search = '';

  @override
  void didUpdateWidget(_CountSheetView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sheet.id != widget.sheet.id) {
      _disposeControllers();
      setState(() => _search = '');
    }
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _disposeControllers() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
  }

  TextEditingController _controllerFor(StockCountLine line) {
    return _controllers.putIfAbsent(
      line.productId,
      () => TextEditingController(text: line.countedQuantity?.toString() ?? ''),
    );
  }

  Map<int, int?> _collectCounts() {
    final counts = <int, int?>{};
    for (final entry in _controllers.entries) {
      final text = entry.value.text.trim();
      counts[entry.key] = text.isEmpty ? null : int.tryParse(text);
    }
    return counts;
  }

  Future<void> _save() async {
    try {
      await ref
          .read(stockCountRepositoryProvider)
          .saveCountedQuantities(
            ref.read(requireCurrentUserProvider),
            countId: widget.sheet.id,
            countedByProductId: _collectCounts(),
          );
      ref.invalidate(selectedStockCountProvider);
      if (mounted) showSuccessSnackBar(context, 'Counted quantities saved.');
    } catch (error) {
      if (mounted) showFailureSnackBar(context, error);
    }
  }

  Future<void> _post() async {
    // Save first, so what is on screen is what gets posted.
    await _save();
    if (!mounted) return;

    final sheet = await ref
        .read(stockCountRepositoryProvider)
        .loadCount(widget.sheet.id);
    final value = await ref
        .read(stockCountRepositoryProvider)
        .varianceValue(sheet.id);
    if (!mounted) return;

    if (!sheet.hasVariances) {
      final confirmed = await ConfirmDialog.show(
        context,
        title: 'No variances found',
        message:
            'Everything counted matches the system. Posting will close the '
            'count without changing any stock.',
        confirmLabel: 'Close the count',
        icon: Icons.check_circle_outline,
      );
      if (!confirmed) return;
    } else {
      final confirmed = await ConfirmDialog.show(
        context,
        title: 'Post ${sheet.documentNumber}?',
        message:
            'This writes adjustment documents through the adjustment '
            'counterparty. The count itself stays on the record either way.',
        details: [
          '${sheet.variances.length} line(s) with a variance',
          'Surplus: ${sheet.surplusUnits} unit(s)',
          'Shortage: ${sheet.shortageUnits} unit(s)',
          'Net value effect: ${value.formatted()}',
        ],
        confirmLabel: 'Post the adjustment',
        isDestructive: true,
        icon: Icons.tune,
      );
      if (!confirmed) return;
    }

    try {
      final results = await ref
          .read(stockCountRepositoryProvider)
          .postCount(ref.read(requireCurrentUserProvider), countId: sheet.id);
      ref.invalidate(selectedStockCountProvider);
      if (mounted) {
        showSuccessSnackBar(
          context,
          results.isEmpty
              ? 'Count closed with no adjustment needed.'
              : 'Posted ${results.map((r) => r.documentNumber).join(' and ')}.',
        );
      }
    } catch (error) {
      if (mounted) showFailureSnackBar(context, error);
    }
  }

  Future<void> _discard() async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Discard ${widget.sheet.documentNumber}?',
      message:
          'Nothing it recorded affected stock, so the sheet is removed rather '
          'than kept as noise.',
      confirmLabel: 'Discard',
      isDestructive: true,
      icon: Icons.delete_outline,
    );
    if (!confirmed) return;

    try {
      await ref
          .read(stockCountRepositoryProvider)
          .discardCount(ref.read(requireCurrentUserProvider), widget.sheet.id);
      ref.read(selectedStockCountIdProvider.notifier).state = null;
      if (mounted) showSuccessSnackBar(context, 'Count discarded.');
    } catch (error) {
      if (mounted) showFailureSnackBar(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sheet = widget.sheet;
    final isDraft = sheet.status == StockDocumentStatus.draft;
    final query = _search.trim().toLowerCase();
    final lines = query.isEmpty
        ? sheet.lines
        : sheet.lines
              .where(
                (line) =>
                    line.productName.toLowerCase().contains(query) ||
                    line.sku.toLowerCase().contains(query),
              )
              .toList(growable: false);

    return SectionCard(
      title: '${sheet.documentNumber} · ${sheet.locationName}',
      subtitle: isDraft
          ? 'Enter what you actually found. Leave a line blank if it was not '
                'counted.'
          : 'Posted on '
                '${DateFormat('d MMM yyyy, HH:mm').format(sheet.countDate.toLocal())}. '
                'This sheet is now read-only.',
      padding: EdgeInsets.zero,
      fillHeight: true,
      actions: [
        if (isDraft) ...[
          TextButton(onPressed: _discard, child: const Text('Discard')),
          OutlinedButton(onPressed: _save, child: const Text('Save')),
          FilledButton(onPressed: _post, child: const Text('Post')),
        ] else
          StatusPill.document(sheet.status),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                AppSearchField(
                  hintText: 'Find a product on this sheet',
                  width: 300,
                  onChanged: (value) => setState(() => _search = value),
                ),
                const Spacer(),
                _SheetSummary(sheet: sheet),
              ],
            ),
          ),
          const Divider(height: 1),
          _SheetHeader(),
          const Divider(height: 1),
          Expanded(
            child: lines.isEmpty
                ? const EmptyState(
                    icon: Icons.search_off,
                    title: 'No products match',
                  )
                : ListView.separated(
                    itemCount: lines.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) => _SheetLine(
                      line: lines[index],
                      controller: _controllerFor(lines[index]),
                      enabled: isDraft,
                      onChanged: () => setState(() {}),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final style = context.text.labelSmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: context.colors.onSurfaceVariant,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(child: Text('PRODUCT', style: style)),
          SizedBox(
            width: 100,
            child: Text('SYSTEM', style: style, textAlign: TextAlign.right),
          ),
          SizedBox(
            width: 110,
            child: Text('COUNTED', style: style, textAlign: TextAlign.right),
          ),
          SizedBox(
            width: 100,
            child: Text('VARIANCE', style: style, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

class _SheetLine extends StatelessWidget {
  const _SheetLine({
    required this.line,
    required this.controller,
    required this.enabled,
    required this.onChanged,
  });

  final StockCountLine line;
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final typed = int.tryParse(controller.text.trim());
    final variance = typed == null ? null : typed - line.systemQuantity;
    final colors = context.statusColors;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(line.productName, style: context.text.bodyMedium),
                Text(line.sku, style: context.text.bodySmall),
              ],
            ),
          ),
          SizedBox(
            width: 100,
            child: Text(
              '${line.systemQuantity}',
              textAlign: TextAlign.right,
              style: AppTheme.monospacedNumbers(context.text.bodyMedium),
            ),
          ),
          SizedBox(
            width: 110,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: TextField(
                controller: controller,
                enabled: enabled,
                textAlign: TextAlign.right,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: AppTheme.monospacedNumbers(context.text.bodyMedium),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '—',
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.sm,
                  ),
                ),
                onChanged: (_) => onChanged(),
              ),
            ),
          ),
          SizedBox(
            width: 100,
            child: Text(
              variance == null
                  ? '—'
                  : variance > 0
                  ? '+$variance'
                  : '$variance',
              textAlign: TextAlign.right,
              style: AppTheme.monospacedNumbers(context.text.bodyMedium)
                  .copyWith(
                    fontWeight: variance == null || variance == 0
                        ? FontWeight.w400
                        : FontWeight.w700,
                    color: variance == null || variance == 0
                        ? context.colors.onSurfaceVariant
                        : variance > 0
                        ? colors.success
                        : colors.danger,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetSummary extends StatelessWidget {
  const _SheetSummary({required this.sheet});

  final StockCountSheet sheet;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.lg,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '${sheet.countedLineCount} of ${sheet.lines.length} counted',
          style: context.text.bodySmall,
        ),
        if (sheet.surplusUnits > 0)
          Text(
            '+${sheet.surplusUnits} surplus',
            style: context.text.bodySmall?.copyWith(
              color: context.statusColors.success,
            ),
          ),
        if (sheet.shortageUnits > 0)
          Text(
            '-${sheet.shortageUnits} short',
            style: context.text.bodySmall?.copyWith(
              color: context.statusColors.danger,
            ),
          ),
      ],
    );
  }
}
