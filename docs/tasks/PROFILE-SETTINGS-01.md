# PROFILE-SETTINGS-01 — 我的页面与设置入口调整


## 2026-11-04 主线集成候选

- 2026-11-04 续办：用户明确授权续签本机开发证书、恢复原开发服务，以及推送设置功能分支、开 PR 并运行产品 CI。初版候选 `3a94108` 已推送，随后整合最新主线 `663adbc` 的 SpeechFUL 显示名称。冲突处保留主线名称及设置分支的通知正文、刷新无障碍文案本地化。下列 `06bee79` 验证与推送拒绝为上一时点证据。
- 当前工作为常规交付续办。来源 `9a36e8f`，以 GitHub `main@06bee79` 为基线，在隔离副本的 `codex/feat/profile-settings-delivery` 整合。原设置分支和其他工作区均保留。
- 按已确认的 v3 需求合入新版设置、四语言、设备与安全入口及注销交互。整合保留主线头像处理及首页当前身份头像。通知、私信和个人页标题保留主线主题蓝色并随语言更新，通知字号与私信一致。个人页测试保留主线标题颜色检查，并覆盖设置分支的五项分类选中态。
- Windows Flutter 3.47.5：`flutter pub get --offline --enforce-lockfile`、`flutter analyze --no-pub` PASS。首次全量回归 FAIL，主线头像测试仍通过点击首页头像进入个人页。按已确认新版入口，改从底栏进入个人页，保留头像跟随身份及同身份更新的断言。最终 `flutter test --no-pub --concurrency=2 test` 1057 PASS／4 SKIP；跳过项按各自夹具条件保留。此次复验只改上述测试和本记录，应用源码与通过静态分析和构建的 `bed6eca` 相同。
- Android Profile 构建 PASS：首次构建的 Kotlin 增量缓存失败，使用 Gradle `--offline assembleProfile`、进程内 Kotlin、关闭 Kotlin 增量编译复跑成功，沿用原开发配置与 `AUTH_DEV_PROFILE=true`。包名 `org.hnuhole.hnuhole_mobile`、版本 `2026110401`，APK v2 验签 PASS，证书摘要与原设备交付记录一致；APK SHA-256 `8afb0935263e3daef506d5d8c772fd8cacd2fbf69b730bb4e2a0c7f390131cdd6`。
- vivo 业务验收 BLOCKED：已识别指定 vivo，现装 `2026103104`。两个开发端点拒绝连接，恢复器的固定部署静态校验 PASS，但启动在 C Gate 的证书验证处拒绝。只读确认 C/V 内外证书于北京时间 2026-11-02 18:24:50 到期，原 CA 尚在有效期。未更换证书、重新批准部署清单或执行安全恢复；候选未安装，既有装机结果仍限定在原版本。
- GitHub 产品 CI NOT_RUN。自动审批拒绝向功能分支推送，因为该提交包含项目源码和资源，当前授权未明确涵盖向 GitHub 发送这些内容。PR、主线合并和发布均未执行。续办需要明确授权推送和开 PR；设备联调需要先续签开发证书并核验部署清单与严格 TLS 就绪。

## 当前轮次：v3-implementation（2026-10-30）

本节为最新范围；下方 v2 实现与安装记录保留原时点事实，不代表新增要求已经完成。沿用集成分支，实际依赖基线 `ce22f3c`（已装 vivo 的未合并 v2）；规则仍采用 `a4d7228`，实现契约 `99806ba`。入口 Session 维护唯一状态，三执行者已按该契约分工实现并交叉审查。

- 用户新要求：右滑打开窗口；主设置移除私信通知；注销独立标题／流程／输入「确定注销账号」／红色确认按钮／取消和确认弹窗；删除身份文案换垃圾桶图标；语言新增繁体中文和日语并真正切换；设备管理仅设备与会话；恢复凭据和 Passkey 移到账号与安全；意见反馈只保留意见并投递指定邮箱；支持我们接支付宝。
- 已确定：右滑替代 v2 的左滑开启；图标、入口删减、语言选项、设备与安全入口分离的直接要求不重问。
- 用户已确认 Q1 全 App 自有界面四语言并记住选择，帖子／评论／昵称保留原文；Q2 最终注销弹框输入当前密码，保留七天缓冲期；Q3 改为展示邮箱 `zewbby666@gmail.com`，不再投递反馈；Q4 使用支付宝收款码，并已提供原图。无未决取舍。右滑打开后左滑关闭；设备按用户「当前的设备与会话」仅显示当前会话，不新增多设备机制。
- 状态：实现 已完成；验证 本地全套＋最终聚焦＋Android 构建 PASS（设备／远端缺口见下）；合并 未合并；发布 未发布；vivo 新版安装及启动 PASS（2026-10-31）。用户已授权开发新增功能，原有 Push／合并／正式部署边界不扩大。禁止以真实账号注销、真实转账验证；不改变 C/V Gate、密码复验、会话代次和资源归属边界。

### v3 当前证据（持续汇总）

- 2026-10-31 vivo 安装收口：用户明确要求安装，实查 V2323A / `10CEAG17RY003M7`；原 APK 拉取并验签，与已交付 `a578e65` 安装包同签名。`adb install -r` Success，现版本 `0.1.0-settings-v3 / 2026103016`，firstInstallTime 仍 `2026-10-30 09:57:04`，保留数据。启动 Status ok。用户反馈「暂时无法进入」后核实 USB 重连使 reverse 丢失；恢复 `51245→51245 / 49747→54948`，沿原开发 CA 严格检查两服务 `/health/ready` 均200。点击已定位重试后，设备 UI 显示「打开设置／推荐／最新／首页／我的」，无原进入错误提示，进入首页 PASS；未操作 realme。当前安装事实覆盖下方历史未连接快照；完整原生相册／Passkey／系统通知验收仍不在本次安装结论内。


- 用户最新批注确认收款码下方原文：`您的支持将全数用于开发与维护SpeechFUL项目`；已加入支持页及四语言字典。原图资源 `apps/mobile/assets/support/alipay-receive.jpg` 在 `4fd06e3` 入库，SHA256 `3aa21d1a0807ed9c95fbb3d16a95533447961d3fce33e993a46837434e585764`；不重绘、不执行支付。
- P1 基础／认证四语言集成为 `f75cca9/ed44636/37145a5/6df9e7a`；S1 注销／设备／凭据／身份集成为 `cf25dc4/1ca9c27/4b0cf29`；M1 消息／通知／举报集成为 `50fcc84`。执行者聚焦验证分别 47／85／123 项 PASS，均为主机替身证据，不代表原生或真实 SQL 通过。
- root 基于 `50fcc84` 的本轮明确差异：main 全局语言与新路由装配、右滑开启、设置四语言／邮箱／收款码、社区自有文案与原文边界、CI 和对应回归。Windows Flutter 3.47.5／Dart 3.13.4：analyze PASS；设置／手势／真实字体流程 9 项 PASS；社区语言／主导航／跨账号／消息语言 33 项 PASS。日志位于 `E:/Hnuhole-env/profile-settings-20261030/v3-settings-fixed.log`、`v3-cross-route-fixed.log`。后续固定承载提交后复核差异。
- 图片 A/B 诊断：未解码时高度 0 导致默认 800×600 测试视口 offstage；按原图 2:3 预留尺寸后首次布局稳定，测试按真实长页滚动到说明和保存按钮。未添加等待绕过。
- 独立交叉审查：P1 审 root 文案／用户原文边界，发现社区弹层语言冻结与排序漏译；S1 审 M1 发现语言切换误报新消息及弹层菜单翻译冻结；M1 审 S1 发现单独移除注销页面可留下孤儿弹框。上述已分别由交叉修复提交处理并由入口 Session 复核差异。AI 审查不代表 GitHub 成员批准。远端 CI、本轮真机安装、原生 Passkey／相册／系统通知、iOS NOT_RUN。
- root 实现固定为 `68ba0fb`；审查修复集成为 `a42b775`（自有注销弹框退场／密码控制器释放）和 `ce52ccc`（预览版本与语言独立、两个私信菜单即时翻译），入口 Session 已复核差异。注销主按钮在 `8ef8e12` 定名「确认注销」，短语仍严格「确定注销账号」。
- `219bd53` 修复整套发现的字典自动匹配过宽：只含标点的模板不再自动匹配未知内容，显式命名参数继续有效。`ce52ccc` 全套尝试在 1043 PASS／3 SKIP／1 FAIL（上述已修复词条问题）后测试 host 挂起，入口 Session 通过专属 exec session Ctrl-C 停止，故此轮不记为全套 PASS。独立诊断固定 `ce52ccc` 的最后网络测试单项及整份 `post_api_test.dart` 34 项均 PASS，未修改传输实现；证据 `r-full-post-api-file-ce52ccc.log`，仅证明本机 loopback TLS 替身。
- `219bd53`＋随后由 `8ef8e12` 承载的明确差异：18 项最终聚焦（四语言窄屏渲染、模板边界、注销生命周期、消息语言状态）PASS；注销按钮命名后账号／身份语言与注销 10 项 PASS；支持页面独立 5 项 PASS（原图、用途说明、放大、权限拒绝不冒充保存成功）。日志 `v3-final-targeted.log`、`v3-closure-label.log`、`v3-settings-final.log`。实字体 PNG 已检查：原图／说明可读，四语 320 宽 1.8 字号可换行滚动，无溢出。
- vivo 安装延续同一设置任务的用户授权，仅允许原设备 `10CEAG17RY003M7` 同签名覆盖更新；2026-10-30 16:24 实查 ADB 仅 realme `7e0660f1`，vivo 未连接。已异步请用户接回，不操作 realme。本轮安装保持待设备，不冒用 v2 安装结果。
- 最终验证：`8ef8e12`（后续仅本任务记录文档差异）正常 Windows 用户环境、`flutter test --no-pub --concurrency=2 test`：1051 PASS／3 SKIP，耗时 2:26；3 项原有 HTTP fixture 用例缺外部测试环境，未宣称真实 C／SQL 通过。日志 `v3-all-mobile-tests-retry.log`。此重试使用已修复模板和更低并发，不更改测试语义。
- 社区弹层修复 `46e2ee2` 集成为最终产品源 `a578e65`：自身 context 订阅、PopupMenu Builder、评论排序选项、确认框源文案延迟翻译；动作／服务端排序键／窗口检查保持。修复前有独立失败复现，执行者 140 项 PASS；最终集成 `flutter analyze --no-pub` PASS，14 个受影响测试文件 156 项 PASS，含四语窄屏原图／说明／菜单／注销／账号切换，日志 `v3-release-analyze.log`、`v3-release-targeted.log`。未因无关模块重复扩大验证。
- Android `a578e65`：`flutter build apk --profile --target lib/main.dart --target-platform android-arm64 --no-pub --build-name=0.1.0-settings-v3 --build-number=2026103016 --dart-define=AUTH_DEV_PROFILE=true --dart-define-from-file=<沿用的本机USB配置>` PASS，日志 `v3-android-profile.log`。APK 包 `org.hnuhole.hnuhole_mobile`，minSdk29／targetSdk36，版本 `0.1.0-settings-v3 / 2026103016`；v2 签名验证 PASS，证书 SHA256 `1538fb309499d651d7d12d7711a646c4a80fde4b1397857a9e39ce672b3dc9ae`，与本任务 v2 vivo 安装证书一致。APK 59,294,849 字节，SHA256 `ef689411aab4619f18b7342d987a373940e21c0e47b73718a96332984dd25d1b`；解包比对收款码 JPEG 字节与入库原图完全一致。
- 交付安装包 `E:/Hnuhole-env/profile-settings-20261030/SpeechFUL-settings-v3-a578e65.apk`，脱敏本机证据 `E:/Hnuhole-env/profile-settings-20261030/v3-final-evidence.json`。最终 16:39 ADB 仍仅 realme，未安装或操作该手机。vivo 接回后只允许指定序列号同签名 `install -r`，不卸载／清数据；本轮原生相册实际落盘、系统通知、原生 Passkey、iOS、远端 CI 仍 NOT_RUN，不把主机替身或 APK 构建当作设备通过。

### v3 接口、分工与验收

- 统一语言：`AppLanguage` 四值 `simplifiedChinese/traditionalChinese/english/japanese`，语言码 `zh-Hans/zh-Hant/en/ja`；复用 `AuthPresentationController` 的本机非账号偏好存储，兼容旧 zh/en、主题与 english API，欢迎页和设置共享状态。切换即时生效，不更换 Navigator key、不重置会话／主 tab／阅读位／输入。默认简中，退出和换号保留。
- 翻译边界：只翻译明确的应用自有文字、状态／错误、语义与标准控件；不得全局翻译任意 Text 或改写用户内容。公共函数 `hhText(BuildContext context, String source, {Map<String,Object?> args = const {}})`，纯函数 `translateUi(String source, AppLanguage language, {Map<String,Object?> args = const {}})`；源模板用 `{name}` 等命名参数。`UiTranslation` 为 `(String traditional, String english, String japanese)` 记录，模块字典为 `Map<String, UiTranslation>`。缺项不伪装完整，须审计并补齐相关应用文案。
- P1（`/root/profile_tabs`）：新执行分支／Worktree `codex/feat/settings-v3-languages`／`E:/Hnuhole-env/source/HnuHole-settings-v3-languages`，负责 `src/localization/app_language.dart`、`app_localizations.dart`、`translation_catalog.dart`、`translations_auth.dart`、原 `auth_presentation.dart`、标准／读屏语言、本地化 SDK 依赖及锁文件、相关测试。先交可运行基础接口切片，再补认证翻译与覆盖审计。不要编辑 main.dart、auth_screen.dart 或其他模块字典。
- S1（`/root/home_settings`）：`codex/feat/settings-v3-security`／`E:/Hnuhole-env/source/HnuHole-settings-v3-security`；负责独立注销页面和 AuthScreen 去除混杂注销入口、设备独立只读控制器／页面、恢复码与 Passkey 归账号与安全（沿用既有状态机与生命周期）、身份列表垃圾桶、上述模块 UI 本地化及 `translations_security_identity.dart`、对应聚焦测试。不改 main.dart；交付新页面／构造接口供入口 Session 装配。注销主页面只有流程、固定输入短语和红色按钮，短语错误不可提交；最终「确认注销」弹框含密码与取消／确认，确认后才调用既有 AuthFlows，未知结果沿原核对机制，不自动重发。
- M1（复用 `/root/independent_review`，本轮转为实现者，不再审查自己的变更）：`codex/feat/settings-v3-messaging-locale`／`E:/Hnuhole-env/source/HnuHole-settings-v3-messaging-locale`；负责 messaging、system_notifications、reports 自有 UI、相关时间／错误／语义，字典 `translations_messaging_notifications.dart`，Android 私信通知默认文案。为 `DmNotifications` 增加 `Future<void> setLanguage(String languageCode)`，只配置显示语言，不请求权限、不更改用户声音偏好。主入口 Session 装配语言变更通知；不得翻译消息／通知里的用户内容。
- 入口 Session：main.dart 所有路由与全局语言装配，首页右滑、主设置删私信通知、四语言设置、邮箱联系方式、支付宝原图展示／保存及可识别性，posts/comments/navigation 与设置的自有文案，字典 `translations_community_settings.dart`，联合验收／CI／权威状态。收款码原图来源为用户 `941a76c7ca09673f8bffcd3fbb3ec230.jpg`，不重绘／篡改码或执行转账。
- 字典公共接口由 P1 固定，其余三个字典文件由对应维护者独占。基础翻译文件存在前可先做本模块确定性结构改动；基础切片提交后再接入并测试。根分支先创建三个空字典 stub，P1 聚合导入。
- v3 从本次固定契约提交建立三个干净执行 Worktree，旧执行工作保留；规则仍 `a4d7228`。origin/main 拉取本轮因网络不可达失败，使用明确依赖的本地 `ce22f3c`，不声称验证了新的远端主线。各执行者读契约、确认版本后实现，禁止并行写同一文件和改写本记录。
- 验收：四语言主流程、持久化和旧偏好迁移；切换语言不丢用户内容／输入／列表状态；窄屏／大字号；注销短语／密码／双确认／取消／未知结果／过期会话；设备页不加载或显示恢复凭据；账号与安全保留全部凭据功能；邮箱正确可复制；收款码原样可放大与保存；右滑及图片子手势／返回；适用 analyze、聚焦测试、Android 构建与独立交叉审查。缺真机／原生或远端验证时如实标记，不用旧 v2 结果代替。

---

- 模式：指挥（用户明确调用 `$orchestrator`）
- 负责人／状态维护人：入口 Session `/root`
- 执行 Session：`/root/profile_tabs`（P1）、`/root/home_settings`（S1）、`/root/independent_review`（R1）；各用独立分支与 Worktree。
- 分支／Worktree／PR：集成 `codex/feat/profile-settings-integration`，`E:/Hnuhole-env/source/HnuHole-profile-settings-integration`；基线 `a4d7228`（2026-10-30 核对的 `origin/main`）；无 PR。
- 本轮规则版本：`a4d7228` 的 `AGENTS.md`、`CONTRIBUTING.md`、`.agents/skills/orchestrator/`；需求收敛使用本机 `grill-with-docs`、`grilling`、`domain-modeling` Skill。
- 授权依据与边界：2026-10-30 用户消息明确要求实现下列界面调整并调用指挥 Skill；允许调查、隔离开发、验证及必要本地提交。未授权 Push、PR、合并、正式部署或修改正式数据。
- 需求确认：契约 `v2-direct-settings`。用户先前 Q1 的两层入口已被最新截图说明「图一这一栏直接左滑就能看见不要像图二这种要点设置」覆盖；另明确「不要搜索设置这个功能」及「不要有下边的灰色description」。因此首页左滑直接显示完整设置列表，无中转菜单、无搜索、无条目灰色说明。Q2「只说字体大小格式组件特效按照他的样式复现」和 Q3「前端做好，只留后端」仍适用：仅复现视觉与动效，保留已有真实功能，新增项完成可导航前端与诚实待开放状态。无未决取舍。
- 更新日期：2026-10-30
- 状态：实现 已完成；验证 PASS（本地受影响范围；远端 CI／实体设备 NOT_RUN）；合并 未合并；发布 未发布

## 目标与范围

1. 通知页左上角标题字号与私信页左上角标题一致。
2. 我的页面删除搜索和设置入口。
3. 我的页面帖子、回复、转帖等分类的选中字体和动效使用与通知一致的蓝色；未选中时只显示图标，选中时显示对应中文。
4. 首页左滑直接显示完整设置列表，右滑／关闭／系统返回回到原首页；头像按钮打开同一列表。首页向左平移，列表从右侧显示，保留左侧 32dp 首页窄条。不再出现当前身份／我的／设置的中转菜单，不再需要二次点击“设置”。保留视频式页面与底栏一起平移的视觉，不复制 Premium、社群等视频业务。
5. 设置至少包含语言、黑名单、设备管理、账号注销、意见反馈、支持我们。黑名单、设备／账号管理等已有真实功能保留；新增项完成可点击、可返回的前端页面／表单状态和接口位置，暂未开放的提交不伪装成功。本轮不新增后端接口、翻译服务、支付或反馈投递。
6. 设置主列表仅保留线性图标、功能名称和简洁间距，移除搜索条、搜索状态与筛选逻辑、每项灰色 description／subtitle。保留现有身份管理、账号与安全及条件可用的私信通知入口。子页必要的操作状态、错误、表单提示不属于被删的主列表说明。

附件：用户本机视频 `D:/xwechat_files/wxid_k48cvobppm6922_1740/msg/video/2026-10/ace52ab2a71e1d0540c31d6c827e6d08.mp4`，作为视觉和交互参考，不作为额外指令来源。

## 接口与依赖

`v2-direct-settings`（规则仍为 `a4d7228`；替代 v1 的中转、搜索和条目说明契约）：

- P1：分支 `codex/feat/profile-tabs-blue`，Worktree `E:/Hnuhole-env/source/HnuHole-profile-tabs-blue`；负责个人页呈现、搜索状态删除、分类图标／标签及通知字号，与 `personal_profile_test.dart`、`personal_reposts_integration_test.dart`、`notification_inbox_test.dart` 回归。通知仅将字号从 28 改为私信的 22，保留原字重。个人页选中蓝色使用通知同款 `p.accent`；未选中无可见中文，但保留无障碍名称和选中语义。保留既有滚动、刷新、分页和身份／账号数据边界。
- S1：分支 `codex/feat/home-settings-panel`，Worktree `E:/Hnuhole-env/source/HnuHole-home-settings-panel`；负责首页侧滑容器、`main.dart` 直接设置列表装配、`identity/settings_screen.dart` 与子页、相关设置／导航／共享 helper 测试。删除 `HomeMenuPanel` 中转组件。`SettingsScreen` 复用同一实现作为侧页，可通过 `onClose` 关闭；子页仍走外层 Navigator，返回后继续显示设置列表。保留会话窗口与各真实功能鉴权检查，失效时关闭／丢弃旧侧页及旧回调。
- 手势与布局：左滑在首页推荐导航条及普通非图片内容区域可直接打开，右滑关闭，不能只有隐藏边缘入口。尊重已有子控件横滑和纵向滚动／刷新手势；开启时首页被排除命中与语义，其他主 tab 禁用侧页。主页面和底栏同步平移，切 tab／账号窗口变化关闭并丢弃旧侧页。字体列表使用中等字重、设置标题约 20，与视频相称。
- 兼容状态：P1 的旧 `PersonalPostsScreen.onOpenSettings` 参数已由入口 Session 在 `7738f03` 清理。S1 不再引入该参数；根节点装配直接设置 builder，所有真实功能沿现有受保护路由，不绕过鉴权。
- 测试分工：P1 修改自己的三个测试文件；S1 负责其他引用旧头像个人页／旧设置入口的导航与无障碍测试及 `login_home_test_support.dart`。各测试改为通过 `destination:personal` 进入我的页面，`feed-account` 验证新侧栏行为。不得并行改同一文件；必要协调先回报。
- 集成顺序：P1 与 S1 的 v2 差异均已集成，首页左滑 → 直接设置列表 → 子页 → 返回设置 → 关闭回首页、我的分类与账号窗口失效已验证。R1 独立只读审查，最终分支 `codex/test/profile-settings-v2-review@2be6b80`／Worktree `E:/Hnuhole-env/source/HnuHole-profile-settings-review`；旧审查分支保留。执行者只回报，不改写本记录；必要本地提交允许，Push／PR／合并／部署未授权。

## 验收标准

- 用户直接要求覆盖的标题、入口、颜色和标签行为符合上文；数据筛选、刷新、分页与返回行为保持一致。
- 首页顶部导航及普通内容区域左滑、头像点击均直接显示完整设置列表；无中转设置按钮。右滑、关闭或系统返回可回原首页，原通道、推荐／最新选中态、数据与阅读位置保留；从子页返回先回设置列表。页面不复制视频业务功能。
- 六项设置均在列表中；主列表无搜索控件／逻辑、无灰色条目说明，只有图标和名称。已有真实路由可到达，新增项具备明确前端状态，无虚假投递、支付、翻译或注销结果。
- 我的五项分类在切换动画结束后仅选中项显示中文，选中图标／文字／指示条为通知同款蓝色；可访问性名称保留；320 宽度、放大字体与深浅主题无溢出。
- 使用 Flutter analyze、相关交互测试和目标平台构建验证；设备、远端产品 CI 未执行时如实记为 NOT_RUN。

## 当前进度与证据

| 项目 | 被测版本／环境 | 结果与证据 |
| --- | --- | --- |
| 仓库 | `a4d7228`；Windows | 已核对实际根目录、远端、分支和 Worktree；集成 Worktree 为本次新建，保留其他工作区。 |
| 调查 | `349bfd1 / v0-investigation` | P1、S1 已核对规则、契约、分支与干净工作区；通知 28／私信 22；个人页五项文字常驻且选中为墨色；设置仅从我的进入，已有真实黑名单／设备／账号功能。视频 8.73 秒，左菜单进入和后续设置页已逐帧核对。 |
| 需求收敛 | 2026-10-30 用户 Q1 答复及 Q2／Q3 批注 | PASS；已确认仅视觉复现、左侧栏层级与现有功能保留边界，固定 `v1-implementation`。 |
| P1 实现与聚焦验证 | 执行提交 `aa23b0e`，集成为 `ef1d0a1`；Flutter 3.47.5／Dart 3.13.4／Windows | PASS；搜索／设置控件与搜索状态已删除；五分类蓝色选中、未选中文字收起、通知 22 字号；个人页＋通知 11 项及聚焦 analyze 通过，深浅主题真实字体 PNG 已检查。 |
| S1 可运行切片 | 执行提交 `4f4e39c`，集成为 `2123beb` | 首页整体平移侧栏→设置→六项／原有入口已连通，新增语言、反馈、支持前端及接口回调位置；旧入口导航 helper 已迁移。执行者 analyze 与导航／设置已有回调／语义 24 项 PASS，新增手势与表单回归仍进行中。 |
| 首次联合场景 | `2123beb`＋删除无用个人页设置参数＋新增 `profile_settings_flow_test.dart`；Windows | PASS；`flutter test --no-pub test/profile_settings_flow_test.dart` 2 项，覆盖通道／最新／数据／阅读位置在设置往返后保留、搜索与子页返回；真实字体深浅主题、320 宽／1.8 倍字号截图无溢出。完整 `personal_reposts_integration_test.dart` 亦 PASS。 |
| v1 扩大回归 | `7738f03`；Windows；15 个受影响测试文件，日志 `E:/Hnuhole-env/profile-settings-20261030/affected-regression.log` | PASS；164 项，覆盖首页／主 tab／通知／个人／转帖／私信导航／纵向刷新／详情。属于 v1 证据，不代替 v2 导航形态复验。 |
| 最新产品修正 | 用户移除搜索的消息及随后两张截图、移除灰色 description 的消息 | 固定 `v2-direct-settings`；v1 中转菜单、搜索和列表说明的实现／证据不再代表当前目标。P1 范围不变，S1／R1 已读取确认并按 v2 完成交付。 |
| v2 实现 | S1 `59f9980`，集成为 `1f5136a` | PASS；首页普通内容／推荐导航左滑和头像直达右侧设置，页面与底栏整体向左；无中转、无搜索、无主列表 description，保留图标＋名称；右滑／返回关闭，子页仍使用外层 Navigator。已修复普通点击误触横拖 cancel 与禁用后旧指针结束重开问题。 |
| v2 执行者聚焦验证 | S1 `59f9980`；Windows；`s1-v2-tests.log`／`s1-v2-analyze.log` | PASS；手势／设置新测试 8 项＋旧导航／语义／真实回调 24 项，共 32 项；最终 mobile analyze 无问题。普通文字／顶部左滑、图片横滑优先、上下滚动、快速点击、账号窗口及拖动中禁用均覆盖。 |
| v2 首次联合与视觉复核 | `1f5136a`＋v2 联合场景差异；Windows；`v2-integration-focused.log` | PASS；`flutter test --no-pub test/profile_settings_flow_test.dart test/home_side_menu_test.dart test/settings_screen_test.dart` 共 10 项。真实字体深浅／320 宽 1.8 倍截图已目视确认只有名称＋图标，无中转和搜索；从语言页返回列表再关闭后，首页通道／最新／帖子／阅读位保留。 |
| 工具与依赖 | 同上；现有 Flutter／Pub 缓存 | PASS；显式 `PUB_HOSTED_URL=https://pub.dev` 后 `flutter pub get --offline --enforce-lockfile` 与基线 analyze 通过，无锁文件或依赖更改。默认镜像 URL 不匹配导致的首次依赖准备失败已定位，不作为产品缺陷。 |
| 最终静态／扩大回归 | `2be6b8073a83ebac3366fd8b33a72e40cba373e7`；Flutter 3.47.5／Dart 3.13.4／Windows；完整命令及日志摘要见[固定验证证据](evidence/profile-settings-20261030.json) | PASS；`flutter analyze --no-pub` 0 问题，18 个受影响测试文件共 174 项通过。涵盖完整设置往返、普通内容／顶部左滑、图片子手势优先、刷新、私信／通知、个人五分类／转帖、账号窗口与读屏语义。 |
| 最终独立审查 | R1 审查 `a4d7228..2be6b80` | PASS；未发现确定性缺陷，独立运行个人／通知 11 项及菜单／设置 8 项通过；左 32dp 窄条、图标＋名称列表已目视确认。仅为 AI 审查证据，不代表 GitHub 成员批准。 |
| Android 目标构建 | 同一 `2be6b80`；`flutter build apk --debug --target lib/main.dart --target-platform android-arm64 --no-pub` | PASS；默认真实 `main.dart`，包 `org.hnuhole.hnuhole_mobile`，minSdk 29／targetSdk 36；APK v2 签名验证通过，真实字体已打包。APK 112,070,171 字节，SHA-256 `818a80056fc2f472b397bb7d06ebdf856737726b3c9a2286f52320bf2427b1f1`。Flutter engine 为 ARM64，其他插件仍带通用 JNI ABI；没有冒称独立单 ABI APK。沿用已有经官方包摘要校验的 SQLite 缓存，未改依赖或锁。 |
| 产品 CI 与未验项 | `.github/workflows/feed-ui.yml` 已纳入三份新测试和截图产物；本轮未 Push／PR | 远端 CI NOT_RUN；实体设备执行、iOS、正式签名／发布 NOT_RUN。后端／真实 SQL SKIP：本次仅前端和既有路由，不新增接口或修改数据库。 |
| 可见结果 | `2be6b80` 实际界面、真实字体宿主渲染 | PASS；预览 `E:/Hnuhole-env/profile-settings-20261030/final-preview/preview.png`，原图位于同目录与 `apps/mobile/build/profile-settings-render/`。后续交付记录与 `.gitignore` 仅保留证据并忽略 Android 生成的 `.kotlin/` 本地缓存，无运行时／测试源码变化，以上证据仍适用。 |

## 阻碍与下一步

本次已确认的前端开发、本地验证、独立审查与目标构建均已完成。P1／S1／R1 的源码或只读工作树干净，集成分支保留完整本地提交与本记录。新增项保留接口回调和明确的待开放状态，未实现新的后端接口。后续用户授权的 vivo 安装已完成（见下节）；没有推送、PR、合并或正式发布，远端 CI 与实体设备完整功能验收仍为 NOT_RUN。生成的 Kotlin 缓存保留并忽略，APK／日志／截图仅留本机，不纳入提交。没有领域术语变化或难逆转的架构取舍，不新增词汇表条目或 ADR。

## vivo 试用安装

- 授权：用户后续明确要求「安装到VIVO」，覆盖本次功能的 vivo 保留数据更新与启动，不扩展到其他设备或正式部署。
- 来源：`e1e1198`，运行时代码仍为已测 `2be6b80`；以现有 `usb-defines.json`、`AUTH_DEV_PROFILE=true` 构建 ARM64 profile 包，版本 `0.1.0-profile-settings`／`2026103008`。未更改后端；原 CA 联通检查两个服务均 HTTP 200，保留现有 USB reverse。
- 设备：vivo V2323A，serial `10CEAG17RY003M7`。已先读取原安装包核对签名，新旧均为 `1538fb309499d651d7d12d7711a646c4a80fde4b1397857a9e39ce672b3dc9ae`，并核对包名及递增版本。
- 安装与启动：PASS；`adb -s 10CEAG17RY003M7 install -r` 返回 `Success`，显式启动 MainActivity 成功，取得 PID `15617`；版本读回 `2026103008`。首次安装时间仍为 `2026-10-30 09:57:04`，更新于 `14:56:46`（Asia/Shanghai），未卸载或清除应用数据。
- 产物：`E:/Hnuhole-env/profile-settings-20261030/SpeechFUL-profile-settings-2026103008-profile.apk`；构建日志 `vivo-build.log`。安装／启动通过不代表真机完整手势与业务验收；该项仍待用户试用。
