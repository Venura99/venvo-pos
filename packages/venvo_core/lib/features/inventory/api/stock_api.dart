import '../../../core/api/api_client.dart';
import '../../../core/api/api_decode.dart';
import '../../../core/api/revision_bus.dart';
import '../../../core/errors/failures.dart';
import '../../../core/utils/money.dart';
import '../../authentication/domain/authenticated_user.dart';
import '../domain/stock_models.dart';

/// Stock reads over HTTP. Mirrors `StockQueryRepository`.
class StockQueryApi {
  const StockQueryApi(this._client);

  final ApiClient _client;

  /// Products with their on-hand quantities.
  ///
  /// Watches products as well as stock: the list shows reorder levels and
  /// prices, so editing a product changes it without any movement being
  /// posted.
  Stream<List<ProductStockRow>> watchProductStock(StockOverviewFilter filter) =>
      _client.watch({ApiTopic.stock, ApiTopic.products}, () async {
        final json = await _client.get(
          '/api/v1/stock',
          query: {
            if (filter.search.trim().isNotEmpty) 'search': filter.search.trim(),
            'categoryId': filter.categoryId,
            'lowStockOnly': filter.lowStockOnly,
            'hideZeroStock': filter.hideZeroStock,
          },
        );
        return decodeList(json, 'stock', ProductStockRow.fromJson);
      });

  Stream<List<StockBalanceRow>> watchLocationStock(
    int locationId, {
    String search = '',
    bool hideZero = true,
  }) => _client.watch({ApiTopic.stock}, () async {
    final json = await _client.get(
      '/api/v1/stock/locations/$locationId',
      query: {
        if (search.trim().isNotEmpty) 'search': search.trim(),
        'hideZero': hideZero,
      },
    );
    return decodeList(json, 'balances', StockBalanceRow.fromJson);
  });

  Stream<List<StockLedgerRow>> watchLedger(StockLedgerFilter filter) =>
      _client.watch({ApiTopic.stock}, () async {
        final json = await _client.get(
          '/api/v1/stock/ledger',
          query: {
            if (filter.search.trim().isNotEmpty) 'search': filter.search.trim(),
            'productId': filter.productId,
            'locationId': filter.locationId,
            'from': filter.from,
            'to': filter.to,
            'includeVirtualLocations': filter.includeVirtualLocations,
            'limit': filter.limit,
          },
        );
        return decodeList(json, 'entries', StockLedgerRow.fromJson);
      });

  Stream<List<StockDocumentSummary>> watchDocuments(
    StockDocumentFilter filter,
  ) => _client.watch({ApiTopic.stock}, () async {
    final json = await _client.get(
      '/api/v1/stock/documents',
      query: {
        if (filter.search.trim().isNotEmpty) 'search': filter.search.trim(),
        // Sent as a repeated parameter, one per selected type.
        'type': filter.types.map((t) => t.name),
        'status': filter.status?.name,
        'agentId': filter.agentId,
        'shopId': filter.shopId,
        'locationId': filter.locationId,
        'from': filter.from,
        'to': filter.to,
        'limit': filter.limit,
      },
    );
    return decodeList(json, 'documents', StockDocumentSummary.fromJson);
  });

  Future<StockDocumentDetail> documentDetail(int transactionId) async {
    final json = await _client.get('/api/v1/stock/documents/$transactionId');
    return StockDocumentDetail.fromJson(_object(json, 'document'));
  }

  Future<List<StockBalanceRow>> stockAtLocation(int locationId) async {
    final json = await _client.get('/api/v1/stock/locations/$locationId');
    return decodeList(json, 'balances', StockBalanceRow.fromJson);
  }
}

/// Stock movements over HTTP. Mirrors `StockLedgerService`.
class StockLedgerApi {
  const StockLedgerApi(this._client);

  final ApiClient _client;

  /// Posts a movement.
  ///
  /// The paired, signed ledger rows, the balance cache and the journal entry
  /// are all written on the server inside one transaction. The client's part
  /// is to send the request and report what comes back — including a refusal,
  /// which is the point: a movement that would take stock negative is refused
  /// there, where the current balance actually is.
  Future<StockMovementResult> postMovement(
    AuthenticatedUser actor,
    StockMovementRequest request,
  ) async {
    final json = await _client.post(
      '/api/v1/stock/movements',
      body: request.toJson(),
      // Invoices and finance too: a movement can carry a value into the
      // journal, and a delivery can be billed later.
      bumps: {ApiTopic.stock, ApiTopic.finance, ApiTopic.invoices},
    );
    return StockMovementResult.fromJson(_object(json, 'movement'));
  }

  Future<StockMovementResult> cancelMovement(
    AuthenticatedUser actor, {
    required int transactionId,
    required String reason,
  }) async {
    final json = await _client.post(
      '/api/v1/stock/movements/$transactionId/cancel',
      body: {'reason': reason},
      bumps: {ApiTopic.stock, ApiTopic.finance, ApiTopic.invoices},
    );
    return StockMovementResult.fromJson(_object(json, 'movement'));
  }

  Future<int> balanceOf({
    required int locationId,
    required int productId,
  }) async {
    final json = await _client.get(
      '/api/v1/stock/balance',
      query: {'locationId': locationId, 'productId': productId},
    );
    final quantity = json['quantity'];
    if (quantity is int) return quantity;
    throw StorageFailure(
      'The server sent a reply this version cannot read.',
      details: 'Expected an integer "quantity", got ${quantity.runtimeType}.',
    );
  }

  /// Replays the ledger and reports whether the cached balance agrees.
  Future<({int cached, int fromLedger, bool matches})> verifyBalance({
    required int locationId,
    required int productId,
  }) async {
    final json = await _client.get(
      '/api/v1/stock/verify',
      query: {'locationId': locationId, 'productId': productId},
    );
    return (
      cached: json['cached']! as int,
      fromLedger: json['fromLedger']! as int,
      matches: json['matches']! as bool,
    );
  }

  Future<List<({int productId, int netDelta})>> findUnbalancedProducts() async {
    final json = await _client.get('/api/v1/stock/unbalanced');
    final raw = json['products'];
    if (raw is! List) {
      throw StorageFailure(
        'The server sent a reply this version cannot read.',
        details: 'Expected a list under "products".',
      );
    }
    return [
      for (final entry in raw.cast<Map<String, Object?>>())
        (
          productId: entry['productId']! as int,
          netDelta: entry['netDelta']! as int,
        ),
    ];
  }
}

/// Reconciliation counts over HTTP. Mirrors `StockCountRepository`.
class StockCountApi {
  const StockCountApi(this._client);

  final ApiClient _client;

  Future<int> createCount(
    AuthenticatedUser actor, {
    required int locationId,
    bool includeZeroStock = false,
    String? notes,
  }) async {
    final json = await _client.post(
      '/api/v1/stock/counts',
      body: {
        'locationId': locationId,
        'includeZeroStock': includeZeroStock,
        if (notes != null) 'notes': notes,
      },
      bumps: {ApiTopic.stock},
    );
    return decodeId(json);
  }

  Stream<List<StockCountSheet>> watchCounts({int? locationId}) =>
      _client.watch({ApiTopic.stock}, () async {
        final json = await _client.get(
          '/api/v1/stock/counts',
          query: {'locationId': locationId},
        );
        return decodeList(json, 'counts', StockCountSheet.fromJson);
      });

  Future<StockCountSheet> loadCount(int countId) async {
    final json = await _client.get('/api/v1/stock/counts/$countId');
    return StockCountSheet.fromJson(_object(json, 'count'));
  }

  Future<void> saveCountedQuantities(
    AuthenticatedUser actor, {
    required int countId,
    required Map<int, int?> countedByProductId,
  }) async {
    await _client.put(
      '/api/v1/stock/counts/$countId/quantities',
      // JSON object keys must be text. A null value is kept, because "not
      // counted yet" is a different fact from a counted zero.
      body: {
        'counted': {
          for (final entry in countedByProductId.entries)
            '${entry.key}': entry.value,
        },
      },
      bumps: {ApiTopic.stock},
    );
  }

  Future<List<StockMovementResult>> postCount(
    AuthenticatedUser actor, {
    required int countId,
    String? reason,
  }) async {
    final json = await _client.post(
      '/api/v1/stock/counts/$countId/post',
      body: {if (reason != null) 'reason': reason},
      bumps: {ApiTopic.stock, ApiTopic.finance},
    );
    return decodeList(json, 'movements', StockMovementResult.fromJson);
  }

  Future<void> discardCount(AuthenticatedUser actor, int countId) async {
    await _client.post(
      '/api/v1/stock/counts/$countId/discard',
      bumps: {ApiTopic.stock},
    );
  }

  Future<Money> varianceValue(int countId) async {
    final json = await _client.get('/api/v1/stock/counts/$countId/variance');
    final variance = json['variance'];
    if (variance is int) return Money(variance);
    throw StorageFailure(
      'The server sent a reply this version cannot read.',
      details: 'Expected integer minor units, got ${variance.runtimeType}.',
    );
  }
}

Map<String, dynamic> _object(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is Map<String, dynamic>) return value;
  throw StorageFailure(
    'The server sent a reply this version cannot read.',
    details: 'Expected an object under "$key", got ${value.runtimeType}.',
  );
}
