# 群组、关联人与通讯录升级

## 数据身份与升级

新通讯录使用身份配置 version 2、SDK schema 2：contacts（表 ID 1）、groups（表 ID 2）和 memberships（表 ID 3）。联系人 document 仍为 version 2；身份版本、SDK schema 版本和联系人 JSON 版本是不同概念。既有身份 version 1 仍按单 contacts 表打开，不自动更改 SQLite 结构。

应用设置中的“升级通讯录”显式迁入新目录、新 dataset/device/incarnation，保留联系人 ID 和完整资料。用户必须先汇集所有设备修改并解决冲突，确认其他设备将升级并重新加入；程序只能确认当前源库已 settled，不能证明未连接设备没有修改。原数据库及远端 namespace 不自动删除。

核心迁移先创建 migration.pending 标记，以每批 64 条写入新库；重新打开目标并逐条核对后才移除标记。未完成目录不能通过 AddressBook::open 打开；失败或进程中断不修改源库。重试使用新目录，失败目录保留供检查，不将半成品当作已升级库。

应用验证完成后才原子替换 active-book.txt 指针；未指定指针仍使用 book。新指针发布失败会重新打开原库；新库已有后续编辑后，不提供会丢弃这些修改的直接回退。CLI migrate 仅产生经过核对的新库，不替用户切换路径。

新加入信息是 card-weave-join/2。旧 /1 信息在新设备加入时明确提示先在原设备升级；旧库仍可完成原 dataset 的手动同步。群组升级不修改 LocalWeave SDK 或其 submodule 引用，也不保留旧因果历史到新 dataset。

## 群组与成员规则

群组名称 trim 后非空，最多 128 UTF-8 字节且不含 NUL。本地创建/重命名按 trim + Unicode lowercase 拒绝已有同名；离线独立创建的同名群组同步后保留独立 ID，显示重名提示，不自动合并。

每个群组为独立 MV register。成员关系的稳定 ID 为固定 32 位 hex group_id、冒号、固定 32 位 hex contact_id，state 为 joined/left；每个关系独立同步。批量变更最多 1000 条，在同一 SDK 事务先核对全部 expected 状态，再整体写入；任一过期则不写入任何成员变更。

群组删除不删除联系人，不级联删除成员记录。删除群组的新同名替代品不继承旧 ID 成员；显式解决冲突恢复同一个 ID 时原成员可重新可见。成员引用的群组或联系人暂缺不阻止远端协议应用。正常计数只包括可用群组、可用联系人及无冲突 joined 成员；待确认状态单独展示。

成员加入/移出并发保留多头，显式选择 joined/left；群组改名/删除并发同样显式解决。冲突标识包含表/实体类型和 ID。采用结果只覆盖 observed 版本，新到达版本可能继续构成冲突。所有读取仍受业务校验约束，不把 SDK 协议校验表述成远端业务 JSON 校验。

联系人首页“列表”切换全部、未分组、自定义群组。搜索和分页在 Rust 核心按当前范围执行；存在有效群组成员待确认的联系人不误归类为未分组。不同成员变更不引入联系人整体冲突。群组管理页调整成员，联系人详情的“群组”页独立调整多个所属群组；取消均不写入。

## 关联联系人

relations 的每项为 `{label,value,target_contact_id?}`：无 ID 为手填，有 ID 为单向引用；value 保存选择时的姓名。每联系人最多 32 条，标签最多 128 字节、姓名快照最多 1024 字节；同一关系标签与目标 ID 不重复，不允许自关联。新增绑定目标须存在且无冲突；未变的既有失效绑定可以保留，允许编辑其他资料。

核心 relation_views 为 UI 提供当前名称和 available/manual/unavailable/conflict 状态。目标改名不会回写引用方；搜索同时匹配保存的快照和可用目标当前名称。目标缺失统一提示“可能未同步或已删除”，不虚构已知删除原因；冲突时显示快照，不挑某个候选冒充当前姓名。目标可用后重新解析即可恢复，无需新的引用方写入。

编辑保留手填、重新选择、改为手填和移除。改为手填时保留可读姓名、解除 ID；编辑页完成前仅修改草稿。手填同名不自动关联，不生成双向关系。关联目标解析只读一层，不递归展开环形关系。冲突候选展示实际保存的标签、快照与目标 ID。

## CLI 入口

保留原 contacts 命令。以下命令的错误仍采用现有结构化错误和退出码：

- `card-weave HOME init`：创建 schema 2 新通讯录。
- `card-weave HOME init-legacy [DATASET]`：显式创建旧格式，用于迁移验证或旧库互通；新用户使用 init。
- `card-weave OLD_HOME migrate NEW_HOME`：源 settled 且 version 1 时迁入新目录，返回新身份。
- `card-weave HOME groups REQUEST.json`：群组与成员操作。
- `card-weave HOME relation-views CONTACT.json`：解析联系人草稿中的关系展示状态。

群组 REQUEST 的 operation 为 list/create/rename/delete/members/set_members/contact_groups/set_contact_groups/contacts/conflicts/resolve。create 接受 name；rename/delete 接受 id 与 expected 原名。members/contact_groups 接受 id。set_members 接受群组 id 与 changes `[{contact_id,expected:null|"joined"|"left",joined:bool}]`；set_contact_groups 接受联系人 id 与 changes `[{group_id,expected,joined}]`。contacts 接受 group（null 全部、空串未分组、其他群组 ID）、search、offset，返回最多 50 条。

resolve 接受 table（2 或 3）、id、observed 版本列表与必须显式提供的 value。群组 value 为名称或 null（删除）；成员 value 必须为 joined/left，不以字段缺失推断删除。

## 验证边界

公开 CLI 与真实 SQLite、Fs/WebDAV/S3 本地参考后端验证迁移、新设备加入、群组成员收敛、并发冲突、批量过期原子性、关联目标改名/删除；1001 条合成资料验证分批迁移及实际进程中断后重试。Android 独立测试包验证群组管理、成员多选、筛选与关联人草稿操作。桌面 Fs 同步证据不等于 Android 本轮 HTTPS/S3 原生同步验证，iOS 仍未验证。
