import 'package:flutter/cupertino.dart';

import '../theme.dart';
import '../tokens.dart';

class ContactAvatar extends StatelessWidget {
  final String name;
  final bool large;
  const ContactAvatar(this.name, {super.key, this.large = false});
  double get size => large ? AppTokens.heroAvatar : AppTokens.avatar;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.of(context).colors.primaryContainer,
        borderRadius: BorderRadius.circular(size / 2),
      ),
      child: Text(
        name.isEmpty ? '人' : name.characters.first,
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontSize: size * .4,
          fontWeight: FontWeight.w600,
          color: AppTheme.of(context).colors.primary,
        ),
      ),
    ),
  );
}
