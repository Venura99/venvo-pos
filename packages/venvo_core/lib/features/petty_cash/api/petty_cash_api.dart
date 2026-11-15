import '../../../core/api/api_client.dart';
import '../../../core/api/api_decode.dart';
import '../../../core/api/revision_bus.dart';
import '../../../core/errors/failures.dart';
import '../../../core/utils/money.dart';
import '../../authentication/domain/authenticated_user.dart';
import '../domain/petty_cash_models.dart';

/// The petty cash float over HTTP. Mirrors `PettyCashService`.
///
/// `appendEntry` is deliberately absent. It is how the expense service writes
/// the float entry that pays for an expense, inside that expense's own
/// transaction; exposing it would let a client add a float movement with no
/// expense behind it, which is exactly the hole the float is meant to close.
class PettyCashApi {
  const PettyCashApi(this._client);

  final ApiClient _client;

  Stream<List<PettyCashRow>> watchEntries(PettyCashFilter filter) =>
      _client.watch({ApiTopic.finance}, () async {
        final json = await _client.get(
          '/api/v1/petty-cash',
          query: _query(filter),
        );
        return decodeList(json, 'entries', PettyCashRow.fromJson);
      });

  Future<PettyCashSnapshot> snapshot(PettyCashFilter filter) async {
    final json = await _client.get(
      '/api/v1/petty-cash/snapshot',
      query: _query(filter),
    );
    return PettyCashSnapshot.fromJson(_object(json, 'snapshot'));
  }

  /// The float as it stands, or as it stood at [asOf].
  Future<Money> floatBalance({DateTime? asOf}) async {
    final json = await _client.get(
      '/api/v1/petty-cash/float',
      query: {'asOf': asOf},
    );
    return _money(json, 'float');
  }

  Future<int> recordEntry(AuthenticatedUser actor, PettyCashDraft draft) async {
    final json = await _client.post(
      '/api/v1/petty-cash',
      body: draft.toJson(),
      bumps: {ApiTopic.finance},
    );
    return decodeId(json);
  }

  /// Replays the entries and rewrites each running balance. Returns how many
  /// rows changed; zero is the expected answer.
  Future<int> recomputeBalances(AuthenticatedUser actor) async {
    final json = await _client.post(
      '/api/v1/petty-cash/recompute',
      bumps: {ApiTopic.finance},
    );
    final changed = json['rowsChanged'];
    if (changed is int) return changed;
    throw StorageFailure(
      'The server sent a reply this version cannot read.',
      details: 'Expected an integer "rowsChanged".',
    );
  }

  /// Entries whose stored running balance disagrees with a replay of the
  /// book. Always empty unless something has gone wrong; shown rather than
  /// assumed.
  Future<List<({String voucherNumber, Money stored, Money replayed})>>
  findBalanceDiscrepancies() async {
    final json = await _client.get('/api/v1/petty-cash/discrepancies');
    final raw = json['discrepancies'];
    if (raw is! List) {
      throw StorageFailure(
        'The server sent a reply this version cannot read.',
        details: 'Expected a list under "discrepancies".',
      );
    }
    return [
      for (final entry in raw.cast<Map<String, Object?>>())
        (
          voucherNumber: entry['voucherNumber']! as String,
          stored: Money(entry['stored']! as int),
          replayed: Money(entry['replayed']! as int),
        ),
    ];
  }

  static Map<String, Object?> _query(PettyCashFilter filter) => {
    if (filter.search.trim().isNotEmpty) 'search': filter.search.trim(),
    'kind': filter.kind?.name,
    'from': filter.from,
    'to': filter.to,
    'limit': filter.limit,
  };
}

Map<String, dynamic> _object(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is Map<String, dynamic>) return value;
  throw StorageFailure(
    'The server sent a reply this version cannot read.',
    details: 'Expected an object under "$key", got ${value.runtimeType}.',
  );
}

Money _money(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) return Money(value);
  throw StorageFailure(
    'The server sent a reply this version cannot read.',
    details: 'Expected integer minor units under "$key".',
  );
}
