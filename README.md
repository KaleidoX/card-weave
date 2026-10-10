# CardWeave

跨平台通讯录工具：通过 LocalWeave 将联系人保存在本地 SQLite，借助 OpenDAL 后端同步，并保留联系人日期的农历、闰月和未知年份语义。

当前交付为 **Rust 通讯录核心 + JSON CLI**，已在 Linux 验证离线管理、三设备同步和显式冲突解决。尚无图形界面或可用的 iOS / Android 产品；其他平台与真实云服务仍待分别验证。

## 构建

需要 Rust 1.96.0、C 编译器、libclang（SQLite Session bindings）以及已初始化的 `vendor/local-weave` Git 子模块。本项目显式使用 bundled SQLite，不需要运行时系统 SQLite。依赖与环境配置见[开发指南](docs/DEVELOPMENT.md)。

```sh
git clone --recurse-submodules git@github.com:KaleidoX/card-weave.git
cd card-weave
git submodule update --init --recursive
cargo build --workspace --locked
./target/debug/card-weave --help
```

## 离线使用

`HOME` 是 CardWeave 数据目录，初始化时必须不存在；其父目录须存在。所有输出为 JSON，联系人数据不会发往网络，直到显式执行 `sync`。

```sh
./target/debug/card-weave /tmp/card-weave-a init
./target/debug/card-weave /tmp/card-weave-a create examples/contact.json
./target/debug/card-weave /tmp/card-weave-a list
./target/debug/card-weave /tmp/card-weave-a list 示例 100 0
./target/debug/card-weave /tmp/card-weave-a status
```

用返回的联系人 `id` 执行 `get ID`、`update ID CONTACT.json` 或 `delete ID`。更新是完整替换，省略的可选字段恢复为空，不是局部 patch。多个同名联系人拥有独立随机 ID。

## 双设备同步

先从 A 的 `info` 获取 `dataset`，在另一设备执行 `init DATASET`；每台设备有独立数据库、device 和 incarnation。不要复制活动数据库或身份文件来创建另一设备。

Fs 后端配置为 `{"type":"fs","root":"/absolute/existing/shared-directory"}`。将配置保存为 `backend.json`，让两个设备访问同一后端：

```sh
./target/debug/card-weave /tmp/card-weave-a sync backend.json
./target/debug/card-weave /tmp/card-weave-b sync backend.json
./target/debug/card-weave /tmp/card-weave-a sync backend.json
```

远端按 dataset 分隔。WebDAV/S3 配置样本见 [WebDAV](examples/webdav.json)、[S3](examples/s3.json)，凭据只从配置中明确指定的宿主环境变量读取。示例 endpoint 为不可用占位地址；不会自动加载 `.env`、AWS 配置或云元数据凭据。

`sync` 执行一次有界同步；退出码 5 表示调用返回但仍有冲突、待同步或未完成扫描。`settled` 只表示当前本地没有已知待处理项，不证明远端全量备份或离线设备没有新修改。

## 冲突处理

`conflicts` 返回完整候选及 version ID，删除候选的 `contact` 为 `null`。`get` 和 `list` 同时暴露冲突，即使确定性投影选中了删除也不会隐藏冲突。普通编辑不能覆盖多头冲突。

保存解决输入：`{"observed":[候选的version对象],"contact":完整联系人数据或null}`，然后执行 `resolve ID RESOLUTION.json`。`contact` 必须显式提供；`null` 表示选择删除。只解决观察到的版本，保留随后出现的并发分支。

## Rust API 与文档

- [核心 API](crates/core/src/lib.rs)：`AddressBook::init/open/create/get/list/update/delete/conflicts/resolve/status/sync/close`。一个实例拥有一个 SDK；方法使用可变借用串行操作，宿主自行提供 async runtime。
- [数据与 CLI 契约](docs/CORE.md)：字段、限制、身份、错误和同步语义。
- [开发与验收](docs/DEVELOPMENT.md)：命令、工具链与测试入口。
- [能力与限制](docs/CAPABILITIES.md)：已验证范围及尚未实现的边界。

## 协作与许可

本项目采用 [Apache-2.0 许可证](LICENSE)，尚未发布 crate、安装包或移动应用。LocalWeave 及其他依赖保留各自许可，见[第三方说明](docs/THIRD_PARTY.md)。修改后运行开发指南中的相关检查；测试只能使用合成联系人和明确授权的存储。

Git 忽略规则按目录维护：根目录处理 Cargo workspace 的 `target/`，`scripts/` 处理 Python 缓存，宿主 `.aws/` 目录整体排除。公开 `docs/` 不受本机全局忽略规则影响；私有任务资料、构建产物和本地配置不属于源码交付。
