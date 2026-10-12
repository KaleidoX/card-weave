# CardWeave Android

Flutter 原生界面，通过 flutter_rust_bridge 调用 Rust 应用宿主与 `card-weave-core`。业务数据仅通过 LocalWeave 所有的 SQLite 连接读写。

## 使用

首次启动创建本地通讯录，或粘贴另一设备的加入信息。创建后可离线新增、搜索、查看、编辑和删除联系人；保存完整电话、邮箱、备注及原始公历/农历日期。未知年份留空，农历闰月单独标记。

在设置中填写 HTTPS WebDAV Basic 或 S3 兼容存储配置。保存配置不访问网络；在同步页点击“立即同步”才上传和下载。凭据可选择设备安全存储或仅本次会话使用，不放入联系人、加入信息或普通配置文件。同步可取消；已经提交的片段不会回滚。

冲突页显示所有当前候选，包括删除版本。可以选择整个版本，也可基于候选编辑合并结果。解决只覆盖实际观察到的候选；稍后到达的新版本继续保留。普通编辑遇到保存基线变化时拒绝覆盖，草稿保留，可查看最新内容并明确选择放弃草稿重新编辑。

## 构建

当前锁定 Flutter 3.47.7 / Dart 3.13.5、flutter_rust_bridge 2.13.0、Rust 1.96.0、NDK 28.2.13676358；Android SDK Platform 36、Build Tools 36.0.0，JNI 插件另需 Platform 35。需要完整 submodule；当前固定的 LocalWeave 提交 `bffb081c6e9a80ad1e14583aab4db23850b814ce` 已包含 Android 文件锁及错误分类修复。

在仓库根目录准备 `ANDROID_HOME`、可选 `ANDROID_NDK_HOME`，将 Flutter 和 Rust 加入 PATH，并安装 Rust Android target。Linux 上需提供 libclang；系统默认找不到时设置 `LIBCLANG_PATH` 和 `CARDWEAVE_BINDGEN_EXTRA_ARGS`。不要把开发机路径写入仓库。

```sh
rustup target add x86_64-linux-android
cd apps/card-weave
flutter pub get
cd ../..
bash apps/card-weave/tool/build_android.sh
```

默认生成 x86_64 debug APK：`apps/card-weave/build/app/outputs/flutter-apk/app-debug.apk`。`CARDWEAVE_ABI=arm64-v8a` 选择 ARM64 构建路径，但 ARM 真机资格尚未验证。脚本默认 Linux NDK host；其他宿主自行提供 `ANDROID_NDK_HOST_TAG` 并单独验证。不提供 release 签名或商店发布流程。

TLS AAR 版本从 Rust Cargo.lock 中的 `rustls-platform-verifier-android` 读取，默认使用项目官方 maven-archive。网络不可用时可用 `CARDWEAVE_RUSTLS_MAVEN` 指向来自同一官方版本的本地 Maven 缓存。Android Activity 在网络前初始化 Application Context，不修改平台信任规则。

软件渲染虚拟机可在构建时设置 `CARDWEAVE_SOFTWARE_RENDERING=1`；默认使用平台渲染。调试包应用 ID 为 `io.cardweave.app`，不覆盖此前 M0 探针。

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
