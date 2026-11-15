import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/features/agents/data/agent_repository.dart';
import 'package:venvo_core/features/agents/domain/agent_models.dart';
import 'package:venvo_core/features/categories/data/category_repository.dart';
import 'package:venvo_core/features/categories/domain/category_models.dart';
import 'package:venvo_core/features/employees/data/employee_repository.dart';
import 'package:venvo_core/features/employees/domain/employee_models.dart';
import 'package:venvo_core/features/inventory/data/location_repository.dart';
import 'package:venvo_core/features/products/data/product_repository.dart';
import 'package:venvo_core/features/products/domain/product_models.dart';
import 'package:venvo_core/features/shops/data/shop_repository.dart';
import 'package:venvo_core/features/shops/domain/shop_models.dart';

import '../auth/auth_middleware.dart';
import '../http/json_body.dart';
import '../http/path_id.dart';
import '../http/query_params.dart';
import '../http/responses.dart';

/// Products, categories, agents, shops, employees and inventory locations.
///
/// The pattern every module follows:
///
/// * **Writes** call the repository with `request.session.user` as the actor.
///   The repository checks the permission itself, inside the same transaction
///   as the change, so the check cannot be bypassed by reaching the operation
///   another way. The route adds nothing.
/// * **Reads** go through `requirePermission`, because the `watch…` methods are
///   plain queries that do no checking of their own — they were written for a
///   UI that had already decided whether to show the screen. On a network that
///   is not good enough, so the permission is required here.
/// * The `watch…` methods return streams for the client's reactive UI. Over
///   HTTP they are read once with `.first`, which runs the query and stops.
Router masterDataRoutes({
  required ProductRepository products,
  required CategoryRepository categories,
  required AgentRepository agents,
  required ShopRepository shops,
  required EmployeeRepository employees,
  required LocationRepository locations,
}) {
  final router = Router();

  // ---- products ----------------------------------------------------------

  router.get('/products', (Request request) async {
    requirePermission(
      request,
      Permissions.productsView,
      action: 'view products',
    );
    final query = QueryParams.of(request);
    final items = await products
        .watchProducts(
          ProductFilter(
            search: query.string('search'),
            categoryId: query.optionalInt('categoryId'),
            brand: query.optionalString('brand'),
            includeInactive: query.boolean('includeInactive'),
            includeArchived: query.boolean('includeArchived'),
            lowStockOnly: query.boolean('lowStockOnly'),
            sortKey: query.enumValue(
              'sortKey',
              ProductSortKey.values,
              fallback: ProductSortKey.name,
            ),
            sortAscending: query.boolean('sortAscending', fallback: true),
          ),
        )
        .first;
    return Api.ok({'products': items.map((p) => p.toJson()).toList()});
  });

  router.get('/products/brands', (Request request) async {
    requirePermission(
      request,
      Permissions.productsView,
      action: 'view products',
    );
    return Api.ok({'brands': await products.watchBrands().first});
  });

  router.get('/products/<id>/stock', (Request request, String id) async {
    requirePermission(request, Permissions.stockView, action: 'view stock');
    final rows = await products.stockByLocation(pathId(id));
    return Api.ok({'locations': rows.map((r) => r.toJson()).toList()});
  });

  router.post('/products', (Request request) async {
    final draft = (await JsonBody.read(request)).decode(ProductDraft.fromJson);
    final newId = await products.create(request.session.user, draft);
    return Api.created({'id': newId});
  });

  router.put('/products/<id>', (Request request, String id) async {
    final draft = (await JsonBody.read(request)).decode(ProductDraft.fromJson);
    requireMatchingId(pathId(id), draft.id);
    await products.update(request.session.user, draft);
    return Api.noContent();
  });

  router.post('/products/<id>/archive', (Request request, String id) async {
    await products.archive(request.session.user, pathId(id));
    return Api.noContent();
  });

  router.post('/products/<id>/restore', (Request request, String id) async {
    await products.restore(request.session.user, pathId(id));
    return Api.noContent();
  });

  router.post('/products/bulk-category', (Request request) async {
    final body = await JsonBody.read(request);
    final changed = await products.bulkUpdateCategory(
      actor: request.session.user,
      productIds: body.requireIntList('productIds'),
      categoryId: body.requireInt('categoryId'),
    );
    return Api.ok({'productsChanged': changed});
  });

  // ---- categories --------------------------------------------------------

  router.get('/categories', (Request request) async {
    requirePermission(
      request,
      Permissions.productsView,
      action: 'view the product catalogue',
    );
    final items = await categories
        .watchCategories(
          includeArchived: QueryParams.of(request).boolean('includeArchived'),
        )
        .first;
    return Api.ok({'categories': items.map((c) => c.toJson()).toList()});
  });

  router.get('/categories/selectable', (Request request) async {
    requirePermission(
      request,
      Permissions.productsView,
      action: 'view the product catalogue',
    );
    final items = await categories.selectableCategories();
    return Api.ok({'categories': items.map((c) => c.toJson()).toList()});
  });

  router.post('/categories', (Request request) async {
    final draft = (await JsonBody.read(request)).decode(CategoryDraft.fromJson);
    final newId = await categories.create(request.session.user, draft);
    return Api.created({'id': newId});
  });

  router.put('/categories/<id>', (Request request, String id) async {
    final draft = (await JsonBody.read(request)).decode(CategoryDraft.fromJson);
    requireMatchingId(pathId(id), draft.id);
    await categories.update(request.session.user, draft);
    return Api.noContent();
  });

  router.post('/categories/<id>/archive', (Request request, String id) async {
    await categories.archive(request.session.user, pathId(id));
    return Api.noContent();
  });

  router.post('/categories/<id>/restore', (Request request, String id) async {
    await categories.restore(request.session.user, pathId(id));
    return Api.noContent();
  });

  // ---- agents ------------------------------------------------------------

  router.get('/agents', (Request request) async {
    requirePermission(request, Permissions.agentsView, action: 'view agents');
    final query = QueryParams.of(request);
    final items = await agents
        .watchAgents(
          AgentFilter(
            search: query.string('search'),
            includeInactive: query.boolean('includeInactive'),
            includeArchived: query.boolean('includeArchived'),
            owingOnly: query.boolean('owingOnly'),
          ),
        )
        .first;
    return Api.ok({'agents': items.map((a) => a.toJson()).toList()});
  });

  router.get('/agents/selectable', (Request request) async {
    requirePermission(request, Permissions.agentsView, action: 'view agents');
    final rows = await agents.selectableAgents();
    return Api.ok({'agents': rows.map((a) => a.toJson()).toList()});
  });

  router.post('/agents', (Request request) async {
    final draft = (await JsonBody.read(request)).decode(AgentDraft.fromJson);
    final newId = await agents.create(request.session.user, draft);
    return Api.created({'id': newId});
  });

  router.put('/agents/<id>', (Request request, String id) async {
    final draft = (await JsonBody.read(request)).decode(AgentDraft.fromJson);
    requireMatchingId(pathId(id), draft.id);
    await agents.update(request.session.user, draft);
    return Api.noContent();
  });

  router.post('/agents/<id>/archive', (Request request, String id) async {
    await agents.archive(request.session.user, pathId(id));
    return Api.noContent();
  });

  router.post('/agents/<id>/restore', (Request request, String id) async {
    await agents.restore(request.session.user, pathId(id));
    return Api.noContent();
  });

  // ---- shops -------------------------------------------------------------

  router.get('/shops', (Request request) async {
    requirePermission(request, Permissions.shopsView, action: 'view shops');
    final query = QueryParams.of(request);
    final items = await shops
        .watchShops(
          ShopFilter(
            search: query.string('search'),
            agentId: query.optionalInt('agentId'),
            includeInactive: query.boolean('includeInactive'),
            includeArchived: query.boolean('includeArchived'),
            owingOnly: query.boolean('owingOnly'),
            overCreditLimitOnly: query.boolean('overCreditLimitOnly'),
            unassignedOnly: query.boolean('unassignedOnly'),
          ),
        )
        .first;
    return Api.ok({'shops': items.map((s) => s.toJson()).toList()});
  });

  router.get('/shops/selectable', (Request request) async {
    requirePermission(request, Permissions.shopsView, action: 'view shops');
    final rows = await shops.selectableShops(
      agentId: QueryParams.of(request).optionalInt('agentId'),
    );
    return Api.ok({'shops': rows.map((s) => s.toJson()).toList()});
  });

  router.post('/shops', (Request request) async {
    final draft = (await JsonBody.read(request)).decode(ShopDraft.fromJson);
    final newId = await shops.create(request.session.user, draft);
    return Api.created({'id': newId});
  });

  router.put('/shops/<id>', (Request request, String id) async {
    final draft = (await JsonBody.read(request)).decode(ShopDraft.fromJson);
    requireMatchingId(pathId(id), draft.id);
    await shops.update(request.session.user, draft);
    return Api.noContent();
  });

  /// Moves a shop to a different agent, or to none.
  ///
  /// `agentId` is explicitly nullable: sending null unassigns the shop, which
  /// is a real operation and distinct from omitting the field.
  router.post('/shops/<id>/agent', (Request request, String id) async {
    final body = await JsonBody.read(request);
    await shops.reassignAgent(
      request.session.user,
      shopId: pathId(id),
      agentId: body.optionalInt('agentId'),
      reason: body.optionalString('reason', maxLength: 500),
    );
    return Api.noContent();
  });

  router.post('/shops/<id>/archive', (Request request, String id) async {
    await shops.archive(request.session.user, pathId(id));
    return Api.noContent();
  });

  router.post('/shops/<id>/restore', (Request request, String id) async {
    await shops.restore(request.session.user, pathId(id));
    return Api.noContent();
  });

  // ---- employees ---------------------------------------------------------

  router.get('/employees', (Request request) async {
    requirePermission(
      request,
      Permissions.employeesView,
      action: 'view employees',
    );
    final query = QueryParams.of(request);
    final items = await employees
        .watchEmployees(
          EmployeeFilter(
            search: query.string('search'),
            designation: query.optionalString('designation'),
            includeInactive: query.boolean('includeInactive'),
            includeArchived: query.boolean('includeArchived'),
          ),
        )
        .first;
    return Api.ok({'employees': items.map((e) => e.toJson()).toList()});
  });

  router.get('/employees/selectable', (Request request) async {
    requirePermission(
      request,
      Permissions.employeesView,
      action: 'view employees',
    );
    final rows = await employees.selectableEmployees();
    return Api.ok({'employees': rows.map((e) => e.toJson()).toList()});
  });

  router.get('/employees/designations', (Request request) async {
    requirePermission(
      request,
      Permissions.employeesView,
      action: 'view employees',
    );
    return Api.ok({'designations': await employees.watchDesignations().first});
  });

  router.post('/employees', (Request request) async {
    final draft = (await JsonBody.read(request)).decode(EmployeeDraft.fromJson);
    final newId = await employees.create(request.session.user, draft);
    return Api.created({'id': newId});
  });

  router.put('/employees/<id>', (Request request, String id) async {
    final draft = (await JsonBody.read(request)).decode(EmployeeDraft.fromJson);
    requireMatchingId(pathId(id), draft.id);
    await employees.update(request.session.user, draft);
    return Api.noContent();
  });

  router.post('/employees/<id>/archive', (Request request, String id) async {
    await employees.archive(request.session.user, pathId(id));
    return Api.noContent();
  });

  router.post('/employees/<id>/restore', (Request request, String id) async {
    await employees.restore(request.session.user, pathId(id));
    return Api.noContent();
  });

  // ---- inventory locations -----------------------------------------------

  router.get('/locations', (Request request) async {
    requirePermission(request, Permissions.stockView, action: 'view stock');
    final query = QueryParams.of(request);
    final items = await locations
        .watchLocations(
          includeVirtual: query.boolean('includeVirtual'),
          includeInactive: query.boolean('includeInactive', fallback: true),
        )
        .first;
    return Api.ok({'locations': items.map((l) => l.toJson()).toList()});
  });

  /// One location by its seeded code, e.g. the in-transit or damaged-stock
  /// location the return form routes goods through.
  router.get('/locations/by-code/<code>', (Request request, String code) async {
    requirePermission(request, Permissions.stockView, action: 'view stock');
    final location = await locations.byCode(code);
    return Api.ok({'location': location.toJson()});
  });

  router.post('/locations/warehouses', (Request request) async {
    final body = await JsonBody.read(request);
    final id = await locations.createWarehouse(
      request.session.user,
      name: body.requireString('name', maxLength: 180),
    );
    return Api.created({'id': id});
  });

  router.put('/locations/<id>/name', (Request request, String id) async {
    final body = await JsonBody.read(request);
    await locations.renameWarehouse(
      request.session.user,
      locationId: pathId(id),
      name: body.requireString('name', maxLength: 180),
    );
    return Api.noContent();
  });

  /// Switches a warehouse on or off. The repository refuses to deactivate one
  /// that still holds stock, so goods cannot be stranded somewhere invisible.
  router.post('/locations/<id>/active', (Request request, String id) async {
    final body = await JsonBody.read(request);
    await locations.setWarehouseActive(
      request.session.user,
      locationId: pathId(id),
      isActive: body.requireBool('isActive'),
    );
    return Api.noContent();
  });

  return router;
}
