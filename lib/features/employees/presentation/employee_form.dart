import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/features/employees/domain/employee_models.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/form_dialog.dart';
import '../../../core/widgets/form_fields.dart';
import '../../authentication/presentation/auth_controller.dart';
import 'employees_screen.dart';

/// Create/edit form for an employee.
class EmployeeFormDialog extends ConsumerStatefulWidget {
  const EmployeeFormDialog({super.key, this.existing});

  final EmployeeListItem? existing;

  static Future<bool> show(
    BuildContext context, {
    EmployeeListItem? existing,
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => EmployeeFormDialog(existing: existing),
    );
    return saved ?? false;
  }

  @override
  ConsumerState<EmployeeFormDialog> createState() => _EmployeeFormDialogState();
}

class _EmployeeFormDialogState extends ConsumerState<EmployeeFormDialog> {
  late final TextEditingController _code;
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _designation;
  late final TextEditingController _address;
  late final TextEditingController _basicSalary;
  late final TextEditingController _notes;
  DateTime? _joiningDate;
  late EntityStatus _status;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;

    _code = TextEditingController(text: existing?.code ?? '');
    _name = TextEditingController(text: existing?.name ?? '');
    _phone = TextEditingController(text: existing?.phone ?? '');
    _designation = TextEditingController(text: existing?.designation ?? '');
    _address = TextEditingController(text: existing?.address ?? '');
    _notes = TextEditingController(text: existing?.notes ?? '');
    _basicSalary = TextEditingController();
    if (existing != null) {
      AppMoneyField.setValue(_basicSalary, existing.basicSalary);
    }
    _joiningDate = existing?.joiningDate;
    _status = existing?.status ?? EntityStatus.active;
  }

  @override
  void dispose() {
    for (final controller in [
      _code,
      _name,
      _phone,
      _designation,
      _address,
      _basicSalary,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final repository = ref.read(employeeRepositoryProvider);
    final actor = ref.read(requireCurrentUserProvider);

    final draft = EmployeeDraft(
      id: widget.existing?.id,
      code: _code.text,
      name: _name.text,
      phone: _phone.text,
      designation: _designation.text,
      address: _address.text,
      joiningDate: _joiningDate,
      basicSalary: AppMoneyField.valueOrZero(_basicSalary),
      status: _status,
      notes: _notes.text,
    );

    if (draft.isNew) {
      await repository.create(actor, draft);
    } else {
      await repository.update(actor, draft);
    }
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;

    return AppFormDialog(
      title: existing == null ? 'Add employee' : 'Edit employee',
      subtitle: existing == null
          ? 'Employees appear on expense vouchers and in the salary module.'
          : existing.hasOpenBalances
          ? 'Open balances: advances '
                '${existing.outstandingAdvances.formatted()}, unpaid salary '
                '${existing.unpaidSalaryTotal.formatted()}'
          : null,
      submitLabel: existing == null ? 'Add employee' : 'Save changes',
      width: 620,
      onSubmit: _submit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          FormSection(
            title: 'Identity',
            children: [
              FormRow(
                children: [
                  AppTextField(
                    controller: _name,
                    label: 'Employee name',
                    isRequired: true,
                    autofocus: true,
                    maxLength: 180,
                    textCapitalization: TextCapitalization.words,
                  ),
                  AppTextField(
                    controller: _code,
                    label: 'Employee code',
                    maxLength: 24,
                    helperText: existing == null
                        ? 'Leave empty to allocate one'
                        : null,
                  ),
                ],
              ),
              AppSpacing.gapLg,
              FormRow(
                children: [
                  AppTextField(
                    controller: _designation,
                    label: 'Designation',
                    maxLength: 120,
                    hintText: 'Driver',
                    textCapitalization: TextCapitalization.words,
                  ),
                  AppTextField(
                    controller: _phone,
                    label: 'Contact number',
                    maxLength: 32,
                  ),
                ],
              ),
              AppSpacing.gapLg,
              AppTextField(
                controller: _address,
                label: 'Address',
                maxLines: 2,
                maxLength: 500,
              ),
            ],
          ),
          AppSpacing.gapXl,
          FormSection(
            title: 'Employment',
            children: [
              FormRow(
                children: [
                  AppDateField(
                    value: _joiningDate,
                    label: 'Joining date',
                    onChanged: (value) => setState(() => _joiningDate = value),
                    lastDate: DateTime.now(),
                  ),
                  AppMoneyField(
                    controller: _basicSalary,
                    label: 'Basic salary',
                    helperText: 'Per month',
                  ),
                ],
              ),
            ],
          ),
          AppSpacing.gapXl,
          FormSection(
            title: 'Notes',
            children: [
              AppTextField(
                controller: _notes,
                label: 'Notes',
                maxLines: 3,
                maxLength: 1000,
              ),
            ],
          ),
          if (existing != null) ...[
            AppSpacing.gapLg,
            SwitchListTile(
              value: _status == EntityStatus.active,
              onChanged: (isActive) => setState(() {
                _status = isActive
                    ? EntityStatus.active
                    : EntityStatus.inactive;
              }),
              title: const Text('Active'),
              subtitle: const Text(
                'An inactive employee is not offered on new vouchers. Their '
                'salary history and advances are kept.',
              ),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ],
      ),
    );
  }
}
