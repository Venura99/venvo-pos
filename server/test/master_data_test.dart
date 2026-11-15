import 'package:test/test.dart';
import 'package:venvo_core/core/constants/permissions.dart';

import 'support/api_harness.dart';

/// Products, categories, agents, shops, employees and locations over HTTP.
void main() {
  late ApiHarness api;
  late String admin;

  setUp(() async {
    api = await ApiHarness.start();
    admin = await api.signUpAdministrator();
  });

  tearDown(() => api.stop());

  group('categories', () {
    test('created, listed, renamed and archived', () async {
      final id = await api.createCategory(admin, name: 'Cables');

      final listed = await api.get('/api/v1/categories', token: admin);
      expect(listed.statusCode, 200, reason: listed.body);
      final names = api
          .list(listed, 'categories')
          .map((c) => c['name'])
          .toList();
      expect(names, contains('Cables'));

      final renamed = await api.send('PUT', '/api/v1/categories/$id', {
        'id': id,
        'name': 'Cables and adapters',
      }, token: admin);
      expect(renamed.statusCode, 204, reason: renamed.body);

      final archived = await api.send(
        'POST',
        '/api/v1/categories/$id/archive',
        null,
        token: admin,
      );
      expect(archived.statusCode, 204, reason: archived.body);

      // Gone from the default list, present when archived ones are asked for.
      final active = await api.get('/api/v1/categories', token: admin);
      expect(
        api.list(active, 'categories').map((c) => c['id']),
        isNot(contains(id)),
      );
      final all = await api.get(
        '/api/v1/categories?includeArchived=true',
        token: admin,
      );
      expect(api.list(all, 'categories').map((c) => c['id']), contains(id));
    });

    test('a duplicate name is refused', () async {
      await api.createCategory(admin, name: 'Batteries');
      final again = await api.send('POST', '/api/v1/categories', {
        'name': 'Batteries',
      }, token: admin);
      expect(again.statusCode, 409, reason: again.body);
    });

    test('the id in the body must match the address', () async {
      final id = await api.createCategory(admin);
      final mismatch = await api.send('PUT', '/api/v1/categories/$id', {
        'id': id + 1,
        'name': 'Somewhere else',
      }, token: admin);
      expect(mismatch.statusCode, 422, reason: mismatch.body);
      expect(api.errorOf(mismatch)['field'], 'id');
    });
  });

  group('products', () {
    test('money survives the round trip exactly', () async {
      // The one property worth more than all the others here. Prices are
      // integer cents end to end; if the wire format ever became a decimal,
      // 1234.56 would come back as 1234.5599999999999 and every total in the
      // business would drift. 107 is deliberately awkward: a third of a rupee
      // and seven cents.
      final categoryId = await api.createCategory(admin);
      final created = await api.send('POST', '/api/v1/products', {
        'sku': 'CHG-25W',
        'name': 'Fast charger 25W',
        'categoryId': categoryId,
        'costPrice': 123457,
        'wholesalePrice': 149999,
        'retailPrice': 199900,
        'unitsPerPack': 12,
        'reorderLevel': 24,
      }, token: admin);
      expect(created.statusCode, 201, reason: created.body);

      final listed = await api.get('/api/v1/products', token: admin);
      final product = api
          .list(listed, 'products')
          .firstWhere((p) => p['sku'] == 'CHG-25W');

      expect(product['costPrice'], 123457);
      expect(product['wholesalePrice'], 149999);
      expect(product['retailPrice'], 199900);
      expect(product['unitsPerPack'], 12);
      expect(product['reorderLevel'], 24);
      // Integers, not strings and not doubles.
      expect(product['costPrice'], isA<int>());
    });

    test('enums cross the wire by name', () async {
      final categoryId = await api.createCategory(admin);
      final created = await api.send('POST', '/api/v1/products', {
        'sku': 'CBL-1M',
        'name': 'USB-C cable 1m',
        'categoryId': categoryId,
        'unitOfMeasure': 'box',
        'status': 'active',
      }, token: admin);
      expect(created.statusCode, 201, reason: created.body);

      final listed = await api.get('/api/v1/products', token: admin);
      final product = api
          .list(listed, 'products')
          .firstWhere((p) => p['sku'] == 'CBL-1M');
      expect(product['unitOfMeasure'], 'box');
      expect(product['status'], 'active');
    });

    test('a duplicate SKU is refused', () async {
      final categoryId = await api.createCategory(admin);
      Future<int> create() async {
        final response = await api.send('POST', '/api/v1/products', {
          'sku': 'DUP-1',
          'name': 'Duplicate',
          'categoryId': categoryId,
        }, token: admin);
        return response.statusCode;
      }

      expect(await create(), 201);
      expect(await create(), 409);
    });

    test('an unknown category is refused, not stored', () async {
      final response = await api.send('POST', '/api/v1/products', {
        'sku': 'ORPHAN-1',
        'name': 'Orphan',
        'categoryId': 999999,
      }, token: admin);
      // Either a not-found or a business-rule refusal is correct here; what
      // must not happen is a 201 or a 500.
      expect(response.statusCode, anyOf(404, 409), reason: response.body);

      final listed = await api.get('/api/v1/products', token: admin);
      expect(
        api.list(listed, 'products').map((p) => p['sku']),
        isNot(contains('ORPHAN-1')),
      );
    });

    test('a missing required field is a 422 naming it', () async {
      final categoryId = await api.createCategory(admin);
      final response = await api.send('POST', '/api/v1/products', {
        'name': 'No SKU',
        'categoryId': categoryId,
      }, token: admin);
      expect(response.statusCode, 422, reason: response.body);
      expect(api.errorOf(response)['field'], 'sku');
    });

    test('a field of the wrong type is a 422, not a 500', () async {
      final categoryId = await api.createCategory(admin);
      final response = await api.send('POST', '/api/v1/products', {
        'sku': 'BAD-TYPE',
        'name': 'Bad type',
        'categoryId': categoryId,
        'costPrice': 'not a number',
      }, token: admin);
      expect(response.statusCode, 422, reason: response.body);
      expect(api.errorOf(response)['field'], 'costPrice');
      expect(
        api.logs.where((line) => line.contains('UNHANDLED')),
        isEmpty,
        reason: api.logs.join('\n'),
      );
    });

    test('search and filters narrow the list', () async {
      final chargers = await api.createCategory(admin, name: 'Chargers');
      final cables = await api.createCategory(admin, name: 'Cables');
      for (final (sku, name, category) in [
        ('F-1', 'Fast charger', chargers),
        ('F-2', 'Slow charger', chargers),
        ('C-1', 'Braided cable', cables),
      ]) {
        final created = await api.send('POST', '/api/v1/products', {
          'sku': sku,
          'name': name,
          'categoryId': category,
        }, token: admin);
        expect(created.statusCode, 201, reason: created.body);
      }

      final byCategory = await api.get(
        '/api/v1/products?categoryId=$cables',
        token: admin,
      );
      expect(api.list(byCategory, 'products').length, 1);

      final bySearch = await api.get(
        '/api/v1/products?search=charger',
        token: admin,
      );
      expect(api.list(bySearch, 'products').length, 2);
    });

    test('a bad filter value is refused rather than ignored', () async {
      // Silently falling back to the default would return a list that looks
      // right and is not.
      final badBool = await api.get(
        '/api/v1/products?includeArchived=perhaps',
        token: admin,
      );
      expect(badBool.statusCode, 422, reason: badBool.body);
      expect(api.errorOf(badBool)['field'], 'includeArchived');

      final badSort = await api.get(
        '/api/v1/products?sortKey=whatever',
        token: admin,
      );
      expect(badSort.statusCode, 422, reason: badSort.body);

      final badInt = await api.get(
        '/api/v1/products?categoryId=abc',
        token: admin,
      );
      expect(badInt.statusCode, 422, reason: badInt.body);
    });

    test('stock by location is reported for a new product', () async {
      final categoryId = await api.createCategory(admin);
      final created = await api.send('POST', '/api/v1/products', {
        'sku': 'STK-1',
        'name': 'Stock probe',
        'categoryId': categoryId,
      }, token: admin);
      final id = api.json(created)['id']! as int;

      final stock = await api.get('/api/v1/products/$id/stock', token: admin);
      expect(stock.statusCode, 200, reason: stock.body);
      // A product nobody has received yet holds no stock anywhere, which is
      // different from the endpoint failing.
      expect(api.json(stock)['locations'], isA<List<Object?>>());
    });

    test('bulk category change moves every product or none', () async {
      final from = await api.createCategory(admin, name: 'From');
      final to = await api.createCategory(admin, name: 'To');
      final ids = <int>[];
      for (final sku in ['B-1', 'B-2']) {
        final created = await api.send('POST', '/api/v1/products', {
          'sku': sku,
          'name': 'Bulk $sku',
          'categoryId': from,
        }, token: admin);
        ids.add(api.json(created)['id']! as int);
      }

      final moved = await api.send('POST', '/api/v1/products/bulk-category', {
        'productIds': ids,
        'categoryId': to,
      }, token: admin);
      expect(moved.statusCode, 200, reason: moved.body);
      expect(api.json(moved)['productsChanged'], 2);

      final listed = await api.get(
        '/api/v1/products?categoryId=$to',
        token: admin,
      );
      expect(api.list(listed, 'products').length, 2);
    });

    test('one bad id rejects the whole bulk request', () async {
      final to = await api.createCategory(admin, name: 'Target');
      final response = await api.send(
        'POST',
        '/api/v1/products/bulk-category',
        {
          'productIds': [1, 'two'],
          'categoryId': to,
        },
        token: admin,
      );
      expect(response.statusCode, 422, reason: response.body);
      expect(api.errorOf(response)['field'], 'productIds');
    });
  });

  group('agents and shops', () {
    test('an agent is created and appears in both lists', () async {
      final created = await api.send('POST', '/api/v1/agents', {
        'name': 'Kandy route',
        'phone': '0770000000',
        'openingBalance': 50000,
      }, token: admin);
      expect(created.statusCode, 201, reason: created.body);

      final listed = await api.get('/api/v1/agents', token: admin);
      expect(
        api.list(listed, 'agents').map((a) => a['name']),
        contains('Kandy route'),
      );

      final selectable = await api.get(
        '/api/v1/agents/selectable',
        token: admin,
      );
      expect(selectable.statusCode, 200, reason: selectable.body);
      expect(api.list(selectable, 'agents'), isNotEmpty);
    });

    test('a shop can be assigned to an agent and then unassigned', () async {
      final agent = await api.send('POST', '/api/v1/agents', {
        'name': 'Galle route',
      }, token: admin);
      final agentId = api.json(agent)['id']! as int;

      final shop = await api.send('POST', '/api/v1/shops', {
        'name': 'Sea Street Mobiles',
        'assignedAgentId': agentId,
        'creditLimit': 2500000,
      }, token: admin);
      expect(shop.statusCode, 201, reason: shop.body);
      final shopId = api.json(shop)['id']! as int;

      final byAgent = await api.get(
        '/api/v1/shops?agentId=$agentId',
        token: admin,
      );
      expect(api.list(byAgent, 'shops').length, 1);

      // Sending null is an operation, not an omission: it unassigns.
      final unassigned = await api.send('POST', '/api/v1/shops/$shopId/agent', {
        'agentId': null,
        'reason': 'Route closed',
      }, token: admin);
      expect(unassigned.statusCode, 204, reason: unassigned.body);

      final unassignedOnly = await api.get(
        '/api/v1/shops?unassignedOnly=true',
        token: admin,
      );
      expect(
        api.list(unassignedOnly, 'shops').map((s) => s['id']),
        contains(shopId),
      );
    });

    test('a shop under an unknown agent is refused', () async {
      final response = await api.send('POST', '/api/v1/shops', {
        'name': 'Nowhere Traders',
        'assignedAgentId': 999999,
      }, token: admin);
      expect(response.statusCode, anyOf(404, 409), reason: response.body);
    });
  });

  group('employees and locations', () {
    test('an employee is created and designations are listed', () async {
      final created = await api.send('POST', '/api/v1/employees', {
        'name': 'Nimal Perera',
        'designation': 'Driver',
        'basicSalary': 6500000,
      }, token: admin);
      expect(created.statusCode, 201, reason: created.body);

      final listed = await api.get('/api/v1/employees', token: admin);
      final employee = api
          .list(listed, 'employees')
          .firstWhere((e) => e['name'] == 'Nimal Perera');
      expect(employee['designation'], 'Driver');

      final designations = await api.get(
        '/api/v1/employees/designations',
        token: admin,
      );
      expect(
        (api.json(designations)['designations']! as List).cast<String>(),
        contains('Driver'),
      );
    });

    test('the seeded warehouse is listed as a location', () async {
      final listed = await api.get('/api/v1/locations', token: admin);
      expect(listed.statusCode, 200, reason: listed.body);
      final locations = api.list(listed, 'locations');
      expect(locations, isNotEmpty);
      expect(locations.map((l) => l['kind']), contains('warehouse'));
    });

    test('creating an agent creates its inventory location', () async {
      // This is what makes the stock ledger balance for that agent: a
      // movement needs somewhere to move to. If the location were missing,
      // the failure would not appear until the first transfer.
      final before = api
          .list(await api.get('/api/v1/locations', token: admin), 'locations')
          .length;

      final created = await api.send('POST', '/api/v1/agents', {
        'name': 'Matara route',
      }, token: admin);
      expect(created.statusCode, 201, reason: created.body);

      final after = api.list(
        await api.get('/api/v1/locations', token: admin),
        'locations',
      );
      expect(after.length, before + 1);
      expect(after.map((l) => l['kind']), contains('agent'));
    });
  });

  group('permissions', () {
    test('a viewer may read the catalogue but not change it', () async {
      final viewer = await api.createWorkingUser(
        adminToken: admin,
        username: 'viewer1',
        roles: [RoleCodes.viewer],
      );

      final read = await api.get('/api/v1/products', token: viewer);
      expect(read.statusCode, 200, reason: read.body);

      final categoryId = await api.createCategory(admin, name: 'Locked');
      final write = await api.send('POST', '/api/v1/products', {
        'sku': 'NOPE-1',
        'name': 'Should not exist',
        'categoryId': categoryId,
      }, token: viewer);
      expect(write.statusCode, 403, reason: write.body);
      expect(api.errorOf(write)['permission'], Permissions.productsManage);

      // And nothing was written.
      final listed = await api.get('/api/v1/products', token: admin);
      expect(
        api.list(listed, 'products').map((p) => p['sku']),
        isNot(contains('NOPE-1')),
      );
    });

    test('a cashier cannot see employees', () async {
      final cashier = await api.createWorkingUser(
        adminToken: admin,
        username: 'cashier9',
        roles: [RoleCodes.cashier],
      );
      final response = await api.get('/api/v1/employees', token: cashier);
      expect(response.statusCode, 403, reason: response.body);
      expect(api.errorOf(response)['permission'], Permissions.employeesView);
    });

    test('every master-data read needs a token', () async {
      for (final path in [
        '/api/v1/products',
        '/api/v1/categories',
        '/api/v1/agents',
        '/api/v1/shops',
        '/api/v1/employees',
        '/api/v1/locations',
      ]) {
        final response = await api.get(path);
        expect(response.statusCode, 401, reason: '$path was not protected');
      }
    });
  });
}
