import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/database/app_database.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/features/authentication/api/user_admin_api.dart';
import 'package:venvo_core/features/authentication/data/user_admin_repository.dart';
import 'package:venvo_core/features/authentication/domain/authenticated_user.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/feedback_views.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/status_pill.dart';
import 'auth_controller.dart';

final userAdminRepositoryProvider = Provider<UserAdminApi>(
  (ref) => UserAdminApi(ref.watch(apiClientProvider)),
);

final usersListProvider = FutureProvider<List<UserListEntry>>(
  (ref) => ref.watch(userAdminRepositoryProvider).listUsers(),
);

final rolesListProvider = FutureProvider<List<Role>>(
  (ref) => ref.watch(userAdminRepositoryProvider).listRoles(),
);

/// User and role administration.
class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(usersListProvider);
    final actor = ref.watch(currentUserProvider);
    final canManage = actor?.can(Permissions.usersManage) ?? false;

    if (!canManage) {
      return const PageScaffold(
        title: 'Users & Roles',
        child: EmptyState(
          icon: Icons.lock_outline,
          title: 'You do not have access to user administration',
        ),
      );
    }

    return PageScaffold(
      title: 'Users & Roles',
      description:
          'Each user signs in with their own account. Roles decide what they '
          'are allowed to do, and every action is recorded in the audit log.',
      scrollable: false,
      actions: [
        FilledButton.icon(
          onPressed: () => _openCreateDialog(context, ref),
          icon: const Icon(Icons.person_add_outlined, size: 18),
          label: const Text('Add user'),
        ),
      ],
      child: AsyncValueView<List<UserListEntry>>(
        value: users,
        onRetry: () => ref.invalidate(usersListProvider),
        builder: (context, data) => SectionCard(
          title: '${data.length} account(s)',
          padding: EdgeInsets.zero,
          fillHeight: true,
          child: SingleChildScrollView(child: _UsersTable(entries: data)),
        ),
      ),
    );
  }

  Future<void> _openCreateDialog(BuildContext context, WidgetRef ref) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => const _CreateUserDialog(),
    );
    if (created ?? false) {
      ref.invalidate(usersListProvider);
    }
  }
}

class _UsersTable extends ConsumerWidget {
  const _UsersTable({required this.entries});

  final List<UserListEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DataTable(
      columns: const [
        DataColumn(label: Text('Name')),
        DataColumn(label: Text('Username')),
        DataColumn(label: Text('Roles')),
        DataColumn(label: Text('Status')),
        DataColumn(label: Text('Last sign-in')),
        DataColumn(label: Text('')),
      ],
      rows: [
        for (final entry in entries)
          DataRow(
            cells: [
              DataCell(Text(entry.fullName)),
              DataCell(Text('@${entry.username}')),
              DataCell(
                Wrap(
                  spacing: AppSpacing.xs,
                  children: [
                    for (final name in entry.roleNames)
                      StatusPill(name, tone: StatusTone.info),
                  ],
                ),
              ),
              DataCell(
                Row(
                  children: [
                    StatusPill.entity(entry.status),
                    if (entry.isLockedOut) ...[
                      AppSpacing.hGapSm,
                      const StatusPill(
                        'Locked',
                        tone: StatusTone.danger,
                        icon: Icons.lock_outline,
                      ),
                    ],
                    if (entry.mustChangePassword) ...[
                      AppSpacing.hGapSm,
                      const StatusPill('Must reset', tone: StatusTone.warning),
                    ],
                  ],
                ),
              ),
              DataCell(
                Text(
                  entry.lastLoginAt == null
                      ? 'Never'
                      : DateFormat(
                          'd MMM yyyy, HH:mm',
                        ).format(entry.lastLoginAt!.toLocal()),
                ),
              ),
              DataCell(_RowActions(entry: entry)),
            ],
          ),
      ],
    );
  }
}

class _RowActions extends ConsumerWidget {
  const _RowActions({required this.entry});

  final UserListEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actor = ref.watch(requireCurrentUserProvider);

    return PopupMenuButton<String>(
      tooltip: 'Actions',
      icon: const Icon(Icons.more_horiz, size: 18),
      onSelected: (value) => _handle(context, ref, actor, value),
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'reset', child: Text('Reset password')),
        if (entry.isLockedOut)
          const PopupMenuItem(value: 'unlock', child: Text('Clear lockout')),
        const PopupMenuItem(value: 'roles', child: Text('Change roles')),
        const PopupMenuDivider(),
        if (entry.status == EntityStatus.active)
          const PopupMenuItem(value: 'disable', child: Text('Disable account'))
        else
          const PopupMenuItem(value: 'enable', child: Text('Enable account')),
      ],
    );
  }

  Future<void> _handle(
    BuildContext context,
    WidgetRef ref,
    AuthenticatedUser actor,
    String action,
  ) async {
    final repository = ref.read(userAdminRepositoryProvider);
    try {
      switch (action) {
        case 'reset':
          final password = await _promptForPassword(context, entry.username);
          if (password == null) return;
          await ref
              .read(authRepositoryProvider)
              .resetPassword(
                actor: actor,
                targetUserId: entry.id,
                temporaryPassword: password,
              );
          if (context.mounted) {
            showSuccessSnackBar(
              context,
              '${entry.fullName} must choose a new password at next sign-in.',
            );
          }
        case 'unlock':
          await repository.clearLockout(actor: actor, targetUserId: entry.id);
          if (context.mounted) {
            showSuccessSnackBar(context, 'Lockout cleared.');
          }
        case 'roles':
          final roles = await _promptForRoles(context, ref, entry);
          if (roles == null) return;
          await repository.setRoles(
            actor: actor,
            targetUserId: entry.id,
            roleCodes: roles,
          );
          if (entry.id == actor.id) {
            await ref
                .read(authControllerProvider.notifier)
                .refreshPermissions();
          }
          if (context.mounted) showSuccessSnackBar(context, 'Roles updated.');
        case 'disable':
          final confirmed = await ConfirmDialog.show(
            context,
            title: 'Disable ${entry.fullName}?',
            message:
                'They will not be able to sign in. Their past documents and '
                'audit history are kept exactly as they are.',
            confirmLabel: 'Disable',
            isDestructive: true,
            icon: Icons.block_outlined,
          );
          if (!confirmed) return;
          await repository.setStatus(
            actor: actor,
            targetUserId: entry.id,
            status: EntityStatus.inactive,
          );
        case 'enable':
          await repository.setStatus(
            actor: actor,
            targetUserId: entry.id,
            status: EntityStatus.active,
          );
      }
      ref.invalidate(usersListProvider);
    } catch (error) {
      if (context.mounted) showFailureSnackBar(context, error);
    }
  }

  Future<String?> _promptForPassword(
    BuildContext context,
    String username,
  ) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Reset password for @$username'),
        content: Form(
          key: formKey,
          child: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Give the user this temporary password. They will be asked '
                  'to choose their own the next time they sign in.',
                ),
                AppSpacing.gapLg,
                TextFormField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Temporary password',
                    helperText:
                        'At least 8 characters, with letters and numbers.',
                  ),
                  validator: (value) {
                    final text = value ?? '';
                    if (text.length < 8) return 'At least 8 characters';
                    if (!text.contains(RegExp(r'[A-Za-z]')) ||
                        !text.contains(RegExp(r'\d'))) {
                      return 'Must contain letters and numbers';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(context).pop(controller.text);
              }
            },
            child: const Text('Reset password'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<List<String>?> _promptForRoles(
    BuildContext context,
    WidgetRef ref,
    UserListEntry entry,
  ) async {
    final roles = await ref.read(rolesListProvider.future);
    final selected = entry.roleCodes.toSet();

    if (!context.mounted) return null;
    return showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Roles for ${entry.fullName}'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final role in roles)
                  CheckboxListTile(
                    value: selected.contains(role.code),
                    onChanged: (checked) => setState(() {
                      if (checked ?? false) {
                        selected.add(role.code);
                      } else {
                        selected.remove(role.code);
                      }
                    }),
                    title: Text(role.name),
                    subtitle: role.description == null
                        ? null
                        : Text(role.description!),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(selected.toList()),
              child: const Text('Save roles'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateUserDialog extends ConsumerStatefulWidget {
  const _CreateUserDialog();

  @override
  ConsumerState<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends ConsumerState<_CreateUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _selectedRoles = <String>{};
  bool _isSaving = false;

  @override
  void dispose() {
    _fullName.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_selectedRoles.isEmpty) {
      showFailureSnackBar(
        context,
        const FormatException('Select at least one role.'),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .createUser(
            actor: ref.read(requireCurrentUserProvider),
            fullName: _fullName.text,
            username: _username.text,
            password: _password.text,
            roleCodes: _selectedRoles.toList(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      showFailureSnackBar(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roles = ref.watch(rolesListProvider);

    return AlertDialog(
      title: const Text('Add user'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _fullName,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Full name'),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'Enter the full name'
                      : null,
                ),
                AppSpacing.gapLg,
                TextFormField(
                  controller: _username,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'[a-zA-Z0-9._-]'),
                    ),
                  ],
                  decoration: const InputDecoration(labelText: 'Username'),
                  validator: (value) => (value ?? '').trim().length < 3
                      ? 'At least 3 characters'
                      : null,
                ),
                AppSpacing.gapLg,
                TextFormField(
                  controller: _password,
                  decoration: const InputDecoration(
                    labelText: 'Temporary password',
                    helperText:
                        'The user chooses their own password at first sign-in.',
                  ),
                  validator: (value) {
                    final text = value ?? '';
                    if (text.length < 8) return 'At least 8 characters';
                    if (!text.contains(RegExp(r'[A-Za-z]')) ||
                        !text.contains(RegExp(r'\d'))) {
                      return 'Must contain letters and numbers';
                    }
                    return null;
                  },
                ),
                AppSpacing.gapLg,
                Text('Roles', style: context.text.titleSmall),
                AppSpacing.gapSm,
                roles.when(
                  data: (data) => Column(
                    children: [
                      for (final role in data)
                        CheckboxListTile(
                          value: _selectedRoles.contains(role.code),
                          onChanged: (checked) => setState(() {
                            if (checked ?? false) {
                              _selectedRoles.add(role.code);
                            } else {
                              _selectedRoles.remove(role.code);
                            }
                          }),
                          title: Text(role.name),
                          subtitle: role.description == null
                              ? null
                              : Text(role.description!),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                    ],
                  ),
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.lg),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  error: (error, _) => ErrorView(error: error, compact: true),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create user'),
        ),
      ],
    );
  }
}
