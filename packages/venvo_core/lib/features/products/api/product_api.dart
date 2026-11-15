import '../../../core/api/api_client.dart';
import '../../../core/api/api_decode.dart';
import '../../../core/api/revision_bus.dart';
import '../../authentication/domain/authenticated_user.dart';
import '../domain/product_models.dart';

/// The product catalogue over HTTP.
///
/// Every method matches `ProductRepository`'s signature exactly, including the
/// `Stream` returns, so the screens and providers that were written against
/// the local database work against a server with no change beyond which object
/// they are handed.
///
/// **The `actor` argument is accepted and ignored.** The server decides who is
/// acting from the bearer token, never from the request, so a client cannot
/// claim to be another user — a property the local build could not have, since
/// there the caller *was* the authority. It stays in the signature so that
/// `product_form.dart` and `products_screen.dart` compile untouched.
class ProductApi {
  const ProductApi(this._client);

  final ApiClient _client;

  /// Products matching [filter], re-fetched whenever a product or a stock
  /// movement changes. Stock is included because the list shows on-hand
  /// quantities, so a transfer changes what this list should say.
  Stream<List<ProductListItem>> watchProducts(ProductFilter filter) =>
      _client.watch({ApiTopic.products, ApiTopic.stock}, () => _list(filter));

  Future<List<ProductListItem>> _list(ProductFilter filter) async {
    final json = await _client.get(
      '/api/v1/products',
      query: {
        if (filter.search.trim().isNotEmpty) 'search': filter.search.trim(),
        'categoryId': filter.categoryId,
        'brand': filter.brand,
        'includeInactive': filter.includeInactive,
        'includeArchived': filter.includeArchived,
        'lowStockOnly': filter.lowStockOnly,
        'sortKey': filter.sortKey.name,
        'sortAscending': filter.sortAscending,
      },
    );
    return decodeList(json, 'products', ProductListItem.fromJson);
  }

  Stream<List<String>> watchBrands() =>
      _client.watch({ApiTopic.products}, () async {
        final json = await _client.get('/api/v1/products/brands');
        return decodeStrings(json, 'brands');
      });

  Future<List<ProductStockAtLocation>> stockByLocation(int productId) async {
    final json = await _client.get('/api/v1/products/$productId/stock');
    return decodeList(json, 'locations', ProductStockAtLocation.fromJson);
  }

  Future<int> create(AuthenticatedUser actor, ProductDraft draft) async {
    final json = await _client.post(
      '/api/v1/products',
      body: draft.toJson(),
      bumps: {ApiTopic.products},
    );
    return decodeId(json);
  }

  Future<void> update(AuthenticatedUser actor, ProductDraft draft) async {
    await _client.put(
      '/api/v1/products/${draft.id}',
      body: draft.toJson(),
      bumps: {ApiTopic.products},
    );
  }

  Future<void> archive(AuthenticatedUser actor, int productId) async {
    await _client.post(
      '/api/v1/products/$productId/archive',
      bumps: {ApiTopic.products},
    );
  }

  Future<void> restore(AuthenticatedUser actor, int productId) async {
    await _client.post(
      '/api/v1/products/$productId/restore',
      bumps: {ApiTopic.products},
    );
  }

  Future<int> bulkUpdateCategory({
    required AuthenticatedUser actor,
    required List<int> productIds,
    required int categoryId,
  }) async {
    final json = await _client.post(
      '/api/v1/products/bulk-category',
      body: {'productIds': productIds, 'categoryId': categoryId},
      // Categories too: the counts shown against each category change.
      bumps: {ApiTopic.products, ApiTopic.categories},
    );
    final changed = json['productsChanged'];
    return changed is int ? changed : productIds.length;
  }
}
