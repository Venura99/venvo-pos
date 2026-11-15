import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:venvo_core/core/utils/money.dart';

import '../theme/app_theme.dart';
import '../theme/design_tokens.dart';

/// Form inputs shared by every master-data form.
///
/// Each one validates the same way the repository behind it does, so a form
/// catches a mistake early without being the only thing standing between bad
/// input and the database.

/// Single-line text input with the application's label and validation
/// conventions.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.helperText,
    this.hintText,
    this.isRequired = false,
    this.maxLength,
    this.maxLines = 1,
    this.prefixIcon,
    this.autofocus = false,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.validator,
    this.onSubmitted,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final String? helperText;
  final String? hintText;
  final bool isRequired;
  final int? maxLength;
  final int maxLines;
  final IconData? prefixIcon;
  final bool autofocus;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;

  /// Runs after the required and length checks pass.
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      maxLines: maxLines,
      maxLength: maxLength,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      textInputAction: maxLines > 1
          ? TextInputAction.newline
          : TextInputAction.next,
      decoration: InputDecoration(
        labelText: isRequired ? '$label *' : label,
        helperText: helperText,
        hintText: hintText,
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: 18),
        counterText: '',
      ),
      validator: (value) {
        final text = (value ?? '').trim();
        if (isRequired && text.isEmpty) return 'Enter the $label';
        if (maxLength != null && text.length > maxLength!) {
          return 'At most $maxLength characters';
        }
        return validator?.call(value);
      },
      onFieldSubmitted: onSubmitted,
    );
  }
}

/// Monetary input. Accepts `20000`, `20,000.50` or `20 000` and resolves to an
/// exact [Money]; the text is normalised to two decimal places when the field
/// loses focus so a saved amount always reads the way it was stored.
class AppMoneyField extends StatefulWidget {
  const AppMoneyField({
    super.key,
    required this.controller,
    required this.label,
    this.helperText,
    this.isRequired = false,
    this.allowZero = true,
    this.allowNegative = false,
    this.enabled = true,
    this.autofocus = false,
    this.onChanged,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String? helperText;
  final bool isRequired;
  final bool allowZero;
  final bool allowNegative;
  final bool enabled;
  final bool autofocus;
  final ValueChanged<Money?>? onChanged;

  /// Extra rule applied once the text is known to be a valid amount.
  final String? Function(Money value)? validator;

  /// Reads the field's current value, or null when it is empty or invalid.
  static Money? valueOf(TextEditingController controller) =>
      Money.tryParse(controller.text);

  /// Reads the field's value, treating empty as zero. For optional amounts
  /// such as an opening balance.
  static Money valueOrZero(TextEditingController controller) =>
      Money.tryParse(controller.text) ?? Money.zero;

  /// Fills a controller with an amount for editing, without the currency
  /// symbol or thousands separators that would have to be stripped again.
  static void setValue(TextEditingController controller, Money value) {
    controller.text = (value.cents / Money.minorPerMajor).toStringAsFixed(2);
  }

  @override
  State<AppMoneyField> createState() => _AppMoneyFieldState();
}

class _AppMoneyFieldState extends State<AppMoneyField> {
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_normaliseOnBlur);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_normaliseOnBlur);
    _focusNode.dispose();
    super.dispose();
  }

  void _normaliseOnBlur() {
    if (_focusNode.hasFocus) return;
    final parsed = Money.tryParse(widget.controller.text);
    if (parsed == null) return;
    AppMoneyField.setValue(widget.controller, parsed);
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      focusNode: _focusNode,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      textAlign: TextAlign.right,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          widget.allowNegative ? RegExp(r'[0-9.,\-\s]') : RegExp(r'[0-9.,\s]'),
        ),
      ],
      style: AppTheme.monospacedNumbers(context.text.bodyMedium),
      decoration: InputDecoration(
        labelText: widget.isRequired ? '${widget.label} *' : widget.label,
        helperText: widget.helperText,
        prefixText: 'Rs. ',
      ),
      validator: (value) {
        final text = (value ?? '').trim();
        if (text.isEmpty) {
          return widget.isRequired ? 'Enter an amount' : null;
        }
        final parsed = Money.tryParse(text);
        if (parsed == null) return 'Enter a valid amount';
        if (!widget.allowNegative && parsed.isNegative) {
          return 'Cannot be negative';
        }
        if (!widget.allowZero && parsed.isZero) {
          return 'Must be more than zero';
        }
        return widget.validator?.call(parsed);
      },
      onChanged: (value) => widget.onChanged?.call(Money.tryParse(value)),
    );
  }
}

/// Whole-number input, for quantities, reorder levels and pack sizes.
class AppIntField extends StatelessWidget {
  const AppIntField({
    super.key,
    required this.controller,
    required this.label,
    this.helperText,
    this.isRequired = false,
    this.minimum,
    this.maximum,
    this.suffixText,
    this.enabled = true,
    this.autofocus = false,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String? helperText;
  final bool isRequired;
  final int? minimum;
  final int? maximum;
  final String? suffixText;
  final bool enabled;
  final bool autofocus;
  final ValueChanged<int?>? onChanged;

  static int? valueOf(TextEditingController controller) =>
      int.tryParse(controller.text.trim());

  static int valueOr(TextEditingController controller, int fallback) =>
      int.tryParse(controller.text.trim()) ?? fallback;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      textAlign: TextAlign.right,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: AppTheme.monospacedNumbers(context.text.bodyMedium),
      decoration: InputDecoration(
        labelText: isRequired ? '$label *' : label,
        helperText: helperText,
        suffixText: suffixText,
      ),
      validator: (value) {
        final text = (value ?? '').trim();
        if (text.isEmpty) return isRequired ? 'Enter a number' : null;
        final parsed = int.tryParse(text);
        if (parsed == null) return 'Enter a whole number';
        if (minimum != null && parsed < minimum!) {
          return 'Must be at least $minimum';
        }
        if (maximum != null && parsed > maximum!) {
          return 'Must be at most $maximum';
        }
        return null;
      },
      onChanged: (value) => onChanged?.call(int.tryParse(value.trim())),
    );
  }
}

/// Percentage input held internally as basis points, so a rate such as 12.5%
/// stays exact rather than becoming a `double`.
class AppPercentField extends StatelessWidget {
  const AppPercentField({
    super.key,
    required this.controller,
    required this.label,
    this.helperText,
    this.isRequired = false,
    this.maximumBps = 10000,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final String? helperText;
  final bool isRequired;
  final int maximumBps;
  final bool enabled;

  /// Reads the field as basis points: "12.5" becomes 1250.
  static int? bpsOf(TextEditingController controller) {
    final text = controller.text.trim();
    if (text.isEmpty) return null;
    final parsed = double.tryParse(text);
    return parsed == null ? null : (parsed * 100).round();
  }

  static void setBps(TextEditingController controller, int bps) {
    final percent = bps / 100;
    controller.text = percent == percent.roundToDouble()
        ? percent.toStringAsFixed(0)
        : percent.toString();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      textAlign: TextAlign.right,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      style: AppTheme.monospacedNumbers(context.text.bodyMedium),
      decoration: InputDecoration(
        labelText: isRequired ? '$label *' : label,
        helperText: helperText,
        suffixText: '%',
      ),
      validator: (value) {
        final text = (value ?? '').trim();
        if (text.isEmpty) return isRequired ? 'Enter a percentage' : null;
        final parsed = double.tryParse(text);
        if (parsed == null) return 'Enter a number';
        if (parsed < 0) return 'Cannot be negative';
        if ((parsed * 100).round() > maximumBps) {
          return 'Must be at most ${maximumBps / 100}%';
        }
        return null;
      },
    );
  }
}

/// Typed dropdown with the application's label conventions.
class AppDropdownField<T> extends StatelessWidget {
  const AppDropdownField({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.label,
    this.helperText,
    this.isRequired = false,
    this.enabled = true,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String label;
  final String? helperText;
  final bool isRequired;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      items: items,
      onChanged: enabled ? onChanged : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: isRequired ? '$label *' : label,
        helperText: helperText,
      ),
      validator: (selected) =>
          isRequired && selected == null ? 'Choose a $label' : null,
    );
  }
}

/// A date picker rendered as a read-only field.
class AppDateField extends StatelessWidget {
  const AppDateField({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    this.helperText,
    this.isRequired = false,
    this.firstDate,
    this.lastDate,
    this.enabled = true,
  });

  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final String label;
  final String? helperText;
  final bool isRequired;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final local = value?.toLocal();
    final text = local == null
        ? ''
        : '${local.day.toString().padLeft(2, '0')}/'
              '${local.month.toString().padLeft(2, '0')}/${local.year}';

    return InkWell(
      onTap: enabled ? () => _pick(context) : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: isRequired ? '$label *' : label,
          helperText: helperText,
          suffixIcon: value == null || !enabled
              ? const Icon(Icons.calendar_today_outlined, size: 18)
              : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () => onChanged(null),
                ),
          errorText: isRequired && value == null ? 'Choose a date' : null,
        ),
        child: Text(
          text.isEmpty ? 'Not set' : text,
          style: text.isEmpty
              ? context.text.bodyMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                )
              : context.text.bodyMedium,
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: value?.toLocal() ?? now,
      firstDate: firstDate ?? DateTime(now.year - 20),
      lastDate: lastDate ?? DateTime(now.year + 5),
    );
    if (picked != null) {
      // Stored as UTC midnight of the chosen local day, matching how every
      // other date in the database is kept.
      onChanged(DateTime(picked.year, picked.month, picked.day).toUtc());
    }
  }
}

/// Search box that waits for the user to stop typing before reporting, so a
/// query does not run on every keystroke of a long product name.
class AppSearchField extends StatefulWidget {
  const AppSearchField({
    super.key,
    required this.onChanged,
    this.hintText = 'Search',
    this.initialValue = '',
    this.width = 320,
    this.autofocus = false,
    this.debounce = const Duration(milliseconds: 220),
  });

  final ValueChanged<String> onChanged;
  final String hintText;
  final String initialValue;
  final double width;
  final bool autofocus;
  final Duration debounce;

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  late final TextEditingController _controller;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _timer?.cancel();
    _timer = Timer(widget.debounce, () => widget.onChanged(value));
    setState(() {});
  }

  void _clear() {
    _timer?.cancel();
    _controller.clear();
    widget.onChanged('');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: TextField(
        controller: _controller,
        autofocus: widget.autofocus,
        decoration: InputDecoration(
          hintText: widget.hintText,
          prefixIcon: const Icon(Icons.search, size: 18),
          suffixIcon: _controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: _clear,
                ),
        ),
        onChanged: _onChanged,
      ),
    );
  }
}
