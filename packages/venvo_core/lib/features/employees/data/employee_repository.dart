import 'package:drift/drift.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/permissions.dart';
import '../../../core/database/app_database.dart';
import '../../../core/enums/app_enums.dart';
import '../../../core/errors/guards.dart';
import '../../../core/services/audit_service.dart';
import '../../../core/services/clock.dart';
import '../../../core/services/sequence_service.dart';
import '../../../core/utils/money.dart';
import '../../authentication/domain/authenticated_user.dart';
import '../domain/employee_models.dart';

/// Reads and maintains employees.
///
/// Unlike agents and shops, an employee holds no stock, so there is no
/// location to create. An employee *can* leave owing an advance or owed a
/// salary, so archiving is allowed with open balances: refusing it would make
/// it impossible to record that somebody left. The figures are surfaced before
/// the archive is confirmed, and the balances stay on the record afterwards.
class EmployeeRepository {
  const EmployeeRepository({
    required AppDatabase database,
    required Clock clock,
    required AuditService audit,
    required SequenceService sequences,
  }) : _db = database,
       _clock = clock,
       _audit = audit,
       _sequences = sequences;

  final AppDatabase _db;
  final Clock _clock;
  final AuditService _audit;
  final SequenceService _sequences;

  Stream<List<EmployeeListItem>> watchEmployees(EmployeeFilter filter) {
    final search = filter.search.trim().toLowerCase();
    final pattern = '%$search%';

    final query = _db.customSelect(
      '''
      SELECT
        e.*,
        COALESCE(advances.outstanding, 0) AS outstanding_advances,
        COALESCE(salaries.unpaid, 0) AS unpaid_salary_total,
        COALESCE(salaries.record_count, 0) AS salary_record_count
      FROM employees e
      LEFT JOIN (
        SELECT employee_id,
               SUM(amount_cents - recovered_cents) AS outstanding
        FROM employee_advances
        WHERE amount_cents > recovered_cents
        GROUP BY employee_id
      ) advances ON advances.employee_id = e.id
      LEFT JOIN (
        SELECT employee_id,
               SUM(net_salary_cents - paid_cents) AS unpaid,
               COUNT(*) AS record_count
        FROM salaries
        WHERE status <> ?
        GROUP BY employee_id
      ) salaries ON salaries.employee_id = e.id
      WHERE (? = 1 OR e.status <> ?)
        AND (? = 1 OR e.status <> ?)
        AND (? = '' OR LOWER(e.name) LIKE ? OR LOWER(e.code) LIKE ?
             OR LOWER(COALESCE(e.phone, '')) LIKE ?
             OR LOWER(COALESCE(e.designation, '')) LIKE ?)
        AND (? IS NULL OR e.designation = ?)
      ORDER BY e.name
      ''',
      variables: [
        Variable<String>(SalaryStatus.cancelled.name),
        Variable<int>(filter.includeArchived ? 1 : 0),
        Variable<String>(EntityStatus.archived.name),
        Variable<int>(filter.includeInactive ? 1 : 0),
        Variable<String>(EntityStatus.inactive.name),
        Variable<String>(search),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<String>(filter.designation),
        Variable<String>(filter.designation),
      ],
      readsFrom: {_db.employees, _db.employeeAdvances, _db.salaries},
    );

    return query.watch().map(
      (rows) => rows.map(_mapRow).toList(growable: false),
    );
  }

  /// Designations currently in use, for the filter dropdown.
  Stream<List<String>> watchDesignations() {
    return _db
        .customSelect(
          'SELECT DISTINCT designation FROM employees '
          'WHERE designation IS NOT NULL AND TRIM(designation) <> ? '
          'ORDER BY designation',
          variables: const [Variable<String>('')],
          readsFrom: {_db.employees},
        )
        .watch()
        .map(
          (rows) => rows
              .map((row) => row.read<String>('designation'))
              .toList(growable: false),
        );
  }

  /// Active employees, for pickers on expense and salary documents.
  Future<List<Employee>> selectableEmployees() {
    return (_db.select(_db.employees)
          ..where((e) => e.status.equalsValue(EntityStatus.active))
          ..orderBy([(e) => OrderingTerm.asc(e.name)]))
        .get();
  }

  Future<int> create(AuthenticatedUser actor, EmployeeDraft draft) async {
    actor.require(Permissions.employeesManage, action: 'add employees');
    final name = requireText(draft.name, 'Employee name', maxLength: 180);
    _validate(draft);

    return _db.transaction(() async {
      final code = await _resolveCode(draft.code, excludingId: null);
      final now = _clock.nowUtc();

      final id = await _db
          .into(_db.employees)
          .insert(
            EmployeesCompanion.insert(
              code: code,
              name: name,
              phone: Value(_cleanOptional(draft.phone)),
              address: Value(_cleanOptional(draft.address)),
              designation: Value(_cleanOptional(draft.designation)),
              joiningDate: Value(draft.joiningDate),
              basicSalaryCents: Value(draft.basicSalary.cents),
              status: Value(draft.status),
              notes: Value(_cleanOptional(draft.notes)),
              createdAt: now,
              updatedAt: now,
            ),
          );

      await _audit.record(
        action: AuditAction.create,
        summary: 'Created the employee "$name" ($code).',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.employee,
        entityId: id,
        after: {
          'code': code,
          'name': name,
          'designation': _cleanOptional(draft.designation),
          'basicSalaryCents': draft.basicSalary.cents,
        },
      );
      return id;
    });
  }

  Future<void> update(AuthenticatedUser actor, EmployeeDraft draft) async {
    actor.require(Permissions.employeesManage, action: 'edit employees');
    final id = requireFound(draft.id, 'This employee has not been saved yet.');
    final name = requireText(draft.name, 'Employee name', maxLength: 180);
    _validate(draft);

    await _db.transaction(() async {
      final existing = requireFound(
        await (_db.select(
          _db.employees,
        )..where((e) => e.id.equals(id))).getSingleOrNull(),
        'That employee no longer exists.',
      );

      final code = await _resolveCode(
        draft.code ?? existing.code,
        excludingId: id,
      );

      await (_db.update(_db.employees)..where((e) => e.id.equals(id))).write(
        EmployeesCompanion(
          code: Value(code),
          name: Value(name),
          phone: Value(_cleanOptional(draft.phone)),
          address: Value(_cleanOptional(draft.address)),
          designation: Value(_cleanOptional(draft.designation)),
          joiningDate: Value(draft.joiningDate),
          basicSalaryCents: Value(draft.basicSalary.cents),
          status: Value(draft.status),
          notes: Value(_cleanOptional(draft.notes)),
          updatedAt: Value(_clock.nowUtc()),
        ),
      );

      await _audit.recordUpdate(
        entityKind: EntityKind.employee,
        entityId: id,
        summary: 'Updated the employee "$name" ($code).',
        userId: actor.id,
        username: actor.username,
        before: {
          'code': existing.code,
          'name': existing.name,
          'phone': existing.phone,
          'designation': existing.designation,
          'joiningDate': existing.joiningDate,
          'basicSalaryCents': existing.basicSalaryCents,
          'status': existing.status.name,
        },
        after: {
          'code': code,
          'name': name,
          'phone': _cleanOptional(draft.phone),
          'designation': _cleanOptional(draft.designation),
          'joiningDate': draft.joiningDate,
          'basicSalaryCents': draft.basicSalary.cents,
          'status': draft.status.name,
        },
      );
    });
  }

  /// Archives an employee. Allowed with open balances - somebody leaving while
  /// still owed a salary is normal - and the balances are recorded in the
  /// audit entry so the figures at the moment of departure are preserved.
  Future<void> archive(AuthenticatedUser actor, int employeeId) async {
    actor.require(Permissions.employeesManage, action: 'archive employees');

    await _db.transaction(() async {
      final existing = requireFound(
        await (_db.select(
          _db.employees,
        )..where((e) => e.id.equals(employeeId))).getSingleOrNull(),
        'That employee no longer exists.',
      );

      await (_db.update(
        _db.employees,
      )..where((e) => e.id.equals(employeeId))).write(
        EmployeesCompanion(
          status: const Value(EntityStatus.archived),
          updatedAt: Value(_clock.nowUtc()),
        ),
      );

      final balances = await _openBalances(employeeId);
      await _audit.record(
        action: AuditAction.archive,
        summary:
            'Archived the employee "${existing.name}" '
            '(${existing.code}).',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.employee,
        entityId: employeeId,
        after: {
          'outstandingAdvancesCents': balances.$1.cents,
          'unpaidSalaryCents': balances.$2.cents,
        },
      );
    });
  }

  Future<void> restore(AuthenticatedUser actor, int employeeId) async {
    actor.require(Permissions.employeesManage, action: 'restore employees');

    final existing = requireFound(
      await (_db.select(
        _db.employees,
      )..where((e) => e.id.equals(employeeId))).getSingleOrNull(),
      'That employee no longer exists.',
    );

    await (_db.update(
      _db.employees,
    )..where((e) => e.id.equals(employeeId))).write(
      EmployeesCompanion(
        status: const Value(EntityStatus.active),
        updatedAt: Value(_clock.nowUtc()),
      ),
    );

    await _audit.record(
      action: AuditAction.update,
      summary: 'Restored the employee "${existing.name}" (${existing.code}).',
      userId: actor.id,
      username: actor.username,
      entityKind: EntityKind.employee,
      entityId: employeeId,
    );
  }

  // --- Rules --------------------------------------------------------------

  void _validate(EmployeeDraft draft) {
    require(
      !draft.basicSalary.isNegative,
      'A basic salary cannot be negative.',
      field: 'basicSalary',
    );
    final joined = draft.joiningDate;
    if (joined != null) {
      require(
        !joined.isAfter(_clock.nowUtc().add(const Duration(days: 1))),
        'A joining date cannot be in the future.',
        field: 'joiningDate',
      );
    }
  }

  /// Outstanding advances and unpaid salary, as a pair.
  Future<(Money, Money)> _openBalances(int employeeId) async {
    final row = await _db
        .customSelect(
          '''
      SELECT
        COALESCE((
          SELECT SUM(amount_cents - recovered_cents) FROM employee_advances
          WHERE employee_id = ? AND amount_cents > recovered_cents
        ), 0) AS advances,
        COALESCE((
          SELECT SUM(net_salary_cents - paid_cents) FROM salaries
          WHERE employee_id = ? AND status <> ?
        ), 0) AS unpaid
      ''',
          variables: [
            Variable<int>(employeeId),
            Variable<int>(employeeId),
            Variable<String>(SalaryStatus.cancelled.name),
          ],
          readsFrom: {_db.employeeAdvances, _db.salaries},
        )
        .getSingle();

    return (Money(row.read<int>('advances')), Money(row.read<int>('unpaid')));
  }

  Future<String> _resolveCode(
    String? requested, {
    required int? excludingId,
  }) async {
    final provided = (requested ?? '').trim().toUpperCase();
    if (provided.isEmpty) {
      return _sequences.nextNumber(
        SequenceKeys.employeeCode,
        resetsYearly: false,
      );
    }

    require(
      RegExp(r'^[A-Z0-9][A-Z0-9._\-/]*$').hasMatch(provided),
      'An employee code may contain letters, numbers, dots, hyphens, '
      'underscores and slashes.',
      field: 'code',
    );

    final query = _db.select(_db.employees)
      ..where((e) => e.code.lower().equals(provided.toLowerCase()));
    if (excludingId != null) {
      query.where((e) => e.id.isNotValue(excludingId));
    }
    final clash = await query.getSingleOrNull();
    requireRule(
      clash == null,
      'The employee code "$provided" is already used by "${clash?.name}".',
      rule: 'employee.code_unique',
    );
    return provided;
  }

  static EmployeeListItem _mapRow(QueryRow row) => EmployeeListItem(
    id: row.read<int>('id'),
    code: row.read<String>('code'),
    name: row.read<String>('name'),
    phone: row.readNullable<String>('phone'),
    address: row.readNullable<String>('address'),
    designation: row.readNullable<String>('designation'),
    joiningDate: row.readNullable<DateTime>('joining_date'),
    basicSalary: Money(row.read<int>('basic_salary_cents')),
    status: EntityStatus.values.byName(row.read<String>('status')),
    notes: row.readNullable<String>('notes'),
    outstandingAdvances: Money(row.read<int>('outstanding_advances')),
    unpaidSalaryTotal: Money(row.read<int>('unpaid_salary_total')),
    salaryRecordCount: row.read<int>('salary_record_count'),
  );

  static String? _cleanOptional(String? value) {
    final text = (value ?? '').trim();
    return text.isEmpty ? null : text;
  }
}
