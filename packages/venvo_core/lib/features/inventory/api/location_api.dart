import '../../../core/api/api_client.dart';
import '../../../core/api/api_decode.dart';
import '../../../core/api/revision_bus.dart';
import '../../../core/database/app_database.dart';
import '../../../core/errors/failures.dart';
import '../../authentication/domain/authenticated_user.dart';
import '../domain/location_models.dart';

/// Inventory locations over HTTP. Mirrors the parts of `LocationRepository`
/// a client uses.
///
/// The repository's `createForAgent`, `createForShop` and the rename/activate
/// helpers for party locations are absent on purpose. They run on the server
/// as part of creating or editing an agent or a shop, inside that operation's
/// transaction; a client calling them directly could create a location with
/// no party behind it.
class LocationApi {
  const LocationApi(this._client);

  final ApiClient _client;

  Stream<List<LocationListItem>> watchLocations({
    bool includeVirtual = false,
    bool includeInactive = true,
  }) => _client.watch(
    // Agents and shops each own a location, so creating either adds one here.
    {ApiTopic.locations, ApiTopic.agents, ApiTopic.shops, ApiTopic.stock},
    () async {
      final json = await _client.get(
        '/api/v1/locations',
        query: {
          'includeVirtual': includeVirtual,
          'includeInactive': includeInactive,
        },
      );
      return decodeList(json, 'locations', LocationListItem.fromJson);
    },
  );

  /// One location by its seeded code, e.g. the in-transit location a return
  /// is routed through.
  Future<InventoryLocation> byCode(String code) async {
    final json = await _client.get(
      '/api/v1/locations/by-code/${Uri.encodeComponent(code)}',
    );
    final location = json['location'];
    if (location is! Map<String, dynamic>) {
      throw StorageFailure(
        'The server sent a reply this version cannot read.',
        details: 'Expected an object under "location".',
      );
    }
    return InventoryLocation.fromJson(location);
  }

  Future<int> createWarehouse(
    AuthenticatedUser actor, {
    required String name,
  }) async {
    final json = await _client.post(
      '/api/v1/locations/warehouses',
      body: {'name': name},
      bumps: {ApiTopic.locations},
    );
    return decodeId(json);
  }

  Future<void> renameWarehouse(
    AuthenticatedUser actor, {
    required int locationId,
    required String name,
  }) async {
    await _client.put(
      '/api/v1/locations/$locationId/name',
      body: {'name': name},
      bumps: {ApiTopic.locations},
    );
  }

  Future<void> setWarehouseActive(
    AuthenticatedUser actor, {
    required int locationId,
    required bool isActive,
  }) async {
    await _client.post(
      '/api/v1/locations/$locationId/active',
      body: {'isActive': isActive},
      bumps: {ApiTopic.locations},
    );
  }
}
