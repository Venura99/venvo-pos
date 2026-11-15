import '../../../core/api/api_client.dart';
import '../../../core/api/api_decode.dart';
import '../../../core/api/revision_bus.dart';
import '../../../core/database/app_database.dart';
import '../../authentication/domain/authenticated_user.dart';
import '../domain/agent_models.dart';

/// Agents over HTTP. Mirrors `AgentRepository`.
class AgentApi {
  const AgentApi(this._client);

  final ApiClient _client;

  /// Agents matching [filter].
  ///
  /// Payments are watched as well because the list shows what each agent
  /// owes: taking a collection changes the balance on this screen without
  /// touching the agent record at all.
  Stream<List<AgentListItem>> watchAgents(AgentFilter filter) => _client.watch(
    {ApiTopic.agents, ApiTopic.payments, ApiTopic.invoices},
    () async {
      final json = await _client.get(
        '/api/v1/agents',
        query: {
          if (filter.search.trim().isNotEmpty) 'search': filter.search.trim(),
          'includeInactive': filter.includeInactive,
          'includeArchived': filter.includeArchived,
          'owingOnly': filter.owingOnly,
        },
      );
      return decodeList(json, 'agents', AgentListItem.fromJson);
    },
  );

  Future<List<Agent>> selectableAgents() async {
    final json = await _client.get('/api/v1/agents/selectable');
    return decodeList(json, 'agents', Agent.fromJson);
  }

  Future<int> create(AuthenticatedUser actor, AgentDraft draft) async {
    final json = await _client.post(
      '/api/v1/agents',
      body: draft.toJson(),
      // Creating an agent also creates its inventory location, so anything
      // listing locations is now stale too.
      bumps: {ApiTopic.agents, ApiTopic.locations},
    );
    return decodeId(json);
  }

  Future<void> update(AuthenticatedUser actor, AgentDraft draft) async {
    await _client.put(
      '/api/v1/agents/${draft.id}',
      body: draft.toJson(),
      bumps: {ApiTopic.agents, ApiTopic.locations},
    );
  }

  Future<void> archive(AuthenticatedUser actor, int agentId) async {
    await _client.post(
      '/api/v1/agents/$agentId/archive',
      bumps: {ApiTopic.agents, ApiTopic.locations},
    );
  }

  Future<void> restore(AuthenticatedUser actor, int agentId) async {
    await _client.post(
      '/api/v1/agents/$agentId/restore',
      bumps: {ApiTopic.agents, ApiTopic.locations},
    );
  }
}
