import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/features/categories/api/category_api.dart';
import 'package:venvo_core/features/categories/domain/category_models.dart';

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
import 'category_form.dart';

final categoryRepositoryProvider = Provider<CategoryApi>(
  (ref) => CategoryApi(ref.watch(apiClientProvider)),
);

/// Whether archived categories are shown.
final showArchivedCategoriesProvider = StateProvider<bool>((ref) => false);

final categorySearchProvider = StateProvider<String>((ref) => '');

/// Live category list. Drift re-emits it whenever categories or products
/// change, so an edit appears without the screen re-querying.
final categoriesProvider = StreamProvider<List<CategoryListItem>>((ref) {
  return ref
      .watch(categoryRepositoryProvider)
      .watchCategories(
        includeArchived: ref.watch(showArchivedCategoriesProvider),
      );
});

/// Categories filtered by the search box. Kept client-side because the list is
/// small and filtering in memory avoids a query per keystroke.
final visibleCategoriesProvider = Provider<List<CategoryListItem>>((ref) {
  final all = ref.watch(categoriesProvider).valueOrNull ?? const [];
  final query = ref.watch(categorySearchProvider).trim().toLowerCase();
  if (query.isEmpty) return all;
  return all
      .where(
        (category) =>
            category.name.toLowerCase().contains(query) ||
            (category.parentName ?? '').toLowerCase().contains(query) ||
            (category.description ?? '').toLowerCase().contains(query),
      )
      .toList(growable: false);
});

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (!(user?.can(Permissions.productsView) ?? false)) {
      return const PageScaffold(
        title: 'Categories',
        child: EmptyState(
          icon: Icons.lock_outline,
          title: 'You do not have access to the product catalogue',
        ),
      );
    }

    final canManage = user?.can(Permissions.productsManage) ?? false;
    final categories = ref.watch(categoriesProvider);
    final visible = ref.watch(visibleCategoriesProvider);
    final showArchived = ref.watch(showArchivedCategoriesProvider);

    return PageScaffold(
      title: 'Categories',
      description:
          'Group the catalogue so products are quick to find during data '
          'entry. Categories are archived, never deleted, so existing '
          'products keep resolving.',
      scrollable: false,
      actions: [
        if (canManage)
          FilledButton.icon(
            onPressed: () => _openForm(context, ref, null),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add category'),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppSearchField(
                hintText: 'Search categories',
                onChanged: (value) =>
                    ref.read(categorySearchProvider.notifier).state = value,
              ),
              AppSpacing.hGapLg,
              FilterChip(
                selected: showArchived,
                label: const Text('Show archived'),
                onSelected: (value) =>
                    ref.read(showArchivedCategoriesProvider.notifier).state =
                        value,
              ),
              const Spacer(),
              Text(
                visible.length == 1
                    ? '1 category'
                    : '${visible.length} categories',
                style: context.text.bodySmall,
              ),
            ],
          ),
          AppSpacing.gapLg,
          Expanded(
            child: AsyncValueView<List<CategoryListItem>>(
              value: categories,
              builder: (context, _) => SectionCard(
                padding: EdgeInsets.zero,
                fillHeight: true,
                child: AppDataTable<CategoryListItem>(
                  rows: visible,
                  minWidth: 820,
                  empty: EmptyState(
                    icon: Icons.folder_outlined,
                    title: ref.read(categorySearchProvider).isEmpty
                        ? 'No categories yet'
                        : 'No categories match your search',
                    message: ref.read(categorySearchProvider).isEmpty
                        ? 'Add a category such as Chargers, Cables or Audio to '
                              'get started.'
                        : null,
                    action:
                        canManage && ref.read(categorySearchProvider).isEmpty
                        ? FilledButton.icon(
                            onPressed: () => _openForm(context, ref, null),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add category'),
                          )
                        : null,
                  ),
                  onRowTap: canManage
                      ? (category) => _openForm(context, ref, category)
                      : null,
                  columns: [
                    AppTableColumn<CategoryListItem>(
                      label: 'Category',
                      flex: 3,
                      cell: (context, row) => row.parentName == null
                          ? TableTextCell(row.name, bold: true)
                          : TableTwoLineCell(
                              primary: row.name,
                              secondary: 'in ${row.parentName}',
                            ),
                    ),
                    AppTableColumn<CategoryListItem>(
                      label: 'Description',
                      flex: 4,
                      cell: (context, row) => TableTextCell(
                        row.description ?? '—',
                        muted: row.description == null,
                      ),
                    ),
                    AppTableColumn<CategoryListItem>(
                      label: 'Products',
                      width: 110,
                      numeric: true,
                      tooltip:
                          'Active products, and the total including '
                          'inactive ones',
                      cell: (context, row) => TableTextCell(
                        row.activeProductCount == row.totalProductCount
                            ? '${row.activeProductCount}'
                            : '${row.activeProductCount} of '
                                  '${row.totalProductCount}',
                      ),
                    ),
                    AppTableColumn<CategoryListItem>(
                      label: 'Order',
                      width: 80,
                      numeric: true,
                      cell: (context, row) => TableTextCell('${row.sortOrder}'),
                    ),
                    AppTableColumn<CategoryListItem>(
                      label: 'Status',
                      width: 110,
                      cell: (context, row) => StatusPill.entity(row.status),
                    ),
                    AppTableColumn<CategoryListItem>(
                      label: '',
                      width: 56,
                      cell: (context, row) => canManage
                          ? _RowMenu(category: row)
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref,
    CategoryListItem? existing,
  ) async {
    final all = ref.read(categoriesProvider).valueOrNull ?? const [];
    final saved = await CategoryFormDialog.show(
      context,
      existing: existing,
      allCategories: all,
    );
    if (saved && context.mounted) {
      showSuccessSnackBar(
        context,
        existing == null ? 'Category added.' : 'Category saved.',
      );
    }
  }
}

class _RowMenu extends ConsumerWidget {
  const _RowMenu({required this.category});

  final CategoryListItem category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Actions',
      icon: const Icon(Icons.more_horiz, size: 18),
      onSelected: (value) => _handle(context, ref, value),
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'edit', child: Text('Edit')),
        if (category.isArchived)
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
    final repository = ref.read(categoryRepositoryProvider);
    final actor = ref.read(requireCurrentUserProvider);

    try {
      switch (action) {
        case 'edit':
          await CategoryFormDialog.show(
            context,
            existing: category,
            allCategories: ref.read(categoriesProvider).valueOrNull ?? const [],
          );
        case 'archive':
          final confirmed = await ConfirmDialog.show(
            context,
            title: 'Archive "${category.name}"?',
            message:
                'It will no longer be offered for new products. Existing '
                'products keep it, and nothing is deleted.',
            confirmLabel: 'Archive',
            icon: Icons.archive_outlined,
          );
          if (!confirmed) return;
          await repository.archive(actor, category.id);
          if (context.mounted) {
            showSuccessSnackBar(context, 'Category archived.');
          }
        case 'restore':
          await repository.restore(actor, category.id);
          if (context.mounted) {
            showSuccessSnackBar(context, 'Category restored.');
          }
      }
    } catch (error) {
      if (context.mounted) showFailureSnackBar(context, error);
    }
  }
}
