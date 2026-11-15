import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:venvo_core/features/inventory/api/stock_api.dart';
import 'package:venvo_core/features/inventory/domain/stock_models.dart';
import 'package:venvo_core/features/products/domain/product_models.dart';

import '../../../core/providers/core_providers.dart';
import '../../products/presentation/products_screen.dart';
import 'location_providers.dart';

final stockLedgerServiceProvider = Provider<StockLedgerApi>(
  (ref) => StockLedgerApi(ref.watch(apiClientProvider)),
);

final stockQueryRepositoryProvider = Provider<StockQueryApi>(
  (ref) => StockQueryApi(ref.watch(apiClientProvider)),
);

final stockCountRepositoryProvider = Provider<StockCountApi>(
  (ref) => StockCountApi(ref.watch(apiClientProvider)),
);

// --- Stock overview --------------------------------------------------------

final stockOverviewFilterProvider = StateProvider<StockOverviewFilter>(
  (ref) => const StockOverviewFilter(),
);

final productStockProvider = StreamProvider<List<ProductStockRow>>((ref) {
  return ref
      .watch(stockQueryRepositoryProvider)
      .watchProductStock(ref.watch(stockOverviewFilterProvider));
});

// --- Movement history ------------------------------------------------------

final stockLedgerFilterProvider = StateProvider<StockLedgerFilter>(
  (ref) => const StockLedgerFilter(),
);

final stockLedgerProvider = StreamProvider<List<StockLedgerRow>>((ref) {
  return ref
      .watch(stockQueryRepositoryProvider)
      .watchLedger(ref.watch(stockLedgerFilterProvider));
});

// --- Document register -----------------------------------------------------

final stockDocumentFilterProvider = StateProvider<StockDocumentFilter>(
  (ref) => const StockDocumentFilter(),
);

final stockDocumentsProvider = StreamProvider<List<StockDocumentSummary>>((
  ref,
) {
  return ref
      .watch(stockQueryRepositoryProvider)
      .watchDocuments(ref.watch(stockDocumentFilterProvider));
});

/// One document with its lines, for the view dialog.
final stockDocumentDetailProvider =
    FutureProvider.family<StockDocumentDetail, int>((ref, transactionId) {
      // Re-read whenever the register changes, so a cancellation is reflected.
      ref.watch(stockDocumentsProvider);
      return ref
          .watch(stockQueryRepositoryProvider)
          .documentDetail(transactionId);
    });

// --- Per-location stock ----------------------------------------------------

/// What one location is holding. Used by the line editor to show what is
/// available before somebody tries to move more than there is.
final locationStockProvider = StreamProvider.family<List<StockBalanceRow>, int>(
  (ref, locationId) {
    return ref
        .watch(stockQueryRepositoryProvider)
        .watchLocationStock(locationId);
  },
);

/// Quantity available per product at a location, keyed by product id.
final availableAtLocationProvider = Provider.family<Map<int, int>, int>((
  ref,
  locationId,
) {
  final rows =
      ref.watch(locationStockProvider(locationId)).valueOrNull ??
      const <StockBalanceRow>[];
  return {for (final row in rows) row.productId: row.quantity};
});

// --- Products for the pickers ---------------------------------------------

/// Every active product, independent of whatever filter the catalogue screen
/// happens to have applied.
final allActiveProductsProvider = StreamProvider<List<ProductListItem>>((ref) {
  return ref
      .watch(productRepositoryProvider)
      .watchProducts(const ProductFilter());
});

// --- Reconciliation --------------------------------------------------------

final stockCountsProvider = StreamProvider<List<StockCountSheet>>((ref) {
  return ref.watch(stockCountRepositoryProvider).watchCounts();
});

/// The count currently open in the reconciliation screen.
final selectedStockCountIdProvider = StateProvider<int?>((ref) => null);

final selectedStockCountProvider = FutureProvider<StockCountSheet?>((
  ref,
) async {
  final countId = ref.watch(selectedStockCountIdProvider);
  if (countId == null) return null;
  // Re-read when the list changes, so posting refreshes the open sheet.
  ref.watch(stockCountsProvider);
  return ref.watch(stockCountRepositoryProvider).loadCount(countId);
});

/// Real, active locations that can be a source or destination on a document.
final stockLocationsProvider = Provider((ref) {
  final locations = ref.watch(locationsProvider).valueOrNull ?? const [];
  return locations.where((location) => location.isActive).toList();
});
