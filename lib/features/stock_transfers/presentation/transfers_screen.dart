import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/inventory/domain/stock_models.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/app_data_table.dart';
import '../../../core/widgets/feedback_views.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/status_pill.dart';
import '../../authentication/presentation/auth_controller.dart';
import '../../inventory/presentation/stock_document_forms.dart';
import '../../inventory/presentation/stock_providers.dart';

/// The stock document register.
///
/// One screen serves the whole phase: transfers, shop supply, opening stock
/// and adjustments all produce stock documents, and an operator wants to see
/// them in one place. [presetTypes] narrows it so the Shop Supply menu item
/// opens straight onto agent-to-shop documents.
class StockDocumentRegisterScreen extends ConsumerStatefulWidget {
  const StockDocumentRegisterScreen({
    super.key,
    required this.title,
    required this.description,
    this.presetTypes = const {},
    this.presetRoute,
    this.showOpeningStockAction = false,
    this.showAdjustmentAction = false,
  });

  /// The transfers register: every movement document.
  const StockDocumentRegisterScreen.transfers({super.key})
    : title = 'Stock Transfers',
      description =
          'Every stock document, newest first. A transfer moves goods and '
          'prints a delivery note; it does not create a receivable on its '
          'own.',
      presetTypes = const {},
      presetRoute = null,
      showOpeningStockAction = true,
      showAdjustmentAction = true;

  /// Agent-to-shop supply only.
  const StockDocumentRegisterScreen.shopSupply({super.key})
    : title = 'Shop Supply',
      description =
          'Goods supplied by an agent to a retail shop. The invoice that '
          'makes this a receivable is raised separately.',
      presetTypes = const {StockDocumentType.agentToShop},
      presetRoute = TransferRoute.agentToShop,
      showOpeningStockAction = false,
      showAdjustmentAction = false;

  /// Opening stock and purchases.
  const StockDocumentRegisterScreen.openingStock({super.key})
    : title = 'Opening Stock',
      description =
          'Stock that existed before the system went live, and goods '
          'arriving from suppliers. Both are posted as documents so the '
          'ledger balances from the first day.',
      presetTypes = const {
        StockDocumentType.openingStock,
        StockDocumentType.purchaseIn,
      },
      presetRoute = null,
      showOpeningStockAction = true,
      showAdjustmentAction = false;

  /// Adjustments, damage write-offs and reconciliation postings.
  const StockDocumentRegisterScreen.adjustments({super.key})
    : title = 'Stock Adjustments',
      description =
          'Authorised corrections and damage write-offs. Each one goes '
          'through the adjustment counterparty, so the ledger still '
          'balances and the correction is traceable.',
      presetTypes = const {
        StockDocumentType.adjustmentIncrease,
        StockDocumentType.adjustmentDecrease,
        StockDocumentType.damageWriteOff,
        StockDocumentType.reconciliation,
      },
      presetRoute = null,
      showOpeningStockAction = false,
      showAdjustmentAction = true;

  final String title;
  final String description;
  final Set<StockDocumentType> presetTypes;
  final TransferRoute? presetRoute;
  final bool showOpeningStockAction;
  final bool showAdjustmentAction;

  @override
  ConsumerState<StockDocumentRegisterScreen> createState() =>
      _StockDocumentRegisterScreenState();
}

class _StockDocumentRegisterScreenState
    extends ConsumerState<StockDocumentRegisterScreen> {
  @override
  void initState() {
    super.initState();
    // Apply this screen's preset once, after the first frame, so the shared
    // filter provider reflects which register the user opened.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(stockDocumentFilterProvider.notifier).state =
          StockDocumentFilter(types: widget.presetTypes);
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (!(user?.can(Permissions.stockView) ?? false)) {
      return PageScaffold(
        title: widget.title,
        child: const EmptyState(
          icon: Icons.lock_outline,
          title: 'You do not have access to stock documents',
        ),
      );
    }

    final canTransfer = user?.can(Permissions.stockTransfer) ?? false;
    final canOpen = user?.can(Permissions.stockOpening) ?? false;
    final canAdjust = user?.can(Permissions.stockAdjust) ?? false;

    final documents = ref.watch(stockDocumentsProvider);
    final filter = ref.watch(stockDocumentFilterProvider);

    return PageScaffold(
      title: widget.title,
      description: widget.description,
      scrollable: false,
      actions: [
        if (widget.showAdjustmentAction && canAdjust)
          OutlinedButton.icon(
            onPressed: () => _postAdjustment(context),
            icon: const Icon(Icons.tune, size: 18),
            label: const Text('New adjustment'),
          ),
        if (widget.showOpeningStockAction && canOpen)
          OutlinedButton.icon(
            onPressed: () => _postOpeningStock(context),
            icon: const Icon(Icons.playlist_add, size: 18),
            label: const Text('Opening stock'),
          ),
        if (canTransfer)
          FilledButton.icon(
            onPressed: () => _postTransfer(context),
            icon: const Icon(Icons.local_shipping_outlined, size: 18),
            label: Text(
              widget.presetRoute == TransferRoute.agentToShop
                  ? 'New shop supply'
                  : 'New transfer',
            ),
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
                hintText: 'Search document number, agent or shop',
                width: 320,
                onChanged: (value) => ref
                    .read(stockDocumentFilterProvider.notifier)
                    .update((state) => state.copyWith(search: value)),
              ),
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<StockDocumentStatus?>(
                  initialValue: filter.status,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem<StockDocumentStatus?>(
                      child: Text('All statuses'),
                    ),
                    DropdownMenuItem<StockDocumentStatus?>(
                      value: StockDocumentStatus.posted,
                      child: Text('Posted'),
                    ),
                    DropdownMenuItem<StockDocumentStatus?>(
                      value: StockDocumentStatus.cancelled,
                      child: Text('Cancelled'),
                    ),
                  ],
                  onChanged: (value) => ref
                      .read(stockDocumentFilterProvider.notifier)
                      .update(
                        (state) => value == null
                            ? state.copyWith(clearStatus: true)
                            : state.copyWith(status: value),
                      ),
                ),
              ),
              SizedBox(
                width: 170,
                child: AppDateField(
                  value: filter.from,
                  label: 'From',
                  onChanged: (value) => ref
                      .read(stockDocumentFilterProvider.notifier)
                      .update(
                        (state) => value == null
                            ? state.copyWith(clearFrom: true)
                            : state.copyWith(from: value),
                      ),
                ),
              ),
              SizedBox(
                width: 170,
                child: AppDateField(
                  value: filter.to,
                  label: 'To',
                  onChanged: (value) => ref
                      .read(stockDocumentFilterProvider.notifier)
                      .update(
                        (state) => value == null
                            ? state.copyWith(clearTo: true)
                            : state.copyWith(to: value),
                      ),
                ),
              ),
            ],
          ),
          AppSpacing.gapLg,
          Expanded(
            child: AsyncValueView<List<StockDocumentSummary>>(
              value: documents,
              builder: (context, rows) => SectionCard(
                padding: EdgeInsets.zero,
                fillHeight: true,
                child: AppDataTable<StockDocumentSummary>(
                  rows: rows,
                  minWidth: 1160,
                  onRowTap: (row) => showStockDocument(context, ref, row.id),
                  empty: EmptyState(
                    icon: Icons.local_shipping_outlined,
                    title: 'No documents yet',
                    message: canTransfer
                        ? 'Post a transfer to move goods out to an agent, or '
                              'enter opening stock first if the warehouse is '
                              'empty.'
                        : null,
                  ),
                  columns: [
                    AppTableColumn<StockDocumentSummary>(
                      label: 'Document',
                      width: 170,
                      cell: (context, row) => TableTwoLineCell(
                        primary: row.documentNumber,
                        secondary: stockDocumentTypeLabel(row.documentType),
                      ),
                    ),
                    AppTableColumn<StockDocumentSummary>(
                      label: 'Date',
                      width: 110,
                      cell: (context, row) => TableTextCell(
                        DateFormat(
                          'd MMM yyyy',
                        ).format(row.documentDate.toLocal()),
                      ),
                    ),
                    AppTableColumn<StockDocumentSummary>(
                      label: 'From',
                      flex: 2,
                      cell: (context, row) => TableTextCell(row.sourceName),
                    ),
                    AppTableColumn<StockDocumentSummary>(
                      label: 'To',
                      flex: 2,
                      cell: (context, row) =>
                          TableTextCell(row.destinationName),
                    ),
                    AppTableColumn<StockDocumentSummary>(
                      label: 'Lines',
                      width: 70,
                      numeric: true,
                      cell: (context, row) => TableTextCell('${row.lineCount}'),
                    ),
                    AppTableColumn<StockDocumentSummary>(
                      label: 'Units',
                      width: 80,
                      numeric: true,
                      cell: (context, row) =>
                          TableTextCell('${row.totalQuantity}', bold: true),
                    ),
                    AppTableColumn<StockDocumentSummary>(
                      label: 'Document value',
                      width: 130,
                      numeric: true,
                      tooltip:
                          'What the delivery note says. Not revenue: '
                          'that needs an invoice.',
                      cell: (context, row) => TableTextCell(
                        row.total.isZero ? '—' : row.total.plain,
                        muted: row.total.isZero,
                      ),
                    ),
                    AppTableColumn<StockDocumentSummary>(
                      label: 'Status',
                      width: 150,
                      cell: (context, row) => Row(
                        children: [
                          StatusPill.document(row.status),
                          if (row.isReversal) ...[
                            AppSpacing.hGapSm,
                            Tooltip(
                              message: 'Reverses ${row.reversesDocumentNumber}',
                              child: const StatusPill(
                                'Reversal',
                                tone: StatusTone.info,
                              ),
                            ),
                          ],
                          if (row.hasNegativeOverride) ...[
                            AppSpacing.hGapSm,
                            Tooltip(
                              message: 'Posted with a negative-stock override',
                              child: Icon(
                                Icons.warning_amber_outlined,
                                size: 15,
                                color: context.statusColors.warning,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    AppTableColumn<StockDocumentSummary>(
                      label: '',
                      width: 56,
                      cell: (context, row) => _RowMenu(document: row),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AppSpacing.gapSm,
          _SummaryBar(documents: documents.valueOrNull ?? const []),
        ],
      ),
    );
  }

  Future<void> _postTransfer(BuildContext context) async {
    final posted = await StockTransferDialog.show(
      context,
      initialRoute: widget.presetRoute,
    );
    if (posted && context.mounted) {
      showSuccessSnackBar(context, 'Transfer posted and stock updated.');
    }
  }

  Future<void> _postOpeningStock(BuildContext context) async {
    final posted = await OpeningStockDialog.show(context);
    if (posted && context.mounted) {
      showSuccessSnackBar(context, 'Opening stock posted.');
    }
  }

  Future<void> _postAdjustment(BuildContext context) async {
    final posted = await StockAdjustmentDialog.show(context);
    if (posted && context.mounted) {
      showSuccessSnackBar(context, 'Adjustment posted.');
    }
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.documents});

  final List<StockDocumentSummary> documents;

  @override
  Widget build(BuildContext context) {
    if (documents.isEmpty) return const SizedBox.shrink();

    final posted = documents.where((row) => !row.isCancelled).toList();
    final units = posted.fold(0, (total, row) => total + row.totalQuantity);
    final value = posted.map((row) => row.total).sum;
    final cancelled = documents.length - posted.length;
    final overrides = documents.where((row) => row.hasNegativeOverride).length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Wrap(
        spacing: AppSpacing.xl,
        runSpacing: AppSpacing.xs,
        children: [
          Text(
            '${documents.length} document(s)',
            style: context.text.bodySmall,
          ),
          Text('$units unit(s) moved', style: context.text.bodySmall),
          if (!value.isZero)
            Text(
              'Document value ${value.formatted()}',
              style: context.text.bodySmall,
            ),
          if (cancelled > 0)
            Text(
              '$cancelled cancelled',
              style: context.text.bodySmall?.copyWith(
                color: context.statusColors.danger,
              ),
            ),
          if (overrides > 0)
            Text(
              '$overrides posted with an override',
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
  const _RowMenu({required this.document});

  final StockDocumentSummary document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final canCancel = user?.can(Permissions.stockTransfer) ?? false;

    return PopupMenuButton<String>(
      tooltip: 'Actions',
      icon: const Icon(Icons.more_horiz, size: 18),
      onSelected: (value) async {
        switch (value) {
          case 'view':
            await showStockDocument(context, ref, document.id);
          case 'cancel':
            await confirmAndCancelDocument(context, ref, document);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'view', child: Text('View document')),
        if (canCancel && document.canBeCancelled) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'cancel',
            child: Text('Cancel and reverse'),
          ),
        ],
      ],
    );
  }
}
