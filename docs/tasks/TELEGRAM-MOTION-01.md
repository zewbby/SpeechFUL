# TELEGRAM-MOTION-01 — 借鉴 Telegram 的交互动效

- 模式：指挥。2026-11-06 用户明确要求“基本能做的都做，工作量太大你先划分为几个模块，然后用 orchestrator 来做”。
- 负责人／状态维护人：当前 Session。
- 执行 Session：按下方模块派发独立子 Agent；本入口负责唯一任务记录，不创建侧栏新聊天。
- 分支／Worktree／PR：集成分支 `codex/feat/telegram-motion`；`E:/Hnuhole-env/source/SpeechFUL-telegram-motion`；PR 未创建。实际基线为已 fetch 的 `origin/main`，`e9bfa80595cd05621ff86bd9da8fade284150110`。执行模块使用独立分支及 Worktree。
- 本轮规则版本：AGENTS.md 与 CONTRIBUTING.md 的最近修改提交均为 `a4d7228a0dd4b91e851746ab7f9fb37d1ec806b5`；orchestrator Skill 最近修改提交为 `454653b329b3d22a1b712c882c9ace942d5a7c16`。全部以本任务基线中的文件内容生效。任务契约版本为本文件下方 **v1**，派单时绑定承载本次文档的提交。
- 授权依据与边界：2026-11-06 用户在 Telegram Android 最新源码研究后要求“可不可以把能应用到的应用到我的 SpeechFUL”。允许调查并落实确认后的适配；推送、PR、合并、正式部署与设备操作尚未授权。
- 需求确认：已使用 `grill-with-docs` 组合技能核对现有源码并集中询问。用户 Q1 确认“基本能做的都做”并要求按模块指挥执行；Q2 选择“按推荐，先做好日常反馈”；随后确认五模块方案并授权“按照你建议的模型及强度来做”。沿用 Flutter/Dart、现有布局／配色／业务流程，完善所有适用的日常反馈；玻璃折射、持续扫光、大粒子消散和未有业务的剧透／贴纸功能不在本轮。执行模块使用 GPT-6.1 Sol / high，独立集成审查使用 GPT-6 Astra / high。
- 更新日期：2026-11-06。
- 状态：实现已完成；本地自动验证/Android 构建 PASS，真机/帧性能及远程 CI NOT_RUN、整体待验；未合并；未发布。

## 目标与范围

把适合 SpeechFUL 日常使用的 Telegram 动效原理映射到现有 Flutter 组件，形成一致、可中断且不阻挡操作的反馈。完整覆盖共享交互、帖子／评论、导航／面板、私信和图片查看。保留既有列表数据、滚动、身份、请求和受保护资源归属机制。

## 任务契约 v1

### 拆分、接口与文件所有权

| ID | 目标与文件范围 | 依赖 |
| --- | --- | --- |
| MOTION-00 | 新增 `apps/mobile/lib/src/design_system/motion.dart` 与 `apps/mobile/test/motion_test.dart`，实现下面约定的共享 API。只写这两个文件。 | 无，优先交付可集成切片。 |
| MOTION-01 | 集成负责人接入列表 `posts/x_feed.dart`、详情／评论共享 `design_system/detail_components.dart` 及必要的消费者和互动测试；统一赞藏选中与计数动画。维护产品 CI 测试入口。 | MOTION-00。 |
| MOTION-02 | `navigation/`、`posts/personal_profile.dart`、`identity/settings_screen.dart`、`design_system/motion_routes.dart`、`design_system/telegram_theme.dart` 及相关导航／个人／设置测试。完善底栏图标、个人分类、现有菜单／面板与页面切换；保留 IndexedStack、返回栈和页面状态。 | MOTION-00 API；可以先读取和实现独立内容，再集成基础组件运行测试。 |
| MOTION-03 | `messaging/` 与私信相关测试。发送按钮按压及启用状态平滑变化、新追加消息局部进入、发送状态切换；不改变受理、失败、未知与已读判定。 | MOTION-00 API；不写 `post_images.dart` 或图片包。 |
| MOTION-04 | `packages/image_viewer/`、`posts/post_images.dart` 及 `apps/mobile/test/post_images_test.dart`。完善现有进入／退出、手势取消回弹、减少动画支持；可实现不依赖更改资源权限／新公开资源接口的缩略图衔接，失效来源直接回退现有淡入淡出。 | 保留现有资源生命周期和撤权检查；与 MOTION-03 文件隔离。 |

MOTION-00 的公共 API 固定为：

- `HhMotion.reduced(BuildContext)`：`disableAnimations` 或 `accessibleNavigation` 为真时返回真；`HhMotion.duration(BuildContext, Duration)` 返回对应时长或零。
- 常量 `HhMotion.quick` 为 160ms，`HhMotion.standard` 为 220ms，`HhMotion.pressIn` 为 70ms，`HhMotion.pressOut` 为 260ms，`HhMotion.curve` 为 `Curves.easeOutCubic`。可为释放回弹另设克制的曲线。
- `HhPressFeedback({Key? key, required Widget Function(BuildContext, WidgetStatesController) builder, bool enabled = true, double pressedScale = .96})`：把 `WidgetStatesController` 交给已有按钮；不增加抢手势的识别器，保留原始布局和点击区域，正确处理拖动取消、禁用、键盘和减少动画。不得在纯 pointer-down 时调用业务回调。
- `HhAnimatedCount({Key? key, required String text, TextStyle? style, TextAlign textAlign = TextAlign.start})`：只改变视觉表现，支持 Unicode／本地化／RTL，动画中读屏只暴露当前文本，初次显示不播放“变化”动画。快速更新可中断，行高不跳动。
- `HhAnimatedSelection({Key? key, required bool selected, required Widget Function(BuildContext, double) builder})`：连续 0–1 选中进度，初次展示直接使用目标值；变更可中断，减少动画即时切换。

若公共 API 确需变化，先通知总指挥修改本契约版本，不能各自建立同名不兼容接口。图片包保持独立，不反向依赖 App 的 design_system。

### 产品行为与验收边界

- 按压反馈只响应当前操作入口；后台同步不制造一次新的“点击”回弹。赞藏填充／颜色及数字跟随既有展示状态变化，原有乐观更新、串行意图、明确失败回退和结果未知核对保持。
- 动效局部、短促，可在连续点击、切页、切账号、前后台和系统减少动画变化时安全结束或中断；不得延迟原操作直到动画完成。
- 导航保留各栏已加载数据、滚动和选中态，隐藏页面的 ticker 仍停止；快速切换不能叠出两份可点击页面。沿用平台返回与键盘行为。
- 私信仅对同会话在当前底部新追加的消息做轻微进入；历史前插、重开会话、离开底部阅读、重试状态更新与后台恢复不重播历史消息。发送按钮与状态过渡不提前画成发送成功，不覆盖重试入口或清空失败草稿。
- 图片进入／关闭动画不延后权限失效处理，不复制额外的受保护明文资源，不为效果修改保存、撤权或来源代次规则。原有手势／后台取消和失效退出仍优先。
- 本轮不改首页静态骨架为持续扫光，不引入玻璃、灰烬或剧透新业务；无需新位图资产。实际 Flutter 组件／帧截图用于可见检查，不能拿生成图代证实现。
- 多 Agent 可报告证据，但仅入口 Session 更新此任务文档。执行 Agent 不自行委派。

## 接口与依赖

- Telegram 参考为当前官方公开源码 13.1.1（7237），提交 `3de37c8cfb039452be7398909461da6288babf15`。官方安装包已更新到 13.2.0；后者尚未找到对应公开源码，不冒称已验证其新增效果。
- 保留其他工作区所有已有差异；`SpeechFUL-global-hotlist` 存在未提交内容，本任务只采用其共享仓库中已提交的 `origin/main` 基线，在独立 Worktree 工作。

## 验收标准

- 赞藏、取消、连续点击、权威失败回退时，图标与计数跟随同一真实展示状态；动画期间仍可操作且语义不重复。
- 底栏／个人分类快速切换及进入／关闭面板时，可见选中态与当前内容一致，返回仍保留原滚动和数据。
- 私信新增与状态过渡符合上述同会话／底部条件，未知结果保留等待含义，历史与账号切换不产生假发送动画。
- 图片打开、拖动取消、关闭及权限失效沿原完整链路工作；减少动画即时呈现，非减少动画路径平滑且有界。
- Flutter analyze、各模块聚焦测试、集成相关回归和 Android 目标构建通过；真实设备与性能证据按实际覆盖登记，缺失必要范围保持待验。产品 CI 配置包含新增测试，远程实际执行须待推送／PR 授权。

## 当前进度与证据

| 项目 | 被测版本／环境 | 结果与证据 |
| --- | --- | --- |
| 仓库与基线 | Windows；实际源码仓库及所有 Worktree 已核对，已 fetch `origin/main` | PASS。本任务独立分支从 `e9bfa805` 建立，未触碰历史工作区内容。 |
| 实现调查 | 同一基线，`apps/mobile` 与 `packages/image_viewer`，只读协助 Agent | PASS（事实调查）。已核对已有静态赞藏／计数、导航与个人分类、搜索、面板、私信及图片手势；不把源码检查记为产品验证。 |
| MOTION-00 | 集成 `34ab139`、`47f0f47`、连续性修复 `f922e17`；Sol/high，独立 Worktree | PASS。固定 API 已实现；原锁离线依赖、最终 14 项聚焦测试、限定 analyze 均通过。测试覆盖原生按钮/键盘/取消、无重复动画启动、任意连续数值与反向回退逐层连续、Unicode/RTL、语义及两种减少动画。 |
| MOTION-01 | `07d2fe4`；Windows Flutter 3.47.5 / Dart 3.13.4，原 App lock；`flutter test --no-pub test/interaction_motion_test.dart --reporter expanded` | PASS，3 项实际集成反馈测试。原生按钮样式仍有减少动画过渡的早期 FAIL 已修复；当前自定义及原生样式时长均遵守设置。`telegram-motion-focused.log`。 |
| 首批静态分析 | `07d2fe4`，App 目录 `flutter analyze --no-pub` | PASS，无问题。`E:/Hnuhole-env/tmp/telegram-motion-analysis-first.log`。早期一次从仓库根使用 App 相对路径的命令未执行有效分析，未计入证据。 |
| MOTION-02 | 模块 `1ba277d`，集成 `2e3ff4c`／`264968e` | PASS。模块 52 项联合回归，最终导航／设置 14 项及 analyze 通过；root 集成后的共享、互动、导航 55 项通过，`telegram-motion-integrated-first.log`。 |
| MOTION-03 | 模块 `0943e137`／焦点修复 `6890038`，集成 `b9860eb`／`3f5424b` | PASS（模块范围）：首版 152 项、3 个既有专用真实 HTTPS/SQL fixture SKIP；最终焦点修复相关 53 项及 analyze 通过。空会话不推断首发进入；发生后台/hidden 的已挂载会话保守停止气泡进入直到重开/切会话，发送按钮和状态动效保持。证据 `E:/Hnuhole-env/motion-messaging-evidence/`。 |
| MOTION-04 | 模块 `1f08d72`，集成 `57d0ffe` | PASS：图片包 138 项，App 图片入口 23 项，分析 0；证据 `E:/Hnuhole-env/evidence/telegram-motion-01/`。按钮/系统返回仍即时关闭；未实现来源缩略图共享元素，不复制受保护资源。撤权后的晚到 pointer 访问已释放 ticker 的初轮 FAIL 已修复并复验。 |
| 首轮联合可见链路 | `4aa6e64`，导航/私信动效/图片入口三个 test 文件 | PASS，45 项，`E:/Hnuhole-env/tmp/telegram-motion-integrated-surface.log`。包含保留手势、减少动画及撤权。 |
| 真实 Flutter 渲染 | `264968e` 中的相关 UI；现有打包字体 | PASS（静态可见范围），已查看帖子选中态、浅色个人页、深色语言页及私信进入中间帧；`E:/Hnuhole-env/tmp/telegram-motion-renders`、导航模块 `build/profile-settings-render` 和私信证据目录。不是设备/帧率证据。 |
| 独立审查与修复 | Astra/high，`/root/motion_review`；最终 `3f5424b33c51271b6ea43c75cf714e4ce30b66a9` 相对基线 `e9bfa805` | PASS（AI 审查）。计数反向不连续、减少动画 pop 延迟、旧私信重试可被 Tab+Enter 激活三项 P2 均由原始外置复现 FAIL→PASS，四个动效文件加三项复现联合 46 项 PASS，未发现剩余可证实可行动问题；外置复现位于 `E:/Hnuhole-env/motion-review-evidence`。不是 GitHub 成员批准。 |
| 最终静态分析与原锁 | 同一 `3f5424b`；App 及图片包 `flutter pub get --offline --enforce-lockfile`、`flutter analyze --no-pub` | PASS，均无问题且锁无变动；`E:/Hnuhole-env/tmp/telegram-motion-{app,viewer}-{lock,analysis}-final.log`。 |
| 最终图片包回归 | `3f5424b`，图片包目录 `flutter test --no-pub --concurrency=2 --reporter expanded` | PASS，138 项；`E:/Hnuhole-env/tmp/telegram-motion-viewer-tests-final.log`。 |
| 最终 App 完整回归 | `3f5424b`；`flutter test --no-pub test --concurrency=2 --reporter expanded` | PASS，1138 项，4 项 SKIP（3 个既有专用真实 TLS/PostgreSQL fixture、1 个需指定头像复现输入的用例）；没有失败，约 3分07秒。`E:/Hnuhole-env/tmp/telegram-motion-app-tests-final.log`。 |
| Android 目标构建 | 同一 `3f5424b`；`flutter build apk --debug --target-platform android-arm64 --no-pub` | PASS，assembleDebug 35.5秒；`E:/Hnuhole-env/tmp/telegram-motion-android-build.log`。未改依赖/平台配置，未装机。 |
| APK 校验与交付 | 同一被测产品源码；Android Build Tools 36.0.0 `apksigner verify --verbose`、`aapt2 dump badging` | PASS，APK v2 签名有效；包名 `org.hnuhole.hnuhole_mobile`，显示名 SpeechFUL，debug 0.1.0+1。交付文件 `E:/Hnuhole-env/deliveries/telegram-motion-20261106/SpeechFUL-motion-3f5424b-arm64-debug.apk`，114,249,644 字节；源输出与交付副本 SHA256 均为 `0d1b4c83a9047c1e5bd2d5c70a53fe1701264e735ae7f35aaf62512026d25b69`。仅证明 ARM64 目标构建，包内其他依赖 ABI 不宣称运行验收。 |
| 远程 CI / 真机 / 帧性能 | 尚未推送、创建 PR 或操作设备 | NOT_RUN。新增测试已接入产品 CI；本地结果不冒充远程 CI、整机、帧率或生产验收。 |

## 阻碍与下一步

五模块及三项审查修复已闭环，本地可交付。验证绑定产品提交 `3f5424b33c51271b6ea43c75cf714e4ce30b66a9`；其后的更新仅为本记录，不改变已测产品代码。尚未推送/创建 PR/合并/发布或操作用户设备；后续若进行真机、帧性能或远程 CI，按对应授权与实际环境继续验收。

App 环境在 dot-source 通用脚本后将当前进程 `PUB_HOSTED_URL` 设为 `https://pub.dev`；图片包独立锁使用其原镜像 `https://pub.flutter-io.cn`，均使用原锁现成缓存，未升级依赖。源配置不匹配导致的原锁预检失败不计为产品 FAIL。
