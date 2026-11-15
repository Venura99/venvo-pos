import 'package:drift/drift.dart';

import '../../../core/constants/permissions.dart';
import '../../../core/database/app_database.dart';
import '../../../core/enums/app_enums.dart';
import '../../../core/errors/failures.dart';
import '../../../core/errors/guards.dart';
import '../../../core/services/audit_service.dart';
import '../../../core/services/clock.dart';
import '../../../core/utils/money.dart';
import '../../authentication/domain/authenticated_user.dart';
import '../domain/product_models.dart';

/// Reads and maintains the product catalogue.
///
/// The list query aggregates stock per location kind in SQL, so the catalogue
/// screen shows warehouse, agent and shop quantities without issuing a query
/// per row.
///
/// Rules enforced here:
///
/// * SKU is unique, compared case-insensitively, because `CHG-25W` and
///   `chg-25w` being different products is always a data-entry mistake.
/// * A barcode, when given, is unique. Many products may have none.
/// * `unitsPerPack` is at least 1, since it is a divisor at data-entry time.
/// * A product holding stock in a real location cannot be archived - that
///   would hide inventory the business still owns.
class ProductRepository {
  const ProductRepository({
    required AppDatabase database,
    required Clock clock,
    required AuditService audit,
  }) : _db = database,
       _clock = clock,
       _audit = audit;

  final AppDatabase _db;
  final Clock _clock;
  final AuditService _audit;

  /// Live, filtered catalogue.
  Stream<List<ProductListItem>> watchProducts(ProductFilter filter) {
    final search = filter.search.trim();
    final pattern = '%${search.toLowerCase()}%';

    // Ordering is built from a closed set of keys, never from user input.
    final direction = filter.sortAscending ? 'ASC' : 'DESC';
    final orderBy = switch (filter.sortKey) {
      ProductSortKey.name => 'p.name $direction',
      ProductSortKey.sku => 'p.sku $direction',
      ProductSortKey.category => 'c.name $direction, p.name ASC',
      ProductSortKey.costPrice => 'p.cost_price_cents $direction',
      ProductSortKey.wholesalePrice => 'p.wholesale_price_cents $direction',
      ProductSortKey.retailPrice => 'p.retail_price_cents $direction',
      ProductSortKey.stock => 'sellable_quantity $direction, p.name ASC',
    };

    final query = _db.customSelect(
      '''
      SELECT
        p.*,
        c.name AS category_name,
        COALESCE(stock.warehouse_quantity, 0) AS warehouse_quantity,
        COALESCE(stock.agent_quantity, 0) AS agent_quantity,
        COALESCE(stock.shop_quantity, 0) AS shop_quantity,
        COALESCE(stock.damaged_quantity, 0) AS damaged_quantity,
        COALESCE(stock.warehouse_quantity, 0)
          + COALESCE(stock.agent_quantity, 0)
          + COALESCE(stock.shop_quantity, 0) AS sellable_quantity
      FROM products p
      JOIN categories c ON c.id = p.category_id
      LEFT JOIN (
        SELECT
          sb.product_id,
          SUM(CASE WHEN l.kind = ? THEN sb.quantity ELSE 0 END)
            AS warehouse_quantity,
          SUM(CASE WHEN l.kind = ? THEN sb.quantity ELSE 0 END)
            AS agent_quantity,
          SUM(CASE WHEN l.kind = ? THEN sb.quantity ELSE 0 END)
            AS shop_quantity,
          SUM(CASE WHEN l.kind = ? THEN sb.quantity ELSE 0 END)
            AS damaged_quantity
        FROM stock_balances sb
        JOIN inventory_locations l ON l.id = sb.location_id
        GROUP BY sb.product_id
      ) stock ON stock.product_id = p.id
      WHERE
        (? = 1 OR p.status <> ?)
        AND (? = 1 OR p.status <> ?)
        AND (? = '' OR LOWER(p.name) LIKE ? OR LOWER(p.sku) LIKE ?
             OR LOWER(COALESCE(p.barcode, '')) LIKE ?
             OR LOWER(COALESCE(p.brand, '')) LIKE ?)
        AND (? IS NULL OR p.category_id = ?)
        AND (? IS NULL OR p.brand = ?)
        AND (? = 0 OR (p.reorder_level > 0
             AND COALESCE(stock.warehouse_quantity, 0)
               + COALESCE(stock.agent_quantity, 0)
               + COALESCE(stock.shop_quantity, 0) <= p.reorder_level))
      ORDER BY $orderBy
      ''',
      variables: [
        Variable<String>(LocationKind.warehouse.name),
        Variable<String>(LocationKind.agent.name),
        Variable<String>(LocationKind.shop.name),
        Variable<String>(LocationKind.damaged.name),
        Variable<int>(filter.includeArchived ? 1 : 0),
        Variable<String>(EntityStatus.archived.name),
        Variable<int>(filter.includeInactive ? 1 : 0),
        Variable<String>(EntityStatus.inactive.name),
        Variable<String>(search.toLowerCase()),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<int>(filter.categoryId),
        Variable<int>(filter.categoryId),
        Variable<String>(filter.brand),
        Variable<String>(filter.brand),
        Variable<int>(filter.lowStockOnly ? 1 : 0),
      ],
      readsFrom: {
        _db.products,
        _db.categories,
        _db.stockBalances,
        _db.inventoryLocations,
      },
    );

    return query.watch().map(
      (rows) => rows.map(_mapRow).toList(growable: false),
    );
  }

  /// Distinct brands currently in use, for the filter dropdown.
  Stream<List<String>> watchBrands() {
    return _db
        .customSelect(
          'SELECT DISTINCT brand FROM products '
          'WHERE brand IS NOT NULL AND TRIM(brand) <> ? ORDER BY brand',
          variables: const [Variable<String>('')],
          readsFrom: {_db.products},
        )
        .watch()
        .map(
          (rows) => rows
              .map((row) => row.read<String>('brand'))
              .toList(growable: false),
        );
  }

  /// Where a product's stock currently sits. Used to explain why a product
  /// cannot be archived, and by the detail panel.
  Future<List<ProductStockAtLocation>> stockByLocation(int productId) async {
    final rows = await _db
        .customSelect(
          '''
      SELECT l.name AS location_name, l.kind AS location_kind, sb.quantity
      FROM stock_balances sb
      JOIN inventory_locations l ON l.id = sb.location_id
      WHERE sb.product_id = ? AND sb.quantity <> 0
      ORDER BY l.kind, l.name
      ''',
          variables: [Variable<int>(productId)],
          readsFrom: {_db.stockBalances, _db.inventoryLocations},
        )
        .get();

    return rows
        .map(
          (row) => ProductStockAtLocation(
            locationName: row.read<String>('location_name'),
            locationKind: LocationKind.values.byName(
              row.read<String>('location_kind'),
            ),
            quantity: row.read<int>('quantity'),
          ),
        )
        .toList(growable: false);
  }

  Future<int> create(AuthenticatedUser actor, ProductDraft draft) async {
    actor.require(Permissions.productsManage, action: 'add products');
    final sku = _normaliseSku(draft.sku);
    final name = requireText(draft.name, 'Product name', maxLength: 180);
    final barcode = _cleanOptional(draft.barcode);
    _validatePricesAndPack(draft);

    return _db.transaction(() async {
      await _assertSkuAvailable(sku, excludingId: null);
      if (barcode != null) {
        await _assertBarcodeAvailable(barcode, excludingId: null);
      }
      await _assertCategoryUsable(draft.categoryId);

      final now = _clock.nowUtc();
      final id = await _db
          .into(_db.products)
          .insert(
            ProductsCompanion.insert(
              sku: sku,
              name: name,
              barcode: Value(barcode),
              categoryId: draft.categoryId,
              brand: Value(_cleanOptional(draft.brand)),
              description: Value(_cleanOptional(draft.description)),
              unitOfMeasure: Value(draft.unitOfMeasure),
              unitsPerPack: Value(draft.unitsPerPack),
              costPriceCents: Value(draft.costPrice.cents),
              wholesalePriceCents: Value(draft.wholesalePrice.cents),
              retailPriceCents: Value(draft.retailPrice.cents),
              reorderLevel: Value(draft.reorderLevel),
              status: Value(draft.status),
              notes: Value(_cleanOptional(draft.notes)),
              createdAt: now,
              updatedAt: now,
            ),
          );

      await _audit.record(
        action: AuditAction.create,
        summary: 'Created the product "$name" ($sku).',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.product,
        entityId: id,
        after: {
          'sku': sku,
          'name': name,
          'costPriceCents': draft.costPrice.cents,
          'wholesalePriceCents': draft.wholesalePrice.cents,
          'retailPriceCents': draft.retailPrice.cents,
        },
      );
      return id;
    });
  }

  Future<void> update(AuthenticatedUser actor, ProductDraft draft) async {
    actor.require(Permissions.productsManage, action: 'edit products');
    final id = requireFound(draft.id, 'This product has not been saved yet.');
    final sku = _normaliseSku(draft.sku);
    final name = requireText(draft.name, 'Product name', maxLength: 180);
    final barcode = _cleanOptional(draft.barcode);
    _validatePricesAndPack(draft);

    await _db.transaction(() async {
      final existing = requireFound(
        await (_db.select(
          _db.products,
        )..where((p) => p.id.equals(id))).getSingleOrNull(),
        'That product no longer exists.',
      );

      await _assertSkuAvailable(sku, excludingId: id);
      if (barcode != null) {
        await _assertBarcodeAvailable(barcode, excludingId: id);
      }
      if (draft.categoryId != existing.categoryId) {
        await _assertCategoryUsable(draft.categoryId);
      }
      if (draft.status == EntityStatus.archived &&
          existing.status != EntityStatus.archived) {
        await _assertNoStockOnHand(id, name);
      }

      await (_db.update(_db.products)..where((p) => p.id.equals(id))).write(
        ProductsCompanion(
          sku: Value(sku),
          name: Value(name),
          barcode: Value(barcode),
          categoryId: Value(draft.categoryId),
          brand: Value(_cleanOptional(draft.brand)),
          description: Value(_cleanOptional(draft.description)),
          unitOfMeasure: Value(draft.unitOfMeasure),
          unitsPerPack: Value(draft.unitsPerPack),
          costPriceCents: Value(draft.costPrice.cents),
          wholesalePriceCents: Value(draft.wholesalePrice.cents),
          retailPriceCents: Value(draft.retailPrice.cents),
          reorderLevel: Value(draft.reorderLevel),
          status: Value(draft.status),
          notes: Value(_cleanOptional(draft.notes)),
          updatedAt: Value(_clock.nowUtc()),
        ),
      );

      // Prices are the figures most worth having a trail of: a changed
      // wholesale price changes what every future invoice charges.
      await _audit.recordUpdate(
        entityKind: EntityKind.product,
        entityId: id,
        summary: 'Updated the product "$name" ($sku).',
        userId: actor.id,
        username: actor.username,
        before: {
          'sku': existing.sku,
          'name': existing.name,
          'barcode': existing.barcode,
          'categoryId': existing.categoryId,
          'brand': existing.brand,
          'unitOfMeasure': existing.unitOfMeasure.name,
          'unitsPerPack': existing.unitsPerPack,
          'costPriceCents': existing.costPriceCents,
          'wholesalePriceCents': existing.wholesalePriceCents,
          'retailPriceCents': existing.retailPriceCents,
          'reorderLevel': existing.reorderLevel,
          'status': existing.status.name,
        },
        after: {
          'sku': sku,
          'name': name,
          'barcode': barcode,
          'categoryId': draft.categoryId,
          'brand': _cleanOptional(draft.brand),
          'unitOfMeasure': draft.unitOfMeasure.name,
          'unitsPerPack': draft.unitsPerPack,
          'costPriceCents': draft.costPrice.cents,
          'wholesalePriceCents': draft.wholesalePrice.cents,
          'retailPriceCents': draft.retailPrice.cents,
          'reorderLevel': draft.reorderLevel,
          'status': draft.status.name,
        },
      );
    });
  }

  Future<void> archive(AuthenticatedUser actor, int productId) async {
    actor.require(Permissions.productsManage, action: 'archive products');

    await _db.transaction(() async {
      final existing = requireFound(
        await (_db.select(
          _db.products,
        )..where((p) => p.id.equals(productId))).getSingleOrNull(),
        'That product no longer exists.',
      );
      await _assertNoStockOnHand(productId, existing.name);

      await (_db.update(
        _db.products,
      )..where((p) => p.id.equals(productId))).write(
        ProductsCompanion(
          status: const Value(EntityStatus.archived),
          updatedAt: Value(_clock.nowUtc()),
        ),
      );

      await _audit.record(
        action: AuditAction.archive,
        summary: 'Archived the product "${existing.name}" (${existing.sku}).',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.product,
        entityId: productId,
      );
    });
  }

  Future<void> restore(AuthenticatedUser actor, int productId) async {
    actor.require(Permissions.productsManage, action: 'restore products');

    final existing = requireFound(
      await (_db.select(
        _db.products,
      )..where((p) => p.id.equals(productId))).getSingleOrNull(),
      'That product no longer exists.',
    );

    await (_db.update(
      _db.products,
    )..where((p) => p.id.equals(productId))).write(
      ProductsCompanion(
        status: const Value(EntityStatus.active),
        updatedAt: Value(_clock.nowUtc()),
      ),
    );

    await _audit.record(
      action: AuditAction.update,
      summary: 'Restored the product "${existing.name}" (${existing.sku}).',
      userId: actor.id,
      username: actor.username,
      entityKind: EntityKind.product,
      entityId: productId,
    );
  }

  /// Changes a price on several products at once, recording one audit row per
  /// product so the trail stays per-product.
  Future<int> bulkUpdateCategory({
    required AuthenticatedUser actor,
    required List<int> productIds,
    required int categoryId,
  }) async {
    actor.require(Permissions.productsManage, action: 'edit products');
    require(productIds.isNotEmpty, 'Select at least one product.');

    return _db.transaction(() async {
      await _assertCategoryUsable(categoryId);
      final category = await (_db.select(
        _db.categories,
      )..where((c) => c.id.equals(categoryId))).getSingle();

      var changed = 0;
      for (final productId in productIds) {
        final product = await (_db.select(
          _db.products,
        )..where((p) => p.id.equals(productId))).getSingleOrNull();
        if (product == null || product.categoryId == categoryId) continue;

        await (_db.update(
          _db.products,
        )..where((p) => p.id.equals(productId))).write(
          ProductsCompanion(
            categoryId: Value(categoryId),
            updatedAt: Value(_clock.nowUtc()),
          ),
        );
        await _audit.recordUpdate(
          entityKind: EntityKind.product,
          entityId: productId,
          summary:
              'Moved "${product.name}" to the category '
              '"${category.name}".',
          userId: actor.id,
          username: actor.username,
          before: {'categoryId': product.categoryId},
          after: {'categoryId': categoryId},
        );
        changed++;
      }
      return changed;
    });
  }

  // --- Rules --------------------------------------------------------------

  void _validatePricesAndPack(ProductDraft draft) {
    require(
      draft.unitsPerPack >= 1,
      'Units per pack must be at least 1.',
      field: 'unitsPerPack',
    );
    require(
      draft.reorderLevel >= 0,
      'The reorder level cannot be negative.',
      field: 'reorderLevel',
    );
    for (final entry in <String, Money>{
      'Cost price': draft.costPrice,
      'Wholesale price': draft.wholesalePrice,
      'Selling price': draft.retailPrice,
    }.entries) {
      require(
        !entry.value.isNegative,
        '${entry.key} cannot be negative.',
        field: entry.key,
      );
    }
  }

  Future<void> _assertSkuAvailable(String sku, {int? excludingId}) async {
    final query = _db.select(_db.products)
      ..where((p) => p.sku.lower().equals(sku.toLowerCase()));
    if (excludingId != null) {
      query.where((p) => p.id.isNotValue(excludingId));
    }
    final clash = await query.getSingleOrNull();
    requireRule(
      clash == null,
      'The SKU "$sku" is already used by "${clash?.name}".',
      rule: 'product.sku_unique',
    );
  }

  Future<void> _assertBarcodeAvailable(
    String barcode, {
    int? excludingId,
  }) async {
    final query = _db.select(_db.products)
      ..where((p) => p.barcode.equals(barcode));
    if (excludingId != null) {
      query.where((p) => p.id.isNotValue(excludingId));
    }
    final clash = await query.getSingleOrNull();
    requireRule(
      clash == null,
      'The barcode "$barcode" is already used by "${clash?.name}".',
      rule: 'product.barcode_unique',
    );
  }

  Future<void> _assertCategoryUsable(int categoryId) async {
    final category = await (_db.select(
      _db.categories,
    )..where((c) => c.id.equals(categoryId))).getSingleOrNull();
    requireFound(category, 'The selected category no longer exists.');
    requireRule(
      category!.status == EntityStatus.active,
      'The category "${category.name}" is not active. Choose another one.',
      rule: 'product.category_active',
    );
  }

  /// Refuses to archive a product that still holds stock anywhere real.
  /// Archiving it would hide inventory the business owns and still has to
  /// account for.
  Future<void> _assertNoStockOnHand(int productId, String name) async {
    final holdings = await stockByLocation(productId);
    final real = holdings
        .where((holding) => holding.locationKind.isStockHolding)
        .toList();
    if (real.isEmpty) return;

    final summary = real
        .map((holding) => '${holding.locationName}: ${holding.quantity}')
        .join(', ');
    throw BusinessRuleFailure(
      '"$name" still has stock on hand, so it cannot be archived. '
      'Transfer or write off the remaining stock first.',
      details: 'Stock held at $summary',
      rule: 'product.no_stock_when_archiving',
    );
  }

  static ProductListItem _mapRow(QueryRow row) => ProductListItem(
    id: row.read<int>('id'),
    sku: row.read<String>('sku'),
    name: row.read<String>('name'),
    barcode: row.readNullable<String>('barcode'),
    categoryId: row.read<int>('category_id'),
    categoryName: row.read<String>('category_name'),
    brand: row.readNullable<String>('brand'),
    description: row.readNullable<String>('description'),
    unitOfMeasure: UnitOfMeasure.values.byName(
      row.read<String>('unit_of_measure'),
    ),
    unitsPerPack: row.read<int>('units_per_pack'),
    costPrice: Money(row.read<int>('cost_price_cents')),
    wholesalePrice: Money(row.read<int>('wholesale_price_cents')),
    retailPrice: Money(row.read<int>('retail_price_cents')),
    reorderLevel: row.read<int>('reorder_level'),
    status: EntityStatus.values.byName(row.read<String>('status')),
    notes: row.readNullable<String>('notes'),
    warehouseQuantity: row.read<int>('warehouse_quantity'),
    agentQuantity: row.read<int>('agent_quantity'),
    shopQuantity: row.read<int>('shop_quantity'),
    damagedQuantity: row.read<int>('damaged_quantity'),
  );

  static String _normaliseSku(String value) {
    final sku = requireText(value, 'SKU', maxLength: 40).toUpperCase();
    require(
      RegExp(r'^[A-Z0-9][A-Z0-9._\-/]*$').hasMatch(sku),
      'A SKU may contain letters, numbers, dots, hyphens, underscores and '
      'slashes, and must start with a letter or number.',
      field: 'sku',
    );
    return sku;
  }

  static String? _cleanOptional(String? value) {
    final text = (value ?? '').trim();
    return text.isEmpty ? null : text;
  }
}
