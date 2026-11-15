import 'package:drift/drift.dart';

import '../../enums/app_enums.dart';

/// Master data: categories, products, parties and inventory locations.
///
/// Monetary columns are suffixed `Cents` and stored as SQLite INTEGER minor
/// currency units. Quantities are whole base units (see `Products.unitsPerPack`
/// for pack handling). No master record is ever physically deleted - it is
/// moved to [EntityStatus.archived] so historical documents keep resolving.

@DataClassName('Category')
@TableIndex(name: 'idx_categories_status', columns: {#status})
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get description => text().nullable().withLength(max: 500)();
  IntColumn get parentId => integer().nullable().references(
    Categories,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get status => textEnum<EntityStatus>().withDefault(
    Constant(EntityStatus.active.name),
  )();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {name},
  ];
}

@DataClassName('Product')
@TableIndex(name: 'idx_products_category', columns: {#categoryId})
@TableIndex(name: 'idx_products_status', columns: {#status})
@TableIndex(name: 'idx_products_name', columns: {#name})
class Products extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Human-facing stock keeping unit, unique across the catalogue.
  TextColumn get sku => text().withLength(min: 1, max: 40)();
  TextColumn get name => text().withLength(min: 1, max: 180)();

  /// Optional scanned barcode. Unique when present.
  TextColumn get barcode => text().nullable().withLength(max: 64)();
  IntColumn get categoryId =>
      integer().references(Categories, #id, onDelete: KeyAction.restrict)();
  TextColumn get brand => text().nullable().withLength(max: 120)();
  TextColumn get description => text().nullable().withLength(max: 1000)();

  /// Unit the product is counted in for display purposes. Stock is always
  /// stored in base units.
  TextColumn get unitOfMeasure => textEnum<UnitOfMeasure>().withDefault(
    Constant(UnitOfMeasure.piece.name),
  )();

  /// Base units contained in one pack/box, used to convert pack entry into
  /// base units at data-entry time. Always >= 1.
  IntColumn get unitsPerPack => integer()
      .withDefault(const Constant(1))
      .check(unitsPerPack.isBiggerOrEqualValue(1))();

  /// Current purchase cost, used as the default valuation cost for new
  /// movements. Historical cost is snapshotted on each ledger entry.
  IntColumn get costPriceCents => integer().withDefault(const Constant(0))();

  /// Default price charged to agents and shops.
  IntColumn get wholesalePriceCents =>
      integer().withDefault(const Constant(0))();

  /// Default price a shop charges an end customer.
  IntColumn get retailPriceCents => integer().withDefault(const Constant(0))();

  /// Quantity at or below which the product is reported as low stock.
  IntColumn get reorderLevel => integer().withDefault(const Constant(0))();
  TextColumn get status => textEnum<EntityStatus>().withDefault(
    Constant(EntityStatus.active.name),
  )();
  TextColumn get notes => text().nullable().withLength(max: 1000)();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {sku},
    {barcode},
  ];
}

@DataClassName('Agent')
@TableIndex(name: 'idx_agents_status', columns: {#status})
class Agents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get code => text().withLength(min: 1, max: 24)();
  TextColumn get name => text().withLength(min: 1, max: 180)();
  TextColumn get phone => text().nullable().withLength(max: 32)();
  TextColumn get address => text().nullable().withLength(max: 500)();
  TextColumn get nic => text().nullable().withLength(max: 24)();

  /// Commission rate in basis points (1000 = 10%). Optional.
  IntColumn get commissionBps => integer().nullable()();

  /// Receivable carried over from before the system went live. Positive means
  /// the agent owes the business.
  IntColumn get openingBalanceCents =>
      integer().withDefault(const Constant(0))();
  TextColumn get status => textEnum<EntityStatus>().withDefault(
    Constant(EntityStatus.active.name),
  )();
  TextColumn get notes => text().nullable().withLength(max: 1000)();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {code},
  ];
}

@DataClassName('Shop')
@TableIndex(name: 'idx_shops_agent', columns: {#assignedAgentId})
@TableIndex(name: 'idx_shops_status', columns: {#status})
class Shops extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get code => text().withLength(min: 1, max: 24)();
  TextColumn get name => text().withLength(min: 1, max: 180)();
  TextColumn get ownerName => text().nullable().withLength(max: 180)();
  TextColumn get phone => text().nullable().withLength(max: 32)();
  TextColumn get address => text().nullable().withLength(max: 500)();

  /// The agent currently responsible for this shop. Reassigning an agent
  /// changes only this pointer; every historical document keeps the agent it
  /// was created with.
  IntColumn get assignedAgentId => integer().nullable().references(
    Agents,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get openingBalanceCents =>
      integer().withDefault(const Constant(0))();

  /// Optional ceiling on unpaid wholesale invoices.
  IntColumn get creditLimitCents => integer().nullable()();
  TextColumn get status => textEnum<EntityStatus>().withDefault(
    Constant(EntityStatus.active.name),
  )();
  TextColumn get notes => text().nullable().withLength(max: 1000)();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {code},
  ];
}

@DataClassName('Employee')
@TableIndex(name: 'idx_employees_status', columns: {#status})
class Employees extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get code => text().withLength(min: 1, max: 24)();
  TextColumn get name => text().withLength(min: 1, max: 180)();
  TextColumn get phone => text().nullable().withLength(max: 32)();
  TextColumn get address => text().nullable().withLength(max: 500)();
  TextColumn get designation => text().nullable().withLength(max: 120)();
  DateTimeColumn get joiningDate => dateTime().nullable()();
  IntColumn get basicSalaryCents => integer().withDefault(const Constant(0))();
  TextColumn get status => textEnum<EntityStatus>().withDefault(
    Constant(EntityStatus.active.name),
  )();
  TextColumn get notes => text().nullable().withLength(max: 1000)();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {code},
  ];
}

/// Every place stock can sit, including the virtual counterparties that make
/// the ledger balance to zero. Exactly one location row exists per agent and
/// per shop; it is created in the same transaction as the party itself.
@DataClassName('InventoryLocation')
@TableIndex(name: 'idx_locations_kind', columns: {#kind})
@TableIndex(name: 'idx_locations_agent', columns: {#agentId})
@TableIndex(name: 'idx_locations_shop', columns: {#shopId})
class InventoryLocations extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get code => text().withLength(min: 1, max: 32)();
  TextColumn get name => text().withLength(min: 1, max: 180)();
  TextColumn get kind => textEnum<LocationKind>()();

  /// Set when [kind] is [LocationKind.agent].
  IntColumn get agentId => integer().nullable().references(
    Agents,
    #id,
    onDelete: KeyAction.restrict,
  )();

  /// Set when [kind] is [LocationKind.shop].
  IntColumn get shopId => integer().nullable().references(
    Shops,
    #id,
    onDelete: KeyAction.restrict,
  )();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {code},
    {agentId},
    {shopId},
  ];
}
