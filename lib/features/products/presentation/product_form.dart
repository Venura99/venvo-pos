import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/categories/domain/category_models.dart';
import 'package:venvo_core/features/products/domain/product_models.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/form_dialog.dart';
import '../../../core/widgets/form_fields.dart';
import '../../authentication/presentation/auth_controller.dart';
import 'products_screen.dart';

/// Create/edit form for a product.
///
/// Three prices are captured: what the product costs the business, what agents
/// and shops are charged, and what a shop is expected to charge an end
/// customer. The form shows the resulting margin live, and warns - without
/// blocking - when a product would be sold below cost, because a clearance
/// price is a legitimate business decision.
class ProductFormDialog extends ConsumerStatefulWidget {
  const ProductFormDialog({super.key, required this.categories, this.existing});

  final ProductListItem? existing;
  final List<CategoryListItem> categories;

  static Future<bool> show(
    BuildContext context, {
    required List<CategoryListItem> categories,
    ProductListItem? existing,
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          ProductFormDialog(categories: categories, existing: existing),
    );
    return saved ?? false;
  }

  @override
  ConsumerState<ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends ConsumerState<ProductFormDialog> {
  late final TextEditingController _sku;
  late final TextEditingController _name;
  late final TextEditingController _barcode;
  late final TextEditingController _brand;
  late final TextEditingController _description;
  late final TextEditingController _unitsPerPack;
  late final TextEditingController _costPrice;
  late final TextEditingController _wholesalePrice;
  late final TextEditingController _retailPrice;
  late final TextEditingController _reorderLevel;
  late final TextEditingController _notes;

  int? _categoryId;
  late UnitOfMeasure _unitOfMeasure;
  late EntityStatus _status;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;

    _sku = TextEditingController(text: existing?.sku ?? '');
    _name = TextEditingController(text: existing?.name ?? '');
    _barcode = TextEditingController(text: existing?.barcode ?? '');
    _brand = TextEditingController(text: existing?.brand ?? '');
    _description = TextEditingController(text: existing?.description ?? '');
    _unitsPerPack = TextEditingController(
      text: (existing?.unitsPerPack ?? 1).toString(),
    );
    _reorderLevel = TextEditingController(
      text: (existing?.reorderLevel ?? 0).toString(),
    );
    _notes = TextEditingController(text: existing?.notes ?? '');

    _costPrice = TextEditingController();
    _wholesalePrice = TextEditingController();
    _retailPrice = TextEditingController();
    if (existing != null) {
      AppMoneyField.setValue(_costPrice, existing.costPrice);
      AppMoneyField.setValue(_wholesalePrice, existing.wholesalePrice);
      AppMoneyField.setValue(_retailPrice, existing.retailPrice);
    }

    _categoryId =
        existing?.categoryId ??
        (widget.categories.length == 1 ? widget.categories.first.id : null);
    _unitOfMeasure = existing?.unitOfMeasure ?? UnitOfMeasure.piece;
    _status = existing?.status ?? EntityStatus.active;
  }

  @override
  void dispose() {
    for (final controller in [
      _sku,
      _name,
      _barcode,
      _brand,
      _description,
      _unitsPerPack,
      _costPrice,
      _wholesalePrice,
      _retailPrice,
      _reorderLevel,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final repository = ref.read(productRepositoryProvider);
    final actor = ref.read(requireCurrentUserProvider);

    final draft = ProductDraft(
      id: widget.existing?.id,
      sku: _sku.text,
      name: _name.text,
      barcode: _barcode.text,
      categoryId: _categoryId!,
      brand: _brand.text,
      description: _description.text,
      unitOfMeasure: _unitOfMeasure,
      unitsPerPack: AppIntField.valueOr(_unitsPerPack, 1),
      costPrice: AppMoneyField.valueOrZero(_costPrice),
      wholesalePrice: AppMoneyField.valueOrZero(_wholesalePrice),
      retailPrice: AppMoneyField.valueOrZero(_retailPrice),
      reorderLevel: AppIntField.valueOr(_reorderLevel, 0),
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
    final cost = AppMoneyField.valueOrZero(_costPrice);
    final wholesale = AppMoneyField.valueOrZero(_wholesalePrice);

    return AppFormDialog(
      title: existing == null ? 'Add product' : 'Edit product',
      subtitle: existing == null
          ? null
          : '${existing.sellableQuantity} unit(s) currently in stock',
      submitLabel: existing == null ? 'Add product' : 'Save changes',
      width: 680,
      onSubmit: _submit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          FormSection(
            title: 'Identification',
            children: [
              FormRow(
                children: [
                  AppTextField(
                    controller: _name,
                    label: 'Product name',
                    isRequired: true,
                    autofocus: true,
                    maxLength: 180,
                    hintText: '25W Charger',
                    textCapitalization: TextCapitalization.words,
                  ),
                  AppTextField(
                    controller: _sku,
                    label: 'SKU',
                    isRequired: true,
                    maxLength: 40,
                    hintText: 'CHG-25W',
                    helperText: 'Stored in upper case',
                  ),
                ],
              ),
              AppSpacing.gapLg,
              FormRow(
                children: [
                  AppDropdownField<int>(
                    value: _categoryId,
                    label: 'Category',
                    isRequired: true,
                    items: [
                      for (final category in widget.categories)
                        DropdownMenuItem<int>(
                          value: category.id,
                          child: Text(category.qualifiedName),
                        ),
                    ],
                    onChanged: (value) => setState(() => _categoryId = value),
                  ),
                  AppTextField(
                    controller: _brand,
                    label: 'Brand',
                    maxLength: 120,
                    textCapitalization: TextCapitalization.words,
                  ),
                  AppTextField(
                    controller: _barcode,
                    label: 'Barcode',
                    maxLength: 64,
                    helperText: 'Optional',
                  ),
                ],
              ),
            ],
          ),
          AppSpacing.gapXl,
          FormSection(
            title: 'Pricing',
            description:
                'Prices here are the defaults offered on new documents. '
                'An invoice keeps the price it was raised with.',
            children: [
              FormRow(
                children: [
                  AppMoneyField(
                    controller: _costPrice,
                    label: 'Cost price',
                    helperText: 'What you pay',
                    onChanged: (_) => setState(() {}),
                  ),
                  AppMoneyField(
                    controller: _wholesalePrice,
                    label: 'Wholesale price',
                    helperText: 'Charged to agents and shops',
                    onChanged: (_) => setState(() {}),
                  ),
                  AppMoneyField(
                    controller: _retailPrice,
                    label: 'Selling price',
                    helperText: 'Shop to customer',
                  ),
                ],
              ),
              AppSpacing.gapMd,
              _MarginHint(cost: cost, wholesale: wholesale),
            ],
          ),
          AppSpacing.gapXl,
          FormSection(
            title: 'Stock handling',
            children: [
              FormRow(
                children: [
                  AppDropdownField<UnitOfMeasure>(
                    value: _unitOfMeasure,
                    label: 'Unit',
                    items: [
                      for (final unit in UnitOfMeasure.values)
                        DropdownMenuItem<UnitOfMeasure>(
                          value: unit,
                          child: Text(unitOfMeasureLabel(unit)),
                        ),
                    ],
                    onChanged: (value) => setState(
                      () => _unitOfMeasure = value ?? UnitOfMeasure.piece,
                    ),
                  ),
                  AppIntField(
                    controller: _unitsPerPack,
                    label: 'Units per pack',
                    minimum: 1,
                    maximum: 10000,
                    helperText: 'Stock is counted in single units',
                  ),
                  AppIntField(
                    controller: _reorderLevel,
                    label: 'Reorder level',
                    minimum: 0,
                    maximum: 1000000,
                    helperText: '0 means not tracked',
                  ),
                ],
              ),
            ],
          ),
          AppSpacing.gapXl,
          FormSection(
            title: 'Notes',
            children: [
              AppTextField(
                controller: _description,
                label: 'Description',
                maxLines: 2,
                maxLength: 1000,
              ),
              AppSpacing.gapLg,
              AppTextField(
                controller: _notes,
                label: 'Internal notes',
                maxLines: 2,
                maxLength: 1000,
                helperText: 'Not printed on documents',
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
                'Inactive products stay in history and in stock reports but '
                'are not offered on new documents.',
              ),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ],
      ),
    );
  }
}

/// Live margin readout under the price fields. A below-cost price is flagged
/// but allowed, since clearance pricing is a real decision.
class _MarginHint extends StatelessWidget {
  const _MarginHint({required this.cost, required this.wholesale});

  final Money cost;
  final Money wholesale;

  @override
  Widget build(BuildContext context) {
    if (cost.isZero && wholesale.isZero) return const SizedBox.shrink();

    final margin = wholesale - cost;
    final belowCost = !wholesale.isZero && wholesale < cost;
    final bps = wholesale.isZero ? 0 : margin.bpsOf(wholesale);
    final colors = context.statusColors;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: belowCost
            ? colors.warningContainer
            : context.colors.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: AppRadii.smAll,
      ),
      child: Row(
        children: [
          Icon(
            belowCost ? Icons.warning_amber_outlined : Icons.trending_up,
            size: 16,
            color: belowCost ? colors.onWarningContainer : colors.success,
          ),
          AppSpacing.hGapSm,
          Expanded(
            child: Text(
              belowCost
                  ? 'This wholesale price is below cost: every sale loses '
                        '${margin.abs.formatted()} per unit.'
                  : 'Wholesale margin ${margin.formatted()} per unit '
                        '(${formatBps(bps)} of the wholesale price).',
              style: context.text.bodySmall?.copyWith(
                color: belowCost ? colors.onWarningContainer : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
