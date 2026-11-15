import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:venvo_core/core/database/app_database.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/errors/failures.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/employees/domain/employee_models.dart';

import '../helpers/master_data_fixtures.dart';

void main() {
  late MasterDataFixture fixture;

  setUp(() async {
    fixture = await MasterDataFixture.create(at: DateTime.utc(2026, 11, 1, 9));
  });

  tearDown(() => fixture.dispose());

  Future<int> addEmployee({
    String name = 'Kamal Silva',
    String? code,
    String? designation,
    Money basicSalary = const Money(6000000),
    DateTime? joiningDate,
  }) {
    return fixture.employees.create(
      fixture.admin,
      EmployeeDraft(
        name: name,
        code: code,
        designation: designation,
        basicSalary: basicSalary,
        joiningDate: joiningDate,
      ),
    );
  }

  Future<List<EmployeeListItem>> list([
    EmployeeFilter filter = const EmployeeFilter(),
  ]) => fixture.employees.watchEmployees(filter).first;

  group('creating', () {
    test('creates an employee with an allocated code', () async {
      await addEmployee();
      final employees = await list();

      expect(employees.length, 1);
      expect(employees.single.name, 'Kamal Silva');
      expect(employees.single.code, 'EMP-00001');
      expect(employees.single.basicSalary, const Money(6000000));
      expect(employees.single.status, EntityStatus.active);
      expect(employees.single.hasOpenBalances, isFalse);
    });

    test('allocates sequential codes', () async {
      await addEmployee(name: 'First');
      await addEmployee(name: 'Second');
      expect((await list()).map((e) => e.code), ['EMP-00001', 'EMP-00002']);
    });

    test('refuses a duplicate code', () async {
      await addEmployee(name: 'First', code: 'DRV-1');
      await expectLater(
        addEmployee(name: 'Second', code: 'drv-1'),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'employee.code_unique',
          ),
        ),
      );
    });

    test('rejects a negative basic salary', () async {
      await expectLater(
        addEmployee(basicSalary: const Money(-1)),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('rejects a joining date in the future', () async {
      await expectLater(
        addEmployee(joiningDate: DateTime.utc(2027, 1, 1)),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('requires the manage-employees permission', () async {
      final viewer = await fixture.createViewer();
      await expectLater(
        fixture.employees.create(viewer, const EmployeeDraft(name: 'Nope')),
        throwsA(isA<PermissionFailure>()),
      );
    });
  });

  group('years of service', () {
    test('counts completed years from the joining date', () async {
      await addEmployee(joiningDate: DateTime.utc(2023, 10, 1));
      final employee = (await list()).single;
      expect(employee.yearsOfService(DateTime.utc(2026, 11, 1)), 3);
    });

    test('is null when no joining date is recorded', () async {
      await addEmployee();
      expect(
        (await list()).single.yearsOfService(DateTime.utc(2026, 11, 1)),
        isNull,
      );
    });
  });

  group('open balances', () {
    test('reports advances given and not yet recovered', () async {
      final employeeId = await addEmployee();

      await fixture.db
          .into(fixture.db.employeeAdvances)
          .insert(
            EmployeeAdvancesCompanion.insert(
              employeeId: employeeId,
              advanceDate: fixture.harness.clock.nowUtc(),
              amountCents: Money.fromMajor(10000).cents,
              recoveredCents: Value(Money.fromMajor(4000).cents),
              paymentMethod: PaymentMethod.cash,
              createdByUserId: fixture.admin.id,
              createdAt: fixture.harness.clock.nowUtc(),
            ),
          );

      final employee = (await list()).single;
      expect(employee.outstandingAdvances, Money.fromMajor(6000));
      expect(employee.hasOpenBalances, isTrue);
    });

    test('ignores a fully recovered advance', () async {
      final employeeId = await addEmployee();
      await fixture.db
          .into(fixture.db.employeeAdvances)
          .insert(
            EmployeeAdvancesCompanion.insert(
              employeeId: employeeId,
              advanceDate: fixture.harness.clock.nowUtc(),
              amountCents: Money.fromMajor(10000).cents,
              recoveredCents: Value(Money.fromMajor(10000).cents),
              paymentMethod: PaymentMethod.cash,
              createdByUserId: fixture.admin.id,
              createdAt: fixture.harness.clock.nowUtc(),
            ),
          );

      expect((await list()).single.outstandingAdvances, Money.zero);
    });

    test('reports salary approved but not fully paid', () async {
      final employeeId = await addEmployee();
      await fixture.db
          .into(fixture.db.salaries)
          .insert(
            SalariesCompanion.insert(
              voucherNumber: 'SAL-2026-00001',
              employeeId: employeeId,
              periodYear: 2026,
              periodMonth: 10,
              netSalaryCents: Value(Money.fromMajor(60000).cents),
              paidCents: Value(Money.fromMajor(25000).cents),
              status: const Value(SalaryStatus.partiallyPaid),
              createdByUserId: fixture.admin.id,
              createdAt: fixture.harness.clock.nowUtc(),
            ),
          );

      final employee = (await list()).single;
      expect(employee.unpaidSalaryTotal, Money.fromMajor(35000));
      expect(employee.salaryRecordCount, 1);
    });

    test('ignores a cancelled salary', () async {
      final employeeId = await addEmployee();
      await fixture.db
          .into(fixture.db.salaries)
          .insert(
            SalariesCompanion.insert(
              voucherNumber: 'SAL-2026-00001',
              employeeId: employeeId,
              periodYear: 2026,
              periodMonth: 10,
              netSalaryCents: Value(Money.fromMajor(60000).cents),
              status: const Value(SalaryStatus.cancelled),
              createdByUserId: fixture.admin.id,
              createdAt: fixture.harness.clock.nowUtc(),
            ),
          );

      final employee = (await list()).single;
      expect(employee.unpaidSalaryTotal, Money.zero);
      expect(employee.salaryRecordCount, 0);
    });
  });

  group('archiving', () {
    test('archives an employee', () async {
      final id = await addEmployee();
      await fixture.employees.archive(fixture.admin, id);

      expect(await list(), isEmpty);
      final all = await list(const EmployeeFilter(includeArchived: true));
      expect(all.single.status, EntityStatus.archived);
    });

    test('is allowed with open balances, and records them', () async {
      // Somebody leaving while still owed a salary has to be recordable;
      // refusing it would make a departure impossible to enter.
      final id = await addEmployee();
      await fixture.db
          .into(fixture.db.salaries)
          .insert(
            SalariesCompanion.insert(
              voucherNumber: 'SAL-2026-00001',
              employeeId: id,
              periodYear: 2026,
              periodMonth: 10,
              netSalaryCents: Value(Money.fromMajor(60000).cents),
              status: const Value(SalaryStatus.approved),
              createdByUserId: fixture.admin.id,
              createdAt: fixture.harness.clock.nowUtc(),
            ),
          );

      await fixture.employees.archive(fixture.admin, id);

      final all = await list(const EmployeeFilter(includeArchived: true));
      expect(all.single.status, EntityStatus.archived);
      // The balance survives the archive.
      expect(all.single.unpaidSalaryTotal, Money.fromMajor(60000));

      final entries = await fixture.auditEntries();
      final archived = entries.firstWhere(
        (entry) => entry.action == AuditAction.archive,
      );
      expect(archived.afterJson, contains('6000000'));
    });

    test('restores an archived employee', () async {
      final id = await addEmployee();
      await fixture.employees.archive(fixture.admin, id);
      await fixture.employees.restore(fixture.admin, id);
      expect((await list()).single.status, EntityStatus.active);
    });
  });

  group('filtering', () {
    setUp(() async {
      await addEmployee(name: 'Kamal Silva', designation: 'Driver');
      await addEmployee(name: 'Sunil Fernando', designation: 'Store Keeper');
      await addEmployee(name: 'Ravi Perera', designation: 'Driver');
    });

    test('searches name and designation', () async {
      expect((await list(const EmployeeFilter(search: 'kamal'))).length, 1);
      expect((await list(const EmployeeFilter(search: 'driver'))).length, 2);
    });

    test('filters by designation', () async {
      final drivers = await list(const EmployeeFilter(designation: 'Driver'));
      expect(drivers.length, 2);
    });

    test('lists the designations in use', () async {
      final designations = await fixture.employees.watchDesignations().first;
      expect(designations, ['Driver', 'Store Keeper']);
    });

    test('offers only active employees for pickers', () async {
      final employees = await list();
      await fixture.employees.archive(fixture.admin, employees.first.id);

      final selectable = await fixture.employees.selectableEmployees();
      expect(selectable.length, 2);
    });
  });

  group('updating', () {
    test('changes the designation and salary', () async {
      final id = await addEmployee(designation: 'Driver');
      await fixture.employees.update(
        fixture.admin,
        EmployeeDraft(
          id: id,
          name: 'Kamal Silva',
          designation: 'Senior Driver',
          basicSalary: Money.fromMajor(75000),
        ),
      );

      final employee = (await list()).single;
      expect(employee.designation, 'Senior Driver');
      expect(employee.basicSalary, Money.fromMajor(75000));
    });

    test('records what changed', () async {
      final id = await addEmployee(basicSalary: Money.fromMajor(60000));
      await fixture.employees.update(
        fixture.admin,
        EmployeeDraft(
          id: id,
          name: 'Kamal Silva',
          basicSalary: Money.fromMajor(65000),
        ),
      );

      final entries = await fixture.auditEntries();
      final update = entries.firstWhere(
        (entry) =>
            entry.entityKind == EntityKind.employee &&
            entry.action == AuditAction.update,
      );
      expect(update.beforeJson, contains('6000000'));
      expect(update.afterJson, contains('6500000'));
    });
  });
}
