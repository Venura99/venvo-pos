import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';

/// A titled panel. The standard container for a form, a table or a group of
/// related figures.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.padding = AppSpacing.card,
    this.child,
    this.slivers,
    this.fillHeight = false,
  }) : assert(
         child != null || slivers != null || title != null,
         'A card has to show something: a child, slivers, or at least a '
         'title. A title with a subtitle and no body is a banner, which is a '
         'legitimate use; a card with none of the three is a mistake.',
       );

  final String? title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final EdgeInsetsGeometry padding;
  final Widget? child;
  final List<Widget>? slivers;

  /// Set when the child is a table or a scrolling list that should take the
  /// space the card is given.
  ///
  /// This matters more than it looks: a [Column] lays its non-flex children
  /// out with an *unbounded* main-axis extent, whatever constraints the Column
  /// itself received. So a table containing an `Expanded`, or a `ListView`
  /// that needs a bounded height, fails to lay out unless it is given a flex
  /// slot here. Forms and figure blocks want the default, which shrink-wraps.
  final bool fillHeight;

  @override
  Widget build(BuildContext context) {
    final hasHeader = title != null || subtitle != null || actions.isNotEmpty;
    final body = Padding(padding: padding, child: child);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: fillHeight ? MainAxisSize.max : MainAxisSize.min,
        children: [
          if (hasHeader)
            _Header(
              title: title,
              subtitle: subtitle,
              leading: leading,
              actions: actions,
            ),
          // Only draw the rule when there is a body under it to separate.
          if (hasHeader && (child != null || slivers != null))
            const Divider(height: 1),
          if (child != null)
            if (fillHeight) Expanded(child: body) else body
          else if (slivers != null)
            Flexible(child: CustomScrollView(slivers: slivers!)),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
  });

  final String? title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          if (leading != null) ...[leading!, AppSpacing.hGapMd],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title != null)
                  Text(title!, style: context.text.titleMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(subtitle!, style: context.text.bodySmall),
                ],
              ],
            ),
          ),
          if (actions.isNotEmpty)
            Wrap(
              spacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actions,
            ),
        ],
      ),
    );
  }
}
