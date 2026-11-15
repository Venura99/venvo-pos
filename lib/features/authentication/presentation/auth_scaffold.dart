import 'package:flutter/material.dart';

import 'package:venvo_core/core/constants/app_constants.dart';
import '../../../core/theme/design_tokens.dart';

/// Centred card layout shared by the sign-in, first-run and change-password
/// screens, with the product identity on the left on wide windows.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.footer,
    this.maxWidth = 440,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? footer;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final showBranding = MediaQuery.sizeOf(context).width >= 980;

    return Scaffold(
      body: Row(
        children: [
          if (showBranding) const Expanded(flex: 5, child: _BrandingPanel()),
          Expanded(
            flex: 6,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!showBranding) ...[const _Logo(), AppSpacing.gapXl],
                      Text(title, style: context.text.headlineMedium),
                      AppSpacing.gapSm,
                      Text(
                        subtitle,
                        style: context.text.bodyMedium?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                      AppSpacing.gapXl,
                      child,
                      if (footer != null) ...[AppSpacing.gapXl, footer!],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandingPanel extends StatelessWidget {
  const _BrandingPanel();

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, scheme.primaryContainer],
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.xxxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Logo(onPrimary: true),
          AppSpacing.gapXl,
          Text(
            'Wholesale operations,\nend to end.',
            style: context.text.displaySmall?.copyWith(
              color: scheme.onPrimary,
              height: 1.2,
            ),
          ),
          AppSpacing.gapLg,
          Text(
            'Warehouse, agents and shops in one stock ledger. Invoices, '
            'collections, cheques and returns that always add up.',
            style: context.text.bodyLarge?.copyWith(
              color: scheme.onPrimary.withValues(alpha: 0.86),
              height: 1.5,
            ),
          ),
          AppSpacing.gapXl,
          Row(
            children: [
              Icon(
                Icons.cloud_done_outlined,
                size: 18,
                color: scheme.onPrimary.withValues(alpha: 0.9),
              ),
              AppSpacing.hGapSm,
              Text(
                'Same data on every device, kept safely on the server',
                style: context.text.bodySmall?.copyWith(
                  color: scheme.onPrimary.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({this.onPrimary = false});

  final bool onPrimary;

  @override
  Widget build(BuildContext context) {
    final foreground = onPrimary
        ? context.colors.onPrimary
        : context.colors.onSurface;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 40,
          width: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: onPrimary
                ? context.colors.onPrimary.withValues(alpha: 0.18)
                : context.colors.primary,
            borderRadius: AppRadii.mdAll,
          ),
          child: Text(
            'V',
            style: context.text.titleLarge?.copyWith(
              color: onPrimary
                  ? context.colors.onPrimary
                  : context.colors.onPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        AppSpacing.hGapMd,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppConstants.appName,
              style: context.text.titleLarge?.copyWith(color: foreground),
            ),
            Text(
              AppConstants.companyName,
              style: context.text.bodySmall?.copyWith(
                color: onPrimary
                    ? context.colors.onPrimary.withValues(alpha: 0.8)
                    : context.colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
