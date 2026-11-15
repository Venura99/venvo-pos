import 'package:flutter_test/flutter_test.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/errors/failures.dart';
import 'package:venvo_core/features/categories/domain/category_models.dart';
import 'package:venvo_core/features/products/domain/product_models.dart';

import '../helpers/master_data_fixtures.dart';

void main() {
  late MasterDataFixture fixture;

  setUp(() async {
    fixture = await MasterDataFixture.create();
  });

  tearDown(() => fixture.dispose());

  Future<int> addCategory(String name, {int? parentId}) {
    return fixture.categories.create(
      fixture.admin,
      CategoryDraft(name: name, parentId: parentId),
    );
  }

  group('creating', () {
    test('creates a category and reports it', () async {
      final id = await addCategory('Chargers');
      final list = await fixture.categories.watchCategories().first;

      expect(list.length, 1);
      expect(list.single.id, id);
      expect(list.single.name, 'Chargers');
      expect(list.single.status, EntityStatus.active);
      expect(list.single.activeProductCount, 0);
      expect(list.single.parentName, isNull);
    });

    test('trims the name', () async {
      await addCategory('  Cables  ');
      final list = await fixture.categories.watchCategories().first;
      expect(list.single.name, 'Cables');
    });

    test('rejects an empty name', () async {
      await expectLater(addCategory('   '), throwsA(isA<ValidationFailure>()));
    });

    test('refuses a duplicate name regardless of case', () async {
      await addCategory('Chargers');
      await expectLater(
        addCategory('chargers'),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'category.name_unique',
          ),
        ),
      );
    });

    test('nests under a parent and reports the parent name', () async {
      final parentId = await addCategory('Cables');
      await addCategory('Type-C', parentId: parentId);

      final list = await fixture.categories.watchCategories().first;
      final child = list.firstWhere((c) => c.name == 'Type-C');
      expect(child.parentId, parentId);
      expect(child.parentName, 'Cables');
      expect(child.qualifiedName, 'Cables / Type-C');
    });

    test('refuses a parent that does not exist', () async {
      await expectLater(
        addCategory('Orphan', parentId: 9999),
        throwsA(isA<NotFoundFailure>()),
      );
    });

    test('records an audit entry', () async {
      await addCategory('Chargers');
      final entries = await fixture.auditEntries();
      final created = entries.firstWhere(
        (entry) =>
            entry.entityKind == EntityKind.category &&
            entry.action == AuditAction.create,
      );
      expect(created.summary, contains('Chargers'));
      expect(created.userId, fixture.admin.id);
    });

    test('requires the manage-products permission', () async {
      final viewer = await fixture.createViewer();
      await expectLater(
        fixture.categories.create(
          viewer,
          const CategoryDraft(name: 'Not allowed'),
        ),
        throwsA(isA<PermissionFailure>()),
      );
      expect(await fixture.categories.watchCategories().first, isEmpty);
    });
  });

  group('updating', () {
    test('renames a category', () async {
      final id = await addCategory('Chargers');
      await fixture.categories.update(
        fixture.admin,
        CategoryDraft(id: id, name: 'Charging'),
      );

      final list = await fixture.categories.watchCategories().first;
      expect(list.single.name, 'Charging');
    });

    test('allows keeping its own name', () async {
      final id = await addCategory('Chargers');
      await fixture.categories.update(
        fixture.admin,
        CategoryDraft(id: id, name: 'Chargers', sortOrder: 5),
      );
      final list = await fixture.categories.watchCategories().first;
      expect(list.single.sortOrder, 5);
    });

    test('refuses taking another category name', () async {
      await addCategory('Chargers');
      final cablesId = await addCategory('Cables');

      await expectLater(
        fixture.categories.update(
          fixture.admin,
          CategoryDraft(id: cablesId, name: 'Chargers'),
        ),
        throwsA(isA<BusinessRuleFailure>()),
      );
    });

    test('refuses making a category its own parent', () async {
      final id = await addCategory('Chargers');
      await expectLater(
        fixture.categories.update(
          fixture.admin,
          CategoryDraft(id: id, name: 'Chargers', parentId: id),
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'category.no_self_parent',
          ),
        ),
      );
    });

    test('refuses a cycle through a descendant', () async {
      // Cables -> Type-C. Making Cables a child of Type-C would close a loop.
      final cablesId = await addCategory('Cables');
      final typeCId = await addCategory('Type-C', parentId: cablesId);

      await expectLater(
        fixture.categories.update(
          fixture.admin,
          CategoryDraft(id: cablesId, name: 'Cables', parentId: typeCId),
        ),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'category.no_cycle',
          ),
        ),
      );
    });
  });

  group('archiving', () {
    test('archives an unused category', () async {
      final id = await addCategory('Chargers');
      await fixture.categories.archive(fixture.admin, id);

      // Hidden by default...
      expect(await fixture.categories.watchCategories().first, isEmpty);
      // ...but still there, because nothing is deleted.
      final all = await fixture.categories
          .watchCategories(includeArchived: true)
          .first;
      expect(all.single.status, EntityStatus.archived);
      expect(all.single.isArchived, isTrue);
    });

    test('refuses to archive a category with active products', () async {
      final categoryId = await addCategory('Chargers');
      await fixture.products.create(
        fixture.admin,
        ProductDraft(
          sku: 'CHG-25W',
          name: '25W Charger',
          categoryId: categoryId,
        ),
      );

      await expectLater(
        fixture.categories.archive(fixture.admin, categoryId),
        throwsA(
          isA<BusinessRuleFailure>()
              .having(
                (failure) => failure.rule,
                'rule',
                'category.no_active_products',
              )
              .having(
                (failure) => failure.message,
                'message',
                contains('1 active product'),
              ),
        ),
      );
    });

    test('allows archiving once its products are inactive', () async {
      final categoryId = await addCategory('Chargers');
      final productId = await fixture.products.create(
        fixture.admin,
        ProductDraft(
          sku: 'CHG-25W',
          name: '25W Charger',
          categoryId: categoryId,
        ),
      );
      await fixture.products.update(
        fixture.admin,
        ProductDraft(
          id: productId,
          sku: 'CHG-25W',
          name: '25W Charger',
          categoryId: categoryId,
          status: EntityStatus.inactive,
        ),
      );

      await fixture.categories.archive(fixture.admin, categoryId);
      final all = await fixture.categories
          .watchCategories(includeArchived: true)
          .first;
      expect(all.single.status, EntityStatus.archived);
    });

    test('refuses to archive a category with active children', () async {
      final cablesId = await addCategory('Cables');
      await addCategory('Type-C', parentId: cablesId);

      await expectLater(
        fixture.categories.archive(fixture.admin, cablesId),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'category.no_active_children',
          ),
        ),
      );
    });

    test('restores an archived category', () async {
      final id = await addCategory('Chargers');
      await fixture.categories.archive(fixture.admin, id);
      await fixture.categories.restore(fixture.admin, id);

      final list = await fixture.categories.watchCategories().first;
      expect(list.single.status, EntityStatus.active);
    });
  });

  group('selectable categories', () {
    test('offers only active categories', () async {
      await addCategory('Chargers');
      final cablesId = await addCategory('Cables');
      await fixture.categories.archive(fixture.admin, cablesId);

      final selectable = await fixture.categories.selectableCategories();
      expect(selectable.map((c) => c.name), ['Chargers']);
    });

    test('resolves parent names for the picker', () async {
      final cablesId = await addCategory('Cables');
      await addCategory('Type-C', parentId: cablesId);

      final selectable = await fixture.categories.selectableCategories();
      final child = selectable.firstWhere((c) => c.name == 'Type-C');
      expect(child.qualifiedName, 'Cables / Type-C');
    });
  });

  group('product counts', () {
    test('counts active and total products separately', () async {
      final categoryId = await addCategory('Chargers');
      await fixture.products.create(
        fixture.admin,
        ProductDraft(
          sku: 'CHG-25W',
          name: '25W Charger',
          categoryId: categoryId,
        ),
      );
      final secondId = await fixture.products.create(
        fixture.admin,
        ProductDraft(
          sku: 'CHG-66W',
          name: '66W Charger',
          categoryId: categoryId,
        ),
      );
      await fixture.products.update(
        fixture.admin,
        ProductDraft(
          id: secondId,
          sku: 'CHG-66W',
          name: '66W Charger',
          categoryId: categoryId,
          status: EntityStatus.inactive,
        ),
      );

      final list = await fixture.categories.watchCategories().first;
      expect(list.single.activeProductCount, 1);
      expect(list.single.totalProductCount, 2);
    });
  });
}
