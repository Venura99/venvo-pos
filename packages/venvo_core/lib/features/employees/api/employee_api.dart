import '../../../core/api/api_client.dart';
import '../../../core/api/api_decode.dart';
import '../../../core/api/revision_bus.dart';
import '../../../core/database/app_database.dart';
import '../../authentication/domain/authenticated_user.dart';
import '../domain/employee_models.dart';

/// Employees over HTTP. Mirrors `EmployeeRepository`.
class EmployeeApi {
  const EmployeeApi(this._client);

  final ApiClient _client;

  /// Employees matching [filter]. Finance is watched because the list shows
  /// each employee's outstanding advance and salary position.
  Stream<List<EmployeeListItem>> watchEmployees(EmployeeFilter filter) =>
      _client.watch({ApiTopic.employees, ApiTopic.finance}, () async {
        final json = await _client.get(
          '/api/v1/employees',
          query: {
            if (filter.search.trim().isNotEmpty) 'search': filter.search.trim(),
            'designation': filter.designation,
            'includeInactive': filter.includeInactive,
            'includeArchived': filter.includeArchived,
          },
        );
        return decodeList(json, 'employees', EmployeeListItem.fromJson);
      });

  Stream<List<String>> watchDesignations() =>
      _client.watch({ApiTopic.employees}, () async {
        final json = await _client.get('/api/v1/employees/designations');
        return decodeStrings(json, 'designations');
      });

  Future<List<Employee>> selectableEmployees() async {
    final json = await _client.get('/api/v1/employees/selectable');
    return decodeList(json, 'employees', Employee.fromJson);
  }

  Future<int> create(AuthenticatedUser actor, EmployeeDraft draft) async {
    final json = await _client.post(
      '/api/v1/employees',
      body: draft.toJson(),
      bumps: {ApiTopic.employees},
    );
    return decodeId(json);
  }

  Future<void> update(AuthenticatedUser actor, EmployeeDraft draft) async {
    await _client.put(
      '/api/v1/employees/${draft.id}',
      body: draft.toJson(),
      bumps: {ApiTopic.employees},
    );
  }

  Future<void> archive(AuthenticatedUser actor, int employeeId) async {
    await _client.post(
      '/api/v1/employees/$employeeId/archive',
      bumps: {ApiTopic.employees},
    );
  }

  Future<void> restore(AuthenticatedUser actor, int employeeId) async {
    await _client.post(
      '/api/v1/employees/$employeeId/restore',
      bumps: {ApiTopic.employees},
    );
  }
}
