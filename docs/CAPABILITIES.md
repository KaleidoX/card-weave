# 当前能力与限制

| 能力 | 实现与验证范围 |
| --- | --- |
| SQLite 本地通讯录 | SDK-owned connection，离线 CRUD/搜索/分页、重启保留；Linux bundled SQLite 实测 |
| 联系人日期 | 公历基本合法性、原始农历/未知年份/闰月保真；无农历转换与具体年份有效性保证 |
| 因果同步 | 真实 Fs、WebDAV Basic、S3 参考服务三设备同步；完整行冲突、删除候选、显式解决 |
| 故障恢复 | 真实缺失 Fs 路径、错误 HTTP 认证后 pending 保留，恢复后收敛；未验证断电/杀进程恢复 |
| Rust API / CLI | 源码与本地 Linux 构建；未发布 crate/预编译包 |
| WebDAV Bearer / S3 session token | 配置和 SDK 接入已实现，尚未验证相应认证方式 |
| Android / iOS / macOS / Windows | 未验证，尚无图形界面/系统通讯录集成 |
| 其他 OpenDAL 后端 | 未开放；不能从 OpenDAL 支持列表推断产品兼容性 |

当前版本不包含提醒、头像附件、导入导出、去重合并、系统通讯录桥接、端到端加密、多人权限或远端自动 GC。联系人/历史/墓碑会持续增长，无大数据性能保证。SQLite 业务 schema 无自动迁移。

LocalWeave 已记录并行关闭/重开时可能出现 `DatabaseInUse` 的未决问题，详见[SDK 已知限制](../vendor/local-weave/docs/KNOWN_LIMITATIONS.md)。CardWeave 尚未提供 backup/restore 产品入口。

详见[运行契约](CORE.md)与[验证方法](DEVELOPMENT.md)。
