# 通讯录核心契约

## 存储与身份

SQLite canonical STRICT 表 `contacts` 具有 `id`、`display_name`、`document` 三个非空 TEXT 字段，首列为主键。document version 为 1。联系人整体是一个 SDK MV register，日期/电话没有单独的同步版本。SDK 管理唯一连接、事务、因果历史、outbox、收件和墓碑；CardWeave 不直接读写内部表。

本地目录包含 `contacts.sqlite`、`identity.json` 和 SDK 所需文件。init 只接受不存在的目录，生成 128-bit 随机 dataset/device/incarnation；加入设备时只共享 dataset。open 要求身份文件和数据库都存在且匹配，损坏/缺失时失败，不自动重建。初始化中断可能留下不完整目录，需人工确认后恢复或另建目录。当前无产品级 backup/restore/clone 入口，不手动复制数据库或更改身份来冒充克隆。

## 联系人输入

`version=1`、`display_name` 必填。`given_name`、`family_name`、`organization`、`notes` 默认空字符串；`phones`、`emails`、`dates` 默认空数组。电话/邮箱项为 `{label,value}`，保持原始文本，不格式化、不校验投递能力、不按电话合并联系人。

输入拒绝未知字段，更新完整替换；不支持任意扩展或自动业务 schema 迁移。输出 `Contact` 包含 `id`、`data`、`has_conflict`。

- 每份输入及序列化 document 最多 64 KiB；显示名/姓名/组织最多 1024 UTF-8 字节，备注最多 32768 字节，文本拒绝 NUL。
- 电话、邮箱、日期各最多 32 项；标签最多 128 字节，电话/邮箱值最多 1024 字节且非空。
- 日期含 `label/calendar/year/month/day/is_leap_month`。历法为 `gregorian` 或 `chinese_lunar`，year 可空或 1..9999，month 1..12。
- 公历按月份/闰年校验日数，未知年份允许 2 月 29 日，不允许闰月标记；农历日数只检查 1..30，保留闰月标记，不校验指定年份是否存在该闰月/日期。不进行历法转换、庆祝策略或提醒计算。

## 查询与冲突

列表按 display_name/id 排序，limit 1..500、默认 100，offset 为匹配项偏移。搜索对显示名、姓名、组织、备注及电话/邮箱值做 Unicode lowercase 子串匹配，不做拼音/模糊检索或语言排序。搜索词最长 1024 字节，内部每次最多读 64 行，最多扫描 100032 行；超限明确失败，不返回伪完整结果。无索引与大通讯录性能保证。

CLI list 的 `contacts` 是投影分页；`conflicts` 是全体冲突（独立于分页/搜索），包括删除投影。get 返回 `{contact,conflict}`；当投影为删除而存在冲突时 contact=null，但调用成功并提供候选。不存在且无冲突返回 not_found。

resolve 必须提供 `observed`（1..1000 个 version ID）和显式 `contact`，选删除必须写 null。版本 seq 为十进制字符串，避免 JS 数字精度丢失。SDK 校验父版本属于目标记录；未观察到的版本保留。resolve 成功不保证冲突清零，检查返回 status 或 conflicts。

## 同步与状态

调用 Sdk::sync_once，使用 SDK 默认上传/下载/分页/重试预算；网络不在 SQL 事务内。当前 AddressBook API 用可变借用串行化操作，不在一次 sync 调用期间并行编辑同一实例；支持传入 Cancellation。

Fs/WebDAV/S3 由 lfs-storage 构造，dataset 命名空间由 SDK 处理。Fs 目录须已存在、绝对路径且符合 SDK 的非符号链接要求。WebDAV 支持 Basic 或 Bearer（二选一）；目前仅 Basic 通过参考服务验证。HTTPS 为默认；`allow_loopback_http=true` 仅用于显式 127.0.0.1/[::1] 本地测试。S3 必填 endpoint/region/bucket，不自动发现宿主凭据；session_token_env 可选。

状态暴露 pending_outbox、conflict_count、stopped_streams、discovery_incomplete、outstanding_objects、inbox_states、last_sync_failed。`protocol_healthy` 是 SDK 健康判定，`settled` 还要求无 pending 和冲突；sync 的 settled 额外要求本次完整扫描。last_sync_failed 是当前实例内的最近错误标记，不是跨 CLI 进程持久日志；持久失败以 inbox/停止流/欠账为准。

同步信任共享该 schema 的 CardWeave 客户端。SDK 验证协议、SQLite 类型和因果结构，不理解 document 的业务 JSON；收到不受支持/损坏的业务 document 后，联系人读取会明确失败，不会默默删字段。业务 JSON 验证不属于远端 apply 事务，目前不能声称能在 SDK apply 前拒绝任意非 CardWeave 写入者构造的业务 payload。hash 只验证完整性，不认证发送者。

## CLI 输出

成功 stdout：`{"ok":true,"result":...}`；失败 stderr：`{"ok":false,"error":{"code":...,"message":...}}`。异常输出不打印凭据、联系人正文或 SDK 的原始错误细节。

| 退出码 | 含义 |
| --- | --- |
| 0 | 命令完成；status 查询成功不表示 settled |
| 2 | 输入不合法、命令参数错误或联系人不存在 |
| 3 | 需要显式解决冲突 |
| 4 | I/O、网络、数据库占用、身份不匹配或其他 SDK 失败 |
| 5 | sync 返回报告，但仍未 settled |

配置错误、未知字段、数据上限和非法日期在写入前拒绝。网络失败保留本地数据和未确认 outbox，后续可重试；不自动清理远端对象。
