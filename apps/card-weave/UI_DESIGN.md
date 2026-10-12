---
version: alpha
name: CardWeave iOS Grouped
description: CardWeave 统一 iOS 分组列表视觉规范
colors:
  primary: "#456B54"
  on-primary: "#FFFFFF"
  secondary: "#456B54"
  background: "#F2F2F7"
  surface: "#FFFFFF"
  text: "#1C1C1E"
  text-secondary: "#707078"
  border: "#D8D8DD"
  accent-container: "#E2E9E4"
  warning: "#705329"
  warning-container: "#F5EBD6"
typography:
  headline-lg:
    fontFamily: system-ui
    fontSize: 34px
    fontWeight: 600
  title-md:
    fontFamily: system-ui
    fontSize: 20px
    fontWeight: 600
  body-md:
    fontFamily: system-ui
    fontSize: 17px
    fontWeight: 400
  label-md:
    fontFamily: system-ui
    fontSize: 14px
    fontWeight: 500
  caption:
    fontFamily: system-ui
    fontSize: 13px
    fontWeight: 400
spacing:
  xs: 4px
  sm: 8px
  md: 12px
  lg: 16px
  xl: 20px
  page: 16px
rounded:
  sm: 8px
  md: 12px
  lg: 12px
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    rounded: "{rounded.md}"
    height: 44px
  content-group:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.text}"
    rounded: "{rounded.lg}"
    padding: "{spacing.lg}"
  divider:
    backgroundColor: "{colors.border}"
    height: 1px
  selection:
    backgroundColor: "{colors.accent-container}"
    textColor: "{colors.primary}"
    rounded: "{rounded.md}"
  body-text:
    textColor: "{colors.text}"
    typography: "{typography.body-md}"
  supporting-text:
    textColor: "{colors.text-secondary}"
    typography: "{typography.label-md}"
  warning-banner:
    backgroundColor: "{colors.warning-container}"
    textColor: "{colors.warning}"
    rounded: "{rounded.md}"
---

## Overview

统一采用 iOS 通讯录与设置式分组列表。信息与操作沿着同一套行式布局展开，主页面使用可折叠大标题。使用 Flutter Cupertino 组件和图标；不包含 Liquid Glass 折射材质，不承诺与最新 iOS 逐像素一致。Android 使用本机系统字体、状态栏、键盘和返回行为。

## Colors

中性灰背景、白色分组、深色正文，鼠尾草绿仅用于操作与选择。浅色 token 见 front matter。深色页面 #000000、分组 #1C1C1E、正文 #F5F5F7、辅助 #A5A5AE、强调 #A8C4AF、分隔 #38383A。错误结合说明文字，不仅使用颜色。

## Typography

大标题34，滚动收起后导航标题17；详情姓名28，正文与输入17，说明13。字体随平台提供，不向 Android 分发 Apple 字体。大字号和长内容自然增长，不以缩小字体替代适配。

## Layout

页面边距16；分组标题上24下8；组内左右16。普通表单行最小52，备注最小88；两行联系人最小64。导航与底部标签栏使用 Cupertino 的标准视觉高度，安全区额外计算。按钮最小44触达区域。宽屏内容最大680。主列表、同步和设置各自使用单一 sliver 滚动容器，使大标题与内容在同一滚动链中，不让固定导航覆盖内容。标签切换保留页面状态。

## Elevation & Depth

分组使用白色或深色表面，不用投影强调普通内容。弹窗与底部菜单使用 Cupertino 模态层次。成功信息和同步结果在相关页面内呈现，不使用全局彩色浮动通知。

## Shapes

分组圆角12；头像统一圆形；搜索使用 Cupertino 搜索框。组内分隔线按普通行、图标行和头像行对齐内容起点，右侧留16，使用1物理像素；右端不贴边。无套叠的卡片边框。普通行在错误、大字号或长文本下允许增高。

## Components

公共组件按职责放在 `lib/ui/components/`；颜色与尺寸分别由 `lib/ui/theme.dart`、`lib/ui/tokens.dart` 管理。`lib/design.dart` 只导出公共接口。联系人业务组合在 `lib/contacts/`，开发预览在 `lib/ui/gallery.dart`，不加入产品导航。

主入口为联系人、同步、设置。大标题滚动折叠；新建入口在联系人右上角。详情右上编辑；编辑以模态路线打开，取消与完成位于顶部，保留未保存退出确认和过期草稿检测。默认仅录入姓名；同组展开姓氏、中间名和名字，展开本身不保存或猜测拆分。修改细分姓名后按内容组合显示姓名；已有自定义显示姓名与细分内容不一致时，需确认更新。电话、邮箱分别成组，自动保留一个尾部空输入行，空行不保存。联系方式标签可从菜单选择或自定义，删除控制与值分列显示。联系方式和日期统一使用 TypeLabel：17号文字、6间距、12号 Cupertino 向下箭头，不将 Unicode 箭头拼入文字。

日期收起为一行，当前编辑项展开滚轮。公历、农历生日各一个；有效年月日、无年份与闰月语义由 Rust 核心统一计算，界面不添加独立闰月开关。有效选择直接更新联系人草稿，未完成项阻止页面保存；无日期级确定/取消按钮，页面取消统一放弃修改。所有新日期默认设备本地今天，公历使用当前年月日，农历由 Rust 换算对应日期；年份滚轮的“——”表示不指定年份。保留自定义标签和加载失败重试。

同步使用状态行、手动动作行与连接入口。同步中支持取消，错误和结果就地展示。冲突页列出不同字段并提供完整候选，明确区分删除版本；采用和编辑合并仍由核心做完整联系人版本解析，用户确认后才执行。设备来源只展示实际版本元数据。

设置保留 WebDAV、S3 配置与安全存储选择；同步配置保存并不表示已连接服务器。复制加入信息给出就地反馈。凭据与联系人同步分离。

## Do's and Don'ts

- 同时维护浅深色、小屏、大字号、软键盘与系统返回。
- 仅使用 Cupertino 与 Flutter 基础 widgets；不依赖 Material 组件、主题或本地化适配层。
- 不引入未经核心支持的字段合并、拼音索引、系统联系人、自动提醒或后台同步。
- 实际 Android 执行与静态设计预览分别记录；Android 通过不代表 iOS 已验证。
