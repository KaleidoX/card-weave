import 'package:flutter/widgets.dart';

abstract final class AppTokens {
  static const page = 16.0;
  static const gap = 12.0;
  static const small = 8.0;
  static const tiny = 4.0;
  static const section = 20.0;
  static const radius = 12.0;
  static const row = 52.0;
  static const twoLineRow = 64.0;
  static const notes = 88.0;
  static const touch = 44.0;
  static const icon = 24.0;
  static const tabIcon = 24.0;
  static const tabLabel = 11.0;
  static const actionIcon = 20.0;
  static const chevron = 12.0;
  static const labelGap = 6.0;
  static const body = 17.0;
  static const caption = 13.0;
  static const title = 20.0;
  static const hero = 28.0;
  static const largeTitle = 34.0;
  static const width = 680.0;
  static const avatar = 40.0;
  static const heroAvatar = 80.0;
  static const wheelHeight = 192.0;
  static const contentInset = page + icon + gap;
  static const pagePadding = EdgeInsets.all(page);
  static const rowPadding = EdgeInsets.symmetric(
    horizontal: page,
    vertical: small,
  );
  static const animation = Duration(milliseconds: 180);
  static const backgroundLight = Color(0xffF2F2F7);
  static const backgroundDark = Color(0xff000000);
  static const surfaceLight = Color(0xffFFFFFF);
  static const surfaceDark = Color(0xff1C1C1E);
  static const accentLight = Color(0xff456B54);
  static const accentDark = Color(0xffA8C4AF);
}
