# CardWeave Android

Flutter 跨平台界面，通过 flutter_rust_bridge 调用 Rust 应用宿主与 `card-weave-core`。业务数据仅通过 LocalWeave 所有的 SQLite 连接读写。

## 使用

首次启动创建本地通讯录，或粘贴另一设备的加入信息。创建后可离线新增、搜索、查看、编辑和删除联系人；保存完整电话、邮箱、备注及原始公历/农历日期。年份可以不指定；指定农历年份后，月份选择器自动包含该年实际闰月。

在设置中填写 HTTPS WebDAV Basic 或 S3 兼容存储配置。保存配置不访问网络；在同步页点击“立即同步”才上传和下载。凭据可选择设备安全存储或仅本次会话使用，不放入联系人、加入信息或普通配置文件。同步可取消；已经提交的片段不会回滚。

冲突页显示所有当前候选，包括删除版本。可以选择整个版本，也可基于候选编辑合并结果。解决只覆盖实际观察到的候选；稍后到达的新版本继续保留。普通编辑遇到保存基线变化时拒绝覆盖，草稿保留，可查看最新内容并明确选择放弃草稿重新编辑。

## 界面

采用统一的 iOS 分组列表设计：中性灰背景、白色分组与鼠尾草绿强调色，浅色和深色跟随系统。主页面大标题随滚动收起，切换标签保留页面状态。联系人列表右上角“＋”新建，下拉刷新。编辑页左侧标签与右侧输入组成52逻辑像素基线的紧凑行，组内细分隔、不叠加字段空白；错误、大字号和长标签自然增高。电话与邮箱分别成组，自动保留尾部空行且空行不保存，备注默认2行并随内容增长。顶部“取消 / 完成”管理编辑草稿，完成后保存到本机。联系方式标签可从菜单选择或自定义，并与日期共用统一的下拉箭头。默认只填写姓名，同组展开姓氏、中间名和名字；修改细分后组合显示姓名，已有自定义显示姓名不一致时需确认。

导航、按钮、开关、类型菜单、确认对话框和日期控件统一使用 Cupertino。同步页将手动操作、待上传内容和冲突分开呈现；冲突候选逐项显示差异，可展开完整内容后明确采用或编辑合并。Android 系统返回、键盘和安全区继续适配，Cupertino 外观不代表已经完成 iOS 设备验证。

“更多信息”一次展开全部昵称、姓名拼音、地址、即时消息、网站和手工关联人。已有非空资料自动显示；职位位于公司组，姓名前后缀位于姓名细分。地址空行从单行开始，随内容增高；关联选择使用行内图标。地址/IM/关联人沿用连续空行、类型选择和逐条删除，空行不保存；直接清空字段可移除对应资料，取消编辑可放弃修改。详情支持选择复制，新增字段参与搜索和完整联系人冲突展示。网站、地址、IM 暂不启动外部应用，拼音手填且不生成首字母索引。第二阶段支持群组及 App 联系人关联，头像仍后置。

扩展资料是 v2 可选字段，旧联系人无需批量改写；填写新字段之前须升级同一通讯录的所有客户端，旧版不能读取新字段。详见 [核心契约](../../docs/CORE.md)。

颜色和尺寸在 `lib/ui/theme.dart`、`lib/ui/tokens.dart`；共享组件按职责拆分到 `lib/ui/components/`，`lib/design.dart` 仅统一导出，约定见 [UI_DESIGN.md](UI_DESIGN.md)。保留现有模型、Rust 农历选项及保存/同步/冲突契约。

## 构建

当前锁定 Flutter 3.47.7 / Dart 3.13.5、flutter_rust_bridge 2.13.0、Rust 1.96.0、NDK 28.2.13676358；Android SDK Platform 36、Build Tools 36.0.0，JNI 插件另需 Platform 35。需要完整 submodule；LocalWeave 版本以仓库固定的 submodule 引用为准，包含 Android 文件锁、错误分类和 WebDAV 空目录初始化修复。

在仓库根目录准备 `ANDROID_HOME`、可选 `ANDROID_NDK_HOME`，将 Flutter 和 Rust 加入 PATH，并安装 Rust Android target。Linux 上需提供 libclang；系统默认找不到时设置 `LIBCLANG_PATH` 和 `CARDWEAVE_BINDGEN_EXTRA_ARGS`。不要把开发机路径写入仓库。

```sh
rustup target add x86_64-linux-android
cd apps/card-weave
flutter pub get
cd ../..
bash apps/card-weave/tool/build_android.sh
```

默认生成 x86_64 debug APK：`apps/card-weave/build/app/outputs/flutter-apk/app-debug.apk`。`CARDWEAVE_ABI=arm64-v8a` 选择 ARM64 真机；每个 APK 只包含指定架构，其他架构的历史构建文件不会混入。脚本默认 Linux NDK host；其他宿主自行提供 `ANDROID_NDK_HOST_TAG` 并单独验证。

日常调试保留 debug；测量体积或分发试用时同时使用 Rust 与 Flutter 的 release 构建：

```sh
rustup target add aarch64-linux-android
CARDWEAVE_ABI=arm64-v8a CARDWEAVE_BUILD_MODE=release bash apps/card-weave/tool/build_android.sh
```

产物为 `apps/card-weave/build/app/outputs/flutter-apk/app-release.apk`。模式仅支持 `debug` / `release`，不要额外传入 Flutter 模式或架构参数，以免 Rust 与 Flutter 构建不一致。release 使用 AOT 和 Flutter 默认资源裁剪；不裁剪通讯录或同步功能。当前 release 仍使用开发签名，尚未提供生产签名和商店发布流程。debug APK 含开发引擎、运行快照及调试依赖，不适合作为发布体积基准。

TLS AAR 版本从 Rust Cargo.lock 中的 `rustls-platform-verifier-android` 读取，默认使用项目官方 maven-archive。网络不可用时可用 `CARDWEAVE_RUSTLS_MAVEN` 指向来自同一官方版本的本地 Maven 缓存。Android Activity 在网络前初始化 Application Context，不修改平台信任规则。

软件渲染虚拟机可在构建时设置 `CARDWEAVE_SOFTWARE_RENDERING=1`；默认使用平台渲染。调试包应用 ID 为 `io.cardweave.app`，不覆盖此前 M0 探针。设置 `CARDWEAVE_ACCEPTANCE=1` 时构建独立的 `io.cardweave.app.acceptance` 验证包，安装、数据和测试卸载均与正式应用隔离；默认构建不设置此变量。

## 验证与绑定生成

```sh
cargo test --workspace --locked
cargo clippy --workspace --all-targets --locked -- -D warnings
cd apps/card-weave
flutter analyze --no-pub
flutter_rust_bridge_codegen generate
```

生成器必须与锁定 runtime 一致，生成的 Dart/Rust 绑定纳入源码。`rust/` 是独立桥接 Cargo workspace，`crates/app-host` 属于根 workspace；两份 lockfile 均需维护。

`integration_test/android_flow_test.dart` 操作真实页面与 Rust/SQLite。测试要求专用、无用户数据的应用目录，以及 `https://127.0.0.1:18941` 上的 HTTPS WebDAV 合成 fixture（账号 m0-fixture，密码 synthetic-test-only）、可信测试 CA 和 Android reverse 端口。测试会创建第二个独立副本并检查同步/并发编辑删除/旧草稿拒绝，不能在用户数据目录上运行。第一次执行完整流程；第二次保留数据并传 `--dart-define=REOPEN=true` 检查进程恢复及搜索/删除。测试 CA 与 fixture 不随产品发布。

```sh
flutter test integration_test/android_flow_test.dart --no-pub --no-uninstall -d DEVICE
flutter test integration_test/android_flow_test.dart --no-pub --no-uninstall -d DEVICE --dart-define=REOPEN=true
```

## 边界

本阶段 Android 优先。iOS、ARM 真机、真实云供应商、硬件 Keystore、GPU/大规模性能尚未授予资格。S3 表单与适配器已实现，Android 本轮原生 UI 同步验收采用 HTTPS WebDAV；Linux CLI 的 S3 证据不能代替 Android S3 验证。

一个 App 只管理一个通讯录；已有数据目录不切换 dataset。系统通讯录集成、后台同步、提醒、附件、备份恢复、端到端加密与分发签名后置。草稿只在当前编辑页面保留，不承诺跨进程恢复。

## 重要日期

新增日期默认设备本地今天，农历使用 Rust 换算出的对应年月日；已有日期不重置。日期采用类型选择和行内年月日滚轮，支持公历生日、农历生日、纪念日、其他、自定义。两种生日各限一个；日期可不指定年份，农历由 Rust 计算有效月份与日数，闰月直接作为月份选项，不提供手动闰月开关。指定农历年份支持 1901–2100；不指定年份时提供普通月/闰月并说明仅保留月日，补上年份后重新校验。已有日期切换历法时不自动换算；新增农历日期使用 Rust 换算出的今天。无效日期须重新选择；有效选择直接更新联系人草稿，未完成日期阻止页面保存；页面“取消 / 完成”统一管理草稿。自定义日期需填写名称。

联系人使用 v2 数据格式（日期新增必填 kind）；本次按产品决定不兼容旧联系人 v1，不执行迁移或清空用户目录。旧联系人需在升级前自行导出处理；新版不会将其当作有效 v2 记录。Android 支持从系统通讯录手动导入；系统写入、导出和提醒仍后置。

公共组件布局回归：`flutter test --no-pub test/components_test.dart`（窄屏、200% 字号、深浅色）。开发预览为 `lib/ui/gallery.dart`，不出现在产品导航。

日期控件回归：`flutter test --no-pub test/date_picker_test.dart`。`integration_test/date_flow_test.dart` 使用当前应用目录，创建一个唯一名称的合成联系人，经实际页面保存、编辑、数据库重开后删除该测试联系人；测试代码只删除自己创建的联系人，但 Flutter 设备测试器可能重装或卸载应用，必须使用无个人数据的隔离测试实例，不在日常使用实例上运行。

扩展资料 Android 验收（专用无个人数据设备）：

```sh
CARDWEAVE_ACCEPTANCE=1 bash tool/build_android.sh
CARDWEAVE_ACCEPTANCE=1 flutter test integration_test/expanded_fields_test.dart --no-pub -d DEVICE
```

该测试验证所有扩展字段实际填写、删除地址行、取消、保存、清空网站、SQLite 重开与搜索，不需要 TLS fixture。CLI `scripts/acceptance.py` 验证这些资料在 Fs/WebDAV/S3 本地参考服务的三副本同步和显式冲突解决。二者与完整 Android HTTPS 流程是不同的验证边界。

## 群组与关联联系人

联系人首页“列表”管理自定义群组、切换全部/未分组/群组范围。群组成员支持搜索多选；详情“群组”调整所属群组。删除群组不删除联系人，成员并发加入/移出需要明确解决冲突。关联人可手填或选择 App 联系人，目标改名自动展示新名，目标不可用保留姓名快照。

既有通讯录需从设置主动升级后使用群组；原库保留，新加入信息需要在其他升级后的设备重新加入。请先汇集所有设备修改并处理冲突，不直接替换数据库文件。数据和 CLI 约定见 [群组与升级](../../docs/GROUPS.md)。

第二阶段 Android 验收：`CARDWEAVE_ACCEPTANCE=1 flutter test integration_test/groups_test.dart --no-pub -d DEVICE`，先以相同环境变量执行构建脚本。测试实例与普通应用隔离，不能使用普通 applicationId 运行会卸载实例的集成测试。

WebDAV 设置将服务地址与同步目录分开填写。坚果云服务地址为 `https://dav.jianguoyun.com/dav/`，同步目录例如 `CardWeave`；留空使用服务根目录。首次同步逐层创建目录，不要求预先建立。既有坚果云地址在读取时按 `/dav/` 拆分，保持远端路径不变；其他服务旧地址原样保留，不猜测服务根路径。加入信息包含目录，所有设备需使用支持此字段的版本。


## 系统通讯录导入

从设置进入“导入系统通讯录”，点击读取并授权后查看预览。仅申请 `READ_CONTACTS`，不修改系统联系人，不自动上传。疑似重复项按整个本地通讯录（含冲突候选）和本次列表的姓名、电话、邮箱提示，默认不选；号码比较不猜测国家区号。确认导入会新建联系人，完成后可手动同步。

标准字段包括姓名及细分、拼音、电话、邮箱、公司职位、地址、即时消息、网站、备注、手工关联人及标准公历日期（含无年份生日）。多个标量值、额外生日和无法解释的日期保留在备注并提示；超限记录禁止导入，不静默截断。头像、群组及未识别的厂商字段暂不转换。realme 日期策略已根据 RMX3800 上的原生通讯录 16.80.15 核对：支持公历、以公历日期为存储基准的农历生日、无年份生日及无年份闰月；农历转换统一调用 Rust 核心。未知或矛盾的历法标记保留原值和标记到备注，不猜测转换。此规则不代表其他厂商或所有 realme 版本已经验证。

导入逐条保存，停止时保留已完成项；当前会话只重试明确失败项。未收到保存结果的条目标为待核对，须重新读取并检查重复提示，避免盲目重试。离开页面后再次导入会重新检查重复。

`lib/system_contacts/contact_mapper.dart` 定义整条联系人的转换接口 `SystemContactMapper`。转换器接收汇总信息及完整明细，可以接管任意已支持字段、联合解释多个源字段，并返回联系人、提示和错误；不局限于日期。`AndroidContactsImportStrategy` 注入转换器，默认使用 `AndroidContactMapper`；`RealmeContactMapper` 复用标准字段规则并覆盖日期解码，也可继续扩展姓名、电话、地址等规则。

扩展字段通过转换器的 `additionalMimeTypes` 显式声明，读取层仅传输已声明的厂商文本字段（DATA1–DATA14），未声明字段只报告 MIME；照片及二进制内容仍不导入。原始资料缺失/超限、联系人格式验证、Rust 校验和重复识别继续由公共导入链路执行。

`lib/system_contacts/strategy.dart` 定义独立的导入与导出能力和按平台/厂商排序的策略注册表；页面及会话只依赖策略接口。realme 策略优先于通用 Android 策略，厂商转换器按 `lib/system_contacts/vendors/<厂商>/` 分目录维护：realme 的 `mapper.dart` 负责联系人转换，`dates.dart` 负责日期编码适配。通用 Android 策略通过 `SystemContacts.kt` 读取 Provider，再由独立映射模块转换；厂商策略可复用 Android 读取层并覆盖映射。iOS 及导出能力尚未注册，不能被显示为支持。不将 Android 特殊判断放入页面或 Rust 联系人模型。

隔离 Android 验证入口为 `integration_test/system_contacts_test.dart`。只能在专用测试设备中准备包含 `Fixture` 名称、电话 `+1 202-555-0199`、邮箱 `cw-import@example.invalid`、公历生日 `--02-29` 及 `vnd.fixture/contact` 扩展行（DATA1=`Vendor fixture`）的合成 Provider 联系人并以 `CARDWEAVE_ACCEPTANCE=1`、正确 `CARDWEAVE_ABI` 运行；普通用户手机只安装默认应用包，由用户在页面授权和选择真实联系人。

日期策略的原生回归入口为 `integration_test/realme_dates_test.dart`，使用合成编码验证真实 Rust 转换与保存重开，不读取系统通讯录。仅在隔离 Android 测试应用中运行。
