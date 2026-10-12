import 'package:flutter/cupertino.dart';

import 'tokens.dart';

class AppPalette {
  final bool dark;
  const AppPalette(this.dark);
  Color get background =>
      dark ? AppTokens.backgroundDark : AppTokens.backgroundLight;
  Color get surface => dark ? AppTokens.surfaceDark : AppTokens.surfaceLight;
  Color get primary => dark ? AppTokens.accentDark : AppTokens.accentLight;
  Color get onSurface =>
      dark ? const Color(0xffF5F5F7) : const Color(0xff1C1C1E);
  Color get onSurfaceVariant =>
      dark ? const Color(0xffA5A5AE) : const Color(0xff707078);
  Color get primaryContainer =>
      dark ? const Color(0xff29372E) : const Color(0xffE2E9E4);
  Color get surfaceContainerHighest =>
      dark ? const Color(0xff2C2C2E) : const Color(0xffE3E3E8);
  Color get outlineVariant =>
      dark ? const Color(0xff38383A) : const Color(0xffD8D8DD);
  Color get error => dark
      ? CupertinoColors.systemRed.darkColor
      : CupertinoColors.systemRed.color;
  Color get errorContainer =>
      dark ? const Color(0xff482322) : const Color(0xffFCE8E6);
  Color get onTertiaryContainer =>
      dark ? const Color(0xffEACA94) : const Color(0xff705329);
}

class AppTypography {
  final AppPalette colors;
  const AppTypography(this.colors);
  TextStyle get bodyLarge =>
      TextStyle(fontSize: AppTokens.body, height: 1.3, color: colors.onSurface);
  TextStyle get bodyMedium => bodyLarge;
  TextStyle get bodySmall => TextStyle(
    fontSize: AppTokens.caption,
    height: 1.4,
    color: colors.onSurfaceVariant,
  );
  TextStyle get titleMedium => bodyLarge.copyWith(fontWeight: FontWeight.w600);
  TextStyle get titleLarge => bodyLarge.copyWith(
    fontSize: AppTokens.title,
    fontWeight: FontWeight.w600,
  );
  TextStyle get headlineSmall =>
      bodyLarge.copyWith(fontSize: AppTokens.hero, fontWeight: FontWeight.w700);
  TextStyle get headlineLarge => bodyLarge.copyWith(
    fontSize: AppTokens.largeTitle,
    fontWeight: FontWeight.w700,
  );
}

class AppTheme {
  final Brightness brightness;
  const AppTheme(this.brightness);
  static AppTheme of(BuildContext context) =>
      AppTheme(CupertinoTheme.brightnessOf(context));
  AppPalette get colors => AppPalette(brightness == Brightness.dark);
  AppTypography get text => AppTypography(colors);
  CupertinoThemeData get cupertino => CupertinoThemeData(
    brightness: brightness,
    primaryColor: colors.primary,
    scaffoldBackgroundColor: colors.background,
    barBackgroundColor: colors.background,
    textTheme: CupertinoTextThemeData(
      primaryColor: colors.primary,
      textStyle: text.bodyLarge,
      tabLabelTextStyle: TextStyle(
        fontSize: AppTokens.tabLabel,
        fontWeight: FontWeight.w500,
        color: colors.onSurfaceVariant,
      ),
      actionTextStyle: text.bodyLarge.copyWith(color: colors.primary),
      navTitleTextStyle: text.titleMedium,
      navLargeTitleTextStyle: text.headlineLarge,
    ),
  );
}
