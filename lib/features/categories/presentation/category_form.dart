import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/features/categories/domain/category_models.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/form_dialog.dart';
import '../../../core/widgets/form_fields.dart';
import '../../authentication/presentation/auth_controller.dart';
import 'categories_screen.dart';

/// Create/edit form for a category.
///
/// Opened for a new category when [existing] is null, otherwise pre-filled for
/// editing. Returns true when something was saved.
class CategoryFormDialog extends ConsumerStatefulWidget {
  const CategoryFormDialog({
    super.key,
    this.existing,
    this.allCategories = const [],
  });

  final CategoryListItem? existing;

  /// Candidates for the parent dropdown.
  final List<CategoryListItem> allCategories;

  static Future<bool> show(
    BuildContext context, {
    CategoryListItem? existing,
    List<CategoryListItem> allCategories = const [],
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          CategoryFormDialog(existing: existing, allCategories: allCategories),
    );
    return saved ?? false;
  }

  @override
  ConsumerState<CategoryFormDialog> createState() => _CategoryFormDialogState();
}

class _CategoryFormDialogState extends ConsumerState<CategoryFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _sortOrder;
  int? _parentId;
  late EntityStatus _status;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _description = TextEditingController(text: existing?.description ?? '');
    _sortOrder = TextEditingController(
      text: (existing?.sortOrder ?? 0).toString(),
    );
    _parentId = existing?.parentId;
    _status = existing?.status ?? EntityStatus.active;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _sortOrder.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final repository = ref.read(categoryRepositoryProvider);
    final actor = ref.read(requireCurrentUserProvider);
    final draft = CategoryDraft(
      id: widget.existing?.id,
      name: _name.text,
      description: _description.text,
      parentId: _parentId,
      sortOrder: AppIntField.valueOr(_sortOrder, 0),
      status: _status,
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
    // A category cannot be its own parent, and the repository also refuses a
    // deeper cycle; the dropdown just removes the obvious case.
    final parentCandidates = widget.allCategories
        .where((c) => c.id != existing?.id && c.parentId == null)
        .toList();

    return AppFormDialog(
      title: existing == null ? 'Add category' : 'Edit category',
      subtitle: existing == null
          ? 'Categories group the product catalogue.'
          : '${existing.totalProductCount} product(s) use this category.',
      submitLabel: existing == null ? 'Add category' : 'Save changes',
      onSubmit: _submit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppTextField(
            controller: _name,
            label: 'Category name',
            isRequired: true,
            autofocus: true,
            maxLength: 120,
            textCapitalization: TextCapitalization.words,
            hintText: 'Chargers',
          ),
          AppSpacing.gapLg,
          FormRow(
            children: [
              AppDropdownField<int?>(
                value: _parentId,
                label: 'Parent category',
                helperText: 'Leave empty for a top-level category',
                items: [
                  const DropdownMenuItem<int?>(child: Text('None (top level)')),
                  for (final candidate in parentCandidates)
                    DropdownMenuItem<int?>(
                      value: candidate.id,
                      child: Text(candidate.name),
                    ),
                ],
                onChanged: (value) => setState(() => _parentId = value),
              ),
              AppIntField(
                controller: _sortOrder,
                label: 'Sort order',
                helperText: 'Lower numbers appear first',
                minimum: 0,
                maximum: 9999,
              ),
            ],
          ),
          AppSpacing.gapLg,
          AppTextField(
            controller: _description,
            label: 'Description',
            maxLines: 2,
            maxLength: 500,
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
                'Inactive categories stay on existing products but cannot be '
                'chosen for new ones.',
              ),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ],
      ),
    );
  }
}
