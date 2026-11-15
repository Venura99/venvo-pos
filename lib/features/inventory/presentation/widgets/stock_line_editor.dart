import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/inventory/domain/stock_models.dart';
import 'package:venvo_core/features/products/domain/product_models.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/design_tokens.dart';

/// One line being typed into a stock document.
///
/// Holds its own text controllers so a row keeps its cursor and selection
/// while other rows are added or removed.
class StockLineDraft {
  StockLineDraft({required this.key, this.product});

  final Object key;
  ProductListItem? product;

  final TextEditingController quantity = TextEditingController();
  final TextEditingController unitCost = TextEditingController();
  final TextEditingController unitPrice = TextEditingController();
  final TextEditingController discountPercent = TextEditingController();

  int get quantityValue => int.tryParse(quantity.text.trim()) ?? 0;

  Money? get unitCostValue => Money.tryParse(unitCost.text);

  Money get unitPriceValue => Money.tryParse(unitPrice.text) ?? Money.zero;

  /// Discount as basis points, so 12.5% stays exact.
  int get discountBps {
    final text = discountPercent.text.trim();
    if (text.isEmpty) return 0;
    final parsed = double.tryParse(text);
    return parsed == null ? 0 : (parsed * 100).round();
  }

  Money get grossValue => unitPriceValue * quantityValue;

  Money get discountValue => grossValue.percentage(discountBps);

  Money get lineTotal => grossValue - discountValue;

  bool get isEmpty => product == null && quantity.text.trim().isEmpty;

  void dispose() {
    quantity.dispose();
    unitCost.dispose();
    unitPrice.dispose();
    discountPercent.dispose();
  }
}

/// Owns the lines of a document being composed.
///
/// The parent form creates one, hands it to a [StockLineEditor], and reads
/// [toMovementLines] when the user posts. Validation lives here rather than in
/// the widget so a form cannot forget to call it.
class StockLineEditorController extends ChangeNotifier {
  final List<StockLineDraft> lines = [];
  int _nextKey = 0;

  bool get isEmpty => lines.where((line) => !line.isEmpty).isEmpty;

  Set<int> get chosenProductIds => {
    for (final line in lines)
      if (line.product != null) line.product!.id,
  };

  int get totalQuantity =>
      lines.fold(0, (total, line) => total + line.quantityValue);

  Money get subtotal => lines.map((line) => line.grossValue).sum;

  Money get discountTotal => lines.map((line) => line.discountValue).sum;

  Money get total => subtotal - discountTotal;

  /// Value of the goods at the cost typed in, for an inbound document.
  Money get costTotal => lines
      .map((line) => (line.unitCostValue ?? Money.zero) * line.quantityValue)
      .sum;

  StockLineDraft addLine({ProductListItem? product}) {
    final draft = StockLineDraft(key: _nextKey++, product: product);
    if (product != null) {
      // Pre-fill the prices the catalogue suggests, so a straightforward
      // document needs only a quantity typed.
      AppMoneySeed.seed(draft.unitCost, product.costPrice);
      AppMoneySeed.seed(draft.unitPrice, product.wholesalePrice);
    }
    lines.add(draft);
    notifyListeners();
    return draft;
  }

  void setProduct(StockLineDraft line, ProductListItem product) {
    line.product = product;
    if (line.unitCost.text.trim().isEmpty) {
      AppMoneySeed.seed(line.unitCost, product.costPrice);
    }
    if (line.unitPrice.text.trim().isEmpty) {
      AppMoneySeed.seed(line.unitPrice, product.wholesalePrice);
    }
    notifyListeners();
  }

  void removeLine(StockLineDraft line) {
    lines.remove(line);
    line.dispose();
    notifyListeners();
  }

  void refresh() => notifyListeners();

  /// Returns the first problem with the lines, or null when they are usable.
  ///
  /// [availableByProductId] is consulted only to warn early; the ledger
  /// service checks availability again and is the real gate.
  String? validate({
    Map<int, int>? availableByProductId,
    bool requireUnitCost = false,
    bool allowOverAvailable = false,
  }) {
    final usable = lines.where((line) => !line.isEmpty).toList();
    if (usable.isEmpty) return 'Add at least one product.';

    final seen = <int>{};
    for (final line in usable) {
      final product = line.product;
      if (product == null) return 'Choose a product on every line.';
      if (!seen.add(product.id)) {
        return '"${product.name}" is on more than one line. Combine them.';
      }
      if (line.quantityValue <= 0) {
        return 'Enter a quantity of at least 1 for "${product.name}".';
      }
      if (requireUnitCost && line.unitCostValue == null) {
        return 'Enter a unit cost for "${product.name}".';
      }
      if (line.discountBps < 0 || line.discountBps > Money.bpsScale) {
        return 'The discount on "${product.name}" must be between 0% and 100%.';
      }
      if (!allowOverAvailable && availableByProductId != null) {
        final available = availableByProductId[product.id] ?? 0;
        if (line.quantityValue > available) {
          return '"${product.name}" has only $available unit(s) available, '
              'but ${line.quantityValue} were entered.';
        }
      }
    }
    return null;
  }

  /// Converts the usable lines into what the ledger service expects.
  List<StockMovementLine> toMovementLines({
    bool includeUnitCost = false,
    bool includePrices = false,
  }) {
    return lines
        .where((line) => !line.isEmpty && line.product != null)
        .map(
          (line) => StockMovementLine(
            productId: line.product!.id,
            quantity: line.quantityValue,
            unitCost: includeUnitCost ? line.unitCostValue : null,
            unitPrice: includePrices ? line.unitPriceValue : Money.zero,
            discountType: includePrices && line.discountBps > 0
                ? DiscountType.percentage
                : DiscountType.none,
            discountValue: includePrices ? line.discountBps : 0,
          ),
        )
        .toList(growable: false);
  }

  @override
  void dispose() {
    for (final line in lines) {
      line.dispose();
    }
    lines.clear();
    super.dispose();
  }
}

/// Small helper to seed a money field without pulling in the form widgets.
class AppMoneySeed {
  const AppMoneySeed._();

  static void seed(TextEditingController controller, Money value) {
    if (value.isZero) return;
    controller.text = (value.cents / Money.minorPerMajor).toStringAsFixed(2);
  }
}

/// The repeating line grid used by every stock document form.
class StockLineEditor extends StatefulWidget {
  const StockLineEditor({
    super.key,
    required this.controller,
    required this.products,
    this.availableByProductId = const {},
    this.showAvailable = true,
    this.showUnitCost = false,
    this.showUnitPrice = false,
    this.showDiscount = false,
    this.availableLabel = 'Available',
  });

  final StockLineEditorController controller;
  final List<ProductListItem> products;

  /// Quantity on hand at the source, shown beside each line so the user can
  /// see what they have before entering a quantity.
  final Map<int, int> availableByProductId;

  final bool showAvailable;

  /// Shown when goods are entering the business and a cost must be stated.
  final bool showUnitCost;

  /// Shown when the document carries delivery-note values.
  final bool showUnitPrice;
  final bool showDiscount;
  final String availableLabel;

  @override
  State<StockLineEditor> createState() => _StockLineEditorState();
}

class _StockLineEditorState extends State<StockLineEditor> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    if (widget.controller.lines.isEmpty) {
      widget.controller.addLine();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final chosen = controller.chosenProductIds;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HeaderRow(
          showAvailable: widget.showAvailable,
          showUnitCost: widget.showUnitCost,
          showUnitPrice: widget.showUnitPrice,
          showDiscount: widget.showDiscount,
          availableLabel: widget.availableLabel,
        ),
        const Divider(height: 1),
        for (final line in controller.lines)
          _LineRow(
            key: ValueKey(line.key),
            line: line,
            products: widget.products
                .where(
                  (product) =>
                      product.id == line.product?.id ||
                      !chosen.contains(product.id),
                )
                .toList(growable: false),
            availableByProductId: widget.availableByProductId,
            showAvailable: widget.showAvailable,
            showUnitCost: widget.showUnitCost,
            showUnitPrice: widget.showUnitPrice,
            showDiscount: widget.showDiscount,
            canRemove: controller.lines.length > 1,
            onProductSelected: (product) =>
                controller.setProduct(line, product),
            onChanged: controller.refresh,
            onRemove: () => controller.removeLine(line),
          ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: controller.addLine,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add line'),
              ),
              const Spacer(),
              _Totals(
                controller: controller,
                showValue: widget.showUnitPrice,
                showCost: widget.showUnitCost && !widget.showUnitPrice,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.showAvailable,
    required this.showUnitCost,
    required this.showUnitPrice,
    required this.showDiscount,
    required this.availableLabel,
  });

  final bool showAvailable;
  final bool showUnitCost;
  final bool showUnitPrice;
  final bool showDiscount;
  final String availableLabel;

  @override
  Widget build(BuildContext context) {
    final style = context.text.labelSmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: context.colors.onSurfaceVariant,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text('PRODUCT', style: style)),
          if (showAvailable)
            SizedBox(
              width: 86,
              child: Text(
                availableLabel.toUpperCase(),
                style: style,
                textAlign: TextAlign.right,
              ),
            ),
          SizedBox(
            width: 92,
            child: Text('QUANTITY', style: style, textAlign: TextAlign.right),
          ),
          if (showUnitCost)
            SizedBox(
              width: 110,
              child: Text(
                'UNIT COST',
                style: style,
                textAlign: TextAlign.right,
              ),
            ),
          if (showUnitPrice)
            SizedBox(
              width: 110,
              child: Text(
                'UNIT PRICE',
                style: style,
                textAlign: TextAlign.right,
              ),
            ),
          if (showDiscount)
            SizedBox(
              width: 80,
              child: Text('DISC %', style: style, textAlign: TextAlign.right),
            ),
          if (showUnitPrice)
            SizedBox(
              width: 110,
              child: Text(
                'LINE TOTAL',
                style: style,
                textAlign: TextAlign.right,
              ),
            ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({
    super.key,
    required this.line,
    required this.products,
    required this.availableByProductId,
    required this.showAvailable,
    required this.showUnitCost,
    required this.showUnitPrice,
    required this.showDiscount,
    required this.canRemove,
    required this.onProductSelected,
    required this.onChanged,
    required this.onRemove,
  });

  final StockLineDraft line;
  final List<ProductListItem> products;
  final Map<int, int> availableByProductId;
  final bool showAvailable;
  final bool showUnitCost;
  final bool showUnitPrice;
  final bool showDiscount;
  final bool canRemove;
  final ValueChanged<ProductListItem> onProductSelected;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final product = line.product;
    final available = product == null
        ? null
        : availableByProductId[product.id] ?? 0;
    final exceedsAvailable =
        available != null && line.quantityValue > available && showAvailable;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 4,
            child: _ProductPicker(
              selected: product,
              products: products,
              onSelected: onProductSelected,
            ),
          ),
          if (showAvailable)
            SizedBox(
              width: 86,
              child: Text(
                available == null ? '—' : '$available',
                textAlign: TextAlign.right,
                style: AppTheme.monospacedNumbers(context.text.bodyMedium)
                    .copyWith(
                      color: available == null
                          ? context.colors.onSurfaceVariant
                          : available <= 0
                          ? context.statusColors.danger
                          : null,
                    ),
              ),
            ),
          SizedBox(
            width: 92,
            child: _NumberCell(
              controller: line.quantity,
              onChanged: onChanged,
              hasError: exceedsAvailable,
              digitsOnly: true,
            ),
          ),
          if (showUnitCost)
            SizedBox(
              width: 110,
              child: _NumberCell(
                controller: line.unitCost,
                onChanged: onChanged,
              ),
            ),
          if (showUnitPrice)
            SizedBox(
              width: 110,
              child: _NumberCell(
                controller: line.unitPrice,
                onChanged: onChanged,
              ),
            ),
          if (showDiscount)
            SizedBox(
              width: 80,
              child: _NumberCell(
                controller: line.discountPercent,
                onChanged: onChanged,
                suffix: '%',
              ),
            ),
          if (showUnitPrice)
            SizedBox(
              width: 110,
              child: Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: Text(
                  line.lineTotal.plain,
                  textAlign: TextAlign.right,
                  style: AppTheme.monospacedNumbers(
                    context.text.bodyMedium,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          SizedBox(
            width: 40,
            child: IconButton(
              tooltip: canRemove ? 'Remove line' : 'A document needs one line',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 16),
              onPressed: canRemove ? onRemove : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Type-to-search product selector. Typing a SKU and pressing Enter is the
/// fast path a counter operator uses; the list is there for everyone else.
class _ProductPicker extends StatelessWidget {
  const _ProductPicker({
    required this.selected,
    required this.products,
    required this.onSelected,
  });

  final ProductListItem? selected;
  final List<ProductListItem> products;
  final ValueChanged<ProductListItem> onSelected;

  @override
  Widget build(BuildContext context) {
    return Autocomplete<ProductListItem>(
      initialValue: TextEditingValue(
        text: selected == null ? '' : '${selected!.name} (${selected!.sku})',
      ),
      displayStringForOption: (product) => '${product.name} (${product.sku})',
      optionsBuilder: (value) {
        final query = value.text.trim().toLowerCase();
        if (query.isEmpty) return products.take(20);
        return products
            .where(
              (product) =>
                  product.name.toLowerCase().contains(query) ||
                  product.sku.toLowerCase().contains(query) ||
                  (product.barcode ?? '').toLowerCase().contains(query),
            )
            .take(20);
      },
      onSelected: onSelected,
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: const InputDecoration(
            isDense: true,
            hintText: 'Search name, SKU or barcode',
            prefixIcon: Icon(Icons.inventory_2_outlined, size: 16),
            contentPadding: EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.sm,
            ),
          ),
          onSubmitted: (_) => onFieldSubmitted(),
        );
      },
      optionsViewBuilder: (context, onSelectedOption, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            borderRadius: AppRadii.smAll,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280, maxWidth: 420),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final product = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    title: Text(product.name),
                    subtitle: Text(
                      '${product.sku} · '
                      '${product.sellableQuantity} in stock · '
                      '${product.wholesalePrice.formatted()}',
                    ),
                    onTap: () => onSelectedOption(product),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NumberCell extends StatelessWidget {
  const _NumberCell({
    required this.controller,
    required this.onChanged,
    this.hasError = false,
    this.digitsOnly = false,
    this.suffix,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;
  final bool hasError;
  final bool digitsOnly;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: TextField(
        controller: controller,
        textAlign: TextAlign.right,
        keyboardType: digitsOnly
            ? TextInputType.number
            : const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          if (digitsOnly)
            FilteringTextInputFormatter.digitsOnly
          else
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
        ],
        style: AppTheme.monospacedNumbers(context.text.bodyMedium),
        decoration: InputDecoration(
          isDense: true,
          suffixText: suffix,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          enabledBorder: hasError
              ? OutlineInputBorder(
                  borderRadius: AppRadii.smAll,
                  borderSide: BorderSide(color: context.statusColors.danger),
                )
              : null,
        ),
        onChanged: (_) => onChanged(),
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({
    required this.controller,
    required this.showValue,
    required this.showCost,
  });

  final StockLineEditorController controller;
  final bool showValue;
  final bool showCost;

  @override
  Widget build(BuildContext context) {
    final usableLines = controller.lines.where((line) => !line.isEmpty).length;

    return Wrap(
      spacing: AppSpacing.xl,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '$usableLines line(s), ${controller.totalQuantity} unit(s)',
          style: context.text.bodySmall,
        ),
        if (showCost)
          Text(
            'Value at cost ${controller.costTotal.formatted()}',
            style: context.text.bodySmall,
          ),
        if (showValue) ...[
          if (!controller.discountTotal.isZero)
            Text(
              'Discount ${controller.discountTotal.formatted()}',
              style: context.text.bodySmall?.copyWith(
                color: context.statusColors.warning,
              ),
            ),
          Text(
            'Document total ${controller.total.formatted()}',
            style: context.text.titleSmall,
          ),
        ],
      ],
    );
  }
}
