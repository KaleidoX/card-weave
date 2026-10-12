import 'package:flutter/cupertino.dart';

import '../design.dart';

/// Development-only catalog; it is not linked from the application navigation.
class AppComponentGallery extends StatelessWidget {
  const AppComponentGallery({super.key});

  @override
  Widget build(BuildContext context) => AppPage(
    navigationBar: const AppNavigation(title: Text('组件预览')),
    body: ListView(
      padding: AppTokens.pagePadding,
      children: [
        const SectionLabel('表单'),
        AppGroup(
          alignment: AppAlignment.icon,
          children: [
            const AppFieldRow(
              icon: CupertinoIcons.person,
              child: AppInput(label: '姓名', labelVisible: false, inline: true),
            ),
            AppFieldRow(
              icon: CupertinoIcons.phone,
              label: AppChoice<String>(
                title: '电话类型',
                selected: 'mobile',
                options: const {'mobile': '手机', 'work': '工作'},
                onChanged: (_) {},
              ),
              trailing: AppRemoveButton(label: '删除电话', onPressed: () {}),
              child: const AppInput(
                label: '电话',
                labelVisible: false,
                inline: true,
              ),
            ),
          ],
        ),
        const SectionLabel('列表与详情'),
        AppGroup(
          alignment: AppAlignment.avatar,
          children: [
            AppRow(
              leading: const ContactAvatar('张明'),
              title: const Text('张明'),
              subtitle: const Text('CardWeave'),
              onTap: () {},
            ),
            const AppInfoRow(label: '电话', value: '13800138000'),
          ],
        ),
        const SectionLabel('状态'),
        const AppStatus('已保存', kind: AppStatusKind.success),
        AppStatus('连接失败，请重试', kind: AppStatusKind.error, onRetry: () {}),
        const AppEmptyState('暂无联系人', message: '添加第一位联系人'),
        const SectionLabel('日期滚轮'),
        Row(
          children: [
            for (final label in ['年份', '月份', '日期'])
              Expanded(
                child: AppWheel(
                  label: label,
                  count: 12,
                  selected: 1,
                  text: (i) => label == '年份' ? '${2020 + i}' : '$i',
                  onChanged: (_) {},
                ),
              ),
          ],
        ),
      ],
    ),
  );
}
