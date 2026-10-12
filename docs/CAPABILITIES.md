# 当前能力与限制

| 能力 | 实现与验证范围 |
| --- | --- |
| SQLite 本地通讯录 | SDK-owned connection，离线 CRUD/搜索/分页、重启保留；Linux bundled SQLite 实测 |
| 联系人日期 | v2 类型化日期：公历/农历生日各一个、纪念日/其他/自定义；Rust 共享月份/日数计算，指定农历年份 1901–2100 校验实际闰月与大小月；未知年份保留月日语义，仅结构校验；无历法转换/提醒 |
| 因果同步 | 真实 Fs、WebDAV Basic、S3 参考服务三设备同步；完整行冲突、删除候选、显式解决 |
| 故障恢复 | 真实缺失 Fs 路径、错误 HTTP 认证后 pending 保留，恢复后收敛；未验证断电/杀进程恢复 |
| Rust API / CLI | 源码与本地 Linux 构建；未发布 crate/预编译包 |
| WebDAV Bearer / S3 session token | 配置和 SDK 接入已实现，尚未验证相应认证方式 |
| Android Flutter UI | 联系人列表、搜索、完整字段编辑、删除；手动 HTTPS WebDAV 同步、旧草稿保护和显式冲突处理；Android 9/API 28 x86_64 原生验证，详见[应用说明](../apps/card-weave/README.md) |
| iOS / macOS / Windows | 产品界面尚未验证；iOS 按用户决定后置 |
| Android S3 / ARM 真机 | 接入/构建路径已提供，原生行为未验证 |
| 其他 OpenDAL 后端 | 未开放；不能从 OpenDAL 支持列表推断产品兼容性 |

当前版本不包含提醒、头像附件、导入导出、去重合并、系统通讯录桥接、端到端加密、多人权限或远端自动 GC。联系人/历史/墓碑会持续增长，无大数据性能保证。SQLite 业务 schema 无自动迁移。

LocalWeave 已记录并行关闭/重开时可能出现 `DatabaseInUse` 的未决问题，详见[SDK 已知限制](../vendor/local-weave/docs/KNOWN_LIMITATIONS.md)。CardWeave 尚未提供 backup/restore 产品入口。

详见[运行契约](CORE.md)与[验证方法](DEVELOPMENT.md)。
