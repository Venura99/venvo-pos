import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:venvo_core/features/inventory/api/location_api.dart';
import 'package:venvo_core/features/inventory/domain/location_models.dart';

import '../../../core/providers/core_providers.dart';

final locationRepositoryProvider = Provider<LocationApi>(
  (ref) => LocationApi(ref.watch(apiClientProvider)),
);

/// Whether the virtual counterparty locations are shown. They are hidden by
/// default because they hold no real goods - they exist so the stock ledger
/// balances.
final showVirtualLocationsProvider = StateProvider<bool>((ref) => false);

final locationsProvider = StreamProvider<List<LocationListItem>>((ref) {
  return ref
      .watch(locationRepositoryProvider)
      .watchLocations(includeVirtual: ref.watch(showVirtualLocationsProvider));
});
