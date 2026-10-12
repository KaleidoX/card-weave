import 'package:flutter/cupertino.dart';

import '../design.dart';
import '../model.dart';

class UpgradeBookPage extends StatefulWidget {
  final AppModel model;
  const UpgradeBookPage(this.model, {super.key});
  @override
  State<UpgradeBookPage> createState() => _UpgradeBookPageState();
}

class _UpgradeBookPageState extends State<UpgradeBookPage> {
  bool confirmed = false, busy = false;
  String? error;
  Future<void> migrate() async {
    setState(() => busy = true);
    try {
      await widget.model.refresh();
      if (widget.model.status['settled'] != true) {
        throw AppFailure('migration_not_ready');
      }
      await widget.model.migrate();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AppPage(
      navigationBar: AppNavigation(title: const Text('升级通讯录')),
      body: ListView(
        padding: AppTokens.pagePadding,
        children: [
          const Text('升级后可使用群组。联系人资料与 ID 会保留，原通讯录不会删除。'),
          const SizedBox(height: 16),
          const Text(
            '将创建新的通讯录加入信息，其他设备需要升级并重新加入。请先让所有设备完成同步，并解决全部冲突；升级期间不要在其他设备继续编辑旧通讯录。',
          ),
          const SizedBox(height: 16),
          const Text('新通讯录产生修改后，不应直接切回旧库。旧远端数据不会自动删除。'),
          AppSwitchRow(
            title: const Text('我已汇集所有设备修改，并了解需要重新加入'),
            value: confirmed,
            onChanged: busy ? null : (v) => setState(() => confirmed = v),
          ),
          if (error != null) AppStatus(error!, kind: AppStatusKind.error),
          AppButton.filled(
            onPressed: !confirmed || busy ? null : migrate,
            child: Text(busy ? '正在核对并迁入…' : '迁入新通讯录'),
          ),
        ],
      ),
    ),
  );
}
