import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';

/// Standard layout for a module page: an optional title block with actions,
/// then the body, inside consistent page padding.
///
/// Pages that own their own scrolling pass [scrollable] as false and manage it
/// themselves, which is what data tables need.
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.child,
    this.title,
    this.description,
    this.actions = const [],
    this.scrollable = true,
    this.padding = AppSpacing.page,
    this.maxContentWidth,
  });

  final Widget child;
  final String? title;
  final String? description;
  final List<Widget> actions;
  final bool scrollable;
  final EdgeInsetsGeometry padding;

  /// Caps the content width so long forms do not stretch across a wide
  /// monitor into unreadable line lengths.
  final double? maxContentWidth;

  @override
  Widget build(BuildContext context) {
    final hasHeader =
        title != null || description != null || actions.isNotEmpty;

    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: scrollable ? MainAxisSize.min : MainAxisSize.max,
      children: [
        if (hasHeader) ...[
          _PageHeader(title: title, description: description, actions: actions),
          AppSpacing.gapLg,
        ],
        if (scrollable) child else Expanded(child: child),
      ],
    );

    if (maxContentWidth != null) {
      content = Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxContentWidth!),
          child: content,
        ),
      );
    }

    if (!scrollable) {
      return Padding(padding: padding, child: content);
    }

    return SingleChildScrollView(padding: padding, child: content);
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({this.title, this.description, this.actions = const []});

  final String? title;
  final String? description;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (title != null)
                Text(title!, style: context.text.headlineSmall),
              if (description != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  description!,
                  style: context.text.bodyMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (actions.isNotEmpty) ...[
          AppSpacing.hGapLg,
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: actions,
          ),
        ],
      ],
    );
  }
}
