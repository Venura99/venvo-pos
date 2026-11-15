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
import '../domain/shop_models.dart';

/// Reads and maintains retail shops.
///
/// Like an agent, a shop gets its own stock location in the same transaction
/// as the shop itself.
///
/// **Reassigning an agent changes one pointer and nothing else.** Historical
/// invoices, transfers and payments all store the agent they were created
/// with, so a shop can move between agents as often as the business needs
/// without any past document changing meaning. [reassignAgent] exists as its
/// own operation so that this shows up in the audit log as what it is.
class ShopRepository {
  const ShopRepository({
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

  Stream<List<ShopListItem>> watchShops(ShopFilter filter) {
    final search = filter.search.trim().toLowerCase();
    final pattern = '%$search%';

    final query = _db.customSelect(
      '''
      SELECT
        sh.*,
        loc.id AS location_id,
        ag.name AS agent_name,
        COALESCE(stock.total_units, 0) AS stock_units,
        COALESCE(stock.stock_value, 0) AS stock_value,
        COALESCE(billed.total, 0) AS billed_total,
        COALESCE(settled.total, 0) AS settled_total,
        COALESCE(credited.total, 0) AS credited_total,
        COALESCE(pending_cheques.total, 0) AS pending_cheque_total,
        COALESCE(retail.total, 0) AS retail_sales_total
      FROM shops sh
      LEFT JOIN inventory_locations loc ON loc.shop_id = sh.id
      LEFT JOIN agents ag ON ag.id = sh.assigned_agent_id
      LEFT JOIN (
        SELECT sb.location_id,
               SUM(sb.quantity) AS total_units,
               SUM(sb.quantity * sb.average_cost_cents) AS stock_value
        FROM stock_balances sb
        GROUP BY sb.location_id
      ) stock ON stock.location_id = loc.id
      LEFT JOIN (
        SELECT shop_id, SUM(net_total_cents) AS total
        FROM invoices
        WHERE status = ? AND kind = ? AND shop_id IS NOT NULL
        GROUP BY shop_id
      ) billed ON billed.shop_id = sh.id
      LEFT JOIN (
        SELECT shop_id, SUM(net_total_cents) AS total
        FROM invoices
        WHERE status = ? AND kind = ? AND shop_id IS NOT NULL
        GROUP BY shop_id
      ) retail ON retail.shop_id = sh.id
      LEFT JOIN (
        SELECT i.shop_id, SUM(pa.amount_cents) AS total
        FROM payment_allocations pa
        JOIN payments p ON p.id = pa.payment_id
        JOIN invoices i ON i.id = pa.invoice_id
        WHERE p.status = ? AND i.status = ? AND i.kind = ?
          AND i.shop_id IS NOT NULL
        GROUP BY i.shop_id
      ) settled ON settled.shop_id = sh.id
      LEFT JOIN (
        SELECT i.shop_id, SUM(cna.amount_cents) AS total
        FROM credit_note_applications cna
        JOIN credit_notes cn ON cn.id = cna.credit_note_id
        JOIN invoices i ON i.id = cna.invoice_id
        WHERE cn.status = ? AND i.status = ? AND i.shop_id IS NOT NULL
        GROUP BY i.shop_id
      ) credited ON credited.shop_id = sh.id
      LEFT JOIN (
        SELECT p.shop_id, SUM(p.amount_cents) AS total
        FROM payments p
        JOIN cheques c ON c.payment_id = p.id
        WHERE p.status = ? AND c.status IN (?, ?) AND p.shop_id IS NOT NULL
        GROUP BY p.shop_id
      ) pending_cheques ON pending_cheques.shop_id = sh.id
      WHERE (? = 1 OR sh.status <> ?)
        AND (? = 1 OR sh.status <> ?)
        AND (? = '' OR LOWER(sh.name) LIKE ? OR LOWER(sh.code) LIKE ?
             OR LOWER(COALESCE(sh.owner_name, '')) LIKE ?
             OR LOWER(COALESCE(sh.phone, '')) LIKE ?)
        AND (? IS NULL OR sh.assigned_agent_id = ?)
        AND (? = 0 OR sh.assigned_agent_id IS NULL)
        AND (? = 0 OR (
          sh.opening_balance_cents + COALESCE(billed.total, 0)
            - COALESCE(settled.total, 0) - COALESCE(credited.total, 0)
          ) > 0)
        AND (? = 0 OR (
          sh.credit_limit_cents IS NOT NULL AND sh.credit_limit_cents > 0
          AND (sh.opening_balance_cents + COALESCE(billed.total, 0)
            - COALESCE(settled.total, 0) - COALESCE(credited.total, 0))
            > sh.credit_limit_cents))
      ORDER BY sh.name
      ''',
      variables: [
        Variable<String>(InvoiceStatus.posted.name),
        Variable<String>(InvoiceKind.shopInvoice.name),
        Variable<String>(InvoiceStatus.posted.name),
        Variable<String>(InvoiceKind.retailSale.name),
        Variable<String>(PaymentStatus.cleared.name),
        Variable<String>(InvoiceStatus.posted.name),
        Variable<String>(InvoiceKind.shopInvoice.name),
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
        Variable<int>(filter.agentId),
        Variable<int>(filter.agentId),
        Variable<int>(filter.unassignedOnly ? 1 : 0),
        Variable<int>(filter.owingOnly ? 1 : 0),
        Variable<int>(filter.overCreditLimitOnly ? 1 : 0),
      ],
      readsFrom: {
        _db.shops,
        _db.agents,
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

  Future<List<Shop>> selectableShops({int? agentId}) {
    final query = _db.select(_db.shops)
      ..where((s) => s.status.equalsValue(EntityStatus.active))
      ..orderBy([(s) => OrderingTerm.asc(s.name)]);
    if (agentId != null) {
      query.where((s) => s.assignedAgentId.equals(agentId));
    }
    return query.get();
  }

  Future<int> create(AuthenticatedUser actor, ShopDraft draft) async {
    actor.require(Permissions.shopsManage, action: 'add shops');
    final name = requireText(draft.name, 'Shop name', maxLength: 180);
    _validateAmounts(draft);

    return _db.transaction(() async {
      final code = await _resolveCode(draft.code, excludingId: null);
      if (draft.assignedAgentId != null) {
        await _assertAgentUsable(draft.assignedAgentId!);
      }

      final now = _clock.nowUtc();
      final shopId = await _db
          .into(_db.shops)
          .insert(
            ShopsCompanion.insert(
              code: code,
              name: name,
              ownerName: Value(_cleanOptional(draft.ownerName)),
              phone: Value(_cleanOptional(draft.phone)),
              address: Value(_cleanOptional(draft.address)),
              assignedAgentId: Value(draft.assignedAgentId),
              openingBalanceCents: Value(draft.openingBalance.cents),
              creditLimitCents: Value(draft.creditLimit?.cents),
              status: Value(draft.status),
              notes: Value(_cleanOptional(draft.notes)),
              createdAt: now,
              updatedAt: now,
            ),
          );

      final locationId = await _locations.createForShop(
        shopId: shopId,
        shopCode: code,
        shopName: name,
      );

      await _audit.record(
        action: AuditAction.create,
        summary:
            'Created the shop "$name" ($code) with stock location '
            '#$locationId.',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.shop,
        entityId: shopId,
        after: {
          'code': code,
          'name': name,
          'assignedAgentId': draft.assignedAgentId,
          'openingBalanceCents': draft.openingBalance.cents,
          'creditLimitCents': draft.creditLimit?.cents,
        },
      );
      return shopId;
    });
  }

  Future<void> update(AuthenticatedUser actor, ShopDraft draft) async {
    actor.require(Permissions.shopsManage, action: 'edit shops');
    final id = requireFound(draft.id, 'This shop has not been saved yet.');
    final name = requireText(draft.name, 'Shop name', maxLength: 180);
    _validateAmounts(draft);

    await _db.transaction(() async {
      final existing = requireFound(
        await (_db.select(
          _db.shops,
        )..where((s) => s.id.equals(id))).getSingleOrNull(),
        'That shop no longer exists.',
      );

      final code = await _resolveCode(
        draft.code ?? existing.code,
        excludingId: id,
      );

      if (draft.assignedAgentId != null &&
          draft.assignedAgentId != existing.assignedAgentId) {
        await _assertAgentUsable(draft.assignedAgentId!);
      }
      if (draft.status == EntityStatus.archived &&
          existing.status != EntityStatus.archived) {
        await _assertArchivable(id, name);
      }

      await (_db.update(_db.shops)..where((s) => s.id.equals(id))).write(
        ShopsCompanion(
          code: Value(code),
          name: Value(name),
          ownerName: Value(_cleanOptional(draft.ownerName)),
          phone: Value(_cleanOptional(draft.phone)),
          address: Value(_cleanOptional(draft.address)),
          assignedAgentId: Value(draft.assignedAgentId),
          openingBalanceCents: Value(draft.openingBalance.cents),
          creditLimitCents: Value(draft.creditLimit?.cents),
          status: Value(draft.status),
          notes: Value(_cleanOptional(draft.notes)),
          updatedAt: Value(_clock.nowUtc()),
        ),
      );

      final location = await _locations.forShop(id);
      if (location != null) {
        if (name != existing.name) {
          await _locations.renameForParty(
            locationId: location.id,
            name: '$name (Shop)',
          );
        }
        await _locations.setActiveForParty(
          locationId: location.id,
          isActive: draft.status == EntityStatus.active,
        );
      }

      await _audit.recordUpdate(
        entityKind: EntityKind.shop,
        entityId: id,
        summary: 'Updated the shop "$name" ($code).',
        userId: actor.id,
        username: actor.username,
        before: {
          'code': existing.code,
          'name': existing.name,
          'ownerName': existing.ownerName,
          'phone': existing.phone,
          'address': existing.address,
          'assignedAgentId': existing.assignedAgentId,
          'openingBalanceCents': existing.openingBalanceCents,
          'creditLimitCents': existing.creditLimitCents,
          'status': existing.status.name,
        },
        after: {
          'code': code,
          'name': name,
          'ownerName': _cleanOptional(draft.ownerName),
          'phone': _cleanOptional(draft.phone),
          'address': _cleanOptional(draft.address),
          'assignedAgentId': draft.assignedAgentId,
          'openingBalanceCents': draft.openingBalance.cents,
          'creditLimitCents': draft.creditLimit?.cents,
          'status': draft.status.name,
        },
      );
    });
  }

  /// Moves a shop to a different agent.
  ///
  /// This is a pointer change and nothing more. Every invoice, transfer and
  /// payment already recorded keeps the agent it was created with, so agent-wise
  /// history and commission remain correct for both the old and the new agent.
  /// Pass null to leave the shop unassigned.
  Future<void> reassignAgent(
    AuthenticatedUser actor, {
    required int shopId,
    required int? agentId,
    String? reason,
  }) async {
    actor.require(Permissions.shopsManage, action: 'reassign shops');

    await _db.transaction(() async {
      final shop = requireFound(
        await (_db.select(
          _db.shops,
        )..where((s) => s.id.equals(shopId))).getSingleOrNull(),
        'That shop no longer exists.',
      );

      requireRule(
        shop.assignedAgentId != agentId,
        agentId == null
            ? 'That shop is already unassigned.'
            : 'That shop is already assigned to this agent.',
        rule: 'shop.reassign_no_op',
      );

      String? previousName;
      if (shop.assignedAgentId != null) {
        final previous = await (_db.select(
          _db.agents,
        )..where((a) => a.id.equals(shop.assignedAgentId!))).getSingleOrNull();
        previousName = previous?.name;
      }

      String? newName;
      if (agentId != null) {
        await _assertAgentUsable(agentId);
        final next = await (_db.select(
          _db.agents,
        )..where((a) => a.id.equals(agentId))).getSingle();
        newName = next.name;
      }

      await (_db.update(_db.shops)..where((s) => s.id.equals(shopId))).write(
        ShopsCompanion(
          assignedAgentId: Value(agentId),
          updatedAt: Value(_clock.nowUtc()),
        ),
      );

      await _audit.record(
        action: AuditAction.update,
        summary: agentId == null
            ? 'Unassigned "${shop.name}" from '
                  '${previousName ?? 'its agent'}. Past documents keep their '
                  'original agent.'
            : 'Reassigned "${shop.name}" from '
                  '${previousName ?? 'no agent'} to $newName. Past documents '
                  'keep their original agent.',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.shop,
        entityId: shopId,
        before: {'assignedAgentId': shop.assignedAgentId},
        after: {
          'assignedAgentId': agentId,
          if (reason != null && reason.trim().isNotEmpty)
            'reason': reason.trim(),
        },
      );
    });
  }

  Future<void> archive(AuthenticatedUser actor, int shopId) async {
    actor.require(Permissions.shopsManage, action: 'archive shops');

    await _db.transaction(() async {
      final existing = requireFound(
        await (_db.select(
          _db.shops,
        )..where((s) => s.id.equals(shopId))).getSingleOrNull(),
        'That shop no longer exists.',
      );
      await _assertArchivable(shopId, existing.name);

      await (_db.update(_db.shops)..where((s) => s.id.equals(shopId))).write(
        ShopsCompanion(
          status: const Value(EntityStatus.archived),
          updatedAt: Value(_clock.nowUtc()),
        ),
      );

      final location = await _locations.forShop(shopId);
      if (location != null) {
        await _locations.setActiveForParty(
          locationId: location.id,
          isActive: false,
        );
      }

      await _audit.record(
        action: AuditAction.archive,
        summary: 'Archived the shop "${existing.name}" (${existing.code}).',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.shop,
        entityId: shopId,
      );
    });
  }

  Future<void> restore(AuthenticatedUser actor, int shopId) async {
    actor.require(Permissions.shopsManage, action: 'restore shops');

    await _db.transaction(() async {
      final existing = requireFound(
        await (_db.select(
          _db.shops,
        )..where((s) => s.id.equals(shopId))).getSingleOrNull(),
        'That shop no longer exists.',
      );

      await (_db.update(_db.shops)..where((s) => s.id.equals(shopId))).write(
        ShopsCompanion(
          status: const Value(EntityStatus.active),
          updatedAt: Value(_clock.nowUtc()),
        ),
      );

      final location = await _locations.forShop(shopId);
      if (location != null) {
        await _locations.setActiveForParty(
          locationId: location.id,
          isActive: true,
        );
      }

      await _audit.record(
        action: AuditAction.update,
        summary: 'Restored the shop "${existing.name}" (${existing.code}).',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.shop,
        entityId: shopId,
      );
    });
  }

  // --- Rules --------------------------------------------------------------

  void _validateAmounts(ShopDraft draft) {
    require(
      !draft.openingBalance.isNegative,
      'An opening balance cannot be negative. If the shop has paid in '
      'advance, record that as a payment instead.',
      field: 'openingBalance',
    );
    final limit = draft.creditLimit;
    if (limit != null) {
      require(
        !limit.isNegative,
        'A credit limit cannot be negative.',
        field: 'creditLimit',
      );
    }
  }

  Future<void> _assertAgentUsable(int agentId) async {
    final agent = await (_db.select(
      _db.agents,
    )..where((a) => a.id.equals(agentId))).getSingleOrNull();
    requireFound(agent, 'The selected agent no longer exists.');
    requireRule(
      agent!.status == EntityStatus.active,
      'The agent "${agent.name}" is not active. Choose another one.',
      rule: 'shop.agent_active',
    );
  }

  /// A shop still holding stock cannot be archived: those goods are still the
  /// business's and still have to be accounted for.
  Future<void> _assertArchivable(int shopId, String name) async {
    final location = await _locations.forShop(shopId);
    if (location == null) return;

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
        '"$name" still holds $units unit(s) of stock, so it cannot be '
        'archived.',
        details: 'Return the stock to the agent or the warehouse first.',
        rule: 'shop.no_stock_when_archiving',
      );
    }
  }

  Future<String> _resolveCode(
    String? requested, {
    required int? excludingId,
  }) async {
    final provided = (requested ?? '').trim().toUpperCase();
    if (provided.isEmpty) {
      return _sequences.nextNumber(SequenceKeys.shopCode, resetsYearly: false);
    }

    require(
      RegExp(r'^[A-Z0-9][A-Z0-9._\-/]*$').hasMatch(provided),
      'A shop code may contain letters, numbers, dots, hyphens, underscores '
      'and slashes.',
      field: 'code',
    );

    final query = _db.select(_db.shops)
      ..where((s) => s.code.lower().equals(provided.toLowerCase()));
    if (excludingId != null) {
      query.where((s) => s.id.isNotValue(excludingId));
    }
    final clash = await query.getSingleOrNull();
    requireRule(
      clash == null,
      'The shop code "$provided" is already used by "${clash?.name}".',
      rule: 'shop.code_unique',
    );
    return provided;
  }

  static ShopListItem _mapRow(QueryRow row) {
    final settled =
        Money(row.read<int>('settled_total')) +
        Money(row.read<int>('credited_total'));
    final creditLimitCents = row.readNullable<int>('credit_limit_cents');

    return ShopListItem(
      id: row.read<int>('id'),
      code: row.read<String>('code'),
      name: row.read<String>('name'),
      ownerName: row.readNullable<String>('owner_name'),
      phone: row.readNullable<String>('phone'),
      address: row.readNullable<String>('address'),
      assignedAgentId: row.readNullable<int>('assigned_agent_id'),
      assignedAgentName: row.readNullable<String>('agent_name'),
      openingBalance: Money(row.read<int>('opening_balance_cents')),
      creditLimit: creditLimitCents == null ? null : Money(creditLimitCents),
      status: EntityStatus.values.byName(row.read<String>('status')),
      notes: row.readNullable<String>('notes'),
      locationId: row.readNullable<int>('location_id'),
      stockUnits: row.read<int>('stock_units'),
      stockValueAtCost: Money(row.read<int>('stock_value')),
      billedTotal: Money(row.read<int>('billed_total')),
      settledTotal: settled,
      pendingChequeTotal: Money(row.read<int>('pending_cheque_total')),
      retailSalesTotal: Money(row.read<int>('retail_sales_total')),
    );
  }

  static String? _cleanOptional(String? value) {
    final text = (value ?? '').trim();
    return text.isEmpty ? null : text;
  }
}
