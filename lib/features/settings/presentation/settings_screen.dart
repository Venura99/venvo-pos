import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:venvo_core/core/constants/app_constants.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/payments/data/cheque_reminders.dart'
    show ChequeReminderService;

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/widgets/feedback_views.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/section_card.dart';
import '../../authentication/presentation/auth_controller.dart';
import '../../payments/presentation/cheque_photo.dart'
    show chequeExtrasApiProvider;
import 'logo_editor.dart';

/// Business details, operating policies and appearance.
///
/// The policy values here are read by the stock and billing services on every
/// posting, so changing them changes behaviour immediately rather than only
/// what is displayed.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _taxId;
  late final TextEditingController _footer;
  late final TextEditingController _maxInvoiceDiscount;
  late final TextEditingController _maxItemDiscount;
  late final TextEditingController _backupRetention;
  late final TextEditingController _whatsappNumbers;
  late final TextEditingController _reminderDays;

  bool _allowNegativeStock = false;
  bool _testing = false;
  bool _autoBackup = true;
  bool _isSaving = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsServiceProvider);

    String read(String key, [String fallback = '']) =>
        settings.getStringSync(key) ?? fallback;

    _name = _controller(
      read(SettingKeys.businessName, AppConstants.companyName),
    );
    _address = _controller(read(SettingKeys.businessAddress));
    _phone = _controller(read(SettingKeys.businessPhone));
    _email = _controller(read(SettingKeys.businessEmail));
    _taxId = _controller(read(SettingKeys.businessTaxId));
    _footer = _controller(read(SettingKeys.invoiceFooterNote));
    _maxInvoiceDiscount = _controller(
      formatBps(
        settings.getIntSync(SettingKeys.maxInvoiceDiscountBps, fallback: 1000),
      ).replaceAll('%', ''),
    );
    _maxItemDiscount = _controller(
      formatBps(
        settings.getIntSync(SettingKeys.maxItemDiscountBps, fallback: 1500),
      ).replaceAll('%', ''),
    );
    _backupRetention = _controller(
      settings
          .getIntSync(SettingKeys.autoBackupRetentionCount, fallback: 14)
          .toString(),
    );
    _whatsappNumbers = _controller(read(SettingKeys.whatsappAdminNumbers));
    _reminderDays = _controller(
      settings
          .getIntSync(SettingKeys.chequeReminderDaysBefore, fallback: 1)
          .toString(),
    );
    _allowNegativeStock = settings.getBoolSync(SettingKeys.allowNegativeStock);
    _autoBackup = settings.getBoolSync(
      SettingKeys.autoBackupEnabled,
      fallback: true,
    );
  }

  TextEditingController _controller(String value) {
    final controller = TextEditingController(text: value);
    controller.addListener(_markChanged);
    return controller;
  }

  void _markChanged() {
    if (!_hasChanges) setState(() => _hasChanges = true);
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _address,
      _phone,
      _email,
      _taxId,
      _footer,
      _maxInvoiceDiscount,
      _maxItemDiscount,
      _backupRetention,
      _whatsappNumbers,
      _reminderDays,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSaving = true);
    final settings = ref.read(settingsServiceProvider);

    try {
      // One request for the whole form. The server applies them together,
      // writes the audit entry itself, and refuses the lot if any one value is
      // wrong — so the form can never end up half saved.
      await settings.update({
        SettingKeys.businessName: _name.text.trim(),
        SettingKeys.businessAddress: _address.text.trim(),
        SettingKeys.businessPhone: _phone.text.trim(),
        SettingKeys.businessEmail: _email.text.trim(),
        SettingKeys.businessTaxId: _taxId.text.trim(),
        SettingKeys.invoiceFooterNote: _footer.text.trim(),
        SettingKeys.maxInvoiceDiscountBps: _bpsFromPercentText(
          _maxInvoiceDiscount.text,
        ),
        SettingKeys.maxItemDiscountBps: _bpsFromPercentText(
          _maxItemDiscount.text,
        ),
        SettingKeys.allowNegativeStock: _allowNegativeStock,
        SettingKeys.autoBackupEnabled: _autoBackup,
        SettingKeys.autoBackupRetentionCount:
            int.tryParse(_backupRetention.text.trim()) ?? 14,
        // Stored as typed: the server cleans the numbers when it uses them,
        // so what the administrator sees here is what they entered.
        SettingKeys.whatsappAdminNumbers: _whatsappNumbers.text.trim(),
        SettingKeys.chequeReminderDaysBefore:
            int.tryParse(_reminderDays.text.trim()) ?? 1,
      });

      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _hasChanges = false;
      });
      showSuccessSnackBar(context, 'Settings saved.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      showFailureSnackBar(context, error);
    }
  }

  /// Sends a sample reminder to every saved number and reports each result,
  /// so a wrong number or missing server setup shows up now rather than on
  /// the day a cheque is due.
  Future<void> _sendTest() async {
    setState(() => _testing = true);
    try {
      final results = await ref
          .read(chequeExtrasApiProvider)
          .sendTestReminder();
      if (!mounted) return;
      await _showReport('Test message', [
        for (final result in results)
          result['delivered'] == true
              ? '+${result['to']}: sent'
              : '+${result['to']}: NOT sent — ${result['error'] ?? 'no reason given'}',
      ]);
    } catch (error) {
      if (mounted) showFailureSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _runReminders() async {
    setState(() => _testing = true);
    try {
      final result = await ref.read(chequeExtrasApiProvider).runReminders();
      if (!mounted) return;
      final skippedLine =
          '${result['skipped']} already sent earlier, or given up after '
          '${ChequeReminderService.maxAttempts} failed attempts.';
      await _showReport('Cheque reminders', [
        '${result['due']} cheque(s) due within the reminder window.',
        '${result['sent']} message(s) sent, ${result['failed']} failed.',
        skippedLine,
        if (result['notConfigured'] != null)
          'Nothing was sent: ${result['notConfigured']}.',
      ]);
    } catch (error) {
      if (mounted) showFailureSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _showReport(String title, List<String> lines) =>
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (lines.isEmpty) const Text('No numbers are saved.'),
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text(line),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final canManage = user?.can(Permissions.settingsManage) ?? false;
    final themeMode = ref.watch(themeModeProvider);

    if (!canManage) {
      return const PageScaffold(
        title: 'Settings',
        child: EmptyState(
          icon: Icons.lock_outline,
          title: 'You do not have access to settings',
          message: 'Ask an administrator for the "Manage settings" permission.',
        ),
      );
    }

    return PageScaffold(
      title: 'Settings',
      description:
          'Business details print on invoices. Policies are enforced when '
          'documents are posted.',
      maxContentWidth: 900,
      actions: [
        FilledButton.icon(
          onPressed: _isSaving || !_hasChanges ? null : _save,
          icon: _isSaving
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined, size: 18),
          label: Text(_hasChanges ? 'Save changes' : 'Saved'),
        ),
      ],
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionCard(
              title: 'Business details',
              subtitle: 'Printed on invoices, delivery notes and receipts.',
              child: Column(
                children: [
                  const LogoEditor(canEdit: true),
                  AppSpacing.gapLg,
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(
                      labelText: 'Business name',
                    ),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? 'Enter the business name'
                        : null,
                  ),
                  AppSpacing.gapLg,
                  TextFormField(
                    controller: _address,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Address'),
                  ),
                  AppSpacing.gapLg,
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _phone,
                          decoration: const InputDecoration(labelText: 'Phone'),
                        ),
                      ),
                      AppSpacing.hGapLg,
                      Expanded(
                        child: TextFormField(
                          controller: _email,
                          decoration: const InputDecoration(labelText: 'Email'),
                          validator: (value) {
                            final text = (value ?? '').trim();
                            if (text.isEmpty) return null;
                            return text.contains('@')
                                ? null
                                : 'Enter a valid email address';
                          },
                        ),
                      ),
                      AppSpacing.hGapLg,
                      Expanded(
                        child: TextFormField(
                          controller: _taxId,
                          decoration: const InputDecoration(
                            labelText: 'Tax / VAT no.',
                          ),
                        ),
                      ),
                    ],
                  ),
                  AppSpacing.gapLg,
                  TextFormField(
                    controller: _footer,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Invoice footer note',
                      helperText: 'Appears at the bottom of printed documents.',
                    ),
                  ),
                ],
              ),
            ),
            AppSpacing.gapXl,
            SectionCard(
              title: 'Inventory policy',
              subtitle: 'Applied whenever a stock document is posted.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile(
                    value: _allowNegativeStock,
                    onChanged: (value) => setState(() {
                      _allowNegativeStock = value;
                      _hasChanges = true;
                    }),
                    title: const Text('Allow stock to go negative'),
                    subtitle: const Text(
                      'Off is strongly recommended. When off, a movement that '
                      'would take a real location below zero is refused, and '
                      'only a user with the override permission can post it '
                      'anyway - which is then recorded on the document.',
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            AppSpacing.gapXl,
            SectionCard(
              title: 'Discount limits',
              subtitle:
                  'The most an ordinary user may grant. A user with the '
                  '"exceed discount limit" permission can authorise more, and '
                  'every such case is recorded in the discount history.',
              child: Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _maxInvoiceDiscount,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Maximum invoice discount',
                        suffixText: '%',
                      ),
                      validator: _validatePercent,
                    ),
                  ),
                  AppSpacing.hGapLg,
                  Expanded(
                    child: TextFormField(
                      controller: _maxItemDiscount,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Maximum item discount',
                        suffixText: '%',
                      ),
                      validator: _validatePercent,
                    ),
                  ),
                ],
              ),
            ),
            AppSpacing.gapXl,
            SectionCard(
              title: 'Backups',
              subtitle:
                  'Backups are taken on the server, once a day when the first '
                  'person signs in. They are listed under Backups.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile(
                    value: _autoBackup,
                    onChanged: (value) => setState(() {
                      _autoBackup = value;
                      _hasChanges = true;
                    }),
                    title: const Text('Automatic daily backup'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  AppSpacing.gapMd,
                  SizedBox(
                    width: 240,
                    child: TextFormField(
                      controller: _backupRetention,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Backups to keep',
                      ),
                      validator: (value) {
                        final count = int.tryParse((value ?? '').trim());
                        if (count == null || count < 1) {
                          return 'Keep at least 1';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
            ),
            AppSpacing.gapXl,
            SectionCard(
              title: 'Cheque reminders on WhatsApp',
              subtitle:
                  'Before a cheque date comes, a WhatsApp message about it is '
                  'sent to each number below — once per cheque. The server '
                  'checks every hour.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _whatsappNumbers,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'WhatsApp numbers',
                      helperText:
                          'One per line, or separated by commas. 0771234567 '
                          'or 94771234567 both work.',
                    ),
                    validator: (value) {
                      final text = (value ?? '').trim();
                      if (text.isEmpty) return null;
                      return ChequeReminderService.parseNumbers(text).isEmpty
                          ? 'Enter at least one full phone number'
                          : null;
                    },
                  ),
                  AppSpacing.gapLg,
                  SizedBox(
                    width: 240,
                    child: TextFormField(
                      controller: _reminderDays,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Days before the cheque date',
                        helperText: '0 means on the day itself',
                      ),
                      validator: (value) {
                        final days = int.tryParse((value ?? '').trim());
                        if (days == null || days < 0 || days > 30) {
                          return 'Between 0 and 30';
                        }
                        return null;
                      },
                    ),
                  ),
                  AppSpacing.gapLg,
                  Wrap(
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _hasChanges || _testing ? null : _sendTest,
                        icon: const Icon(Icons.send_outlined, size: 18),
                        label: Text(
                          _testing ? 'Sending…' : 'Send a test message',
                        ),
                      ),
                      if (user?.can(Permissions.chequeManage) ?? false)
                        OutlinedButton.icon(
                          onPressed: _hasChanges || _testing
                              ? null
                              : _runReminders,
                          icon: const Icon(
                            Icons.notifications_active_outlined,
                            size: 18,
                          ),
                          label: const Text('Send due reminders now'),
                        ),
                      if (_hasChanges)
                        Text(
                          'Save your changes first.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            AppSpacing.gapXl,
            SectionCard(
              title: 'Appearance',
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode_outlined, size: 16),
                    label: Text('Light'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode_outlined, size: 16),
                    label: Text('Dark'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.brightness_auto_outlined, size: 16),
                    label: Text('Follow device'),
                  ),
                ],
                selected: {themeMode},
                onSelectionChanged: (selection) =>
                    ref.read(themeModeProvider.notifier).set(selection.first),
              ),
            ),
            AppSpacing.gapXl,
            _DataLocationCard(),
          ],
        ),
      ),
    );
  }

  static String? _validatePercent(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Enter a percentage';
    final parsed = double.tryParse(text);
    if (parsed == null) return 'Enter a number';
    if (parsed < 0 || parsed > 100) return 'Between 0 and 100';
    return null;
  }

  /// Percent text to basis points, exactly: "12.5" becomes 1250.
  static int _bpsFromPercentText(String text) {
    final parsed = double.tryParse(text.trim()) ?? 0;
    return (parsed * 100).round();
  }
}

/// Shows where the data actually lives. With every device sharing one
/// server, the honest answer is "not on this device".
class _DataLocationCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final server = ref.watch(apiClientProvider).baseUrl.toString();

    return SectionCard(
      title: 'Where your data is stored',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Server', style: context.text.titleSmall),
          const SizedBox(height: AppSpacing.xxs),
          SelectableText(server, style: context.text.bodySmall),
          AppSpacing.gapMd,
          Text(
            'Nothing is kept on this device. Every device signed in to this '
            'server sees the same data, and backups are taken on the server: '
            'see Backup & Restore.',
            style: context.text.bodySmall,
          ),
        ],
      ),
    );
  }
}
