import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:venvo_core/core/constants/app_constants.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/errors/failures.dart';
import 'package:venvo_core/features/inventory/domain/location_models.dart';
import 'package:venvo_core/features/inventory/domain/stock_models.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/feedback_views.dart';
import '../../../core/widgets/form_dialog.dart';
import '../../../core/widgets/form_fields.dart';
import '../../authentication/presentation/auth_controller.dart';
import 'location_providers.dart';
import 'stock_providers.dart';
import 'widgets/stock_line_editor.dart';

/// The routes a transfer can take. Each one fixes which kinds of location may
/// appear at either end, which is what keeps agent-wise and shop-wise
/// reporting meaningful.
enum TransferRoute {
  warehouseToAgent(
    documentType: StockDocumentType.warehouseToAgent,
    label: 'Warehouse to agent',
    description: 'Send goods from a warehouse to an agent to distribute.',
    sourceKind: LocationKind.warehouse,
    destinationKind: LocationKind.agent,
  ),
  agentToShop(
    documentType: StockDocumentType.agentToShop,
    label: 'Agent to shop',
    description: 'An agent supplies a retail shop.',
    sourceKind: LocationKind.agent,
    destinationKind: LocationKind.shop,
  ),
  warehouseToShop(
    documentType: StockDocumentType.warehouseToShop,
    label: 'Warehouse to shop',
    description: 'Supply a shop directly, bypassing the agent.',
    sourceKind: LocationKind.warehouse,
    destinationKind: LocationKind.shop,
  ),
  betweenWarehouses(
    documentType: StockDocumentType.interLocationTransfer,
    label: 'Between warehouses',
    description: 'Move goods between two of your own warehouses.',
    sourceKind: LocationKind.warehouse,
    destinationKind: LocationKind.warehouse,
  );

  const TransferRoute({
    required this.documentType,
    required this.label,
    required this.description,
    required this.sourceKind,
    required this.destinationKind,
  });

  final StockDocumentType documentType;
  final String label;
  final String description;
  final LocationKind sourceKind;
  final LocationKind destinationKind;
}

/// Records stock the business already had before the system went live, or a
/// fresh purchase arriving into a location.
///
/// Goods enter from the supplier counterparty, so a cost has to be stated:
/// there is no earlier balance for the cost to travel from.
class OpeningStockDialog extends ConsumerStatefulWidget {
  const OpeningStockDialog({super.key, this.isPurchase = false});

  /// Opening stock and a purchase differ only in the document type and the
  /// wording; both bring goods in from the supplier counterparty.
  final bool isPurchase;

  static Future<bool> show(
    BuildContext context, {
    bool isPurchase = false,
  }) async {
    final posted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => OpeningStockDialog(isPurchase: isPurchase),
    );
    return posted ?? false;
  }

  @override
  ConsumerState<OpeningStockDialog> createState() => _OpeningStockDialogState();
}

class _OpeningStockDialogState extends ConsumerState<OpeningStockDialog> {
  final _lines = StockLineEditorController();
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  int? _destinationId;
  DateTime? _documentDate;

  @override
  void dispose() {
    _lines.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final problem = _lines.validate(requireUnitCost: true);
    if (problem != null) throw ValidationFailure(problem);

    final supplier = await ref
        .read(locationRepositoryProvider)
        .byCode(AppConstants.supplierLocationCode);

    await ref
        .read(stockLedgerServiceProvider)
        .postMovement(
          ref.read(requireCurrentUserProvider),
          StockMovementRequest(
            documentType: widget.isPurchase
                ? StockDocumentType.purchaseIn
                : StockDocumentType.openingStock,
            sourceLocationId: supplier.id,
            destinationLocationId: _destinationId!,
            documentDate: _documentDate,
            referenceNote: _reference.text,
            notes: _notes.text,
            lines: _lines.toMovementLines(includeUnitCost: true),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final locations = ref.watch(stockLocationsProvider);
    final destinations = locations
        .where(
          (location) => location.kind.isStockHolding && !location.isVirtual,
        )
        .toList(growable: false);
    final products =
        ref.watch(allActiveProductsProvider).valueOrNull ?? const [];

    _destinationId ??= destinations
        .where((location) => location.code == AppConstants.mainWarehouseCode)
        .map((location) => location.id)
        .firstOrNull;

    return AppFormDialog(
      title: widget.isPurchase ? 'Record a purchase' : 'Enter opening stock',
      subtitle: widget.isPurchase
          ? 'Goods arriving from a supplier. The cost entered here becomes '
                'their carrying cost.'
          : 'Stock that already existed before the system went live. It is '
                'posted as a document, so the ledger balances from day one.',
      submitLabel: 'Post document',
      width: 1020,
      onSubmit: _submit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          FormRow(
            children: [
              AppDropdownField<int>(
                value: _destinationId,
                label: 'Into location',
                isRequired: true,
                items: [
                  for (final location in destinations)
                    DropdownMenuItem<int>(
                      value: location.id,
                      child: Text(
                        '${location.name} · '
                        '${locationKindLabel(location.kind)}',
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _destinationId = value),
              ),
              AppDateField(
                value: _documentDate,
                label: 'Document date',
                helperText: 'Defaults to today',
                onChanged: (value) => setState(() => _documentDate = value),
                lastDate: DateTime.now(),
              ),
              AppTextField(
                controller: _reference,
                label: 'Reference',
                maxLength: 200,
                helperText: widget.isPurchase ? 'Supplier invoice no.' : null,
              ),
            ],
          ),
          AppSpacing.gapXl,
          _LinesCard(
            title: 'Products arriving',
            child: StockLineEditor(
              controller: _lines,
              products: products,
              showAvailable: false,
              showUnitCost: true,
            ),
          ),
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

/// Moves goods between two real locations.
class StockTransferDialog extends ConsumerStatefulWidget {
  const StockTransferDialog({super.key, this.initialRoute});

  /// Preselects the route, so the Shop Supply menu item opens straight into an
  /// agent-to-shop document.
  final TransferRoute? initialRoute;

  static Future<bool> show(
    BuildContext context, {
    TransferRoute? initialRoute,
  }) async {
    final posted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StockTransferDialog(initialRoute: initialRoute),
    );
    return posted ?? false;
  }

  @override
  ConsumerState<StockTransferDialog> createState() =>
      _StockTransferDialogState();
}

class _StockTransferDialogState extends ConsumerState<StockTransferDialog> {
  final _lines = StockLineEditorController();
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  final _overrideReason = TextEditingController();

  late TransferRoute _route;
  int? _sourceId;
  int? _destinationId;
  DateTime? _documentDate;
  bool _allowNegative = false;

  @override
  void initState() {
    super.initState();
    _route = widget.initialRoute ?? TransferRoute.warehouseToAgent;
  }

  @override
  void dispose() {
    _lines.dispose();
    _reference.dispose();
    _notes.dispose();
    _overrideReason.dispose();
    super.dispose();
  }

  void _changeRoute(TransferRoute route) {
    setState(() {
      _route = route;
      // The chosen locations almost certainly no longer suit the new route.
      _sourceId = null;
      _destinationId = null;
    });
  }

  Future<void> _submit() async {
    final available = _sourceId == null
        ? const <int, int>{}
        : ref.read(availableAtLocationProvider(_sourceId!));

    final problem = _lines.validate(
      availableByProductId: available,
      allowOverAvailable: _allowNegative,
    );
    if (problem != null) throw ValidationFailure(problem);

    final destination = ref
        .read(stockLocationsProvider)
        .firstWhere((location) => location.id == _destinationId);
    final source = ref
        .read(stockLocationsProvider)
        .firstWhere((location) => location.id == _sourceId);

    await ref
        .read(stockLedgerServiceProvider)
        .postMovement(
          ref.read(requireCurrentUserProvider),
          StockMovementRequest(
            documentType: _route.documentType,
            sourceLocationId: source.id,
            destinationLocationId: destination.id,
            documentDate: _documentDate,
            agentId: destination.agentId ?? source.agentId,
            shopId: destination.shopId ?? source.shopId,
            referenceNote: _reference.text,
            notes: _notes.text,
            allowNegativeStock: _allowNegative,
            negativeStockReason: _overrideReason.text,
            lines: _lines.toMovementLines(includePrices: true),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(requireCurrentUserProvider);
    final locations = ref.watch(stockLocationsProvider);
    final products =
        ref.watch(allActiveProductsProvider).valueOrNull ?? const [];

    final sources = locations
        .where((location) => location.kind == _route.sourceKind)
        .toList(growable: false);
    final destinations = locations
        .where(
          (location) =>
              location.kind == _route.destinationKind &&
              location.id != _sourceId,
        )
        .toList(growable: false);

    if (_sourceId == null && sources.length == 1) {
      _sourceId = sources.single.id;
    }

    final available = _sourceId == null
        ? const <int, int>{}
        : ref.watch(availableAtLocationProvider(_sourceId!));

    return AppFormDialog(
      title: 'New stock transfer',
      subtitle: _route.description,
      submitLabel: 'Post transfer',
      width: 1080,
      onSubmit: _submit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<TransferRoute>(
            segments: [
              for (final route in TransferRoute.values)
                ButtonSegment<TransferRoute>(
                  value: route,
                  label: Text(route.label),
                ),
            ],
            selected: {_route},
            onSelectionChanged: (selection) => _changeRoute(selection.first),
          ),
          AppSpacing.gapXl,
          FormRow(
            children: [
              AppDropdownField<int>(
                value: _sourceId,
                label: 'From',
                isRequired: true,
                items: [
                  for (final location in sources)
                    DropdownMenuItem<int>(
                      value: location.id,
                      child: Text(location.name),
                    ),
                ],
                onChanged: (value) => setState(() => _sourceId = value),
              ),
              AppDropdownField<int>(
                value: _destinationId,
                label: 'To',
                isRequired: true,
                items: [
                  for (final location in destinations)
                    DropdownMenuItem<int>(
                      value: location.id,
                      child: Text(location.name),
                    ),
                ],
                onChanged: (value) => setState(() => _destinationId = value),
              ),
              AppDateField(
                value: _documentDate,
                label: 'Date',
                helperText: 'Defaults to today',
                onChanged: (value) => setState(() => _documentDate = value),
                lastDate: DateTime.now(),
              ),
            ],
          ),
          if (sources.isEmpty || destinations.isEmpty) ...[
            AppSpacing.gapLg,
            _InlineNote(
              tone: StatusNoteTone.warning,
              message: sources.isEmpty
                  ? 'There are no active ${_route.sourceKind.name} locations '
                        'to send from. Add one first.'
                  : 'There are no active ${_route.destinationKind.name} '
                        'locations to send to. Add one first.',
            ),
          ],
          AppSpacing.gapXl,
          _LinesCard(
            title: 'Products being moved',
            subtitle:
                'Prices here print on the delivery note. They do not '
                'create a receivable: that needs an invoice.',
            child: StockLineEditor(
              controller: _lines,
              products: products,
              availableByProductId: available,
              showUnitPrice: true,
              showDiscount: true,
              availableLabel: 'At source',
            ),
          ),
          AppSpacing.gapLg,
          AppTextField(
            controller: _reference,
            label: 'Reference',
            maxLength: 200,
          ),
          AppSpacing.gapLg,
          AppTextField(
            controller: _notes,
            label: 'Notes',
            maxLines: 2,
            maxLength: 1000,
          ),
          if (user.can('stock.negative_override')) ...[
            AppSpacing.gapLg,
            SwitchListTile(
              value: _allowNegative,
              onChanged: (value) => setState(() => _allowNegative = value),
              title: const Text('Allow this document to take stock below zero'),
              subtitle: const Text(
                'Only for goods already physically dispatched. The override '
                'and your reason are recorded on the document.',
              ),
              contentPadding: EdgeInsets.zero,
            ),
            if (_allowNegative)
              AppTextField(
                controller: _overrideReason,
                label: 'Reason for the override',
                isRequired: true,
                maxLength: 500,
              ),
          ],
        ],
      ),
    );
  }
}

/// Authorised corrections: an increase, a decrease, or moving goods into the
/// damaged store.
class StockAdjustmentDialog extends ConsumerStatefulWidget {
  const StockAdjustmentDialog({super.key});

  static Future<bool> show(BuildContext context) async {
    final posted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const StockAdjustmentDialog(),
    );
    return posted ?? false;
  }

  @override
  ConsumerState<StockAdjustmentDialog> createState() =>
      _StockAdjustmentDialogState();
}

enum _AdjustmentKind {
  increase('Increase stock', StockDocumentType.adjustmentIncrease),
  decrease('Decrease stock', StockDocumentType.adjustmentDecrease),
  damage('Move to damaged', StockDocumentType.damageWriteOff);

  const _AdjustmentKind(this.label, this.documentType);

  final String label;
  final StockDocumentType documentType;
}

class _StockAdjustmentDialogState extends ConsumerState<StockAdjustmentDialog> {
  final _lines = StockLineEditorController();
  final _reason = TextEditingController();
  _AdjustmentKind _kind = _AdjustmentKind.increase;
  int? _locationId;
  DateTime? _documentDate;

  @override
  void dispose() {
    _lines.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final isOutbound = _kind != _AdjustmentKind.increase;
    final available = isOutbound && _locationId != null
        ? ref.read(availableAtLocationProvider(_locationId!))
        : null;

    final problem = _lines.validate(
      availableByProductId: available,
      requireUnitCost: _kind == _AdjustmentKind.increase,
    );
    if (problem != null) throw ValidationFailure(problem);

    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      throw const ValidationFailure('Give a reason for the adjustment.');
    }

    final repository = ref.read(locationRepositoryProvider);
    final adjustment = await repository.byCode(
      AppConstants.adjustmentLocationCode,
    );
    final damaged = await repository.byCode(AppConstants.damagedLocationCode);

    final (sourceId, destinationId) = switch (_kind) {
      _AdjustmentKind.increase => (adjustment.id, _locationId!),
      _AdjustmentKind.decrease => (_locationId!, adjustment.id),
      _AdjustmentKind.damage => (_locationId!, damaged.id),
    };

    await ref
        .read(stockLedgerServiceProvider)
        .postMovement(
          ref.read(requireCurrentUserProvider),
          StockMovementRequest(
            documentType: _kind.documentType,
            sourceLocationId: sourceId,
            destinationLocationId: destinationId,
            documentDate: _documentDate,
            referenceNote: reason,
            notes: reason,
            lines: _lines.toMovementLines(
              includeUnitCost: _kind == _AdjustmentKind.increase,
            ),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final locations = ref.watch(stockLocationsProvider);
    final holdingLocations = locations
        .where(
          (location) => location.kind.isStockHolding && !location.isVirtual,
        )
        .where(
          (location) =>
              _kind != _AdjustmentKind.damage ||
              location.kind != LocationKind.damaged,
        )
        .toList(growable: false);
    final products =
        ref.watch(allActiveProductsProvider).valueOrNull ?? const [];

    _locationId ??= holdingLocations
        .where((location) => location.code == AppConstants.mainWarehouseCode)
        .map((location) => location.id)
        .firstOrNull;

    final isOutbound = _kind != _AdjustmentKind.increase;
    final available = isOutbound && _locationId != null
        ? ref.watch(availableAtLocationProvider(_locationId!))
        : const <int, int>{};

    return AppFormDialog(
      title: 'Stock adjustment',
      subtitle:
          'Adjustments go through the adjustment counterparty, so the ledger '
          'still balances and the correction is traceable.',
      submitLabel: 'Post adjustment',
      width: 1000,
      onSubmit: _submit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<_AdjustmentKind>(
            segments: [
              for (final kind in _AdjustmentKind.values)
                ButtonSegment<_AdjustmentKind>(
                  value: kind,
                  label: Text(kind.label),
                ),
            ],
            selected: {_kind},
            onSelectionChanged: (selection) =>
                setState(() => _kind = selection.first),
          ),
          AppSpacing.gapXl,
          FormRow(
            children: [
              AppDropdownField<int>(
                value: _locationId,
                label: _kind == _AdjustmentKind.increase
                    ? 'Increase at'
                    : 'Take from',
                isRequired: true,
                items: [
                  for (final location in holdingLocations)
                    DropdownMenuItem<int>(
                      value: location.id,
                      child: Text(location.name),
                    ),
                ],
                onChanged: (value) => setState(() => _locationId = value),
              ),
              AppDateField(
                value: _documentDate,
                label: 'Date',
                helperText: 'Defaults to today',
                onChanged: (value) => setState(() => _documentDate = value),
                lastDate: DateTime.now(),
              ),
            ],
          ),
          AppSpacing.gapLg,
          AppTextField(
            controller: _reason,
            label: 'Reason',
            isRequired: true,
            maxLength: 300,
            helperText: 'Recorded on the document and in the audit log',
            hintText: _kind == _AdjustmentKind.damage
                ? 'Water damage in transit'
                : 'Stock-take correction',
          ),
          AppSpacing.gapXl,
          _LinesCard(
            title: _kind == _AdjustmentKind.increase
                ? 'Products to add'
                : 'Products to remove',
            child: StockLineEditor(
              controller: _lines,
              products: products,
              availableByProductId: available,
              showAvailable: isOutbound,
              showUnitCost: _kind == _AdjustmentKind.increase,
            ),
          ),
        ],
      ),
    );
  }
}

class _LinesCard extends StatelessWidget {
  const _LinesCard({required this.title, required this.child, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

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
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: context.text.titleSmall),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(subtitle!, style: context.text.bodySmall),
                ],
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

enum StatusNoteTone { info, warning }

class _InlineNote extends StatelessWidget {
  const _InlineNote({required this.message, this.tone = StatusNoteTone.info});

  final String message;
  final StatusNoteTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.statusColors;
    final isWarning = tone == StatusNoteTone.warning;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isWarning ? colors.warningContainer : colors.infoContainer,
        borderRadius: AppRadii.smAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isWarning ? Icons.warning_amber_outlined : Icons.info_outline,
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

/// Confirms, then cancels a posted document by posting its reversal.
Future<void> confirmAndCancelDocument(
  BuildContext context,
  WidgetRef ref,
  StockDocumentSummary document,
) async {
  final reasonController = TextEditingController();

  final cancelled = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AppFormDialog(
      title: 'Cancel ${document.documentNumber}?',
      subtitle:
          'The original document and its ledger entries are kept. A reversing '
          'document is posted to put the goods back.',
      submitLabel: 'Post the reversal',
      width: 520,
      onSubmit: () => ref
          .read(stockLedgerServiceProvider)
          .cancelMovement(
            ref.read(requireCurrentUserProvider),
            transactionId: document.id,
            reason: reasonController.text,
          ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppTextField(
            controller: reasonController,
            label: 'Reason',
            isRequired: true,
            autofocus: true,
            maxLines: 2,
            maxLength: 500,
          ),
          AppSpacing.gapLg,
          _InlineNote(
            message:
                'If the goods have already moved on from '
                '${document.destinationName}, the reversal will be refused '
                'rather than driving that location negative.',
          ),
        ],
      ),
    ),
  );

  reasonController.dispose();
  if ((cancelled ?? false) && context.mounted) {
    showSuccessSnackBar(
      context,
      '${document.documentNumber} cancelled and reversed.',
    );
  }
}

/// Shows a posted document and its lines.
Future<void> showStockDocument(
  BuildContext context,
  WidgetRef ref,
  int transactionId,
) {
  return showDialog<void>(
    context: context,
    builder: (context) => Consumer(
      builder: (context, ref, child) {
        final detail = ref.watch(stockDocumentDetailProvider(transactionId));

        return AlertDialog(
          title: const Text('Stock document'),
          content: SizedBox(
            width: 760,
            child: AsyncValueView<StockDocumentDetail>(
              value: detail,
              builder: (context, data) => _DocumentView(detail: data),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    ),
  );
}

class _DocumentView extends StatelessWidget {
  const _DocumentView({required this.detail});

  final StockDocumentDetail detail;

  @override
  Widget build(BuildContext context) {
    final summary = detail.summary;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      summary.documentNumber,
                      style: context.text.titleLarge,
                    ),
                    Text(
                      stockDocumentTypeLabel(summary.documentType),
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
              if (summary.isCancelled)
                const Chip(label: Text('Cancelled'))
              else
                const Chip(label: Text('Posted')),
            ],
          ),
          AppSpacing.gapLg,
          _field(context, 'From', summary.sourceName),
          _field(context, 'To', summary.destinationName),
          if (summary.agentName != null)
            _field(context, 'Agent', summary.agentName!),
          if (summary.shopName != null)
            _field(context, 'Shop', summary.shopName!),
          _field(context, 'Raised by', summary.createdBy),
          if (summary.referenceNote != null)
            _field(context, 'Reference', summary.referenceNote!),
          if (detail.notes != null) _field(context, 'Notes', detail.notes!),
          if (summary.reversesDocumentNumber != null)
            _field(context, 'Reverses', summary.reversesDocumentNumber!),
          if (summary.reversedByDocumentNumber != null)
            _field(context, 'Reversed by', summary.reversedByDocumentNumber!),
          if (detail.cancelReason != null)
            _field(
              context,
              'Cancellation reason',
              '${detail.cancelReason}'
                  '${detail.cancelledBy == null ? '' : ' (${detail.cancelledBy})'}',
            ),
          if (detail.overrideReason != null)
            _field(context, 'Negative-stock override', detail.overrideReason!),
          AppSpacing.gapLg,
          const Divider(),
          AppSpacing.gapSm,
          for (final line in detail.lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      '${line.productName} (${line.sku})',
                      style: context.text.bodyMedium,
                    ),
                  ),
                  SizedBox(
                    width: 70,
                    child: Text(
                      '${line.quantity}',
                      textAlign: TextAlign.right,
                      style: context.text.bodyMedium,
                    ),
                  ),
                  SizedBox(
                    width: 110,
                    child: Text(
                      line.unitPrice.isZero ? '—' : line.unitPrice.plain,
                      textAlign: TextAlign.right,
                      style: context.text.bodyMedium,
                    ),
                  ),
                  SizedBox(
                    width: 110,
                    child: Text(
                      line.lineTotal.isZero ? '—' : line.lineTotal.plain,
                      textAlign: TextAlign.right,
                      style: context.text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const Divider(),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${summary.lineCount} line(s), '
                  '${summary.totalQuantity} unit(s)',
                  style: context.text.bodySmall,
                ),
              ),
              Text(
                summary.total.isZero
                    ? 'No document value'
                    : 'Total ${summary.total.formatted()}',
                style: context.text.titleSmall,
              ),
            ],
          ),
          AppSpacing.gapSm,
          Text(
            'Goods valued at ${detail.costValue.formatted()} at carrying cost.',
            style: context.text.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _field(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 170,
            child: Text(label, style: context.text.bodySmall),
          ),
          Expanded(child: Text(value, style: context.text.bodyMedium)),
        ],
      ),
    );
  }
}

/// Used by the register to describe what a document did, in one line.
String describeDocumentEffect(StockDocumentSummary document) {
  return '${document.totalQuantity} unit(s) · ${document.sourceName} to '
      '${document.destinationName}';
}
