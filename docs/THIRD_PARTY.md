# 第三方依赖说明

项目采用 [Apache-2.0 许可证](../LICENSE)，尚未发布可分发包。以下说明用于源码开发，不替代将来二进制分发所需的完整许可清单及通知。

- LocalWeave（lfs-sqlite / lfs-protocol / lfs-storage）0.1.0：Git 子模块 `vendor/local-weave` 源码依赖，Apache-2.0，保留其 [LICENSE](../vendor/local-weave/LICENSE) 与 [第三方声明](../vendor/local-weave/docs/THIRD_PARTY.md)。
- OpenDAL 0.59.4：通过 LocalWeave 存储适配器使用，Apache-2.0。
- SQLite：通过 SDK 的 bundled profile 使用；SQLite 本体为 public domain，Rust bindings 有各自许可。
- Serde / serde_json、Tokio、getrandom：版本见 Cargo.lock，许可与完整传递依赖以 package metadata 和各包随附许可为准。
- rclone：仅作为显式传入的测试工具，不嵌入产品；验收工具版本为 1.75.1。

源码依赖版本、验证和已知边界见[开发指南](DEVELOPMENT.md)。完整分发许可核查属于后续发布工作，不能用此概览宣称完成。

Android 界面使用 Flutter/Dart、flutter_rust_bridge 2.13.0、flutter_secure_storage 11.2.0、path_provider 2.1.6，以及 Android JNI 0.22.4 / rustls-platform-verifier 0.7.1（匹配 Android AAR 0.2.0）。精确依赖图见 apps/card-weave/pubspec.lock 和 apps/card-weave/rust/Cargo.lock；依赖许可继续以各包随附 LICENSE 为准。当前仅提供开发构建，未完成商店分发许可与签名流程。
