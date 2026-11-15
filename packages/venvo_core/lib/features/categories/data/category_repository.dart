import 'package:drift/drift.dart';

import '../../../core/constants/permissions.dart';
import '../../../core/database/app_database.dart';
import '../../../core/enums/app_enums.dart';
import '../../../core/errors/failures.dart';
import '../../../core/errors/guards.dart';
import '../../../core/services/audit_service.dart';
import '../../../core/services/clock.dart';
import '../../authentication/domain/authenticated_user.dart';
import '../domain/category_models.dart';

/// Reads and maintains product categories.
///
/// Categories may be one level nested (a parent and its children). Two rules
/// are enforced here rather than in the form, so they hold however the
/// operation is reached:
///
/// * a category can never become its own ancestor, which would make the tree
///   unwalkable;
/// * a category with active products cannot be archived, which would leave
///   those products pointing at something the catalogue no longer offers.
class CategoryRepository {
  const CategoryRepository({
    required AppDatabase database,
    required Clock clock,
    required AuditService audit,
  }) : _db = database,
       _clock = clock,
       _audit = audit;

  final AppDatabase _db;
  final Clock _clock;
  final AuditService _audit;

  /// Live list of categories, re-emitted whenever categories or products
  /// change, so an edit shows up without the screen asking again.
  Stream<List<CategoryListItem>> watchCategories({
    bool includeArchived = false,
  }) {
    final query = _db.customSelect(
      '''
      SELECT
        c.id,
        c.name,
        c.description,
        c.parent_id,
        c.sort_order,
        c.status,
        parent.name AS parent_name,
        (
          SELECT COUNT(*) FROM products p
          WHERE p.category_id = c.id AND p.status = ?
        ) AS active_product_count,
        (
          SELECT COUNT(*) FROM products p WHERE p.category_id = c.id
        ) AS total_product_count
      FROM categories c
      LEFT JOIN categories parent ON parent.id = c.parent_id
      WHERE (? = 1 OR c.status <> ?)
      ORDER BY COALESCE(parent.name, c.name), c.parent_id IS NOT NULL,
               c.sort_order, c.name
      ''',
      variables: [
        Variable<String>(EntityStatus.active.name),
        Variable<int>(includeArchived ? 1 : 0),
        Variable<String>(EntityStatus.archived.name),
      ],
      readsFrom: {_db.categories, _db.products},
    );

    return query.watch().map(
      (rows) => rows.map(_mapRow).toList(growable: false),
    );
  }

  /// Categories that may be chosen as a product's category: active ones only.
  Future<List<CategoryListItem>> selectableCategories() async {
    final rows =
        await (_db.select(_db.categories)
              ..where((c) => c.status.equalsValue(EntityStatus.active))
              ..orderBy([(c) => OrderingTerm.asc(c.name)]))
            .get();

    final byId = {for (final row in rows) row.id: row};
    return rows
        .map(
          (row) => CategoryListItem(
            id: row.id,
            name: row.name,
            parentId: row.parentId,
            parentName: row.parentId == null ? null : byId[row.parentId]?.name,
            sortOrder: row.sortOrder,
            status: row.status,
            activeProductCount: 0,
            totalProductCount: 0,
            description: row.description,
          ),
        )
        .toList(growable: false);
  }

  Future<int> create(AuthenticatedUser actor, CategoryDraft draft) async {
    actor.require(Permissions.productsManage, action: 'add categories');
    final name = requireText(draft.name, 'Category name', maxLength: 120);

    return _db.transaction(() async {
      await _assertNameAvailable(name, excludingId: null);
      if (draft.parentId != null) {
        await _assertParentExists(draft.parentId!);
      }

      final now = _clock.nowUtc();
      final id = await _db
          .into(_db.categories)
          .insert(
            CategoriesCompanion.insert(
              name: name,
              description: Value(_cleanOptional(draft.description)),
              parentId: Value(draft.parentId),
              sortOrder: Value(draft.sortOrder),
              status: Value(draft.status),
              createdAt: now,
              updatedAt: now,
            ),
          );

      await _audit.record(
        action: AuditAction.create,
        summary: 'Created the category "$name".',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.category,
        entityId: id,
      );
      return id;
    });
  }

  Future<void> update(AuthenticatedUser actor, CategoryDraft draft) async {
    actor.require(Permissions.productsManage, action: 'edit categories');
    final id = requireFound(draft.id, 'This category has not been saved yet.');
    final name = requireText(draft.name, 'Category name', maxLength: 120);

    await _db.transaction(() async {
      final existing = requireFound(
        await (_db.select(
          _db.categories,
        )..where((c) => c.id.equals(id))).getSingleOrNull(),
        'That category no longer exists.',
      );

      await _assertNameAvailable(name, excludingId: id);
      if (draft.parentId != null) {
        requireRule(
          draft.parentId != id,
          'A category cannot be its own parent.',
          rule: 'category.no_self_parent',
        );
        await _assertParentExists(draft.parentId!);
        await _assertNoCycle(categoryId: id, proposedParentId: draft.parentId!);
      }

      if (draft.status == EntityStatus.archived &&
          existing.status != EntityStatus.archived) {
        await _assertNoActiveProducts(id, name);
      }

      await (_db.update(_db.categories)..where((c) => c.id.equals(id))).write(
        CategoriesCompanion(
          name: Value(name),
          description: Value(_cleanOptional(draft.description)),
          parentId: Value(draft.parentId),
          sortOrder: Value(draft.sortOrder),
          status: Value(draft.status),
          updatedAt: Value(_clock.nowUtc()),
        ),
      );

      await _audit.recordUpdate(
        entityKind: EntityKind.category,
        entityId: id,
        summary: 'Updated the category "$name".',
        userId: actor.id,
        username: actor.username,
        before: {
          'name': existing.name,
          'description': existing.description,
          'parentId': existing.parentId,
          'sortOrder': existing.sortOrder,
          'status': existing.status.name,
        },
        after: {
          'name': name,
          'description': _cleanOptional(draft.description),
          'parentId': draft.parentId,
          'sortOrder': draft.sortOrder,
          'status': draft.status.name,
        },
      );
    });
  }

  /// Soft-deletes a category. The row stays so historical products keep
  /// resolving their category.
  Future<void> archive(AuthenticatedUser actor, int categoryId) async {
    actor.require(Permissions.productsManage, action: 'archive categories');

    await _db.transaction(() async {
      final existing = requireFound(
        await (_db.select(
          _db.categories,
        )..where((c) => c.id.equals(categoryId))).getSingleOrNull(),
        'That category no longer exists.',
      );
      await _assertNoActiveProducts(categoryId, existing.name);

      final children =
          await (_db.select(_db.categories)..where(
                (c) =>
                    c.parentId.equals(categoryId) &
                    c.status.equalsValue(EntityStatus.active),
              ))
              .get();
      requireRule(
        children.isEmpty,
        'This category has ${children.length} active sub-categories. '
        'Archive or move those first.',
        rule: 'category.no_active_children',
      );

      await (_db.update(
        _db.categories,
      )..where((c) => c.id.equals(categoryId))).write(
        CategoriesCompanion(
          status: const Value(EntityStatus.archived),
          updatedAt: Value(_clock.nowUtc()),
        ),
      );

      await _audit.record(
        action: AuditAction.archive,
        summary: 'Archived the category "${existing.name}".',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.category,
        entityId: categoryId,
      );
    });
  }

  Future<void> restore(AuthenticatedUser actor, int categoryId) async {
    actor.require(Permissions.productsManage, action: 'restore categories');

    final existing = requireFound(
      await (_db.select(
        _db.categories,
      )..where((c) => c.id.equals(categoryId))).getSingleOrNull(),
      'That category no longer exists.',
    );

    await (_db.update(
      _db.categories,
    )..where((c) => c.id.equals(categoryId))).write(
      CategoriesCompanion(
        status: const Value(EntityStatus.active),
        updatedAt: Value(_clock.nowUtc()),
      ),
    );

    await _audit.record(
      action: AuditAction.update,
      summary: 'Restored the category "${existing.name}".',
      userId: actor.id,
      username: actor.username,
      entityKind: EntityKind.category,
      entityId: categoryId,
    );
  }

  // --- Rules --------------------------------------------------------------

  Future<void> _assertNameAvailable(String name, {int? excludingId}) async {
    final query = _db.select(_db.categories)
      ..where((c) => c.name.lower().equals(name.toLowerCase()));
    if (excludingId != null) {
      query.where((c) => c.id.isNotValue(excludingId));
    }
    final clash = await query.getSingleOrNull();
    requireRule(
      clash == null,
      'A category called "$name" already exists.',
      rule: 'category.name_unique',
    );
  }

  Future<void> _assertParentExists(int parentId) async {
    final parent = await (_db.select(
      _db.categories,
    )..where((c) => c.id.equals(parentId))).getSingleOrNull();
    requireFound(parent, 'The selected parent category no longer exists.');
    requireRule(
      parent!.status == EntityStatus.active,
      'The selected parent category is not active.',
      rule: 'category.parent_active',
    );
  }

  /// Walks up from the proposed parent looking for [categoryId]. A depth cap
  /// stops a pre-existing cycle in the data from looping forever.
  Future<void> _assertNoCycle({
    required int categoryId,
    required int proposedParentId,
  }) async {
    var currentId = proposedParentId;
    for (var depth = 0; depth < 32; depth++) {
      requireRule(
        currentId != categoryId,
        'That would make the category a descendant of itself.',
        rule: 'category.no_cycle',
      );
      final parent = await (_db.select(
        _db.categories,
      )..where((c) => c.id.equals(currentId))).getSingleOrNull();
      final nextId = parent?.parentId;
      if (nextId == null) return;
      currentId = nextId;
    }
    throw const BusinessRuleFailure(
      'The category tree is nested too deeply.',
      rule: 'category.max_depth',
    );
  }

  Future<void> _assertNoActiveProducts(int categoryId, String name) async {
    final row = await _db
        .customSelect(
          'SELECT COUNT(*) AS c FROM products WHERE category_id = ? AND status = ?',
          variables: [
            Variable<int>(categoryId),
            Variable<String>(EntityStatus.active.name),
          ],
          readsFrom: {_db.products},
        )
        .getSingle();
    final count = row.data['c'] as int;
    requireRule(
      count == 0,
      'The category "$name" still has $count active product(s). '
      'Move or deactivate them first.',
      rule: 'category.no_active_products',
    );
  }

  static CategoryListItem _mapRow(QueryRow row) => CategoryListItem(
    id: row.read<int>('id'),
    name: row.read<String>('name'),
    description: row.readNullable<String>('description'),
    parentId: row.readNullable<int>('parent_id'),
    parentName: row.readNullable<String>('parent_name'),
    sortOrder: row.read<int>('sort_order'),
    status: EntityStatus.values.byName(row.read<String>('status')),
    activeProductCount: row.read<int>('active_product_count'),
    totalProductCount: row.read<int>('total_product_count'),
  );

  static String? _cleanOptional(String? value) {
    final text = (value ?? '').trim();
    return text.isEmpty ? null : text;
  }
}
