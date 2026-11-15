import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:venvo_core/core/constants/app_constants.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/features/inventory/domain/location_models.dart';
import 'package:venvo_core/features/returns/domain/return_models.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/form_dialog.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/status_pill.dart';
import '../../agents/presentation/agents_screen.dart';
import '../../authentication/presentation/auth_controller.dart';
import '../../inventory/presentation/location_providers.dart';
import '../../inventory/presentation/stock_providers.dart';
import '../../inventory/presentation/widgets/stock_line_editor.dart';
import '../../shops/presentation/shops_screen.dart';
import 'return_providers.dart';

/// Records a return.
///
/// The route is chosen first, because everything else follows from it: which
/// party is involved, which two locations the goods travel between, and
/// whether an extra authorisation is needed. Linking the return to the
/// invoice the goods were billed on is optional but strongly preferred - it is
/// what caps the quantity and what makes the credit note repay the price
/// actually charged.
class ReturnFormDialog extends ConsumerStatefulWidget {
  const ReturnFormDialog({super.key});

  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const ReturnFormDialog(),
    );
    return result ?? false;
  }

  @override
  ConsumerState<ReturnFormDialog> createState() => _ReturnFormDialogState();
}

class _ReturnFormDialogState extends ConsumerState<ReturnFormDialog> {
  final _lines = StockLineEditorController();
  final _reasonNote = TextEditingController();
  final _notes = TextEditingController();

  /// Quantity being returned per invoice line, for a traced return.
  final Map<int, TextEditingController> _tracedQuantities = {};

  ReturnRoute _route = ReturnRoute.shopToAgent;
  int? _shopId;
  int? _agentId;
  int? _warehouseLocationId;
  int? _originInvoiceId;
  ReturnReason _reason = ReturnReason.defectiveItem;
  DateTime? _returnDate;

  @override
  void initState() {
    super.initState();
    _lines.addLine();
  }

  @override
  void dispose() {
    _lines.dispose();
    _reasonNote.dispose();
    _notes.dispose();
    for (final controller in _tracedQuantities.values) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get _needsShop =>
      _route == ReturnRoute.customerToShop ||
      _route == ReturnRoute.shopToAgent ||
      _route == ReturnRoute.shopToWarehouse;

  bool get _needsAgent =>
      _route == ReturnRoute.shopToAgent ||
      _route == ReturnRoute.agentToWarehouse;

  bool get _needsWarehouse =>
      _route == ReturnRoute.agentToWarehouse ||
      _route == ReturnRoute.shopToWarehouse;

  /// A customer return has no party ledger behind it, so there is no invoice
  /// to trace it to and nothing to credit against an outstanding balance.
  bool get _canTraceToInvoice => _route != ReturnRoute.customerToShop;

  bool get _isTraced => _originInvoiceId != null;

  @override
  Widget build(BuildContext context) {
    final locations = ref.watch(locationsProvider).valueOrNull ?? const [];
    final shops = ref.watch(shopsProvider).valueOrNull ?? const [];
    final agents = ref.watch(selectableAgentsProvider).valueOrNull ?? const [];
    final warehouses = locations
        .where((l) => l.kind == LocationKind.warehouse && l.isActive)
        .toList();

    final fromLocation = _resolveFrom(locations);
    final toLocation = _resolveTo(locations, warehouses);

    return AppFormDialog(
      title: 'New return',
      subtitle:
          'The goods leave the returning location when this is posted, but '
          'wait in transit until somebody inspects them.',
      submitLabel: 'Post the return',
      width: 900,
      onSubmit: _submit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          FormSection(
            title: 'What is coming back, and from where',
            children: [
              FormRow(
                children: [
                  AppDropdownField<ReturnRoute>(
                    label: 'Route',
                    isRequired: true,
                    value: _route,
                    helperText: returnRouteExplanation(_route),
                    items: [
                      for (final route in ReturnRoute.values)
                        DropdownMenuItem(
                          value: route,
                          child: Text(returnRouteLabel(route)),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _route = value;
                        _originInvoiceId = null;
                        _clearTracedQuantities();
                      });
                    },
                  ),
                  AppDateField(
                    label: 'Return date',
                    value: _returnDate ?? ref.watch(clockProvider).nowUtc(),
                    onChanged: (value) => setState(() => _returnDate = value),
                  ),
                ],
              ),
              if (_route == ReturnRoute.shopToWarehouse) _AuthorisationNotice(),
              FormRow(
                children: [
                  if (_needsShop)
                    AppDropdownField<int>(
                      label: 'Shop',
                      isRequired: true,
                      value: _shopId,
                      items: [
                        for (final shop in shops)
                          DropdownMenuItem(
                            value: shop.id,
                            child: Text('${shop.name} (${shop.code})'),
                          ),
                      ],
                      onChanged: (value) => setState(() {
                        _shopId = value;
                        // The shop's own agent is the usual counterparty.
                        final shop = shops
                            .where((s) => s.id == value)
                            .firstOrNull;
                        _agentId = shop?.assignedAgentId ?? _agentId;
                        _originInvoiceId = null;
                        _clearTracedQuantities();
                      }),
                    ),
                  if (_needsAgent)
                    AppDropdownField<int>(
                      label: 'Agent',
                      isRequired: true,
                      value: _agentId,
                      items: [
                        for (final agent in agents)
                          DropdownMenuItem(
                            value: agent.id,
                            child: Text('${agent.name} (${agent.code})'),
                          ),
                      ],
                      onChanged: (value) => setState(() {
                        _agentId = value;
                        _originInvoiceId = null;
                        _clearTracedQuantities();
                      }),
                    ),
                  if (_needsWarehouse)
                    AppDropdownField<int>(
                      label: 'Warehouse',
                      isRequired: true,
                      value: _warehouseLocationId ?? warehouses.firstOrNull?.id,
                      items: [
                        for (final warehouse in warehouses)
                          DropdownMenuItem(
                            value: warehouse.id,
                            child: Text(warehouse.name),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _warehouseLocationId = value),
                    ),
                ],
              ),
              _RouteSummary(from: fromLocation, to: toLocation),
            ],
          ),
          AppSpacing.gapLg,
          if (_canTraceToInvoice)
            FormSection(
              title: 'Against which invoice',
              description:
                  'Tracing the return to an invoice caps it at what was '
                  'billed and credits the price actually charged. Leave it '
                  'empty for goods that cannot be traced.',
              children: [
                _InvoicePicker(
                  party: CreditParty(agentId: _agentId, shopId: _shopId),
                  selected: _originInvoiceId,
                  onChanged: (value) => setState(() {
                    _originInvoiceId = value;
                    _clearTracedQuantities();
                  }),
                ),
              ],
            ),
          AppSpacing.gapLg,
          FormSection(
            title: 'Lines',
            children: [
              if (_isTraced)
                _TracedLines(
                  invoiceId: _originInvoiceId!,
                  controllerFor: _controllerFor,
                )
              else
                StockLineEditor(
                  controller: _lines,
                  products:
                      ref.watch(allActiveProductsProvider).valueOrNull ??
                      const [],
                  availableByProductId: fromLocation == null
                      ? const {}
                      : ref.watch(availableAtLocationProvider(fromLocation.id)),
                  showAvailable: fromLocation?.isVirtual == false,
                  showUnitPrice: true,
                  availableLabel: 'At source',
                ),
            ],
          ),
          AppSpacing.gapLg,
          FormSection(
            title: 'Why',
            children: [
              FormRow(
                children: [
                  AppDropdownField<ReturnReason>(
                    label: 'Reason',
                    isRequired: true,
                    value: _reason,
                    items: [
                      for (final reason in ReturnReason.values)
                        DropdownMenuItem(
                          value: reason,
                          child: Text(returnReasonLabel(reason)),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _reason = value ?? _reason),
                  ),
                  AppTextField(
                    controller: _reasonNote,
                    label: 'Reason note',
                    isRequired: _reason == ReturnReason.other,
                    maxLength: 500,
                    helperText: _reason == ReturnReason.other
                        ? 'Required when the reason is "Other".'
                        : null,
                  ),
                ],
              ),
              AppTextField(
                controller: _notes,
                label: 'Notes',
                maxLines: 2,
                maxLength: 1000,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _clearTracedQuantities() {
    for (final controller in _tracedQuantities.values) {
      controller.dispose();
    }
    _tracedQuantities.clear();
  }

  TextEditingController _controllerFor(int invoiceItemId) {
    return _tracedQuantities.putIfAbsent(
      invoiceItemId,
      TextEditingController.new,
    );
  }

  LocationListItem? _resolveFrom(List<LocationListItem> locations) {
    switch (_route) {
      case ReturnRoute.customerToShop:
        // Resolved at submit time from the seeded code; it is not in the
        // locations list, which hides the virtual counterparties.
        return null;
      case ReturnRoute.shopToAgent:
      case ReturnRoute.shopToWarehouse:
        return locations.where((l) => l.shopId == _shopId).firstOrNull;
      case ReturnRoute.agentToWarehouse:
        return locations.where((l) => l.agentId == _agentId).firstOrNull;
    }
  }

  LocationListItem? _resolveTo(
    List<LocationListItem> locations,
    List<LocationListItem> warehouses,
  ) {
    switch (_route) {
      case ReturnRoute.customerToShop:
        return locations.where((l) => l.shopId == _shopId).firstOrNull;
      case ReturnRoute.shopToAgent:
        return locations.where((l) => l.agentId == _agentId).firstOrNull;
      case ReturnRoute.agentToWarehouse:
      case ReturnRoute.shopToWarehouse:
        final chosen = _warehouseLocationId;
        return chosen == null
            ? warehouses.firstOrNull
            : warehouses.where((l) => l.id == chosen).firstOrNull;
    }
  }

  Future<void> _submit() async {
    final locations = ref.read(locationsProvider).valueOrNull ?? const [];
    final warehouses = locations
        .where((l) => l.kind == LocationKind.warehouse && l.isActive)
        .toList();

    int fromLocationId;
    if (_route == ReturnRoute.customerToShop) {
      fromLocationId = (await ref.read(
        returnVirtualLocationProvider(AppConstants.customerLocationCode).future,
      )).id;
    } else {
      final from = _resolveFrom(locations);
      if (from == null) {
        throw const FormatException('Choose where the goods are coming from.');
      }
      fromLocationId = from.id;
    }

    final to = _resolveTo(locations, warehouses);
    if (to == null) {
      throw const FormatException('Choose where the goods are going.');
    }

    final lines = _isTraced ? await _tracedLines() : _freeLines();
    if (lines.isEmpty) {
      throw const FormatException('Enter a quantity on at least one line.');
    }

    await ref
        .read(returnServiceProvider)
        .postReturn(
          ref.read(requireCurrentUserProvider),
          ReturnDraft(
            route: _route,
            fromLocationId: fromLocationId,
            toLocationId: to.id,
            agentId: _agentId,
            shopId: _shopId,
            originInvoiceId: _originInvoiceId,
            reason: _reason,
            reasonNote: _reasonNote.text,
            notes: _notes.text,
            returnDate: _returnDate,
            lines: lines,
          ),
        );
  }

  Future<List<ReturnLineDraft>> _tracedLines() async {
    final returnable = await ref.read(
      returnableLinesProvider(_originInvoiceId!).future,
    );
    final drafts = <ReturnLineDraft>[];

    for (final line in returnable) {
      final text = _tracedQuantities[line.invoiceItemId]?.text.trim() ?? '';
      if (text.isEmpty) continue;
      final quantity = int.tryParse(text);
      if (quantity == null || quantity <= 0) {
        throw FormatException(
          'The quantity for "${line.productName}" is not a whole number of '
          'units.',
        );
      }
      if (quantity > line.returnableQuantity) {
        throw FormatException(
          'Only ${line.returnableQuantity} unit(s) of "${line.productName}" '
          'can still be returned.',
        );
      }
      drafts.add(
        ReturnLineDraft(
          productId: line.productId,
          quantity: quantity,
          originInvoiceItemId: line.invoiceItemId,
        ),
      );
    }
    return drafts;
  }

  List<ReturnLineDraft> _freeLines() {
    final problem = _lines.validate(allowOverAvailable: true);
    if (problem != null) throw FormatException(problem);

    return [
      for (final line in _lines.lines)
        if (!line.isEmpty && line.product != null)
          ReturnLineDraft(
            productId: line.product!.id,
            quantity: line.quantityValue,
            unitPrice: line.unitPriceValue,
          ),
    ];
  }
}

class _AuthorisationNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        children: [
          Icon(
            Icons.gpp_maybe_outlined,
            size: 18,
            color: context.statusColors.warning,
          ),
          AppSpacing.hGapSm,
          Expanded(
            child: Text(
              'This route bypasses the agent. It needs the '
              '"return.direct_to_warehouse" permission, and whoever posts it '
              'is recorded on the document as having authorised it.',
              style: context.text.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteSummary extends StatelessWidget {
  const _RouteSummary({required this.from, required this.to});

  final LocationListItem? from;
  final LocationListItem? to;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          StatusPill(
            from?.name ?? 'Retail customers',
            tone: StatusTone.neutral,
          ),
          const Icon(Icons.arrow_forward, size: 16),
          const StatusPill('Goods in transit', tone: StatusTone.warning),
          const Icon(Icons.arrow_forward, size: 16),
          StatusPill(
            to?.name ?? 'choose a destination',
            tone: to == null ? StatusTone.danger : StatusTone.success,
          ),
          AppSpacing.hGapSm,
          Text(
            'after inspection',
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoicePicker extends ConsumerWidget {
  const _InvoicePicker({
    required this.party,
    required this.selected,
    required this.onChanged,
  });

  final CreditParty party;
  final int? selected;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!party.isChosen) {
      return Text(
        'Choose the party first.',
        style: context.text.bodySmall?.copyWith(
          color: context.colors.onSurfaceVariant,
        ),
      );
    }

    final invoices = ref.watch(partyInvoicesProvider(party)).valueOrNull;
    if (invoices == null) {
      return const LinearProgressIndicator(minHeight: 2);
    }
    if (invoices.isEmpty) {
      return Text(
        'This party has no posted invoices, so the return cannot be traced to '
        'one.',
        style: context.text.bodySmall,
      );
    }

    return AppDropdownField<int?>(
      label: 'Original invoice',
      value: selected,
      items: [
        const DropdownMenuItem<int?>(child: Text('Not traced to an invoice')),
        for (final invoice in invoices)
          DropdownMenuItem<int?>(
            value: invoice.id,
            child: Text(
              '${invoice.invoiceNumber} · '
              '${DateFormat('d MMM yyyy').format(invoice.invoiceDate.toLocal())}'
              ' · ${invoice.net.formatted()}',
            ),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

class _TracedLines extends ConsumerWidget {
  const _TracedLines({required this.invoiceId, required this.controllerFor});

  final int invoiceId;
  final TextEditingController Function(int invoiceItemId) controllerFor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lines = ref.watch(returnableLinesProvider(invoiceId)).valueOrNull;
    if (lines == null) return const LinearProgressIndicator(minHeight: 2);

    final returnable = lines.where((line) => !line.isFullyReturned).toList();
    if (returnable.isEmpty) {
      return Text(
        'Every unit on this invoice has already been returned.',
        style: context.text.bodySmall?.copyWith(
          color: context.statusColors.warning,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final line in returnable)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
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
                          '${line.sku} · billed ${line.billedQuantity} at '
                          '${line.effectiveUnitPrice.formatted()} each'
                          '${line.returnedQuantity == 0 ? '' : ' · ${line.returnedQuantity} already returned'}',
                          style: context.text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                AppSpacing.hGapMd,
                SizedBox(
                  width: 150,
                  child: AppIntField(
                    controller: controllerFor(line.invoiceItemId),
                    label: 'Return',
                    minimum: 0,
                    maximum: line.returnableQuantity,
                    suffixText: 'of ${line.returnableQuantity}',
                  ),
                ),
              ],
            ),
          ),
        Text(
          'Leave a line empty to return nothing of it. The credit note repays '
          'the price shown, which already includes any discount given on the '
          'invoice.',
          style: context.text.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
