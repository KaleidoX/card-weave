import 'package:flutter/cupertino.dart';

import '../theme.dart';
import '../tokens.dart';

class AppPage extends StatelessWidget {
  final ObstructingPreferredSizeWidget? navigationBar;
  final Widget body;
  final Widget? bottomBar;
  final bool safeTop;
  const AppPage({
    super.key,
    this.navigationBar,
    required this.body,
    this.bottomBar,
    this.safeTop = true,
  });
  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: navigationBar,
    child: SafeArea(
      top: safeTop,
      bottom: bottomBar == null,
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: AppTokens.width),
                child: body,
              ),
            ),
          ),
          ?bottomBar,
        ],
      ),
    ),
  );
}

class AppNavigation extends StatelessWidget
    implements ObstructingPreferredSizeWidget {
  final Widget title;
  final Widget? leading;
  final List<Widget> actions;
  const AppNavigation({
    super.key,
    required this.title,
    this.leading,
    this.actions = const [],
  });
  @override
  Size get preferredSize => const Size.fromHeight(44);
  @override
  bool shouldFullyObstruct(BuildContext context) => true;
  @override
  Widget build(BuildContext context) => CupertinoNavigationBar(
    middle: title,
    leading: leading,
    previousPageTitle: '返回',
    trailing: actions.isEmpty
        ? null
        : Row(mainAxisSize: MainAxisSize.min, children: actions),
    backgroundColor: CupertinoTheme.of(context).barBackgroundColor,
    border: null,
    transitionBetweenRoutes: false,
  );
}

class LargeTitlePage extends StatelessWidget {
  final String title;
  final List<Widget> slivers;
  final Widget? trailing;
  final Widget? leading;
  const LargeTitlePage({
    super.key,
    required this.title,
    required this.slivers,
    this.trailing,
    this.leading,
  });
  @override
  Widget build(BuildContext context) => CustomScrollView(
    key: PageStorageKey(title),
    physics: const BouncingScrollPhysics(
      parent: AlwaysScrollableScrollPhysics(),
    ),
    slivers: [
      CupertinoSliverNavigationBar(
        largeTitle: Text(title),
        trailing: trailing,
        leading: leading,
        automaticallyImplyLeading: false,
        backgroundColor: AppTheme.of(context).colors.background,
        border: null,
        transitionBetweenRoutes: false,
      ),
      ...slivers,
    ],
  );
}

class GroupedPageList extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const GroupedPageList({
    super.key,
    required this.title,
    required this.children,
  });
  @override
  Widget build(BuildContext context) => LargeTitlePage(
    title: title,
    slivers: [
      SliverPadding(
        padding: AppTokens.pagePadding,
        sliver: SliverList.list(children: children),
      ),
    ],
  );
}

class AppTabItem {
  final IconData icon;
  final String label;
  const AppTabItem(this.icon, this.label);
}

class AppTabs extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  final List<AppTabItem> items;
  const AppTabs({
    super.key,
    required this.index,
    required this.onChanged,
    required this.items,
  });
  @override
  Widget build(BuildContext context) => CupertinoTabBar(
    currentIndex: index,
    onTap: onChanged,
    items: [
      for (final item in items)
        BottomNavigationBarItem(icon: Icon(item.icon), label: item.label),
    ],
    backgroundColor: AppTheme.of(context).colors.surface,
    activeColor: AppTheme.of(context).colors.primary,
    inactiveColor: AppTheme.of(context).colors.onSurfaceVariant,
    height:
        49 +
        (MediaQuery.textScalerOf(context).scale(AppTokens.caption) -
                AppTokens.caption)
            .clamp(0, AppTokens.touch),
  );
}
