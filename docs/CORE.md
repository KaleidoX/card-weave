# 通讯录核心契约

## 存储与身份

通讯录结构与升级见 [群组及升级契约](GROUPS.md)。新通讯录使用 SDK schema 2，既有 schema 1 按原结构打开。SQLite canonical STRICT 表 `contacts` 具有 `id`、`display_name`、`document` 三个非空 TEXT 字段，首列为主键。document version 为 2。联系人整体是一个 SDK MV register，日期/电话没有单独的同步版本。SDK 管理唯一连接、事务、因果历史、outbox、收件和墓碑；CardWeave 不直接读写内部表。

本地目录包含 `contacts.sqlite`、`identity.json` 和 SDK 所需文件。init 只接受不存在的目录，生成 128-bit 随机 dataset/device/incarnation；加入设备时只共享 dataset。open 要求身份文件和数据库都存在且匹配，损坏/缺失时失败，不自动重建。初始化中断可能留下不完整目录，需人工确认后恢复或另建目录。当前无产品级 backup/restore/clone 入口，不手动复制数据库或更改身份来冒充克隆。

## 联系人输入

`version=2`、`display_name` 必填。`given_name`、`middle_name`、`family_name`、`organization`、`notes` 默认空字符串；`phones`、`emails`、`dates` 默认空数组。电话/邮箱项为 `{label,value}`，保持原始文本，不格式化、不校验投递能力、不按电话合并联系人。

中间名 `middle_name` 为可选字符串，与其他姓名字段使用相同长度限制并参与搜索。空中间名序列化时省略，避免改变既有文档的并发编辑比较；缺失时按空值读取。非空中间名会随完整联系人同步，参与同步的客户端须支持此字段；旧客户端按未知字段规则拒绝，不会静默丢弃。

仅支持联系人格式 v2；不兼容或自动迁移旧联系人 v1，旧数据读取明确失败，不自动删除或重建。所有共享通讯录的客户端需使用 v2。身份文件和 SDK schema/protocol 版本不随联系人 document 版本改变。

扩展资料沿用 v2 可选字段：`name_prefix`、`name_suffix`、`phonetic_family_name`、`phonetic_middle_name`、`phonetic_given_name`、`nickname`、`job_title`、`website` 为字符串；`addresses`、`instant_messages`、`relations` 为 `{label,value}` 数组。关联人支持可选 `target_contact_id` 引用 App 联系人，value 保留姓名快照，具体规则见 [关联人与群组](GROUPS.md)。地址为自由文本，网站为单值，IM 仅存账号。

这些新增字段缺失时按空读取，空值在序列化时省略；旧 v2 文档无需批量改写，未改保存不产生新的业务同步操作。旧客户端不能读取非空新字段，所有参与同步的客户端须先升级；未知字段继续明确拒绝，不过滤后回写，不保证旧二进制能读取新资料。扩展资料仍属于整个联系人版本，不引入字段级自动合并、字段级协议变化；第二阶段群组和成员新增独立业务表，不修改 LocalWeave 协议。

输入拒绝未知字段，更新完整替换；不支持任意扩展或自动业务 schema 迁移。输出 `Contact` 包含 `id`、`data`、`has_conflict`。

- 每份输入及序列化 document 最多 64 KiB；显示名/姓名（含前后缀）/拼音/昵称/组织/职位最多 1024 UTF-8 字节，备注最多 32768 字节，文本拒绝 NUL。
- 电话、邮箱、日期、地址、即时消息、关联人各最多 32 项；标签最多 128 字节，电话/邮箱/IM/关联人值最多 1024 字节且非空，地址值最多 4096 字节且非空，网站最多 4096 字节。地址/IM/关联人标签必填，条目保持顺序，不自动去重。
- 日期含 `kind/label/calendar/year/month/day/is_leap_month`。kind 必填且为 `birthday/anniversary/other/custom`，不按 label 推断语义。自定义名称必填，其余类型 label 可空。每个联系人公历生日和农历生日各最多一项，其他类型可重复。历法为 `gregorian` 或 `chinese_lunar`，year 可空；公历支持 1..9999，指定年份的农历支持 1901..2100（以农历新年所在公历年份编号），month 1..12。
- 公历按月份/闰年校验日数，未知年份允许 2 月 29 日，不允许闰月标记；指定年份的农历由 `chinese-lunisolar-calendar 0.2.5` 校验该年实际月份、闰月和 29/30 天日数，范围外明确拒绝。未知年份的农历保留普通月或闰月 1..12、日 1..30，只校验结构，不按任意年份判定存在性。不进行历法转换、庆祝策略或提醒计算。

## 查询与冲突

列表按 display_name/id 排序，limit 1..500、默认 100，offset 为匹配项偏移。搜索对显示名、姓名前后缀及细分、手填拼音、昵称、组织、职位、网站、备注及电话/邮箱/地址/IM/关联人值做 Unicode lowercase 子串匹配，不做拼音/模糊检索或语言排序。搜索词最长 1024 字节，内部每次最多读 64 行，最多扫描 100032 行；超限明确失败，不返回伪完整结果。无索引与大通讯录性能保证。

CLI list 的 `contacts` 是投影分页；`conflicts` 是全体联系人冲突（独立于分页/搜索；群组和成员冲突通过 groups/conflicts 查询），包括删除投影。get 返回 `{contact,conflict}`；当投影为删除而存在冲突时 contact=null，但调用成功并提供候选。不存在且无冲突返回 not_found。

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

## 图形宿主的编辑基线

`AddressBook::save_guarded(id, expected, replacement)` 在 SDK 受控写事务中比较完整已观察联系人文档；仅匹配时替换或删除。已删除/基线变化返回 `edit_stale`，不写入业务数据或新增 outbox；多头返回 `conflict_requires_resolution`。既有 CLI update/delete 契约保持不变。该基线是完整文档相等，不是操作版本历史比较。

`card-weave-app-host` 串行拥有一个 AddressBook，FRB 异步调用在 worker 执行，另有独立取消句柄。同步前同步注册 Cancellation，保存/删除/解决先取消同步，再等待现有原子片段结束并检查基线。UI 可浏览缓存和编辑草稿；不另开业务 SQLite 连接。错误通过 `{ok, data/error:{code}}` 结构化响应传递，不包含原始传输错误、密码或密钥。同步配置直接提供会话凭据，不修改进程环境变量。

## 共享日历计算

核心 `calendar_options(calendar, year)` 同时用于联系人校验和应用宿主 `calendar_options` 命令，后者无需打开通讯录。返回 `{min_year,max_year,year_specific,months:[{month,is_leap_month,days}]}`，月份按时间顺序排列。指定农历年份只有真实存在的 12 或 13 个月；未知年份提供普通月与闰月各 12 项，不推断出生年或未来庆祝日期。Flutter 只展示该结果，不维护第二套月长/闰月计算。未知年份补上年份后，若所选闰月或日不存在，必须重新选择，不自动改为普通月。

依赖使用有界历表，限定在其支持的 1901–2100 农历年；代表月份和日数以香港天文台历表验证，并不声称提供范围外的天文计算。界面不提供已有日期的公农历转换，也不包含系统生日写入或提醒策略；新增日期的今日换算见下文。

应用宿主 `calendar_date` 命令接受 `{calendar, year, month, day}`，输入为设备本地公历日期，返回目标历法 `{year, month, day, is_leap_month}`，无需打开通讯录。Flutter 每次添加日期时传入设备本地今天，Rust 使用相同农历库换算，不读取宿主 UTC 日期；无效公历或超出农历范围返回错误，不伪造默认值。现有日期及手动选择不指定年份保持原值。
