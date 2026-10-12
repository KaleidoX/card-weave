import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import 'model.dart';
import 'groups/upgrade.dart';
import 'system_contacts/page.dart';
import 'design.dart';

class SettingsPage extends StatefulWidget {
  final AppModel model;
  const SettingsPage(this.model, {super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final form = GlobalKey<FormState>();
  late String type = widget.model.config['type'] as String? ?? 'webdav';
  late final endpoint = TextEditingController(
    text: widget.model.config['endpoint'] as String? ?? '',
  );
  late final directory = TextEditingController(
    text: widget.model.config['directory'] as String? ?? 'CardWeave',
  );
  late final region = TextEditingController(
    text: widget.model.config['region'] as String? ?? '',
  );
  late final bucket = TextEditingController(
    text: widget.model.config['bucket'] as String? ?? '',
  );
  late final username = TextEditingController(
    text: widget.model.credentials['username'] as String? ?? '',
  );
  late final password = TextEditingController(
    text: widget.model.credentials['password'] as String? ?? '',
  );
  late final access = TextEditingController(
    text: widget.model.credentials['access_key'] as String? ?? '',
  );
  late final secret = TextEditingController(
    text: widget.model.credentials['secret_key'] as String? ?? '',
  );
  late final token = TextEditingController(
    text: widget.model.credentials['session_token'] as String? ?? '',
  );
  late bool remember = widget.model.config['credential_ref'] != null;
  bool saving = false;
  String? error, feedback;
  @override
  void dispose() {
    for (final c in [
      endpoint,
      directory,
      region,
      bucket,
      username,
      password,
      access,
      secret,
      token,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget input(
    TextEditingController controller,
    String label, {
    bool hidden = false,
    bool required = true,
  }) => AppInput(
    controller: controller,
    label: label,
    obscureText: hidden,
    validator: (v) => required && (v ?? '').trim().isEmpty ? '请填写$label' : null,
  );
  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final backend = {
      'type': type,
      'endpoint': endpoint.text.trim(),
      if (type == 'webdav') 'directory': directory.text.trim(),
      if (type == 's3') 'region': region.text.trim(),
      if (type == 's3') 'bucket': bucket.text.trim(),
    };
    final credentials = type == 'webdav'
        ? <String, dynamic>{
            'username': username.text,
            'password': password.text,
          }
        : <String, dynamic>{
            'access_key': access.text,
            'secret_key': secret.text,
            'session_token': token.text.isEmpty ? null : token.text,
          };
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.model.saveConfig(backend, credentials, remember);
      if (mounted) setState(() => feedback = '配置已保存；尚未连接服务器。可前往同步页面开始同步。');
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Form(
    key: form,
    child: AbsorbPointer(
      absorbing: saving,
      child: GroupedPageList(
        title: '设置',
        children: [
          AppGroup(
            children: [
              AppRow(
                title: const Text('导入系统通讯录'),
                leading: const Icon(CupertinoIcons.person_crop_rectangle),
                trailing: const Icon(CupertinoIcons.chevron_forward),
                onTap: () => Navigator.push(
                  context,
                  CupertinoPageRoute(
                    builder: (_) => SystemContactsImportPage(widget.model),
                  ),
                ),
              ),
            ],
          ),
          if (!widget.model.supportsGroups)
            AppGroup(
              children: [
                AppRow(
                  title: const Text('升级通讯录以使用群组'),
                  onTap: () =>
                      Navigator.push(
                        context,
                        CupertinoPageRoute(
                          builder: (_) => UpgradeBookPage(widget.model),
                        ),
                      ).then((_) {
                        if (mounted) setState(() {});
                      }),
                ),
              ],
            ),
          AppSection(
            title: '远端连接',
            child: const Text(
              '使用你自己的 HTTPS WebDAV 或 S3 兼容存储。所有设备需使用同一通讯录加入信息与同步位置。',
            ),
          ),
          AppGroup(
            children: [
              AppRow(
                title: const Text('存储类型'),
                trailing: AppChoice<String>(
                  title: '存储类型',
                  selected: type,
                  options: const {'webdav': 'WebDAV', 's3': 'S3 兼容存储'},
                  onChanged: (v) => setState(() => type = v),
                ),
              ),
              input(endpoint, type == 'webdav' ? 'WebDAV 服务地址' : '服务地址'),
              if (type == 'webdav') input(directory, '同步目录', required: false),
              if (type == 's3') ...[
                input(region, '区域'),
                input(bucket, '存储桶'),
                input(access, 'Access Key'),
                input(secret, 'Secret Key', hidden: true),
                input(
                  token,
                  'Session Token（可选）',
                  hidden: true,
                  required: false,
                ),
              ] else ...[
                input(username, '用户名'),
                input(password, '密码', hidden: true),
              ],
            ],
          ),
          if (type == 'webdav')
            const Text(
              '坚果云服务地址：https://dav.jianguoyun.com/dav/\n同步目录如 CardWeave，支持多级目录，首次同步自动创建；留空使用服务根目录。',
            ),
          AppGroup(
            children: [
              AppSwitchRow(
                title: const Text('记住凭据'),
                subtitle: Text(
                  remember ? '使用设备安全存储，凭据不会随联系人同步。' : '仅本次使用；重启应用后需重新输入。',
                ),
                value: remember,
                onChanged: (v) => setState(() => remember = v),
              ),
            ],
          ),
          if (error != null) AppStatus(error!, kind: AppStatusKind.error),
          SurfaceBox(
            child: AppButton(
              onPressed: saving || widget.model.syncing ? null : save,
              child: Text(saving ? '正在保存…' : '保存同步配置'),
            ),
          ),
          if (feedback != null)
            AppStatus(feedback!, kind: AppStatusKind.success),
          AppSection(
            title: '连接另一台设备',
            child: const Text(
              '在新设备首次启动时粘贴加入信息，然后单独填写访问凭据。加入信息不包含密码，也不授予存储访问权限。',
            ),
          ),
          AppButton.icon(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: widget.model.joinText()),
              );
              if (mounted) setState(() => feedback = '加入信息已复制，不包含凭据');
            },
            icon: const Icon(CupertinoIcons.doc_on_doc),
            label: const Text('复制加入信息'),
          ),
          AppGroup(
            children: [
              AppDisclosure(
                title: const Text('设备与通讯录信息'),
                children: [
                  AppSelectableText(
                    '通讯录：${widget.model.identity['dataset']}\n设备：${widget.model.identity['device']}',
                  ),
                ],
              ),
            ],
          ),
          const Text('CardWeave 0.1.0 · Android 开发版\n外观与字号跟随系统。'),
        ],
      ),
    ),
  );
}
