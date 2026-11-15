import 'package:flutter/material.dart';

/// The design system's primitives.
///
/// Every screen composes from these rather than hardcoding numbers, which is
/// what keeps spacing and corner radii consistent across twenty modules.

class AppSpacing {
  const AppSpacing._();

  /// 4px grid. Desktop data entry is dense, so the common steps are small.
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  /// Standard page padding for a content area inside the shell.
  static const EdgeInsets page = EdgeInsets.fromLTRB(xl, lg, xl, xl);

  /// Padding inside a card or panel.
  static const EdgeInsets card = EdgeInsets.all(lg);

  /// Vertical rhythm between stacked sections.
  static const SizedBox gapXs = SizedBox(height: xs);
  static const SizedBox gapSm = SizedBox(height: sm);
  static const SizedBox gapMd = SizedBox(height: md);
  static const SizedBox gapLg = SizedBox(height: lg);
  static const SizedBox gapXl = SizedBox(height: xl);

  static const SizedBox hGapSm = SizedBox(width: sm);
  static const SizedBox hGapMd = SizedBox(width: md);
  static const SizedBox hGapLg = SizedBox(width: lg);
  static const SizedBox hGapXl = SizedBox(width: xl);
}

class AppRadii {
  const AppRadii._();

  static const double sm = 6;
  static const double md = 10;
  static const double lg = 14;
  static const double xl = 20;
  static const double pill = 999;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));
}

/// Fixed dimensions of the application shell.
class AppLayout {
  const AppLayout._();

  static const double sidebarExpandedWidth = 252;
  static const double sidebarCollapsedWidth = 72;
  static const double topBarHeight = 60;

  /// Below this width the sidebar collapses to icons automatically.
  static const double sidebarCollapseBreakpoint = 1280;

  /// Below this width dashboard KPI cards stack into fewer columns.
  static const double compactBreakpoint = 1024;

  /// Height of a row in a data table. Compact but still comfortably clickable.
  static const double tableRowHeight = 44;
  static const double tableHeaderHeight = 40;
}

/// Brand and semantic colours.
///
/// A single seed drives the Material 3 scheme; the status colours are defined
/// separately because "paid", "pending" and "bounced" must stay recognisable
/// and must not shift when the brand colour is retuned.
class AppColors {
  const AppColors._();

  /// Deep teal: readable on white, calm under long use, distinct from the
  /// red/amber/green used for status.
  static const Color brandSeed = Color(0xFF13616B);
  static const Color brandAccent = Color(0xFFB8860B);

  static const Color success = Color(0xFF1B7F3B);
  static const Color successContainer = Color(0xFFD7F0DE);
  static const Color warning = Color(0xFFA9680C);
  static const Color warningContainer = Color(0xFFFDEBCF);
  static const Color danger = Color(0xFFB3261E);
  static const Color dangerContainer = Color(0xFFFADAD7);
  static const Color info = Color(0xFF1B5E9E);
  static const Color infoContainer = Color(0xFFD9E7F7);
  static const Color neutral = Color(0xFF5A6570);
  static const Color neutralContainer = Color(0xFFE8EBEE);

  static const Color successDark = Color(0xFF6FD08C);
  static const Color warningDark = Color(0xFFF0B860);
  static const Color dangerDark = Color(0xFFF2B8B5);
  static const Color infoDark = Color(0xFF8FBDF0);
  static const Color neutralDark = Color(0xFFB4BDC6);
}

/// Status colour pairs resolved for the current brightness, exposed on
/// [ThemeData] through [AppStatusColors].
@immutable
class AppStatusColors extends ThemeExtension<AppStatusColors> {
  const AppStatusColors({
    required this.success,
    required this.onSuccessContainer,
    required this.successContainer,
    required this.warning,
    required this.onWarningContainer,
    required this.warningContainer,
    required this.danger,
    required this.onDangerContainer,
    required this.dangerContainer,
    required this.info,
    required this.onInfoContainer,
    required this.infoContainer,
    required this.neutral,
    required this.onNeutralContainer,
    required this.neutralContainer,
  });

  factory AppStatusColors.light() => const AppStatusColors(
    success: AppColors.success,
    successContainer: AppColors.successContainer,
    onSuccessContainer: Color(0xFF09411D),
    warning: AppColors.warning,
    warningContainer: AppColors.warningContainer,
    onWarningContainer: Color(0xFF53330A),
    danger: AppColors.danger,
    dangerContainer: AppColors.dangerContainer,
    onDangerContainer: Color(0xFF5F1410),
    info: AppColors.info,
    infoContainer: AppColors.infoContainer,
    onInfoContainer: Color(0xFF0E3357),
    neutral: AppColors.neutral,
    neutralContainer: AppColors.neutralContainer,
    onNeutralContainer: Color(0xFF333B43),
  );

  factory AppStatusColors.dark() => const AppStatusColors(
    success: AppColors.successDark,
    successContainer: Color(0xFF18442A),
    onSuccessContainer: Color(0xFFBFEFCD),
    warning: AppColors.warningDark,
    warningContainer: Color(0xFF4A3410),
    onWarningContainer: Color(0xFFFBE0B6),
    danger: AppColors.dangerDark,
    dangerContainer: Color(0xFF5A1B18),
    onDangerContainer: Color(0xFFFBD9D6),
    info: AppColors.infoDark,
    infoContainer: Color(0xFF17344F),
    onInfoContainer: Color(0xFFCFE1F6),
    neutral: AppColors.neutralDark,
    neutralContainer: Color(0xFF353B41),
    onNeutralContainer: Color(0xFFDDE2E7),
  );

  final Color success;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color danger;
  final Color dangerContainer;
  final Color onDangerContainer;
  final Color info;
  final Color infoContainer;
  final Color onInfoContainer;
  final Color neutral;
  final Color neutralContainer;
  final Color onNeutralContainer;

  @override
  AppStatusColors copyWith({
    Color? success,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? danger,
    Color? dangerContainer,
    Color? onDangerContainer,
    Color? info,
    Color? infoContainer,
    Color? onInfoContainer,
    Color? neutral,
    Color? neutralContainer,
    Color? onNeutralContainer,
  }) {
    return AppStatusColors(
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      danger: danger ?? this.danger,
      dangerContainer: dangerContainer ?? this.dangerContainer,
      onDangerContainer: onDangerContainer ?? this.onDangerContainer,
      info: info ?? this.info,
      infoContainer: infoContainer ?? this.infoContainer,
      onInfoContainer: onInfoContainer ?? this.onInfoContainer,
      neutral: neutral ?? this.neutral,
      neutralContainer: neutralContainer ?? this.neutralContainer,
      onNeutralContainer: onNeutralContainer ?? this.onNeutralContainer,
    );
  }

  @override
  AppStatusColors lerp(ThemeExtension<AppStatusColors>? other, double t) {
    if (other is! AppStatusColors) return this;
    return AppStatusColors(
      success: Color.lerp(success, other.success, t)!,
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      onSuccessContainer: Color.lerp(
        onSuccessContainer,
        other.onSuccessContainer,
        t,
      )!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer: Color.lerp(
        warningContainer,
        other.warningContainer,
        t,
      )!,
      onWarningContainer: Color.lerp(
        onWarningContainer,
        other.onWarningContainer,
        t,
      )!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerContainer: Color.lerp(dangerContainer, other.dangerContainer, t)!,
      onDangerContainer: Color.lerp(
        onDangerContainer,
        other.onDangerContainer,
        t,
      )!,
      info: Color.lerp(info, other.info, t)!,
      infoContainer: Color.lerp(infoContainer, other.infoContainer, t)!,
      onInfoContainer: Color.lerp(onInfoContainer, other.onInfoContainer, t)!,
      neutral: Color.lerp(neutral, other.neutral, t)!,
      neutralContainer: Color.lerp(
        neutralContainer,
        other.neutralContainer,
        t,
      )!,
      onNeutralContainer: Color.lerp(
        onNeutralContainer,
        other.onNeutralContainer,
        t,
      )!,
    );
  }
}

extension AppThemeX on ThemeData {
  /// Status colours for the current theme. Never null: both themes register
  /// the extension.
  AppStatusColors get status =>
      extension<AppStatusColors>() ?? AppStatusColors.light();
}

extension AppContextX on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  AppStatusColors get statusColors => Theme.of(this).status;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}
