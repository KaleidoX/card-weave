import 'package:flutter/cupertino.dart';

import '../tokens.dart';
import 'groups.dart';

/// A section owns its heading; its parent owns the gap between sections.
class AppSection extends StatelessWidget {
  final String? title;
  final Widget child;
  const AppSection({super.key, this.title, required this.child});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [if (title != null) SectionLabel(title!, topSpacing: 0), child],
  );
}

/// Include only visible sections; nested lists add no leading or trailing gap.
class AppSectionList extends StatelessWidget {
  final List<Widget> children;
  const AppSectionList({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) const SizedBox(height: AppTokens.section),
        children[i],
      ],
    ],
  );
}

class AppSectionScrollView extends StatelessWidget {
  final List<Widget> children;
  const AppSectionScrollView({super.key, required this.children});

  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: AppTokens.pagePadding,
    itemCount: children.length,
    separatorBuilder: (_, _) => const SizedBox(height: AppTokens.section),
    itemBuilder: (_, index) => children[index],
  );
}
