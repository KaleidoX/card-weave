# 开发与验收

## 源码依赖

LocalWeave 通过 `vendor/local-weave` Git 子模块接入，远端为 `https://github.com/KaleidoX/local-weave`，gitlink 固定 SDK 基线 commit `b0c457eeb3efc3b60aeab032bb78fe6cfd6a352b`。Cargo 仅引用子模块内部路径，不依赖仓库外的 SDK checkout。子模块保持自身 workspace，排除于 CardWeave workspace 成员之外。Cargo.lock 固定第三方依赖。

首次获取仓库可使用 `git clone --recurse-submodules <CardWeave 仓库地址>`；已有 checkout 执行：

```sh
git submodule update --init --recursive
git submodule status
```

切换父仓库版本后再次运行 update，以恢复对应 gitlink。不要使用 `--remote` 将日常构建自动升级到分支最新版本。升级 SDK 时显式选择子模块 commit、重新验收，并随父仓库变更一起记录 gitlink；Cargo.lock 本身不固定 path 依赖的源码。

工具链 Rust 1.96.0，bundled SQLite 3.53.2，LocalWeave 0.1.0，OpenDAL 0.59.4。C 编译器和 libclang/Clang 内建头文件用于构建 Session bindings。libclang 不在默认搜索路径时，按本机安装位置设置：

```sh
export LIBCLANG_PATH=/absolute/path/to/libclang-library-directory
export BINDGEN_EXTRA_CLANG_ARGS=-I/absolute/path/to/clang/builtin/include
cargo build --workspace --locked
```

这两个路径是构建依赖位置，不是 SQLite 动态库路径。根据本机安装位置设置，不将机器专用路径写进源码。

## 检查

在仓库根目录执行；依赖已缓存时可追加 `--offline`。

```sh
cargo fmt --all --check
cargo clippy --workspace --all-targets --locked -- -D warnings
cargo test --workspace --locked
cargo build --workspace --locked
python3 scripts/acceptance.py
python3 scripts/acceptance.py --backend webdav --rclone /absolute/path/to/rclone
python3 scripts/acceptance.py --backend s3 --rclone /absolute/path/to/rclone
```

`cargo test` 的公开 API 集成测试验证重复占用、关闭/重开、身份与 pending 保留。CLI 脚本从公开入口验收 CRUD、搜索、分页、输入拒绝、日期往返、三设备并发、旧 observed heads 解决、删除冲突、失败恢复和身份错误。每次创建独立临时目录，HTTP 测试启动仅绑定 loopback 的自有进程，以合成认证配置运行，finally 中停止该进程并移除 fixture。无真实联系人/账户/云盘访问。

HTTP 验收使用 rclone 1.75.1，要求支持 `serve webdav` 和 `serve s3`。测试必须显式指定 rclone；不自动安装或连接已有服务。本地参考服务验证不能代替真实云供应商的兼容性测试。已验证范围见[能力与限制](CAPABILITIES.md)。
