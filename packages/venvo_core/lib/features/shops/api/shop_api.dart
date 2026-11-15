import '../../../core/api/api_client.dart';
import '../../../core/api/api_decode.dart';
import '../../../core/api/revision_bus.dart';
import '../../../core/database/app_database.dart';
import '../../authentication/domain/authenticated_user.dart';
import '../domain/shop_models.dart';

/// Shops over HTTP. Mirrors `ShopRepository`.
class ShopApi {
  const ShopApi(this._client);

  final ApiClient _client;

  /// Shops matching [filter]. Invoices and payments are watched because the
  /// list shows outstanding balances and credit-limit breaches.
  Stream<List<ShopListItem>> watchShops(ShopFilter filter) => _client.watch(
    {ApiTopic.shops, ApiTopic.agents, ApiTopic.invoices, ApiTopic.payments},
    () async {
      final json = await _client.get(
        '/api/v1/shops',
        query: {
          if (filter.search.trim().isNotEmpty) 'search': filter.search.trim(),
          'agentId': filter.agentId,
          'includeInactive': filter.includeInactive,
          'includeArchived': filter.includeArchived,
          'owingOnly': filter.owingOnly,
          'overCreditLimitOnly': filter.overCreditLimitOnly,
          'unassignedOnly': filter.unassignedOnly,
        },
      );
      return decodeList(json, 'shops', ShopListItem.fromJson);
    },
  );

  Future<List<Shop>> selectableShops({int? agentId}) async {
    final json = await _client.get(
      '/api/v1/shops/selectable',
      query: {'agentId': agentId},
    );
    return decodeList(json, 'shops', Shop.fromJson);
  }

  Future<int> create(AuthenticatedUser actor, ShopDraft draft) async {
    final json = await _client.post(
      '/api/v1/shops',
      body: draft.toJson(),
      bumps: {ApiTopic.shops, ApiTopic.locations},
    );
    return decodeId(json);
  }

  Future<void> update(AuthenticatedUser actor, ShopDraft draft) async {
    await _client.put(
      '/api/v1/shops/${draft.id}',
      body: draft.toJson(),
      bumps: {ApiTopic.shops, ApiTopic.locations},
    );
  }

  /// Moves a shop to another agent, or to none.
  ///
  /// [agentId] is deliberately nullable and is always sent: null means
  /// "unassign", which is a different instruction from leaving the field out.
  Future<void> reassignAgent(
    AuthenticatedUser actor, {
    required int shopId,
    required int? agentId,
    String? reason,
  }) async {
    await _client.post(
      '/api/v1/shops/$shopId/agent',
      body: {'agentId': agentId, if (reason != null) 'reason': reason},
      bumps: {ApiTopic.shops, ApiTopic.agents},
    );
  }

  Future<void> archive(AuthenticatedUser actor, int shopId) async {
    await _client.post(
      '/api/v1/shops/$shopId/archive',
      bumps: {ApiTopic.shops, ApiTopic.locations},
    );
  }

  Future<void> restore(AuthenticatedUser actor, int shopId) async {
    await _client.post(
      '/api/v1/shops/$shopId/restore',
      bumps: {ApiTopic.shops, ApiTopic.locations},
    );
  }
}
