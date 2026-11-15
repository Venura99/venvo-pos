import 'package:drift/drift.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/permissions.dart';
import '../../../core/database/app_database.dart';
import '../../../core/enums/app_enums.dart';
import '../../../core/errors/guards.dart';
import '../../../core/services/audit_service.dart';
import '../../../core/services/clock.dart';
import '../../../core/services/sequence_service.dart';
import '../../../core/utils/money.dart';
import '../../authentication/domain/authenticated_user.dart';
import '../domain/location_models.dart';

/// Reads and maintains inventory locations.
///
/// Locations are not free-form: exactly one exists per agent and per shop, and
/// it is created in the **same transaction** as the party itself. That is why
/// [createForAgent] and [createForShop] take no transaction of their own - they
/// are designed to be called from inside the agent or shop repository's
/// transaction, so a party can never exist without somewhere to put its stock.
class LocationRepository {
  const LocationRepository({
    required AppDatabase database,
    required Clock clock,
    required AuditService audit,
    required SequenceService sequences,
  }) : _db = database,
       _clock = clock,
       _audit = audit,
       _sequences = sequences;

  final AppDatabase _db;
  final Clock _clock;
  final AuditService _audit;
  final SequenceService _sequences;

  /// Live list of locations with what each one holds.
  Stream<List<LocationListItem>> watchLocations({
    bool includeVirtual = false,
    bool includeInactive = true,
  }) {
    final virtualKinds = [
      LocationKind.supplier,
      LocationKind.customer,
      LocationKind.adjustment,
      LocationKind.inTransit,
    ].map((kind) => "'${kind.name}'").join(', ');

    final query = _db.customSelect(
      '''
      SELECT
        l.id,
        l.code,
        l.name,
        l.kind,
        l.is_active,
        l.agent_id,
        l.shop_id,
        COALESCE(a.name, s.name) AS owner_name,
        COALESCE(stock.product_lines, 0) AS product_lines,
        COALESCE(stock.total_units, 0) AS total_units,
        COALESCE(stock.stock_value, 0) AS stock_value
      FROM inventory_locations l
      LEFT JOIN agents a ON a.id = l.agent_id
      LEFT JOIN shops s ON s.id = l.shop_id
      LEFT JOIN (
        SELECT
          location_id,
          COUNT(*) AS product_lines,
          SUM(quantity) AS total_units,
          SUM(quantity * average_cost_cents) AS stock_value
        FROM stock_balances
        WHERE quantity <> 0
        GROUP BY location_id
      ) stock ON stock.location_id = l.id
      WHERE (? = 1 OR l.kind NOT IN ($virtualKinds))
        AND (? = 1 OR l.is_active = 1)
      ORDER BY
        CASE l.kind
          WHEN 'warehouse' THEN 0
          WHEN 'agent' THEN 1
          WHEN 'shop' THEN 2
          WHEN 'damaged' THEN 3
          ELSE 4
        END,
        l.name
      ''',
      variables: [
        Variable<int>(includeVirtual ? 1 : 0),
        Variable<int>(includeInactive ? 1 : 0),
      ],
      readsFrom: {
        _db.inventoryLocations,
        _db.agents,
        _db.shops,
        _db.stockBalances,
      },
    );

    return query.watch().map(
      (rows) => rows.map(_mapRow).toList(growable: false),
    );
  }

  /// The main warehouse, which the seed guarantees exists.
  Future<InventoryLocation> mainWarehouse() async {
    final row =
        await (_db.select(_db.inventoryLocations)
              ..where((l) => l.code.equals(AppConstants.mainWarehouseCode)))
            .getSingleOrNull();
    return requireFound(
      row,
      'The main warehouse is missing from this database.',
    );
  }

  /// A well-known location by its seeded code.
  Future<InventoryLocation> byCode(String code) async {
    final row = await (_db.select(
      _db.inventoryLocations,
    )..where((l) => l.code.equals(code))).getSingleOrNull();
    return requireFound(row, 'The location "$code" is missing.');
  }

  Future<InventoryLocation?> forAgent(int agentId) {
    return (_db.select(
      _db.inventoryLocations,
    )..where((l) => l.agentId.equals(agentId))).getSingleOrNull();
  }

  Future<InventoryLocation?> forShop(int shopId) {
    return (_db.select(
      _db.inventoryLocations,
    )..where((l) => l.shopId.equals(shopId))).getSingleOrNull();
  }

  /// Creates the stock location that belongs to an agent.
  ///
  /// Call this inside the transaction that inserts the agent. Returns the
  /// existing location if one is already present, so it is safe to retry.
  Future<int> createForAgent({
    required int agentId,
    required String agentCode,
    required String agentName,
  }) async {
    final existing = await forAgent(agentId);
    if (existing != null) return existing.id;

    return _db
        .into(_db.inventoryLocations)
        .insert(
          InventoryLocationsCompanion.insert(
            code: 'LOC-$agentCode',
            name: '$agentName (Agent)',
            kind: LocationKind.agent,
            agentId: Value(agentId),
            createdAt: _clock.nowUtc(),
          ),
        );
  }

  /// Creates the stock location that belongs to a shop. Call inside the
  /// shop's own transaction.
  Future<int> createForShop({
    required int shopId,
    required String shopCode,
    required String shopName,
  }) async {
    final existing = await forShop(shopId);
    if (existing != null) return existing.id;

    return _db
        .into(_db.inventoryLocations)
        .insert(
          InventoryLocationsCompanion.insert(
            code: 'LOC-$shopCode',
            name: '$shopName (Shop)',
            kind: LocationKind.shop,
            shopId: Value(shopId),
            createdAt: _clock.nowUtc(),
          ),
        );
  }

  /// Keeps a party-owned location's name in step with its party. Call inside
  /// the party's update transaction.
  Future<void> renameForParty({
    required int locationId,
    required String name,
  }) async {
    await (_db.update(_db.inventoryLocations)
          ..where((l) => l.id.equals(locationId)))
        .write(InventoryLocationsCompanion(name: Value(name)));
  }

  /// Follows a party's active/inactive state. An inactive location keeps its
  /// stock; it simply stops being offered on new documents.
  Future<void> setActiveForParty({
    required int locationId,
    required bool isActive,
  }) async {
    await (_db.update(_db.inventoryLocations)
          ..where((l) => l.id.equals(locationId)))
        .write(InventoryLocationsCompanion(isActive: Value(isActive)));
  }

  /// Creates an additional warehouse. The schema has always supported several;
  /// this is what makes a second one reachable without a migration.
  Future<int> createWarehouse(
    AuthenticatedUser actor, {
    required String name,
  }) async {
    actor.require(Permissions.stockAdjust, action: 'add warehouses');
    final cleanName = requireText(name, 'Warehouse name', maxLength: 180);

    return _db.transaction(() async {
      final clash =
          await (_db.select(_db.inventoryLocations)
                ..where((l) => l.name.lower().equals(cleanName.toLowerCase())))
              .getSingleOrNull();
      requireRule(
        clash == null,
        'A location called "$cleanName" already exists.',
        rule: 'location.name_unique',
      );

      final code = await _sequences.nextNumber(
        SequenceKeys.warehouseCode,
        resetsYearly: false,
      );

      final id = await _db
          .into(_db.inventoryLocations)
          .insert(
            InventoryLocationsCompanion.insert(
              code: code,
              name: cleanName,
              kind: LocationKind.warehouse,
              createdAt: _clock.nowUtc(),
            ),
          );

      await _audit.record(
        action: AuditAction.create,
        summary: 'Created the warehouse "$cleanName" ($code).',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.inventoryLocation,
        entityId: id,
      );
      return id;
    });
  }

  Future<void> renameWarehouse(
    AuthenticatedUser actor, {
    required int locationId,
    required String name,
  }) async {
    actor.require(Permissions.stockAdjust, action: 'rename warehouses');
    final cleanName = requireText(name, 'Warehouse name', maxLength: 180);

    await _db.transaction(() async {
      final existing = requireFound(
        await (_db.select(
          _db.inventoryLocations,
        )..where((l) => l.id.equals(locationId))).getSingleOrNull(),
        'That location no longer exists.',
      );
      requireRule(
        existing.kind == LocationKind.warehouse,
        'Only warehouses can be renamed here. Agent and shop locations '
        'follow the name of the agent or shop they belong to.',
        rule: 'location.rename_warehouse_only',
      );

      await (_db.update(_db.inventoryLocations)
            ..where((l) => l.id.equals(locationId)))
          .write(InventoryLocationsCompanion(name: Value(cleanName)));

      await _audit.recordUpdate(
        entityKind: EntityKind.inventoryLocation,
        entityId: locationId,
        summary: 'Renamed the warehouse "${existing.name}" to "$cleanName".',
        userId: actor.id,
        username: actor.username,
        before: {'name': existing.name},
        after: {'name': cleanName},
      );
    });
  }

  /// Deactivates a warehouse. Refused while it still holds stock, which would
  /// otherwise strand inventory in a location nobody can select.
  Future<void> setWarehouseActive(
    AuthenticatedUser actor, {
    required int locationId,
    required bool isActive,
  }) async {
    actor.require(Permissions.stockAdjust, action: 'deactivate warehouses');

    await _db.transaction(() async {
      final existing = requireFound(
        await (_db.select(
          _db.inventoryLocations,
        )..where((l) => l.id.equals(locationId))).getSingleOrNull(),
        'That location no longer exists.',
      );
      requireRule(
        existing.kind == LocationKind.warehouse,
        'Only warehouses can be deactivated here.',
        rule: 'location.deactivate_warehouse_only',
      );
      requireRule(
        existing.code != AppConstants.mainWarehouseCode,
        'The main warehouse cannot be deactivated.',
        rule: 'location.keep_main_warehouse',
      );

      if (!isActive) {
        final units = await _totalUnitsAt(locationId);
        requireRule(
          units == 0,
          '"${existing.name}" still holds $units unit(s). Move the stock out '
          'before deactivating it.',
          rule: 'location.no_stock_when_deactivating',
        );
      }

      await (_db.update(_db.inventoryLocations)
            ..where((l) => l.id.equals(locationId)))
          .write(InventoryLocationsCompanion(isActive: Value(isActive)));

      await _audit.record(
        action: isActive ? AuditAction.update : AuditAction.archive,
        summary: isActive
            ? 'Reactivated the warehouse "${existing.name}".'
            : 'Deactivated the warehouse "${existing.name}".',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.inventoryLocation,
        entityId: locationId,
      );
    });
  }

  Future<int> _totalUnitsAt(int locationId) async {
    final row = await _db
        .customSelect(
          'SELECT COALESCE(SUM(quantity), 0) AS units FROM stock_balances '
          'WHERE location_id = ?',
          variables: [Variable<int>(locationId)],
          readsFrom: {_db.stockBalances},
        )
        .getSingle();
    return row.read<int>('units');
  }

  static LocationListItem _mapRow(QueryRow row) => LocationListItem(
    id: row.read<int>('id'),
    code: row.read<String>('code'),
    name: row.read<String>('name'),
    kind: LocationKind.values.byName(row.read<String>('kind')),
    isActive: row.read<bool>('is_active'),
    agentId: row.readNullable<int>('agent_id'),
    shopId: row.readNullable<int>('shop_id'),
    ownerName: row.readNullable<String>('owner_name'),
    productLines: row.read<int>('product_lines'),
    totalUnits: row.read<int>('total_units'),
    stockValueAtCost: Money(row.read<int>('stock_value')),
  );
}
