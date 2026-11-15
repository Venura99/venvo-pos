import '../../../core/api/api_client.dart';
import '../../../core/api/api_decode.dart';
import '../../../core/api/revision_bus.dart';
import '../../authentication/domain/authenticated_user.dart';
import '../domain/category_models.dart';

/// Product categories over HTTP. Mirrors `CategoryRepository`.
class CategoryApi {
  const CategoryApi(this._client);

  final ApiClient _client;

  Stream<List<CategoryListItem>> watchCategories({
    bool includeArchived = false,
  }) => _client.watch(
    // Products as well: the list carries a product count per category, so
    // adding or moving a product changes it.
    {ApiTopic.categories, ApiTopic.products},
    () async {
      final json = await _client.get(
        '/api/v1/categories',
        query: {'includeArchived': includeArchived},
      );
      return decodeList(json, 'categories', CategoryListItem.fromJson);
    },
  );

  Future<List<CategoryListItem>> selectableCategories() async {
    final json = await _client.get('/api/v1/categories/selectable');
    return decodeList(json, 'categories', CategoryListItem.fromJson);
  }

  Future<int> create(AuthenticatedUser actor, CategoryDraft draft) async {
    final json = await _client.post(
      '/api/v1/categories',
      body: draft.toJson(),
      bumps: {ApiTopic.categories},
    );
    return decodeId(json);
  }

  Future<void> update(AuthenticatedUser actor, CategoryDraft draft) async {
    await _client.put(
      '/api/v1/categories/${draft.id}',
      body: draft.toJson(),
      bumps: {ApiTopic.categories},
    );
  }

  Future<void> archive(AuthenticatedUser actor, int categoryId) async {
    await _client.post(
      '/api/v1/categories/$categoryId/archive',
      bumps: {ApiTopic.categories},
    );
  }

  Future<void> restore(AuthenticatedUser actor, int categoryId) async {
    await _client.post(
      '/api/v1/categories/$categoryId/restore',
      bumps: {ApiTopic.categories},
    );
  }
}
