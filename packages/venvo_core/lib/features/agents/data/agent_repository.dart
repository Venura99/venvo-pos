import 'package:drift/drift.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/permissions.dart';
import '../../../core/database/app_database.dart';
import '../../../core/enums/app_enums.dart';
import '../../../core/errors/failures.dart';
import '../../../core/errors/guards.dart';
import '../../../core/services/audit_service.dart';
import '../../../core/services/clock.dart';
import '../../../core/services/sequence_service.dart';
import '../../../core/utils/money.dart';
import '../../authentication/domain/authenticated_user.dart';
import '../../inventory/data/location_repository.dart';
import '../domain/agent_models.dart';

/// Reads and maintains agents.
///
/// Creating an agent also creates the stock location that agent holds goods
/// in, **in the same transaction**. An agent without a location would be an
/// agent nothing could be transferred to, so the two either both exist or
/// neither does.
///
/// The outstanding balance is computed the same way everywhere in the
/// application: opening balance, plus posted invoices, less what *cleared*
/// payments and posted credit notes have settled. A pending cheque is
/// reported separately and never counted as settlement.
class AgentRepository {
  const AgentRepository({
    required AppDatabase database,
    required Clock clock,
    required AuditService audit,
    required SequenceService sequences,
    required LocationRepository locations,
  }) : _db = database,
       _clock = clock,
       _audit = audit,
       _sequences = sequences,
       _locations = locations;

  final AppDatabase _db;
  final Clock _clock;
  final AuditService _audit;
  final SequenceService _sequences;
  final LocationRepository _locations;

  Stream<List<AgentListItem>> watchAgents(AgentFilter filter) {
    final search = filter.search.trim().toLowerCase();
    final pattern = '%$search%';

    final query = _db.customSelect(
      '''
      SELECT
        a.*,
        loc.id AS location_id,
        (
          SELECT COUNT(*) FROM shops s
          WHERE s.assigned_agent_id = a.id AND s.status = ?
        ) AS active_shop_count,
        COALESCE(stock.total_units, 0) AS stock_units,
        COALESCE(stock.stock_value, 0) AS stock_value,
        COALESCE(billed.total, 0) AS billed_total,
        COALESCE(settled.total, 0) AS settled_total,
        COALESCE(credited.total, 0) AS credited_total,
        COALESCE(pending_cheques.total, 0) AS pending_cheque_total
      FROM agents a
      LEFT JOIN inventory_locations loc ON loc.agent_id = a.id
      LEFT JOIN (
        SELECT sb.location_id,
               SUM(sb.quantity) AS total_units,
               SUM(sb.quantity * sb.average_cost_cents) AS stock_value
        FROM stock_balances sb
        GROUP BY sb.location_id
      ) stock ON stock.location_id = loc.id
      LEFT JOIN (
        SELECT agent_id, SUM(net_total_cents) AS total
        FROM invoices
        WHERE status = ? AND party_type = ? AND agent_id IS NOT NULL
        GROUP BY agent_id
      ) billed ON billed.agent_id = a.id
      LEFT JOIN (
        SELECT i.agent_id, SUM(pa.amount_cents) AS total
        FROM payment_allocations pa
        JOIN payments p ON p.id = pa.payment_id
        JOIN invoices i ON i.id = pa.invoice_id
        WHERE p.status = ? AND i.status = ? AND i.agent_id IS NOT NULL
        GROUP BY i.agent_id
      ) settled ON settled.agent_id = a.id
      LEFT JOIN (
        SELECT i.agent_id, SUM(cna.amount_cents) AS total
        FROM credit_note_applications cna
        JOIN credit_notes cn ON cn.id = cna.credit_note_id
        JOIN invoices i ON i.id = cna.invoice_id
        WHERE cn.status = ? AND i.status = ? AND i.agent_id IS NOT NULL
        GROUP BY i.agent_id
      ) credited ON credited.agent_id = a.id
      LEFT JOIN (
        SELECT p.agent_id, SUM(p.amount_cents) AS total
        FROM payments p
        JOIN cheques c ON c.payment_id = p.id
        WHERE p.status = ? AND c.status IN (?, ?) AND p.agent_id IS NOT NULL
        GROUP BY p.agent_id
      ) pending_cheques ON pending_cheques.agent_id = a.id
      WHERE (? = 1 OR a.status <> ?)
        AND (? = 1 OR a.status <> ?)
        AND (? = '' OR LOWER(a.name) LIKE ? OR LOWER(a.code) LIKE ?
             OR LOWER(COALESCE(a.phone, '')) LIKE ?
             OR LOWER(COALESCE(a.nic, '')) LIKE ?)
        AND (? = 0 OR (
          a.opening_balance_cents + COALESCE(billed.total, 0)
            - COALESCE(settled.total, 0) - COALESCE(credited.total, 0)
          ) > 0)
      ORDER BY a.name
      ''',
      variables: [
        Variable<String>(EntityStatus.active.name),
        Variable<String>(InvoiceStatus.posted.name),
        Variable<String>(PartyType.agent.name),
        Variable<String>(PaymentStatus.cleared.name),
        Variable<String>(InvoiceStatus.posted.name),
        Variable<String>(InvoiceStatus.posted.name),
        Variable<String>(InvoiceStatus.posted.name),
        Variable<String>(PaymentStatus.pending.name),
        Variable<String>(ChequeStatus.pending.name),
        Variable<String>(ChequeStatus.deposited.name),
        Variable<int>(filter.includeArchived ? 1 : 0),
        Variable<String>(EntityStatus.archived.name),
        Variable<int>(filter.includeInactive ? 1 : 0),
        Variable<String>(EntityStatus.inactive.name),
        Variable<String>(search),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<int>(filter.owingOnly ? 1 : 0),
      ],
      readsFrom: {
        _db.agents,
        _db.shops,
        _db.inventoryLocations,
        _db.stockBalances,
        _db.invoices,
        _db.payments,
        _db.paymentAllocations,
        _db.creditNotes,
        _db.creditNoteApplications,
        _db.cheques,
      },
    );

    return query.watch().map(
      (rows) => rows.map(_mapRow).toList(growable: false),
    );
  }

  /// Active agents, for pickers on documents and on the shop form.
  Future<List<Agent>> selectableAgents() {
    return (_db.select(_db.agents)
          ..where((a) => a.status.equalsValue(EntityStatus.active))
          ..orderBy([(a) => OrderingTerm.asc(a.name)]))
        .get();
  }

  /// Creates an agent and the stock location that belongs to them.
  Future<int> create(AuthenticatedUser actor, AgentDraft draft) async {
    actor.require(Permissions.agentsManage, action: 'add agents');
    final name = requireText(draft.name, 'Agent name', maxLength: 180);
    _validateOptionalFields(draft);

    return _db.transaction(() async {
      final code = await _resolveCode(draft.code, excludingId: null);
      final now = _clock.nowUtc();

      final agentId = await _db
          .into(_db.agents)
          .insert(
            AgentsCompanion.insert(
              code: code,
              name: name,
              phone: Value(_cleanOptional(draft.phone)),
              address: Value(_cleanOptional(draft.address)),
              nic: Value(_cleanOptional(draft.nic)),
              commissionBps: Value(draft.commissionBps),
              openingBalanceCents: Value(draft.openingBalance.cents),
              status: Value(draft.status),
              notes: Value(_cleanOptional(draft.notes)),
              createdAt: now,
              updatedAt: now,
            ),
          );

      // Same transaction: an agent is never left without a stock location.
      final locationId = await _locations.createForAgent(
        agentId: agentId,
        agentCode: code,
        agentName: name,
      );

      await _audit.record(
        action: AuditAction.create,
        summary:
            'Created the agent "$name" ($code) with stock location '
            '#$locationId.',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.agent,
        entityId: agentId,
        after: {
          'code': code,
          'name': name,
          'openingBalanceCents': draft.openingBalance.cents,
          'commissionBps': draft.commissionBps,
        },
      );
      return agentId;
    });
  }

  Future<void> update(AuthenticatedUser actor, AgentDraft draft) async {
    actor.require(Permissions.agentsManage, action: 'edit agents');
    final id = requireFound(draft.id, 'This agent has not been saved yet.');
    final name = requireText(draft.name, 'Agent name', maxLength: 180);
    _validateOptionalFields(draft);

    await _db.transaction(() async {
      final existing = requireFound(
        await (_db.select(
          _db.agents,
        )..where((a) => a.id.equals(id))).getSingleOrNull(),
        'That agent no longer exists.',
      );

      final code = await _resolveCode(
        draft.code ?? existing.code,
        excludingId: id,
      );

      if (draft.status == EntityStatus.archived &&
          existing.status != EntityStatus.archived) {
        await _assertArchivable(id, name);
      }

      // Changing the opening balance changes the agent's outstanding balance
      // directly, so it is worth its own guard and its own audit entry.
      if (draft.openingBalance.cents != existing.openingBalanceCents) {
        actor.require(
          Permissions.agentsManage,
          action: 'change an opening balance',
        );
      }

      await (_db.update(_db.agents)..where((a) => a.id.equals(id))).write(
        AgentsCompanion(
          code: Value(code),
          name: Value(name),
          phone: Value(_cleanOptional(draft.phone)),
          address: Value(_cleanOptional(draft.address)),
          nic: Value(_cleanOptional(draft.nic)),
          commissionBps: Value(draft.commissionBps),
          openingBalanceCents: Value(draft.openingBalance.cents),
          status: Value(draft.status),
          notes: Value(_cleanOptional(draft.notes)),
          updatedAt: Value(_clock.nowUtc()),
        ),
      );

      // The location follows the agent's name and active state, so stock
      // reports never show a stale name.
      final location = await _locations.forAgent(id);
      if (location != null) {
        if (name != existing.name) {
          await _locations.renameForParty(
            locationId: location.id,
            name: '$name (Agent)',
          );
        }
        await _locations.setActiveForParty(
          locationId: location.id,
          isActive: draft.status == EntityStatus.active,
        );
      }

      await _audit.recordUpdate(
        entityKind: EntityKind.agent,
        entityId: id,
        summary: 'Updated the agent "$name" ($code).',
        userId: actor.id,
        username: actor.username,
        before: {
          'code': existing.code,
          'name': existing.name,
          'phone': existing.phone,
          'address': existing.address,
          'nic': existing.nic,
          'commissionBps': existing.commissionBps,
          'openingBalanceCents': existing.openingBalanceCents,
          'status': existing.status.name,
        },
        after: {
          'code': code,
          'name': name,
          'phone': _cleanOptional(draft.phone),
          'address': _cleanOptional(draft.address),
          'nic': _cleanOptional(draft.nic),
          'commissionBps': draft.commissionBps,
          'openingBalanceCents': draft.openingBalance.cents,
          'status': draft.status.name,
        },
      );
    });
  }

  Future<void> archive(AuthenticatedUser actor, int agentId) async {
    actor.require(Permissions.agentsManage, action: 'archive agents');

    await _db.transaction(() async {
      final existing = requireFound(
        await (_db.select(
          _db.agents,
        )..where((a) => a.id.equals(agentId))).getSingleOrNull(),
        'That agent no longer exists.',
      );
      await _assertArchivable(agentId, existing.name);

      await (_db.update(_db.agents)..where((a) => a.id.equals(agentId))).write(
        AgentsCompanion(
          status: const Value(EntityStatus.archived),
          updatedAt: Value(_clock.nowUtc()),
        ),
      );

      final location = await _locations.forAgent(agentId);
      if (location != null) {
        await _locations.setActiveForParty(
          locationId: location.id,
          isActive: false,
        );
      }

      await _audit.record(
        action: AuditAction.archive,
        summary: 'Archived the agent "${existing.name}" (${existing.code}).',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.agent,
        entityId: agentId,
      );
    });
  }

  Future<void> restore(AuthenticatedUser actor, int agentId) async {
    actor.require(Permissions.agentsManage, action: 'restore agents');

    await _db.transaction(() async {
      final existing = requireFound(
        await (_db.select(
          _db.agents,
        )..where((a) => a.id.equals(agentId))).getSingleOrNull(),
        'That agent no longer exists.',
      );

      await (_db.update(_db.agents)..where((a) => a.id.equals(agentId))).write(
        AgentsCompanion(
          status: const Value(EntityStatus.active),
          updatedAt: Value(_clock.nowUtc()),
        ),
      );

      final location = await _locations.forAgent(agentId);
      if (location != null) {
        await _locations.setActiveForParty(
          locationId: location.id,
          isActive: true,
        );
      }

      await _audit.record(
        action: AuditAction.update,
        summary: 'Restored the agent "${existing.name}" (${existing.code}).',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.agent,
        entityId: agentId,
      );
    });
  }

  // --- Rules --------------------------------------------------------------

  void _validateOptionalFields(AgentDraft draft) {
    final commission = draft.commissionBps;
    if (commission != null) {
      require(
        commission >= 0 && commission <= Money.bpsScale,
        'Commission must be between 0% and 100%.',
        field: 'commission',
      );
    }
    require(
      !draft.openingBalance.isNegative,
      'An opening balance cannot be negative. If the agent has paid in '
      'advance, record that as a payment instead.',
      field: 'openingBalance',
    );
  }

  /// An agent still holding stock, or still responsible for active shops,
  /// cannot be archived: the stock would be stranded in a location nobody can
  /// select, and the shops would be left without an agent.
  Future<void> _assertArchivable(int agentId, String name) async {
    final location = await _locations.forAgent(agentId);
    if (location != null) {
      final row = await _db
          .customSelect(
            'SELECT COALESCE(SUM(quantity), 0) AS units FROM stock_balances '
            'WHERE location_id = ?',
            variables: [Variable<int>(location.id)],
            readsFrom: {_db.stockBalances},
          )
          .getSingle();
      final units = row.read<int>('units');
      if (units != 0) {
        throw BusinessRuleFailure(
          '"$name" is still holding $units unit(s) of stock, so they cannot '
          'be archived.',
          details: 'Return the stock to the warehouse first.',
          rule: 'agent.no_stock_when_archiving',
        );
      }
    }

    final shops =
        await (_db.select(_db.shops)..where(
              (s) =>
                  s.assignedAgentId.equals(agentId) &
                  s.status.equalsValue(EntityStatus.active),
            ))
            .get();
    if (shops.isNotEmpty) {
      throw BusinessRuleFailure(
        '"$name" is still responsible for ${shops.length} active shop(s), so '
        'they cannot be archived.',
        details:
            'Reassign ${shops.map((s) => s.name).take(5).join(', ')} '
            'to another agent first.',
        rule: 'agent.no_active_shops_when_archiving',
      );
    }
  }

  /// Returns the code to store: the one given, or a freshly allocated one.
  Future<String> _resolveCode(
    String? requested, {
    required int? excludingId,
  }) async {
    final provided = (requested ?? '').trim().toUpperCase();
    if (provided.isEmpty) {
      return _sequences.nextNumber(SequenceKeys.agentCode, resetsYearly: false);
    }

    require(
      RegExp(r'^[A-Z0-9][A-Z0-9._\-/]*$').hasMatch(provided),
      'An agent code may contain letters, numbers, dots, hyphens, '
      'underscores and slashes.',
      field: 'code',
    );

    final query = _db.select(_db.agents)
      ..where((a) => a.code.lower().equals(provided.toLowerCase()));
    if (excludingId != null) {
      query.where((a) => a.id.isNotValue(excludingId));
    }
    final clash = await query.getSingleOrNull();
    requireRule(
      clash == null,
      'The agent code "$provided" is already used by "${clash?.name}".',
      rule: 'agent.code_unique',
    );
    return provided;
  }

  static AgentListItem _mapRow(QueryRow row) {
    final settled =
        Money(row.read<int>('settled_total')) +
        Money(row.read<int>('credited_total'));

    return AgentListItem(
      id: row.read<int>('id'),
      code: row.read<String>('code'),
      name: row.read<String>('name'),
      phone: row.readNullable<String>('phone'),
      address: row.readNullable<String>('address'),
      nic: row.readNullable<String>('nic'),
      commissionBps: row.readNullable<int>('commission_bps'),
      openingBalance: Money(row.read<int>('opening_balance_cents')),
      status: EntityStatus.values.byName(row.read<String>('status')),
      notes: row.readNullable<String>('notes'),
      locationId: row.readNullable<int>('location_id'),
      activeShopCount: row.read<int>('active_shop_count'),
      stockUnits: row.read<int>('stock_units'),
      stockValueAtCost: Money(row.read<int>('stock_value')),
      billedTotal: Money(row.read<int>('billed_total')),
      settledTotal: settled,
      pendingChequeTotal: Money(row.read<int>('pending_cheque_total')),
    );
  }

  static String? _cleanOptional(String? value) {
    final text = (value ?? '').trim();
    return text.isEmpty ? null : text;
  }
}
