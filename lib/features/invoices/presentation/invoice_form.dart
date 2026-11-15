import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:venvo_core/core/constants/app_constants.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/errors/failures.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/invoices/data/invoice_query_repository.dart';
import 'package:venvo_core/features/invoices/domain/invoice_models.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/form_dialog.dart';
import '../../../core/widgets/form_fields.dart';
import '../../authentication/presentation/auth_controller.dart';
import '../../inventory/presentation/location_providers.dart';
import '../../inventory/presentation/stock_providers.dart';
import '../../inventory/presentation/widgets/stock_line_editor.dart';
import '../../shops/presentation/shops_screen.dart';
import 'invoice_providers.dart';

/// What the invoice being raised is for. Each mode fixes the kind of invoice
/// and whether goods move with it.
enum InvoiceMode {
  supplyAndBill(
    label: 'Supply a shop',
    description:
        'An agent supplies a shop and bills it. The goods move and '
        'the receivable is created together.',
    kind: InvoiceKind.shopInvoice,
    movesStock: true,
  ),
  retailSale(
    label: 'Retail sale',
    description:
        'A shop sells to an end customer. Reduces that shop stock '
        'and is reported apart from what the shop was supplied.',
    kind: InvoiceKind.retailSale,
    movesStock: true,
  ),
  chargeOnly(
    label: 'Charge only',
    description:
        'Bills a shop without moving any goods, for example a '
        'correction or a charge agreed separately.',
    kind: InvoiceKind.shopInvoice,
    movesStock: false,
  );

  const InvoiceMode({
    required this.label,
    required this.description,
    required this.kind,
    required this.movesStock,
  });

  final String label;
  final String description;
  final InvoiceKind kind;
  final bool movesStock;
}

/// Raises a new invoice.
class InvoiceFormDialog extends ConsumerStatefulWidget {
  const InvoiceFormDialog({super.key, this.initialMode});

  final InvoiceMode? initialMode;

  static Future<bool> show(
    BuildContext context, {
    InvoiceMode? initialMode,
  }) async {
    final posted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => InvoiceFormDialog(initialMode: initialMode),
    );
    return posted ?? false;
  }

  @override
  ConsumerState<InvoiceFormDialog> createState() => _InvoiceFormDialogState();
}

class _InvoiceFormDialogState extends ConsumerState<InvoiceFormDialog> {
  final _lines = StockLineEditorController();
  final _customerName = TextEditingController();
  final _customerPhone = TextEditingController();
  final _notes = TextEditingController();
  final _invoiceDiscount = TextEditingController();
  final _discountReason = TextEditingController();
  final _paymentAmount = TextEditingController();
  final _chequeNumber = TextEditingController();
  final _chequeBank = TextEditingController();

  late InvoiceMode _mode;
  int? _shopId;
  DateTime? _invoiceDate;
  DateTime? _dueDate;
  DiscountType _invoiceDiscountType = DiscountType.percentage;
  PaymentMethod? _paymentMethod;
  DateTime? _chequeDate;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode ?? InvoiceMode.supplyAndBill;
  }

  @override
  void dispose() {
    _lines.dispose();
    for (final controller in [
      _customerName,
      _customerPhone,
      _notes,
      _invoiceDiscount,
      _discountReason,
      _paymentAmount,
      _chequeNumber,
      _chequeBank,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  /// The location goods leave from, which depends on the mode.
  int? _sourceLocationId() {
    final shopId = _shopId;
    if (shopId == null) return null;
    final locations = ref.read(stockLocationsProvider);

    if (_mode == InvoiceMode.retailSale) {
      return locations.firstWhereOrNull((l) => l.shopId == shopId)?.id;
    }
    // Supplying a shop comes out of its agent's stock.
    final shop = ref
        .read(shopsProvider)
        .valueOrNull
        ?.firstWhereOrNull((s) => s.id == shopId);
    final agentId = shop?.assignedAgentId;
    if (agentId == null) return null;
    return locations.firstWhereOrNull((l) => l.agentId == agentId)?.id;
  }

  Future<void> _submit() async {
    final shopId = _shopId;
    if (shopId == null) {
      throw const ValidationFailure('Choose the shop this invoice is for.');
    }

    final available = _mode.movesStock
        ? ref.read(availableAtLocationProvider(_sourceLocationId() ?? -1))
        : null;
    final problem = _lines.validate(
      availableByProductId: available,
      allowOverAvailable: !_mode.movesStock,
    );
    if (problem != null) throw ValidationFailure(problem);

    final lines = _lines.lines
        .where((line) => !line.isEmpty && line.product != null)
        .map(
          (line) => InvoiceLineRequest(
            productId: line.product!.id,
            quantity: line.quantityValue,
            unitPrice: line.unitPriceValue,
            discountType: line.discountBps > 0
                ? DiscountType.percentage
                : DiscountType.none,
            discountValue: line.discountBps,
          ),
        )
        .toList(growable: false);

    InvoiceStockLinkage linkage = const NoStockMovement();
    if (_mode.movesStock) {
      final sourceId = _sourceLocationId();
      if (sourceId == null) {
        throw const ValidationFailure(
          'That shop has no agent assigned, so there is no stock location to '
          'supply from. Assign an agent first, or use "Charge only".',
        );
      }
      final destinationId = _mode == InvoiceMode.retailSale
          ? (await ref
                    .read(locationRepositoryProvider)
                    .byCode(AppConstants.customerLocationCode))
                .id
          : ref
                .read(stockLocationsProvider)
                .firstWhere((l) => l.shopId == shopId)
                .id;

      linkage = MoveStockWithInvoice(
        documentType: _mode == InvoiceMode.retailSale
            ? StockDocumentType.retailSale
            : StockDocumentType.agentToShop,
        sourceLocationId: sourceId,
        destinationLocationId: destinationId,
      );
    }

    final shop = ref
        .read(shopsProvider)
        .valueOrNull
        ?.firstWhereOrNull((s) => s.id == shopId);

    await ref
        .read(invoiceServiceProvider)
        .postInvoice(
          ref.read(requireCurrentUserProvider),
          InvoiceRequest(
            kind: _mode.kind,
            shopId: shopId,
            agentId: shop?.assignedAgentId,
            customerName: _mode == InvoiceMode.retailSale
                ? _customerName.text
                : null,
            customerPhone: _mode == InvoiceMode.retailSale
                ? _customerPhone.text
                : null,
            invoiceDate: _invoiceDate,
            dueDate: _dueDate,
            invoiceDiscountType: _resolvedDiscountType(),
            invoiceDiscountValue: _resolvedDiscountValue(),
            discountReason: _discountReason.text,
            stockLinkage: linkage,
            payment: _buildPayment(),
            notes: _notes.text,
            lines: lines,
          ),
        );
  }

  DiscountType _resolvedDiscountType() {
    final text = _invoiceDiscount.text.trim();
    if (text.isEmpty) return DiscountType.none;
    return _invoiceDiscountType;
  }

  int _resolvedDiscountValue() {
    final text = _invoiceDiscount.text.trim();
    if (text.isEmpty) return 0;
    if (_invoiceDiscountType == DiscountType.percentage) {
      return ((double.tryParse(text) ?? 0) * 100).round();
    }
    return (Money.tryParse(text) ?? Money.zero).cents;
  }

  ImmediatePayment? _buildPayment() {
    final method = _paymentMethod;
    if (method == null) return null;
    final amount = Money.tryParse(_paymentAmount.text);
    if (amount == null || !amount.isPositive) return null;

    return ImmediatePayment(
      method: method,
      amount: amount,
      chequeNumber: method == PaymentMethod.cheque ? _chequeNumber.text : null,
      bankName: method == PaymentMethod.cheque ? _chequeBank.text : null,
      chequeDate: method == PaymentMethod.cheque ? _chequeDate : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final shops = ref.watch(shopsProvider).valueOrNull ?? const [];
    final products =
        ref.watch(allActiveProductsProvider).valueOrNull ?? const [];
    final sourceId = _sourceLocationId();
    final available = _mode.movesStock && sourceId != null
        ? ref.watch(availableAtLocationProvider(sourceId))
        : const <int, int>{};

    final shop = shops.firstWhereOrNull((s) => s.id == _shopId);
    final totals = _previewTotals();

    return AppFormDialog(
      title: 'New invoice',
      subtitle: _mode.description,
      submitLabel: 'Post invoice',
      width: 1120,
      onSubmit: _submit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<InvoiceMode>(
            segments: [
              for (final mode in InvoiceMode.values)
                ButtonSegment<InvoiceMode>(
                  value: mode,
                  label: Text(mode.label),
                ),
            ],
            selected: {_mode},
            onSelectionChanged: (selection) =>
                setState(() => _mode = selection.first),
          ),
          AppSpacing.gapXl,
          FormRow(
            children: [
              AppDropdownField<int>(
                value: _shopId,
                label: 'Shop',
                isRequired: true,
                items: [
                  for (final option in shops)
                    DropdownMenuItem<int>(
                      value: option.id,
                      child: Text(
                        option.hasAgent
                            ? '${option.name} · ${option.assignedAgentName}'
                            : '${option.name} · no agent',
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _shopId = value),
              ),
              AppDateField(
                value: _invoiceDate,
                label: 'Invoice date',
                helperText: 'Defaults to today',
                onChanged: (value) => setState(() => _invoiceDate = value),
                lastDate: DateTime.now(),
              ),
              AppDateField(
                value: _dueDate,
                label: 'Due date',
                helperText: 'Optional',
                onChanged: (value) => setState(() => _dueDate = value),
              ),
            ],
          ),
          if (shop != null && shop.isOverCreditLimit) ...[
            AppSpacing.gapLg,
            _Note(
              tone: _NoteTone.warning,
              message:
                  '${shop.name} already owes '
                  '${shop.outstandingBalance.formatted()}, over its limit of '
                  '${shop.creditLimit!.formatted()}. The invoice will go '
                  'through and the breach will be recorded.',
            ),
          ],
          if (_mode.movesStock && shop != null && !shop.hasAgent) ...[
            AppSpacing.gapLg,
            const _Note(
              tone: _NoteTone.warning,
              message:
                  'This shop has no agent, so there is no stock location to '
                  'supply from. Assign an agent, or use "Charge only".',
            ),
          ],
          if (_mode == InvoiceMode.retailSale) ...[
            AppSpacing.gapLg,
            FormRow(
              children: [
                AppTextField(
                  controller: _customerName,
                  label: 'Customer name',
                  maxLength: 180,
                  helperText: 'Optional',
                ),
                AppTextField(
                  controller: _customerPhone,
                  label: 'Customer phone',
                  maxLength: 32,
                  helperText: 'Optional',
                ),
              ],
            ),
          ],
          AppSpacing.gapXl,
          _LinesPanel(
            title: 'Products being billed',
            subtitle: _mode.movesStock
                ? 'Quantities come out of the source stock when this is posted.'
                : 'No goods move: this is a charge only.',
            child: StockLineEditor(
              controller: _lines,
              products: products,
              availableByProductId: available,
              showAvailable: _mode.movesStock,
              showUnitPrice: true,
              showDiscount: true,
              availableLabel: 'Available',
            ),
          ),
          AppSpacing.gapXl,
          _DiscountAndPayment(
            invoiceDiscount: _invoiceDiscount,
            discountReason: _discountReason,
            discountType: _invoiceDiscountType,
            onDiscountTypeChanged: (type) =>
                setState(() => _invoiceDiscountType = type),
            paymentAmount: _paymentAmount,
            paymentMethod: _paymentMethod,
            onPaymentMethodChanged: (method) =>
                setState(() => _paymentMethod = method),
            chequeNumber: _chequeNumber,
            chequeBank: _chequeBank,
            chequeDate: _chequeDate,
            onChequeDateChanged: (value) => setState(() => _chequeDate = value),
            onChanged: () => setState(() {}),
          ),
          AppSpacing.gapLg,
          _TotalsPreview(totals: totals, payment: _buildPayment()),
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

  /// The same arithmetic the service will apply, so what the user sees before
  /// posting is what gets posted.
  InvoiceTotals _previewTotals() {
    final lines = _lines.lines
        .where((line) => !line.isEmpty && line.product != null)
        .map(
          (line) => InvoiceLineRequest(
            productId: line.product!.id,
            quantity: line.quantityValue,
            unitPrice: line.unitPriceValue,
            discountType: line.discountBps > 0
                ? DiscountType.percentage
                : DiscountType.none,
            discountValue: line.discountBps,
          ),
        )
        .toList(growable: false);

    if (lines.isEmpty) return InvoiceTotals.zero;
    return InvoiceTotals.from(
      lines: lines,
      invoiceDiscountType: _resolvedDiscountType(),
      invoiceDiscountValue: _resolvedDiscountValue(),
    );
  }
}

class _DiscountAndPayment extends StatelessWidget {
  const _DiscountAndPayment({
    required this.invoiceDiscount,
    required this.discountReason,
    required this.discountType,
    required this.onDiscountTypeChanged,
    required this.paymentAmount,
    required this.paymentMethod,
    required this.onPaymentMethodChanged,
    required this.chequeNumber,
    required this.chequeBank,
    required this.chequeDate,
    required this.onChequeDateChanged,
    required this.onChanged,
  });

  final TextEditingController invoiceDiscount;
  final TextEditingController discountReason;
  final DiscountType discountType;
  final ValueChanged<DiscountType> onDiscountTypeChanged;
  final TextEditingController paymentAmount;
  final PaymentMethod? paymentMethod;
  final ValueChanged<PaymentMethod?> onPaymentMethodChanged;
  final TextEditingController chequeNumber;
  final TextEditingController chequeBank;
  final DateTime? chequeDate;
  final ValueChanged<DateTime?> onChequeDateChanged;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: FormSection(
            title: 'Invoice discount',
            description: 'Applied after the line discounts.',
            children: [
              FormRow(
                children: [
                  AppDropdownField<DiscountType>(
                    value: discountType,
                    label: 'Type',
                    items: const [
                      DropdownMenuItem(
                        value: DiscountType.percentage,
                        child: Text('Percentage'),
                      ),
                      DropdownMenuItem(
                        value: DiscountType.fixedAmount,
                        child: Text('Fixed amount'),
                      ),
                    ],
                    onChanged: (value) =>
                        onDiscountTypeChanged(value ?? DiscountType.percentage),
                  ),
                  TextField(
                    controller: invoiceDiscount,
                    textAlign: TextAlign.right,
                    decoration: InputDecoration(
                      labelText: 'Discount',
                      suffixText: discountType == DiscountType.percentage
                          ? '%'
                          : null,
                      prefixText: discountType == DiscountType.fixedAmount
                          ? 'Rs. '
                          : null,
                    ),
                    onChanged: (_) => onChanged(),
                  ),
                ],
              ),
              AppSpacing.gapLg,
              AppTextField(
                controller: discountReason,
                label: 'Discount reason',
                maxLength: 300,
                helperText: 'Required above the ceiling',
              ),
            ],
          ),
        ),
        AppSpacing.hGapXl,
        Expanded(
          child: FormSection(
            title: 'Payment taken now',
            description: 'Leave blank to bill on credit.',
            children: [
              FormRow(
                children: [
                  AppDropdownField<PaymentMethod?>(
                    value: paymentMethod,
                    label: 'Method',
                    items: const [
                      DropdownMenuItem<PaymentMethod?>(
                        child: Text('None — on credit'),
                      ),
                      DropdownMenuItem<PaymentMethod?>(
                        value: PaymentMethod.cash,
                        child: Text('Cash'),
                      ),
                      DropdownMenuItem<PaymentMethod?>(
                        value: PaymentMethod.bankTransfer,
                        child: Text('Bank transfer'),
                      ),
                      DropdownMenuItem<PaymentMethod?>(
                        value: PaymentMethod.cheque,
                        child: Text('Cheque'),
                      ),
                      DropdownMenuItem<PaymentMethod?>(
                        value: PaymentMethod.cardOrDigital,
                        child: Text('Card or digital'),
                      ),
                    ],
                    onChanged: onPaymentMethodChanged,
                  ),
                  AppMoneyField(
                    controller: paymentAmount,
                    label: 'Amount received',
                    enabled: paymentMethod != null,
                    onChanged: (_) => onChanged(),
                  ),
                ],
              ),
              if (paymentMethod == PaymentMethod.cheque) ...[
                AppSpacing.gapLg,
                FormRow(
                  children: [
                    AppTextField(
                      controller: chequeNumber,
                      label: 'Cheque number',
                      isRequired: true,
                      maxLength: 32,
                    ),
                    AppTextField(
                      controller: chequeBank,
                      label: 'Bank',
                      isRequired: true,
                      maxLength: 120,
                    ),
                    AppDateField(
                      value: chequeDate,
                      label: 'Cheque date',
                      isRequired: true,
                      onChanged: onChequeDateChanged,
                    ),
                  ],
                ),
                AppSpacing.gapMd,
                const _Note(
                  message:
                      'A cheque is recorded as pending. It does not reduce '
                      'what is owed until it clears.',
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _TotalsPreview extends StatelessWidget {
  const _TotalsPreview({required this.totals, required this.payment});

  final InvoiceTotals totals;
  final ImmediatePayment? payment;

  @override
  Widget build(BuildContext context) {
    if (totals.gross.isZero) return const SizedBox.shrink();

    final clearsNow = payment != null && !payment!.isCheque;
    final outstanding = clearsNow ? totals.net - payment!.amount : totals.net;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: AppRadii.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _line(context, 'Gross', totals.gross),
          if (!totals.itemDiscount.isZero)
            _line(context, 'Line discounts', -totals.itemDiscount),
          if (!totals.invoiceDiscount.isZero)
            _line(
              context,
              'Invoice discount '
              '(${formatBps(totals.invoiceDiscountBps)} of '
              '${totals.afterItemDiscounts.formatted()})',
              -totals.invoiceDiscount,
            ),
          const Divider(),
          _line(context, 'Net payable', totals.net, emphasise: true),
          if (payment != null) ...[
            _line(
              context,
              payment!.isCheque
                  ? 'Cheque received (pending clearance)'
                  : 'Received now',
              -payment!.amount,
            ),
            _line(context, 'Outstanding', outstanding, emphasise: true),
            if (payment!.isCheque)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  'The cheque does not reduce the outstanding balance until '
                  'it clears.',
                  style: context.text.bodySmall?.copyWith(
                    color: context.statusColors.warning,
                  ),
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
    Money amount, {
    bool emphasise = false,
  }) {
    final style = emphasise ? context.text.titleSmall : context.text.bodySmall;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(amount.formatted(), style: style),
        ],
      ),
    );
  }
}

class _LinesPanel extends StatelessWidget {
  const _LinesPanel({required this.title, required this.child, this.subtitle});

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

enum _NoteTone { info, warning }

class _Note extends StatelessWidget {
  const _Note({required this.message, this.tone = _NoteTone.info});

  final String message;
  final _NoteTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.statusColors;
    final isWarning = tone == _NoteTone.warning;

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

/// Bills a posted delivery that has not been invoiced yet.
class BillDeliveryDialog extends ConsumerStatefulWidget {
  const BillDeliveryDialog({super.key, required this.delivery});

  final UnbilledDelivery delivery;

  static Future<bool> show(
    BuildContext context, {
    required UnbilledDelivery delivery,
  }) async {
    final posted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => BillDeliveryDialog(delivery: delivery),
    );
    return posted ?? false;
  }

  @override
  ConsumerState<BillDeliveryDialog> createState() => _BillDeliveryDialogState();
}

class _BillDeliveryDialogState extends ConsumerState<BillDeliveryDialog> {
  final _invoiceDiscount = TextEditingController();
  final _discountReason = TextEditingController();
  final _notes = TextEditingController();
  DateTime? _dueDate;

  @override
  void dispose() {
    _invoiceDiscount.dispose();
    _discountReason.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final percent = double.tryParse(_invoiceDiscount.text.trim());
    await ref
        .read(invoiceServiceProvider)
        .billDelivery(
          ref.read(requireCurrentUserProvider),
          stockTransactionId: widget.delivery.stockTransactionId,
          dueDate: _dueDate,
          invoiceDiscountType: percent == null || percent == 0
              ? DiscountType.none
              : DiscountType.percentage,
          invoiceDiscountValue: percent == null ? 0 : (percent * 100).round(),
          discountReason: _discountReason.text,
          notes: _notes.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final delivery = widget.delivery;

    return AppFormDialog(
      title: 'Bill ${delivery.documentNumber}',
      subtitle:
          'Raises an invoice for goods already delivered. The delivery itself '
          'is not changed.',
      submitLabel: 'Raise the invoice',
      width: 560,
      onSubmit: _submit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: context.colors.surfaceContainerHighest.withValues(
                alpha: 0.5,
              ),
              borderRadius: AppRadii.smAll,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(delivery.partyName, style: context.text.titleSmall),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  '${delivery.totalQuantity} unit(s) · '
                  '${delivery.sourceName} to ${delivery.destinationName}',
                  style: context.text.bodySmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  delivery.needsPrices
                      ? 'The delivery note carried no prices, so the '
                            'catalogue wholesale price will be used.'
                      : 'Billing at the delivery note prices: '
                            '${delivery.documentValue.formatted()}.',
                  style: context.text.bodySmall,
                ),
              ],
            ),
          ),
          AppSpacing.gapLg,
          FormRow(
            children: [
              AppDateField(
                value: _dueDate,
                label: 'Due date',
                helperText: 'Optional',
                onChanged: (value) => setState(() => _dueDate = value),
              ),
              TextField(
                controller: _invoiceDiscount,
                textAlign: TextAlign.right,
                decoration: const InputDecoration(
                  labelText: 'Invoice discount',
                  suffixText: '%',
                ),
              ),
            ],
          ),
          AppSpacing.gapLg,
          AppTextField(
            controller: _discountReason,
            label: 'Discount reason',
            maxLength: 300,
            helperText: 'Required above the ceiling',
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
