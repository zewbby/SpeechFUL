# TELEGRAM-MOTION-01 — 借鉴 Telegram 的交互动效

- 模式：指挥。2026-11-06 用户明确要求“基本能做的都做，工作量太大你先划分为几个模块，然后用 orchestrator 来做”。
- 负责人／状态维护人：当前 Session。
- 执行 Session：按下方模块派发独立子 Agent；本入口负责唯一任务记录，不创建侧栏新聊天。
- 分支／Worktree／PR：集成分支 `codex/feat/telegram-motion`；`E:/Hnuhole-env/source/SpeechFUL-telegram-motion`；PR [#107](https://github.com/zewbby/SpeechFUL/pull/107)（Draft）。实际基线为已 fetch 的 `origin/main`，`e9bfa80595cd05621ff86bd9da8fade284150110`。执行模块使用独立分支及 Worktree。
- 本轮规则版本：AGENTS.md 与 CONTRIBUTING.md 的最近修改提交均为 `a4d7228a0dd4b91e851746ab7f9fb37d1ec806b5`；orchestrator Skill 最近修改提交为 `454653b329b3d22a1b712c882c9ace942d5a7c16`。全部以本任务基线中的文件内容生效。任务契约版本为本文件下方 **v1**，派单时绑定承载本次文档的提交。
- 授权依据与边界：2026-11-06 用户最初要求把适用效果应用到 SpeechFUL；本轮进一步明确“合并、装机，验真机手感、帧率及远程 CI”，授权本任务 push、PR、通过门槛后合并，以及同签保数据装机和真机/帧率验收。正式后端/生产部署不在本轮；不卸载/清数据，不绕过认证或安全 Gate，不给真实他人发送测试消息。
- 恢复专项授权：既有日常开发连接拒绝后，普通 resume 在 2026-11-06 02:23:47Z 检出 C DB/anchor 高水位差异并触发保护性冻结。用户随后明确选择“授权恢复，接受重新登录（推荐）”，授权按既有部署流程显式恢复 C Gate，接受 C 授权代次提升及旧 C 会话失效；不恢复 V 代次、不重置 schema 或清理业务数据。
- 需求确认：已使用 `grill-with-docs` 组合技能核对现有源码并集中询问。用户 Q1 确认“基本能做的都做”并要求按模块指挥执行；Q2 选择“按推荐，先做好日常反馈”；随后确认五模块方案并授权“按照你建议的模型及强度来做”。沿用 Flutter/Dart、现有布局／配色／业务流程，完善所有适用的日常反馈；玻璃折射、持续扫光、大粒子消散和未有业务的剧透／贴纸功能不在本轮。执行模块使用 GPT-6.1 Sol / high，独立集成审查使用 GPT-6 Astra / high。
- 更新日期：2026-11-06。
- 状态：产品实现、独立AI审查、同签0603安装及本轮真机覆盖项 PASS；最终包滚动P95仍达标，少量输入后布局尖峰保留；远程CI/合并以[PR107当前检查与实时状态](https://github.com/zewbby/SpeechFUL/pull/107/checks)为准，入口核对当前head门槛后按已有授权合并；未正式发布。

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

### 交付契约 v2（2026-11-06）

产品契约 v1 和既有行为不变。本轮按用户新授权扩大交付操作，派单绑定承载本节的固定提交；规则版本与前轮相同。

- CI 单元：独立只读监视本任务 PR 的当前 head/测试合并提交及全部适用产品 workflow，报告真实失败日志；不自行合并、改仓库设置或降级检查。
- 构建准备单元：在独立 Worktree 基于同一产品代码准备 profile、原 public origins/CA、原测试签名和更高 versionCode；不得打印/提交凭据，不操作设备/后端。优先用 VM timeline 取 build/raster 帧数据；如需外部测量入口，明确记录仅测量 observer 的源码差异，最终日常包保持正式 main.dart。
- 入口 Session 独占设备：核对 vivo `10CEAG17RY003M7` 的租约、已装包/签名、解锁和显示模式；原租约已 released 后才登记本任务。保留应用数据，使用同签 `adb install -r`，不使用卸载、清数据、签名绕过或数据库 fixture reset。
- 真机操作：导航/个人分类/菜单/设置、帖子与评论按钮/数字、私信状态、图片打开/拖动取消/退出和减少动画按可达范围验证；涉及真实业务写入时只使用本任务明确拥有的合成 fixture，真实其他人的消息不发送。生产组件内存场景与真实后端场景分开记证据，不相互冒充。
- 帧率：profile 模式、当前真实显示刷新率、预热后采样；记录场景、样本数、build/raster P50/P95/P99/max、超刷新预算数、呈现帧间隔和可用的实际观察。60Hz 时 build/raster P95 目标均不超过16.67ms；样本不足保持待验，冷启动/首次着色器尖峰单列。不得拿 debug、Android UI线程 gfxinfo或静态截图冒充 Flutter 帧时序。
- 合并前核对当前 PR head 的适用产品 CI、独立审查与本轮必要设备证据；故障先修复并聚焦复验。合并后确认 main/合并 SHA 与被测产品代码对应，交付已安装包的实际版本、签名及哈希；正式生产仍未发布。

### 滚动性能修复契约 v4（2026-11-06）

用户反馈“滑动帖子的时候帧率很低”；本次已核对设备实际停在首页“最新”列表。目标为定位并修复可复现滚动掉帧，沿用 v1 交互和 v2 性能门槛，不改变列表模式、数据、鉴权或业务流程。先 profile 真机采样并结合源码/CPU 堆栈定位，再作有证据的最小修复；调试附加 instrumentation 的采样不充作最终性能验收。root 独占设备及唯一任务记录，执行者独立 Worktree，不控制设备/后端。

- SCROLL-DIAG：Sol/high，只读审计真实 FeedScreen 的滚动构建、布局与动效链路，回报可验证触发机制及外置工作量诊断，不能把调试测试当真机帧率。
- SCROLL-FIX：定位后派给原模块所有者，在独立分支交付修复、覆盖复现原因的适用聚焦验证；root 集成并同签升级 profile。保留原页面/数据流程及图片权限代次，禁止以关闭正常内容/动画掩盖卡顿。
- SCROLL-REVIEW：Astra/high，独立审查修复及证据；最终设备样本覆盖固定双向滑动、预热/冷样本分列，记录真实显示刷新率及完整采样范围。帧性能门槛沿用v2的P95目标；超预算帧和未解释尖峰单列，不宣称每帧达标或全程满帧，未解决的重复掉帧机制保持待验。
- PR #107 保持 Draft；完成当前 head 的产品 CI、独立审查与必要设备验收后再按已有授权合并。

### 恢复专项契约 v3（2026-11-06）

- 产品 v1、装机/CI/帧率交付 v2 不变。仅允许使用已部署 `8582593` 的 `authdev recover`、既有 C operator 与 5 分钟证据有效期，显式恢复 C 一次；预期 C generation/recoverEvents 10→11，Gate FROZEN→OPEN，DB/anchor 一致。
- 恢复后只读核对状态，随后用既有普通 resume 入口续签 C/V 证据并启动原 watchers/API。预期 V generation/recoverEvents 仍为8，普通 resume 不新增 RECOVER。任何非零、代次异常、DB/anchor 不一致均停止诊断，不自动重跑 RECOVER。
- 禁止直接修改 Gate/anchor、改钟、reset fixture/schema、迁移或清理用户业务数据。源码已只读核实 Recover 仅更新 Gate/审计/签名证据与 anchor，不删除 session 或业务表；旧会话仍由原代次检查拒绝。具体私有操作参数和脱敏回执留在本任务外部证据目录。

### 图片返回显示修复契约 v5（2026-11-06）

0602真机完成分类、设置语言切换并恢复中文、图片打开/短拖回弹/长拖退出后，发现黑底viewer退出后首页状态栏图标仍浅色、白底难以阅读。已核对main基线也只有viewer持有AnnotatedRegion，PrimaryTabs没有自己的样式；是既有缺口，不冒称本轮引入。按既定图片返回正常页面的验收范围作确定性修复，无新增产品取舍。

- SYSUI-FIX：Sol/high复用独立scroll-fix Worktree，ff本节固定提交；仅改PrimaryTabs及navigation_motion_test，为根标签页声明随实际主题变化的系统栏样式，使viewer/子路由覆盖后可自然恢复，不使用全局持久设置，不更改业务/数据/滚动或屏幕刷新率。聚焦回归须覆盖浅/深主题、viewer覆盖和pop后解析到原页面样式。
- SYSUI-REVIEW：Astra/high独立复核及原始回归，root同签0603装机后验证图片退出状态栏可读、滚动门槛未退化；最终head CI重核，旧head只历史证据。

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
| 远程 CI | PR107 head c3f27381、base e9bfa805、测试合并67f2b0fb；Sol/high只读核查 | PASS。11适用workflow、22 job成功、1既有条件SKIP；全部22成功job实际checkout已核对（19测试合并、3精确head）。不覆盖之后产品修复。外部证据 ci-pr107-c3f27381-{final,checkouts,checks}.json。 |
| 同签真机安装 | vivo V2323A / 10CEAG17RY003M7；profile c3f2738，产品等价3f5424b；正式main.dart、原开发origins/CA | PASS。保数据install-r，用户完成vivo本人验证；实际versionCode2026110601，证书1538fb30…，APK SHA256 ae021cc8e29e4a41f7ea6bddc6e29ce8ef2ae1ee04c2e3c0f610e856086012cf。私有原始证据 E:/Hnuhole-env/telegram-motion-device-20261106。 |
| 开发连接恢复 | 已部署8582593，C30/V7，原WSL2运行时；用户专项授权v3 | PASS。普通resume检出anchor领先23.898ms并保护性冻结；授权后既有authdev recover仅一次EXIT0。独立核对C OPEN/gen11/recoverEvents11、DB/anchor一致；V OPEN/gen8/recoverEvents8未变；随后普通resume启动4服务、C/V ready且recoverInvoked=false。没有schema重置/迁移或业务数据清理。 |
| 滚动问题初次采样 | 同一profile，首页最新，60Hz，固定双向滑动、预热2cycles | FAIL（性能门槛，待修复）。timeline环形buffer末4.89秒213帧：build P50/P95/P99/max=5.061/16.726/20.362/28.323ms、11超16.67；raster=2.693/5.862/9.780/23.963ms、1超预算。布局P95=13.382ms，正在进一步归因；该局部窗口不冒充完整12.63秒采样或总FPS。原始scroll-before-warm.private.json及summary。 |

### 滚动修复与真机对比（v4补充）

- 修复：Sol/high `51d23d6ecf1b024864b2b78a237a562a490513b2`，集成 `e257b1714c807ca9de86268e596c0fee9bd28d0a`，两提交产品差异0。PrimaryTabs body读取Scaffold动态MediaQuery并逐帧新建所有tab配置；拆出独立padding wrapper，稳定child由真正tabs build构造。原始外置复现首页3→18、隐藏DM2→17，修复后3→3/2→2。Sol联合55项、analyze/原锁PASS；Astra独立原始2项及导航/账号总45项PASS，无剩余可行动代码问题。真实size/insets/textScale、返回State、TickerMode及authority更新仍传播。
- 装机：`e257b17` 正式 `lib/main.dart`、profile、ARM64，同一origins/CA/StorageScope，同签保数据install-r PASS，实际versionCode `2026110602`。证书 `1538fb30…`；APK SHA256 `d83691035a98d4e7c057010ca9cf4ca99c8d927371b1f8297014c5128461d69c`，59,623,173字节，AOT/签名校验PASS。没有卸载、清数据或注入fixture/observer。外部证据 `profile-after-build-metadata.json`。
- 场景：同一vivo/60Hz、首页Latest/20帖，修复后准备offset2991（旧版最后测量位置3010），先访问个人/DM再回首页，预热2cycles后固定500ms双向3cycles；稳定列表再独立复样3cycles。后两组均保留，没有挑选结果。全部原始文件在 `E:/Hnuhole-env/telegram-motion-device-20261106`，不入仓。

| 样本 | UI Frame P50/P95/P99/max ms；超16.67 | Raster P50/P95/P99/max ms；超16.67 | SF观测pointer包络内呈现间隔 |
| --- | --- | --- | --- |
| 修复前完整分段基准；394对 | 4.430/14.453/18.144/33.465；9 | 2.662/5.129/5.914/8.859；0 | 139项，P95 33.230/max49.864ms，14>25ms |
| 修复后预热基准；379对 | 4.135/10.950/32.269/59.020；8 | 2.671/5.306/6.316/23.119；1 | 152项，P95 16.624/max33.218ms，2>25ms |
| 修复后稳定复样；406对 | 4.313/11.988/18.275/57.628；7 | 2.762/5.657/6.841/14.266；0 | 153项，P95 16.619/max33.236ms，2>25ms |

结果：后两组均 **PASS（v2 P95门槛）**，持续手势期间的呈现明显改善，仍有输入后布局尖峰；不能称每帧达标。证据为 `scroll-before-present`、`scroll-after-present`、`scroll-after-confirm` 各自的 `.summary.json` 与 `.private.json`；Astra独立复算配对、时钟单位和窗口均一致。

口径：Frame为Flutter-driver统计的整个UI阶段（包含animation/build/layout/paint/postframe），不是孤立BUILD；按Frame小写b/e的id及Draw B/E配对，只算完整事件。每cycle取出清理避免环形覆盖，复合timeline覆盖范围从traceEvents取。SF取目标BLAST layer的actualPresentTime，用实际PointerEvent flow-start首末包络双端裁20ms筛选；不是physical input或总体FPS。第一组修复后59/35/33/32ms尖峰均在命令结束76–698ms后，以嵌套布局/构建为主，无GC时间重叠，仍真实保留。临时CPU/widget插桩仅用于诊断，全部flag恢复原值，不把插桩时长当验收。

### 最终0603与可见链路（v5补充）

- `ce42d4a10c79a9794a1f7f300acbe7a3790c3998` 集成为 `970dd68cb1abecc5e1bacfe56f1945ccbef84031`，产品差异0。根PrimaryTabs声明随Theme变化的statusBarColor/brightness，底部系统导航栏字段全null，无全局SystemChrome/系统设置改写。Sol联合80项与analyze PASS；Astra原外置浅深两项FAIL→PASS、原scroll两项PASS，联合18项PASS；独立AI审查无剩余可行动问题，非GitHub成员批准。
- 最终正式 `lib/main.dart` profile包同签保数据安装PASS，实际versionCode `2026110603`，签名证书仍1538fb30…；59,623,173字节，SHA256 `ed2f99cb368627537bc5b221e44ba2aaedff31c40264221be80be5445341da37`。构建43.4秒，原config/CA/StorageScope保持；`profile-final-build-metadata.json`。
- 0603真机重复图片打开→250px/800ms短拖回原位→900px/1000ms长拖退出：首页深色状态栏文字恢复，底部导航栏原外观保留。截图 `final0603-viewer-{open,short-return,exit-home}.png`。0602已核对个人页帖子/回复/喜欢/收藏切换、真实空态/回复、DM列表、菜单、语言中文→English→中文及返回阅读位置；0603重访个人/DM后回首页并聚焦复验图片与滚动。没有发送私信、点赞、发帖或重置数据；涉及写入结果/撤权/减少动画的其他路径由原组件/完整回归证明，不冒充全部真机业务已执行。
- 0603最终独立3cycles（已预热2cycles、60Hz、Latest20帖、准备offset2893）：UI Frame335项，P50/P95/P99/max=3.822/11.127/19.133/57.994ms，5超16.67；raster334项=2.455/5.091/6.571/10.751ms，0超；SF观测pointer包络147间隔，P95=16.619/max33.231ms，3>25ms。**PASS（v2 P95）**，仍保留偶发尖峰及不完整边界事件差异，不声称全程满帧。`scroll-final0603.{summary,private}.json`。
- 临时CPU/widget/layout/paint flags与原timeline streams均已还原（`final-diagnostic-flags.json`）；手机留首页、停止自动触控。原开发C/V连接与两条USB reverse仍供已装日常包使用，不误清理依赖资源。最终head CI及合并事实引用PR107实时检查/元数据，不用历史c3f2738/709789d冒充最终检查。

## 阻碍与下一步

五模块、三项审查问题、chrome逐帧tabs重建及图片返回状态栏已闭环。完整旧产品验证绑定 `3f5424b`；后续两文件修复分别为 `e257b17`、`970dd68`，有对应聚焦/独立审查、Android构建与0603真机证据；其后的更新仅本任务记录。保留输入后少量布局尖峰；转帖读取开始/结束全局通知是已证实的额外工作量来源，但没有证据把设备57–59ms直接归因于它，不跳过读取或安全检查作掩盖。正式生产未发布；PR107的当前head CI和实时合并状态为交付操作证据入口。

App 环境在 dot-source 通用脚本后将当前进程 `PUB_HOSTED_URL` 设为 `https://pub.dev`；图片包独立锁使用其原镜像 `https://pub.flutter-io.cn`，均使用原锁现成缓存，未升级依赖。源配置不匹配导致的原锁预检失败不计为产品 FAIL。
