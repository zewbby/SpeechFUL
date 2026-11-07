# ANDROID-V1-ACCEPTANCE-01 — Android 首版完整业务验收

- 模式：常规；负责人／状态维护人：当前 Session；无委派。
- 分支／Worktree／PR：`codex/test/android-v1-acceptance-01`；`E:/Hnuhole-env/source/SpeechFUL-android-v1-acceptance-01`；[PR #113](https://github.com/zewbby/SpeechFUL/pull/113)已合并。
- 初始主线基线（最新候选见文末）：2026-11-06 fetch 的 `origin/main`：`6b722f071f07cbd94d96095734499f8cdd061641`。远端配置 `https://github.com/zewbby/HnuHole.git`（项目已更名 SpeechFUL）。实际共享仓库 `E:/Hnuhole-env/source/HnuHole`，detached `af272dc`、干净；外层用户目录为无提交的交接仓库，所有内容保留。既有 Worktree 未切换、未清理。
- 授权依据与边界：本次用户完整验收指令。允许隔离 Worktree、一次性 PostgreSQL/Redis、合成账号／数据、独立验收包构建和安装、正常 App／系统权限操作、确定性最小修复及必要本地提交。未获得本任务覆盖日常包／修改日常后端、Push、PR、合并、正式部署的新授权；完成可独立准备后再处理。只清理本任务明确创建且无依赖的资源。
- 需求确认：以本次指令及下列已确认任务为准；私信运行中提醒，进程结束后再次进入同步并提醒，保留权限和免打扰；iOS 延期；热榜既有30分钟持续负载 FAIL 保留，先调查适用性及交付影响，不自动长测或优化。业务取舍有歧义时使用本机 `grill-with-docs` 及依赖；当前事实调查阶段无新增取舍。
- 更新日期：2026-11-07。
- 状态：PR113及热榜性能PR115已合并并有适用CI；新一轮热榜30分钟隔离长测PASS，旧FAIL保留原版本。D05已本地修复、146项认证回归通过，新修复远程CI/合并未执行。公网试用包2026110707的真实开户/冷启/公网读取PASS，但公网后端尚无PR115部署与联合复验。当前仍不具备完整交付条件；日常更新/正式发布未执行。最新复核见文末。

## 目标与范围

判断最新 main 的 Android 首版当前已确认业务是否具备交付条件。完整覆盖用户指定的账号／会话、身份、首页阅读、发布草稿、编辑删除、搜索标签热榜、评论回复、私信、通知治理、我的设置分享。正常 App 入口的实际可见状态与真实数据结果和自动化替身证据分别登记；缺口不记 PASS。

## 接口与依赖

- 最新主线含搜索 #101/#104、编辑兼容 #102 及功能 #103、私信恢复 #105、动效 #107、自定义标签 #109、分享后端 #108／客户端 #111、全站热榜 #112。
- 已读 [POST-SEARCH-01](POST-SEARCH-01.md)、[POST-EDIT-01](POST-EDIT-01.md)、[DM-RESUME-NOTIFICATIONS-01](DM-RESUME-NOTIFICATIONS-01.md)、[CUSTOM-TAGS-01](CUSTOM-TAGS-01.md)、[POST-SHARE-01](POST-SHARE-01.md)、[GLOBAL-HOTLIST-01](GLOBAL-HOTLIST-01.md)、[TELEGRAM-MOTION-01](TELEGRAM-MOTION-01.md)。旧记录的 PASS 仅适用于所列旧版本。
- 当前日常后端／包指针来源 `b46244d023cb0c3a2b847ef0855082c0cade9a01`，C34/V7；手机安装记录为 vivo `10CEAG17RY003M7`，2026110605 profile。相对候选存在分享客户端等实质差异，不能认作最新 main 联合候选。当前 ADB 仅 realme `7e0660f1` 在线，原独占租约已于 2026-11-05 23:08 +08 到期，已核实后选择本任务独立包，不覆盖日常包。
- 原始日志、私有运行材料、APK／截图集中于本机 `E:/Hnuhole-env/android-v1-acceptance-01`；只在本文保存脱敏摘要和链接，不提交凭据、数据库、日志或构建物。

## 验收标准

- 候选客户端、后端、迁移、配置、签名和设备可追溯且兼容；真实服务和真机结果绑定完整 SHA／明确包装差异。
- 场景由已确认行为推导，覆盖操作→可见状态→真实数据→重进恢复；失败、重复、未知结果、撤权和账号隔离保持最终 C Gate。
- 适用 Go test/build/vet、Flutter analyze/test、完整 OpenAPI、真实 SQL/Redis/HTTPS、迁移／权限、Android 构建／设备及产品 CI 有实际结果。
- 未执行及外部阻碍保留 NOT_RUN/BLOCKED，iOS 使用 SKIP（用户延期）；阻断缺陷未闭环时不宣称具备交付条件。

## 当前进度与证据

| 项目 | 被测版本／环境 | 结果与证据 |
| --- | --- | --- |
| 基线隔离 | 上述候选，Windows PowerShell／共享 Git | PASS：fetch、根目录、远端、branch、worktree、status 已核对；从 main 新建独立分支与 Worktree，保留原内容。 |
| 版本一致性 | 日常来源 b46244d 对候选 6b722f0 | PASS（独立联合候选）：已另装完整客户端并启动兼容独立后端；日常包仍旧40文件差异，不给日常版本出具本候选结论。 |
| 热榜性能 | 既有 [30分钟持续负载证据](evidence/global-hotlist-sustained-20261106.md) | FAIL（历史，适用风险保留）：计算重叠窗口搜索 P95 +77.83%，2 次503、40次容量丢弃；本轮未重跑／优化。 |
| 候选构建／安装 | `6b722f0`、Flutter3.47.5/Dart3.13.4、JDK17、SDK36；realme RMX3366 Android14、1080×2400、density408 | PASS（安装及启动；此行为初始包，后续统一包已替代）。独立 `org.hnuhole.hnuhole_mobile.androidv1`，正式 `lib/main.dart`，profile/arm64、2026110601/0.1.0-android-v1-acceptance；仅applicationId和可见标签包装差异。APK 59,754,605字节、SHA256 `52c2e7c16ebeacd459c2206367f2303637b092921f0d28c7573eed5148a5c438`；实际证书SHA256 `1538fb309499d651d7d12d7711a646c4a80fde4b1397857a9e39ce672b3dc9ae`（profile实际沿用现有debug测试证书，未使用新生成验收key，不能称独立新签名或生产签名）。[包回执](E:/Hnuhole-env/android-v1-acceptance-01/android-receipt.json)、[装机回执](E:/Hnuhole-env/android-v1-acceptance-01/device-install-receipt.json)。日常包未改。 |
| 客户端参数 | 同一候选；严格任务CA及两条loopback HTTPS origins、`AUTH_DEV_PROFILE=true` | PASS。define文件SHA256见包回执；未注入会话、fixture或测试入口。图片包iOS两个symlink在Windows构建副本展开为原目标文件，不影响Android。原始候选Git archive与Worktree产品无差异。 |
| 独立后端 | 同一候选，非root WSL2 Linux文件系统、Go1.22.2、PG16、Goose3.22.1、Pillow12.3.0；新C34/V7、独立评论与热榜Redis7 | PASS（初始环境就绪；最终C修复与App版本组合见文末）。[运行回执](E:/Hnuhole-env/android-v1-acceptance-01/lab-receipt.json)。使用既有grant-community/images/moderation/comments/direct-messages；基础角色审计在DM opt-in前PASS，基础审计按设计拒绝完整DM授权，DM opt-in另由运行时严格schema/不可变列拒绝和真实DM runner验证；不删审计限制。UI实例未启用共享admission Redis，该范围另跑真实隔离runner。 |
| 环境准备失败 | 本任务一次性实例 | 已定位并修正配置：snapshot namespace必须绑定dev；Redis7.0不支持CLIENT SETINFO；初始化operator需SETNX。C启动最初漏DM专用grant，最终补精确canonical grant后启动。两新Gate各显式recover一次初始化，之后只resume/watch；无修改Gate行、改钟或再次recover。工具probe-posts在完成HTTPS动作后的受限SQL核验拒绝非其marker，记工具NOT_RUN，不算完整probe PASS。 |
| Go host／完整契约 | 候选archive，无产品修改 | PASS：`go test -mod=readonly ./...`、build、vet；完整13份OpenAPI和25个保护操作静态契约通过。`go-host.log`、`openapi.log`。全目录gofmt发现21个原有文件格式差异，未为本轮验收批量改写；适用近期产品格式检查已有CI。 |
| Flutter完整回归 | 同一候选；Windows、原锁离线解析 | PASS：App analyze零问题，1164 PASS/4 SKIP；图片包analyze零问题、138 PASS。4项SKIP依赖专用真实fixture/头像输入，不冒充真机通过。日志[App](E:/Hnuhole-env/android-v1-acceptance-01/flutter-tests.log)、[图片](E:/Hnuhole-env/android-v1-acceptance-01/viewer-tests.log)。 |
| 真实Feed系列 | 候选Linux副本，race、一次性PG/Redis/HTTPS；`run-backend.sh`固定pattern | PASS：[真实回归](E:/Hnuhole-env/android-v1-acceptance-01/feed-real-sql-redis-https.log)，覆盖搜索/历史、标签、编辑文本图片、分享、榜单排序过滤/权限、评论及迁移。依赖Dart可执行文件和专用迁移库的SKIP单列，后续补探针。 |
| 远程产品CI | [PR112最终head检查](https://github.com/zewbby/SpeechFUL/pull/112/checks)，head `084bd3e8536634922dfb2776181a212005a2017a` | PASS：实时28项check，27 success/1 actual-process-acceptance skipped，无失败；含Go/PG/HTTPS/Flutter/Android候选与升级回滚。`git diff --name-only 084bd3e 6b722f0`为空，PR最终head与main基线tree一致。不是本轮真机全业务PASS，也不把协作policy当产品验收。 |
| 旧热榜FAIL适用性 | `8af7b08`→候选 | FAIL保留：worker、candidate Gate准备、runtime rankings及rankings cache无差异；搜索增加标签匹配和最终匹配复核，不能外推旧具体P95数值为本候选实测，但不存在消除既有资源争用/503/drop的新性能修复证据。本轮未长测/扩压/优化；交付风险未闭环。 |
| 六组真实专项回归 | 原候选；非root WSL2 Linux，PG16、Redis7、race；`run-other-sql.sh` | PASS：email-login、identity-avatars、dm-chat、moderation、comment-snapshot、shared-rate-limit六个runner退出0。各自创建私有一次性库，非设备证据。[退出码](E:/Hnuhole-env/android-v1-acceptance-01/other-sql-status.txt)，原始`*-real.log`同目录。尚未执行原生Passkey或真实校园邮件供应商。 |
| 五个生产Dart真实探针 | 原候选，现有锁及Linux Dart原生可执行；PG/Redis/HTTPS/race | PASS：Feed、Search、Share、Tags、Rankings五项，非替身网络层。[真实日志](E:/Hnuhole-env/android-v1-acceptance-01/dart-real-https-sql.log)。初次工具误列不存在的独立rankings探针，纠正为复用现有post_search探针后执行，没有产品改动。 |
| 编辑未知结果／冲突 | 原候选D+R；仅A及其原帖的任务专用TLS代理 | PASS：真实服务SAVED后丢响应，App显示待核对；结束进程重进本人帖子编辑，先核对并回公开版，随后正常编辑。另用原会话通过真实API保存一个同revision并发编辑，再转发原请求，真实409；App保留旧输入、提示复制和主动载新版。非伪造服务端成功。[未知](E:/Hnuhole-env/android-v1-acceptance-01/04-edit-unknown.png)、[冲突](E:/Hnuhole-env/android-v1-acceptance-01/05-edit-conflict.png)，代理事件在Linux私有runtime的`acceptance-fault-events.jsonl`。 |
| 编辑图片／标签补充 | 原候选D+R，同一原帖且已有两条评论 | PASS：删除第三张图、真实长按拖动将GIF从第二移到第一、新增ReuseV1标签并保存；原身份/分类/首次发布时间/两条评论保留。[拖动后](E:/Hnuhole-env/android-v1-acceptance-01/07-edit-reordered.png)。早期ADB draganddrop未成功操作不计PASS；独立DOWN/长按/MOVE/UP后的实际顺序已目视核实。 |
| 私信真实链路 | 原候选D+R，A正常App，B经真实SMTP/注册/恢复及正常API；32帖为B的正常发布命令生成 | PASS（已执行范围）：从真实帖子联系、身份选择、首图禁止发送、首条文字等待、B回复后文字和图片、原生本地历史；B待收接口确认A图片为IMAGE。备注、置顶、免打扰已走普通菜单；未完成项见矩阵。 |
| 私信恢复和通知 | 原候选D+R，原生POST_NOTIFICATIONS通过系统设置授权 | PASS（指定链路）：正常主页面恢复补收；force-stop期间B实际发送、PID为空且通知0；正常入口重开后原生安全存储恢复账号、补收且通知1，默认标题SpeechFUL/正文“你有一条新私信”；系统通知点击实际进入A身份与B会话且可见新消息。免打扰时消息收取、无通知。权限关闭/恢复操作已执行；最终统一包的权限关闭ACK及恢复提醒/去重已补完，见M05。[停止](E:/Hnuhole-env/android-v1-acceptance-01/notifications-process-stopped.json)、[冷启](E:/Hnuhole-env/android-v1-acceptance-01/notifications-cold-start.json)、[免打扰](E:/Hnuhole-env/android-v1-acceptance-01/notifications-muted.json)。 |

### 本轮缺陷与修复

- D01／P2：已确认删除楼中楼后，回复内容消失、帖子总评论数下降，但主评论回复计数仍为1；手动刷新后才清零。真机原候选复现；根因是`CommentPostPane._changed`移除已删除子行时没有同步其主行`replyCount`。
- 最小本地修复：仅在已加载回复被权威`runtime.deleted`确认并首次移除时，扣减对应已加载主行的数量且下界0；重复通知时子行已移除，不二次扣减；不重排楼层、不加请求、不改变删除协议或权限。
- 回归：`comment_views_test.dart`新用例真实点本人回复菜单删除，断言子行消失、主行回复数由2→1且重复notify仍1。原产品先FAIL（Expected1/Actual2），修复后PASS；证据`comment-count-before.log`／`comment-count-after.log`。后续完整App回归与统一包真机复验均通过，见下节。
- 修复后完整App回归PASS：1165通过/4既有专用fixture SKIP，`flutter-after-fix.log`；聚焦analyze零问题。首个专项命令误列不存在的`comment_controller_test.dart`，其余90项通过但该命令整体不作PASS；以随后完整App回归替代，不将工具路径错误记为产品缺陷。
- 以上为D01修复当时的历史阶段；最终统一包已包含D01/D02，后端另修D03，以下最终冻结组合取代早期装机状态。

### 第二批计数修复与包复验

- D01 已由本地提交 `9950b7ad3824c485873ee0b16b3729c52086a5f2` 承载；2026110701 独立验收包已安装，签名与原验收包一致，数据保留。设备刷新取得主评论回复数1，删除其唯一回复后不刷新即清零，总数2→1；[真机证据](E:/Hnuhole-env/android-v1-acceptance-01/10-fixed-delete-count.png)。
- D02／P2：已有主评论下新回复已发表并可见，主行回复数仍0，刷新才更新。定位为发布定位只补新行、不更新已有根行计数。最小修复仅在确认发表并定位后读根行权威计数；保持列表顺序，按账号权限代次、列表版本、删除变化及同根请求顺序拒绝过期响应；读计数失败不隐藏已确认回复。
- D02 新用例在旧实现先 FAIL（新回复已可见而根计数没有1），修复后 comment_views 66项 PASS；完整 App analyze 0问题、1166 PASS／4既有 SKIP。`comment-created-count-before.log`、`comment-created-count-after.log`、`flutter-final-analyze.log`、`flutter-final.log`。此前用例第一次断言误用了与固定回复fixture不同的文字，纠正后才复现目标计数失败，不作为产品失败证据。
- 当时后端仍为main；后续D03更新C。D02已在最终统一包真机复验通过。新增本地修复尚无远程产品CI，不把main已有CI算作修复head CI。

### 通知 UTC 缺陷、真实兼容 fixture 与后续设备记录

- D03／P1：A 收到 B 的真实回复和点赞后，整个通知页持续“通知暂时无法读取”，直连同样复现。严格 TLS 原响应200，interaction `createdAt`为`+08:00`，而契约与`PostJson.utc`要求`Z`；已有系统通知使用UTC，故此前纯系统页可读。最小服务端修复在读取 interaction 记录后调用`UTC()`，不放宽客户端校验、不改数据／权限／Gate。
- 真实 PG 回归将该测试专用连接的 timestamptz codec 设为UTC+8，未改系统时钟或全局时区：旧实现先 FAIL，修复后`TestNotificationInboxPostgres` PASS（含跨身份、已读、点赞聚合及治理链路）；[修复前](E:/Hnuhole-env/android-v1-acceptance-01/inbox-utc-before.log)、[修复后](E:/Hnuhole-env/android-v1-acceptance-01/inbox-utc-after.log)。已更新本任务C后端，设备回复/点赞/系统通知与身份筛选均复验通过；[后端回执](E:/Hnuhole-env/android-v1-acceptance-01/backend-fixed-receipt.json)、[真机通知](E:/Hnuhole-env/android-v1-acceptance-01/16-fixed-notification-inbox.png)。
- 全量安全回归首轮 FAIL：一项旧兼容fixture删0033结构仍宣称0033已应用；另外authprivacy包总计超过30m终止，未把刚开始的用例误作超时根因。修复仅限测试：先断言这种半迁移应拒绝，再移除本测试私有tracker构造既有非tracker历史形态；生产schema检查不变。真实PG复验PASS：`gate-compat-after.log`。
- 原runner明确只允许1–30m。尝试90m被参数验证拒绝，未改上限；随后本任务外部runner按Test[A-M]/Test[N-Z]分组authprivacy，再运行其余全部包及vet，均保留race和每组30m限制。分组和其余包实际结果见文末；原始失败/超时不删除。不是热榜持续负载，未扩压或性能优化。
- 客户端统一包已安装：源码`79025cbcd9af41e1bbc60b0d804064246a4be7f7`，2026110702/profile/arm64、正常main入口，SHA256 `fb40fd349fcb823ac473fce71b77c61ad0c008974de60c24614d4c3b4e3e77c8`、59,754,605字节；define及签名同前。[最终包回执](E:/Hnuhole-env/android-v1-acceptance-01/android-final-receipt.json)。D02已真机不刷新由0→1，[证据](E:/Hnuhole-env/android-v1-acceptance-01/11-final-publication-count.png)。
- A→B→A普通密码登录完成：B无A搜索历史、A私人聊天备注及草稿入口状态；A从“我的”恢复原草稿。另有图片／标签／第二身份草稿，经正常保存退出、冷启动、切回其所属身份后完整恢复并发布，首页读回一致；中央新建按钮不是原草稿恢复入口，早期误用不记缺陷。[发布后](E:/Hnuhole-env/android-v1-acceptance-01/13-draft-restored-published.png)。
- 身份真机：A从1→3，第二身份改名及图库头像成功，30天改名提示；第三次累计创建后名额已满，删除一次性第三身份后仍等6个月。最后一个身份删除按钮初始禁用。已有A帖子在全局切到第二身份后仍以原A发言，B回复身份正确。
- 治理真机＋正常API：A App举报B seed31→C审核API领取并MUTE1天→A进度／处理详情→B App处罚通知／申诉→独立D审核API接受→B App处罚撤销及申诉结果通知，恢复DM发送。只用合成资源；网页浏览器拒绝私有CA，网页实际操作BLOCKED。[举报结果](E:/Hnuhole-env/android-v1-acceptance-01/12-report-handled.png)。
- 设备附加：四语言切换，繁／英／日各冷启动保留；搜索历史复用、单删、吐槽范围确认清空；喜欢／收藏／转帖正常写入后本人各分类一致。B seed31正常删除，A旧榜点击诚实显示目标不可读，返回刷新移除并补位；一次性热榜503保留旧榜和重试，随后成功恢复。[失败保留](E:/Hnuhole-env/android-v1-acceptance-01/15-hotlist-retains-old-on-failure.png)。
- 分享公网关联：设备真实`pm get-app-links`显示任务包127.0.0.1状态1024，非验证成功；当前没有已确认公开C域／发布签名。[设备关联](E:/Hnuhole-env/android-v1-acceptance-01/device-app-links.txt)。无效链接＋连续HTTPS＋登录恢复组合命令被自动审批以`blocked by policy`拒绝，未给更具体原因，未执行也未换命令绕过；该组D保持BLOCKED。已有运行中／冷启scheme和系统分享证据仅各自范围。
- 评论故障注入准备一次受WSL shell逗号花括号展开影响，规则未命中，已取消；该次普通评论成功和重启不算丢回包验收。与原编辑确实命中的丢回包分开登记。

## 场景矩阵

环境缩写：D＝realme Android14，正常 `lib/main.dart`、原生安全存储、任务独立包；R＝候选一次性 C34/V7、真实 PostgreSQL16、独立评论 Redis 和热榜 Redis、严格私有 CA HTTPS；H＝候选 Flutter host/widget，网络／平台替身；S＝仓库真实 SQL/HTTPS/race runner；P＝公网公开域名及发布签名。D+R 才作为联合真机业务证据。数据 A/B/C 均为任务合成账号；IP、邮箱、恢复码、私钥及令牌只在私有材料中。

以下预期来自用户本次清单及链接中的既定产品契约；关联场景共享 fixture，但执行结果分别登记。普通失败/未知结果仅对任务隔离实例注入，禁止修改日常后端。

| ID／链路 | 已确认的预期行为 | 环境／所需数据 | 结果／证据入口 |
| --- | --- | --- | --- |
| A01 校邮注册 | 固定 hainanu.edu.cn；验证码确认→账号设置→安全收尾→基础身份；失败不绕过 Gate | D+R；新 A；隔离 SMTP 捕获 | PASS（合成SMTP正常App完整链路）；[已脱敏UI序列](E:/Hnuhole-env/android-v1-acceptance-01/ui-dumps)及[首次首页](E:/Hnuhole-env/android-v1-acceptance-01/01-first-home.png)。真实校邮供应商另列 BLOCKED，合成 SMTP 不代表外部实际投递 |
| A02 密码／邮箱登录 | 回原账号；错误不泄露账号存在性；重登读取权威目录 | D+R；A/B、正确及错误密码 | PASS：D+R 普通密码A→B→A、新密码登录；正常App切换邮箱登录→隔离SMTP验证码→原A恢复。真实校园供应商BLOCKED。 |
| A03 恢复及现有凭据 | 现有恢复码、Passkey 等入口可达；恢复流程按既有协议；原生 Passkey 单独验收 | D+R；独立恢复凭据 | PASS：D+R 完整恢复码验证→新码隐藏重输→重设密码→旧码失效→新密码登录；不自动登录。原生Passkey入口可见；其实际关联／绑定 BLOCKED。 |
| A04 退出／冷启／前后台 | 退出清会话，冷启恢复有效会话，回前台校验及同步，失效不继续读写 | D+R；A 有效／撤销会话 | PASS：D+R 正常退出、有效冷启恢复、前后台同步、凭据重设及替代会话失效；S最终会话/Gate事务回归另见日志。 |
| A05 换号隔离 | A 草稿、未决编辑、聊天、搜索历史与迟到响应不进入 B；返回 A 依原约定恢复 | D+R/H/S；A/B 各有不同材料 | PASS（明确证据边界）：D+R A/B历史、草稿、私信备注与会话隔离，原账号恢复；迟到响应隔离由H/S验证，未称D故意挂起跨账号响应。 |
| A06 设备接替 | 新移动设备登录使旧会话失去在线权限；旧本地记录须原账号重登 | 两设备或独立设备密钥客户端+S；A | PASS：R另一installation正常登录后D旧会话退出业务界面，重登恢复；第二台物理设备 BLOCKED，不把API安装身份称为双真机。 |
| I01 身份创建切换 | 至少1、最多3；同账号昵称不重名；选择、头像与实际使用身份一致 | D+R/S；A 1→3身份 | PASS：D+R 1→3创建、切换实际身份、达到上限；S并发/重名限制PASS。 |
| I02 资料／限制 | 昵称2–12字且30天冷却；头像更换；累计第三次创建后6个月，不因删除重置 | D+R/S；合成资料及边界 fixture | PASS：D+R 昵称及图库头像修改、30天提示、累计三次后6个月冷却；删除不重置。S边界PASS，未改钟等待。 |
| I03 同帖身份 | 同帖首次受理后固定，帖子／评论／DM／通知归属正确，不按昵称推断身份 | D+R/S；A两身份+B同名身份 | PASS：D+R 全局第二身份时原帖仍以原A发言，B楼中楼和身份对私信正确；通知交互按选中身份过滤、系统按账号共享。 |
| I04 删除身份 | 不可删最后身份；旧公开内容占位；本人对应聊天与备注清除；未决任务核对后处理 | D+R/S；可删除合成身份 | PASS：D+R 最后身份禁删，删除第三身份和有公开帖的第二身份；旧帖可搜索且作者注销占位。聊天清理和未决任务边界S/H PASS，D未为被删身份另建聊天。 |
| F01 首页模式 | 推荐／固定分类顺序与选中态、账号屏蔽、刷新／分页、空态／重试一致 | D+R/H；7分类、足够分页、屏蔽 | PASS（分层）：D+R 推荐/分类/固定顺序、空态、屏蔽及刷新；首页首20条→加载更多→第二页实际阅读。网络失败重试S/H PASS；[第二页](E:/Hnuhole-env/android-v1-acceptance-01/31-feed-second-page.png)。 |
| F02 阅读返回 | 列表→详情→返回保留范围／位置，权威计数更新，失效内容不泄露 | D+R/H/S；分页内容、删／下架帖 | PASS：D+R 搜索/标签及首页第二页详情返回；首页所有可见卡片标题及bounds前后一致，[位置比对](E:/Hnuhole-env/android-v1-acceptance-01/feed-second-page-return.json)。计数及失效目标按真实结果更新。 |
| F03 图片阅读 | 图片／GIF加载、缩放、短拖回弹／长拖退出、保存原图；权限拒绝可恢复；返回系统栏正确 | D+R；合成PNG/JPEG/GIF、相册拒绝 | PASS：D+R PNG/JPEG/GIF、双击缩放、拖动回弹/退出、保存提示及系统栏；[缩放前](E:/Hnuhole-env/android-v1-acceptance-01/24-viewer-before-zoom.png)/[后](E:/Hnuhole-env/android-v1-acceptance-01/25-viewer-double-tap.png)。Android14 picker/MediaStore不要求旧广泛存储许可；旧API拒绝分支H PASS，D BLOCKED（无旧版设备）。 |
| W01 发布内容 | 纯文字／纯图／组合，标题正文规则；移除／排序图片；成功首页／详情／我的一致 | D+R/S；A、三张可区分图片 | PASS：D+R 文字、组合、标题+GIF且正文空的纯图帖发布并首页读回；空标题正确拒绝；移除/排序在编辑中D验证，发布编辑器排序S/H PASS。[纯图](E:/Hnuhole-env/android-v1-acceptance-01/28-image-only-published.png)。 |
| W02 标签／草稿 | 最多3标签各1–10字，选择面板不提前发布；草稿恢复图片顺序／标签／身份 | D+R/H；新词、复用、非法词 | PASS：D+R 新标签/既有建议复用；图片、标签、身份、文字草稿正常保存→冷启→所属身份恢复→发布。数量/字符边界S/H PASS。 |
| W03 发布故障 | 明确失败可重试；连点幂等；未知先核对原命令；取消不能换键重发已受理任务 | D+R/H/S；任务隔离故障代理 | PASS：D+R 实际受理丢响应→进程结束→原任务恢复已发表，SQL仅一帖；明确失败/取消/连点去重S/H PASS，D未对全部发布故障逐项注入。 |
| E01 编辑读回 | 本人菜单编辑标题正文／有序图片／标签；保存同帖并显示已编辑时间；原身份分类互动不变 | D+R/S；A有互动的已发帖 | PASS：D+R 标题、正文、图片增删/真实拖动排序、标签修改，原身份/分类/时间/互动保留。举报证据不可变由S验证。 |
| E02 退出／失败 | 未提交退出丢弃；明确失败旧版仍公开且当前页可重试 | D+R/H/S；合成已发帖 | PASS：D未保存退出丢弃；真实C缺失媒体REJECTED后输入保留、公开版不变，重试成功；独立B HTTPS读者核对旧/新版，edit-old-after-reject.json及edit-saved-after-retry.json。 |
| E03 未知恢复 | 原账号同机保留原输入／命令／图片；回包丢失重进先核对；成功载入公开版，未知只核对或原次重试 | D+R/H/S；隔离代理丢响应 | PASS：D+R 实际SAVED丢回包，待核对；结束进程后从本人入口先核对、载入公开版，再编辑。04-edit-unknown.png。 |
| E04 冲突／权限 | 同版先成功者生效，后者保留输入主动载新版；删除／下架后关闭编辑；举报留存当时证据 | D+R/S；两客户端、合成举报 | PASS：D+R 同revision真实并发冲突、保留输入并主动载新；本人正常确认删除后我的移除。下架/撤权编辑闭锁及举报原证据S PASS。 |
| Q01 搜索状态 | 自动输入与明确提交、相关度／最新、分类范围、空结果扩大、分页与详情返回保持状态 | D+R/H/S；不同分类命中及无结果 | PASS：D+R 自动/显式搜索、范围、相关度/最新、无结果扩大、32条分页、第二页详情返回原位置；S生产Dart探针PASS。 |
| Q02 历史 | 仅明确提交词记录；同账号身份共享、按范围隔离，跨设备读取；复用置顶、删除／确认清空 | D+R/H/S；A/B 多范围历史 | PASS：D+R A/B历史隔离、范围隔离、复用、单删和范围确认清空；跨设备权威读取S PASS。 |
| Q03 标签结果 | 点击单标签默认全站按最新混排，可切分类；关键词匹配标签；返回来源位置 | D+R/H/S；跨分类同标签 | PASS：D+R 标签默认全站最新多分类；切科技只显示科技，详情返回保留科技；关键词标签匹配S PASS。 |
| Q04 全站热榜 | 空输入统一纯文字全站榜并隐藏分类筛选；关键词恢复范围／排序；真实分类详情返回刷新 | D+R/H/S；跨分类热帖 | PASS：D+R 空输入全站纯文字榜，分类筛选隐藏，关键词恢复范围/排序；真实跨分类详情及返回刷新。 |
| Q05 热榜可见性／失败 | 删除／下架／屏蔽过滤并补位；请求失败保留旧榜及重试，不显示过期账号旧响应 | D+R/H/S；21+排序帖、隔离Redis故障 | PASS：D+R seed31真实删除后旧榜目标不可读，返回过滤补位；屏蔽吐槽后榜单过滤；一次503保留旧榜并可重试。下架及容量/候选补位规则S PASS；负载仍见Q06 FAIL。 |
| Q06 持续负载 | 沿既定30分钟、算榜窗口搜索P95增幅≤5%及零错误／容量丢弃的验收门槛 | 历史隔离负载；本轮只比对适用性 | FAIL（历史保留，未自动重跑） |
| C01 评论／回复 | 主评、楼中楼文字图片；准确回复目标定位、排序分页、点赞；同帖身份固定 | D+R/S；A/B、足够评论与图片 | PASS：D+R 主评/楼中楼文字图片、回复A/B正确；两处根计数修复真机PASS。另32个真实根评论，最近排序、翻至没有更多、点赞。[分页末端](E:/Hnuhole-env/android-v1-acceptance-01/29-comment-pagination-end.png)。 |
| C02 输入／删除 | 离帖清未发送输入；切换目标有输入先确认；主评删整楼、楼中楼仅删本条 | D+R/H/S；合成讨论楼 | PASS：D+R 主评删整楼、子回复仅删本条；带文字图片换目标先确认、保留输入且不自动发布；H重复删除通知不二次扣数。离帖临时输入清理H/S PASS。 |
| C03 失败／恢复 | 失败系统通知入口，重启核对原任务；重复提交只受理一次；未知不当作失败换键 | D+R/H/S；隔离故障代理 | PASS：D+R 受理丢响应→重启原任务恢复，SQL仅1条；另真实受理图片回复后目标被其作者删除→FAILED/COMMENT_TARGET_DELETED→冷启失败通知→原身份/正文/图片保留→明确确认换目标→手动发布且SQL仅1条。原失败任务保持FAILED、owner_visible=false。[失败恢复](E:/Hnuhole-env/android-v1-acceptance-01/33-failed-comment-recovery.png)、[新发表](E:/Hnuhole-env/android-v1-acceptance-01/34-comment-retargeted-published.png)、[SQL/Gate核对](E:/Hnuhole-env/android-v1-acceptance-01/lab-final-check.json)。 |
| M01 首次联系 | 点帖子作者进入身份对会话；保留来源帖；对方回应前仅一条文字，不可先图 | D+R/S；A/B、双方帖子 | PASS：D+R 从seed20联系、选身份、来源帖保留；首图不可发送、首条文字等回应；B正常回复后解锁。 |
| M02 发送／重试／撤回 | 文字图片本地持久化后ACK，失败原次重试，2分钟内撤回；结果未知不伪装失败 | D+R/H/S；A/B、合成图片 | PASS：D+R 文字/图片、两分钟内撤回；历史跨冷启/换号/密码重设保留。B真实拉黑使A命令FAILED，解除后App确认重发同内容，SQL仅1条。[失败](E:/Hnuhole-env/android-v1-acceptance-01/26-dm-authoritative-failure.png)、[重试成功](E:/Hnuhole-env/android-v1-acceptance-01/27-dm-retry-sent.png)。 |
| M03 会话治理 | 备注本人可见；置顶、隐藏、删除按各自规则；拉黑按账号，解除后可联系 | D+R/S；合成身份对 | PASS：D+R 备注、置顶、确认隐藏及新消息恢复、确认本地删除只保留新历史/备注、拉黑真实拒绝与解除后成功。 |
| M04 恢复提醒 | 首页／我的／私信页回前台立即同步；进程结束后重开补收并提醒；杀进程期间无保活要求 | D+R；B真实发信，A前后台／force-stop后正常入口重开 | PASS：D+R 主页面回前台补收；force-stop时无进程/通知0，正常入口冷启补收并提醒；不要求进程终止期间后台保活。 |
| M05 权限／DND／去重 | 权限关闭／恢复和免打扰仍生效，默认隐藏正文；重复同步不重复提醒；点击进正确身份会话 | D+R；系统通知许可、合成A/B | PASS：D+R 关权限新seq16从未ACK/有body→ACK/清body、手机可读而通知0；恢复权限seq17通知1，清通知再回前台0；免打扰/点击正确会话初始候选D证据保留。最终包权限/去重证据notifications-permission-off-acknowledged.json、notifications-permission-restored.json、notifications-final-dedup.json。 |
| N01 通知分类／身份 | 回复、点赞、系统分类及身份切换、未读与目标跳转；已删／下架目标诚实显示不可用 | D+R/S；不同身份通知、失效目标 | PASS：D+R UTC修复后全部/回复/赞/系统、身份筛选、未读和跳转正常；B真实删除被通知评论后保留通知，点击原帖显示该评论暂不可读。[已删评论目标](E:/Hnuhole-env/android-v1-acceptance-01/30-deleted-notification-target.png)。下架细分S PASS。 |
| G01 举报审核 | App提交合成举报→网页审核处理→用户处理通知，权限限制真实生效；证据不随编辑改写 | D+R+网页/S；独立管理员及A/B举报 | PASS（分层证据）：原D App提交/通知/限制按原版本保留；本轮6483ac1真实网页补完证据核对、领取及禁言，非API代替网页操作；新工单由正常API准备。详见文末补验，新版App新工单通知列表及申诉详情已补验。 |
| G02 申诉／限制 | 从处理通知申诉；审核通过撤销对应处罚；非管理员与其他账号不越权 | D+R+网页/S；仅合成处罚／申诉 | PASS（分层证据）：原D申诉/结果通知按原版本保留；本轮真实网页原处理人回避、独立管理员复核通过，真实API核对处罚撤销/原帖恢复/通知生成/普通账号403；新版App通知回看已补验；新工单举报/申诉准备为正常API，不称全部环节同次D执行。 |
| P01 我的分类 | 帖子／评论／点赞／收藏／转帖现有分类刷新分页和返回；失效内容按既有状态 | D+R/H/S；A各分类数据及删除帖 | PASS：D+R 帖子/回复/喜欢/收藏/转帖、身份筛选、删帖/删身份失效内容；列表大分页和缓存返回S/H PASS，D未为每种分类生成多页。 |
| P02 四语言 | 简／繁／英／日即时且持久；不重置路由、用户内容、输入与阅读位；换号仍保留设备偏好 | D+R/H；多语言／重启／A→B | PASS：D+R 简/繁/英/日切换，繁/英/日分别冷启保留；恢复CN后冷启、A/B切换仍CN；用户正文未翻译。路由/输入边界H PASS。 |
| P03 外观与安全入口 | 主题字号、窄屏大字、减少动画；黑名单、当前设备／最近替代设备、账号安全入口正确 | D+R/H；系统字体、两身份、黑名单 | PASS（分层）：D Auth浅深主题、320dp+1.6字体设置/语言、系统关闭动态效果后路由；黑名单、当前设备会话/期限、账号安全及Passkey入口均实际到达。已恢复密度408/字号0.9/动画各1.0，[设备最终核对](E:/Hnuhole-env/android-v1-acceptance-01/device-final-reconciled.json)。全页面窄屏组合H PASS，D未逐页穷举。 |
| L01 系统分享 | 首页／详情／菜单共享忙态；仅品牌和规范URL；取消不提示发送成功，迟到失权不弹面板 | D+R/H；公开帖和失效会话 | SKIP（最新需求延期外部分享）：原候选系统面板证据仅原版本适用；新版入口改为站内卡片，见PC01。 |
| L02 链接恢复 | 热启动在原路由上开帖，冷启动／登录注册后首页开原帖；登录中最后点击为准，退出清除，最近任务旧Intent不重放 | D+R/H/S；A/B、多个有效与无效链接 | SKIP（最新需求延期外链）：原候选热/冷scheme及自动审批拒绝记录保留；新版默认入口不接收外链，Android外链intent filter撤下。不是修复或验收通过。 |
| L03 公网关联 | 实际公开C域HTTPS、应用ID及签名匹配assetlinks，设备验证；AASA配置单列，iOS延期 | P；当前仅loopback私有CA、缺已确认公开域及发布签名 | SKIP（最新需求延期外链关联）：首版不交付外链唤起App，assetlinks/AASA不再作为此次分享功能的交付门槛；软件上线公网业务后端仍需单独部署。 |
| X01 iOS | 保留用户原延期边界 | 无macOS／Xcode／iOS设备 | SKIP（本次用户明确延期） |

## 最终验证收尾

- 上一轮冻结时矩阵共44个链路组：行级38 PASS、1 FAIL、4 BLOCKED、1 SKIP；PASS组内仍标明仅H/S覆盖或D未执行的子场景，不能当作38组全子项真机通过。全部证据均由本Session调查/执行/复验，未使用执行子Agent。
- 命令入口：App执行`flutter analyze --no-pub`及`flutter test --no-pub test --concurrency=2 --reporter expanded`；Go执行`go test -mod=readonly ./...`、`go build -mod=readonly ./...`、`go vet -mod=readonly ./...`，真实环境再运行仓库`authlab/run-*-isolated.sh`与formal-Goose/race分组。可追溯的任务外部包装器为`run-backend.sh`、`run-other-sql.sh`、`run-gate-cohorts.sh`、`run-gate-rest.sh`、`run-migration-followup.sh`，仅连接归属明确的一次性资源。
- 最终Android命令：`flutter build apk --profile --no-pub --target-platform android-arm64 --target lib/main.dart --build-number=2026110702 --build-name=0.1.0-android-v1-acceptance3 --dart-define-from-file=<任务build-defines.json>`，随后apksigner核验、ADB明确realme序列号安装；[构建日志](E:/Hnuhole-env/android-v1-acceptance-01/android-final-build.log)、[签名](E:/Hnuhole-env/android-v1-acceptance-01/android-final-signature.log)、[安装](E:/Hnuhole-env/android-v1-acceptance-01/device-final-install.log)。
- **Go真实回归：PASS（聚合实际证据），原单命令FAIL保留。** authprivacy A–M分组1689.335s通过；N–Z实际运行1166.547s仅正式Goose元表盘点fixture失败。修正仅允许精确`public.goose_db_version`及其四个canonical列，不放宽其他C/V关系盘点；[针对C/V实际复验](E:/Hnuhole-env/android-v1-acceptance-01/privacy-formal-after.log)通过。此前半迁移兼容fixture修复亦已真实通过。生产检查未放宽。
- [327个authprivacy顶层测试覆盖核对](E:/Hnuhole-env/android-v1-acceptance-01/go-parent-coverage.json)：318项在分组/针对复验PASS，分组SKIP的9项均在所需真实专项runner PASS，missing/remainingSkip/unresolvedFailures均为空。不是宣称每个子测试或设备/公网外部条件都通过。原[完整失败/超时](E:/Hnuhole-env/android-v1-acceptance-01/safety-gate-full-real.log)及[分组原始记录](E:/Hnuhole-env/android-v1-acceptance-01/safety-gate-cohorts-real.log)保留。
- [其余所有Go包/race及完整vet](E:/Hnuhole-env/android-v1-acceptance-01/safety-gate-rest-real.log) PASS；[最终Go build](E:/Hnuhole-env/android-v1-acceptance-01/go-final-build.log) PASS，四个触及Go文件gofmt无差异。未批量改写21个基线格式差异文件。
- [通知Goose fresh/upgrade](E:/Hnuhole-env/android-v1-acceptance-01/notification-migrations-real.log)、[评论举报升级与治理升级/down拒绝](E:/Hnuhole-env/android-v1-acceptance-01/migration-followup-real.log)实际PASS，补齐分组环境未配置的迁移专用库条件。
- 最终App [analyze](E:/Hnuhole-env/android-v1-acceptance-01/flutter-final-analyze.log)零问题、[完整测试](E:/Hnuhole-env/android-v1-acceptance-01/flutter-final.log)1166 PASS/4既有SKIP；图片包未改、既有本轮138 PASS适用。网页admin核心[13项](E:/Hnuhole-env/android-v1-acceptance-01/admin-core.log)PASS，仅此自动化范围，网页浏览器仍BLOCKED。
- 真机后续补完：邮箱OTP登录、纯图发布、首页第二页阅读位置、评论排序分页/点赞、已删评论通知跳转、失败图片回复的冷启恢复/改目标/唯一发表、真实DM失败与确认重试；详见矩阵。测试结束正常冷启首页及图片加载可用。
- 故障代理已停止，唯一故障规则终态forwarded；仅本任务C/V ADB映射恢复直连55183/60331。C/V Gate均OPEN、generation1，未再次recover、未改钟/改Gate行。[最终实验室核对](E:/Hnuhole-env/android-v1-acceptance-01/lab-final-check.json)。独立实验室保留供已装包使用；设备字体/密度/动画恢复原值，通知许可保留开启。日常环境及其他Worktree未改。
- 884份UI XML已统一去除输入框值和独立恢复码，自动化实时内存树不变；[脱敏回执](E:/Hnuhole-env/android-v1-acceptance-01/evidence-sanitization.json)。私有凭据/恢复码/证书私钥仅留任务私有运行材料，不纳入证据链接或Git。图片、日志及APK均不提交。

## 上一轮冻结与交付结论（外部分享方案，已被最新范围取代）

**结论：FAIL，暂不具备Android首版交付条件。** 主线发现的D01/D02/P2计数问题及D03/P1通知页不可读均已最小本地修复、对应回归和真机复验通过；这些修复尚未合并。不存在以已装日常旧包冒充当前候选的情况。

- 冻结代码候选SHA：**`b3a9ac820ea48812dbfb16a6894a05c8b540c839`**；这是main `6b722f071f07cbd94d96095734499f8cdd061641` 加本任务三项修复及测试/文档。2026-11-07最终`ls-remote`核对远端main仍为该基线。
- 客户端实际构建源 **`79025cbcd9af41e1bbc60b0d804064246a4be7f7`**，最终候选App产品树与之相同；C实际构建源 **`2c8199dfff07922b483c5fa5a80539acda54bd90`**，之后只改测试/文档；V源为main基线、无产品差异。不是未经构建的全新产品版本；以这三个精确构建来源与最终代码等价核对绑定联合结论。
- 已装realme RMX3366 `7e0660f1`、Android14/SDK34/arm64；包`org.hnuhole.hnuhole_mobile.androidv1`，2026110702、`0.1.0-android-v1-acceptance3`、profile、正常main入口；APK **59,754,605字节**，SHA256 **`fb40fd349fcb823ac473fce71b77c61ad0c008974de60c24614d4c3b4e3e77c8`**。设备内base.apk实算完全一致，[最终设备回执](E:/Hnuhole-env/android-v1-acceptance-01/device-final-reconciled.json)。
- 实际测试证书SHA256 **`1538fb309499d651d7d12d7711a646c4a80fde4b1397857a9e39ce672b3dc9ae`**；defines SHA256 **`c0df5ca0a03a304e1fc013811ff632f95947ad429a1ff882fea7e83c128bdd4e`**。仅包名/标签包装差异、既有debug测试签名；不把profile包认作正式发布签名产物。
- C二进制SHA256 **`7e645dd7433cd8be438cf025529ce0e2c4c6eab7b79d5b53f43ab95cfc06635e`**；C配置SHA256 **`3263ffe2b17961b83dc492bb8ebbb7254341148b0965bb7636033a53c487372a`**；PG C34/V7、Goose3.22.1、评论/热榜Redis7、严格CA HTTPS/mTLS；C `https://127.0.0.1:55183`、V `https://127.0.0.1:60331`。以[后端修复回执](E:/Hnuhole-env/android-v1-acceptance-01/backend-fixed-receipt.json)覆盖[初始实验室回执](E:/Hnuhole-env/android-v1-acceptance-01/lab-receipt.json)的C版本，未重写初始sourceSha历史。UI实例无共享admission Redis，该产品配置仅有独立真实runner证据。

- [源码等价核对回执](E:/Hnuhole-env/android-v1-acceptance-01/final-source-equivalence.json)：候选相对已构建App及packages无差异；相对已构建C仅上述privacy测试夹具差异。后续任务记录提交只改文档，不增加产品差异。
- [证据摘要清单](E:/Hnuhole-env/android-v1-acceptance-01/final-evidence-manifest.json)记录本文所链本机证据的字节数/摘要，链接均实际存在；私有运行凭据和私钥排除。

### 上一轮阻断项（分享相关取舍以后文最新确认为准）

1. **Q06 FAIL（既有性能门槛未闭环）**：旧30分钟计算窗口搜索P95+77.8335%、2次503、40次capacity drop保留；全程+4.7985%不能抵消窗口FAIL。核心竞争路径未有性能修复，不能用旧数值冒充新候选测量。需沿既有授权/暂停边界另行完成性能处置与获准的同门槛验证，本轮未扩压或自动优化。
2. **L03 BLOCKED（公网HTTPS关联）**：缺已确认实际公开C域/发布指纹及可验证assetlinks，设备状态1024；AASA亦无实际公网证据，iOS客户端仍延期。需域名、实际正式包签名、服务配置及Android设备验证闭环。
3. **G01/G02 BLOCKED（实际网页审核）**：API真实处罚/通知/申诉/撤销及权限通过，浏览器被任务私有CA阻断；用户离线，未做人工系统信任操作。需可信审核网页环境或合法人工信任后，用同类合成资源完成网页链路，不以API替代。
4. **L02 部分D BLOCKED**：无效链接、连续HTTPS及认证后原帖恢复组合操作被自动审批拒绝，原因仅`blocked by policy`，未执行或换方式绕过；必须补齐合规真机证据。H及真实生产Dart探针不抵消D缺口。
5. **修复候选远程产品CI NOT_RUN，合并/发布未执行**：只有main基线27成功/1跳过的既有CI。需获得对应Push/PR授权后运行适用产品CI、审查与明确合并授权；随后才按授权更新日常环境/正式发布及校验目标配置。无需对仅测试/文档提交重装相同产品包。

### 其他未验范围与非阻断记录

- 真实校园邮箱供应商投递BLOCKED（仅隔离SMTP完整App注册/登录）；原生Passkey实际RP关联/绑定BLOCKED，保留已有专项边界；第二台物理设备BLOCKED（另一installation真实接替已验）；旧Android广泛存储权限拒绝D BLOCKED；iOS SKIP。需相应真实外部资源，不能由本轮合成替代。
- 已列PASS行只覆盖其所写证据层：全组合迟到响应、每类“我的”多页、每页窄屏/大字、全部发布故障、删身份聊天清理、下架/撤权等部分由H/S覆盖，未逐项D穷举，具体见矩阵；未执行的真机子场景保持NOT_RUN。矩阵行级PASS不能解释为所有子场景真机PASS。
- 21个基线Go格式差异未扩修；两处正式Goose测试夹具已修复并真实复验，不列为未修产品缺陷。D01/D02/D03均本地关闭，无新增未修确定性功能缺陷被隐去。
- 实现：本地完成；验证：本轮完成但有上述FAIL/BLOCKED/NOT_RUN；合并：未合并；独立安装：完成；日常包/后端：原版本保留；正式发布：未发布。任务资源保留用于后续复验，不自动清理有依赖的实验室。

## 后续分享范围讨论（2026-11-07，待确认）

- 用户提出：“我觉得这个分享，要么只做站内私信分享吧”。这是对原先确认的外部系统分享/HTTPS原帖链接范围的调整意向，尚未完成必要取舍确认；不提前将L02/L03改为SKIP或PASS，不改已冻结候选。
- 事实核对：现有分享为系统面板发送品牌+HTTPS链接；私信消息只有TEXT/IMAGE，无帖子卡片。首次联系受来源帖子/评论、身份绑定及单条文字限制，不能把分享当作任意陌生人联系入口。App上线仍需要公网业务服务；站内分享可省去外部链接关联验收，不能免除公网部署。
- 使用本机`grill-with-docs`及grilling/domain-modeling依赖收敛：首版是否撤下外部分享并延期链接功能；私信分享是否用可点击帖子卡片而非纯文本URL；首版收件范围是否仅已互相回复的既有身份对会话。建议依次为是/帖子卡片/已互回会话；发送身份、权限、目标可见性、预览与失效处理在相应选择确定后继续收敛。
- 本轮只调查及记录提议，无产品修改、构建、安装或远程操作；现有验收结论及证据保持原适用范围。

### 首轮确认及剩余取舍

- 用户逐项回答“1. 不加外部私信了；2. 可以；3. 可以”。按上一轮Q1的外部分享上下文解释第1项，并已向用户明确说明：首版取消外部分享，改为可点击私信帖子卡片，仅能发给已互相回复的既有会话；拉黑/禁言/身份限制不变。该最新确认取代首版外部分享交付目标，既有实现/历史外链验收不抹去，不自动提升为PASS。
- 已确认原帖点击读取最新公开版本，删除/下架不可读；新增“私信帖子卡片”“可分享会话”术语，不与私人转帖混称。现有私信TEXT/IMAGE、可靠投递/ACK/撤回/举报及本机历史需完整兼容，尚未开始产品修改。
- 剩余必要选择集中到下一轮：卡片只显示最新标题/分类，失效及离线显示通用占位而不保存旧标题/正文/图片副本；首版单会话发送，发送前明确双方身份确认，发送后留原阅读页并显示结果（取消不发送）。均待用户确认，未将建议默认为需求。
- 首版范围调整后L01–L03将按确认的新标准改为延期/不适用并新增站内链路，原先被测版本仍保留其原结果；热榜FAIL、网页审核和其他未验范围不因本次调整关闭。软件上线依然需要公网业务服务。

### 第二轮确认与站内分享实施

- 用户回答“4. 可以；5. 可以”，全部影响实现的取舍已确认：仅最新标题/分类、失效或离线通用占位；单会话、双方身份确认、取消不发送、发送后留原页。没有剩余产品取舍。当前Session继续承担设计/实现/验证/独立装机，本次仍无Push/PR/合并/日常环境或正式部署授权。
- 在现有隔离分支、main 6b722f0＋验收修复基础上增量实现；2026-11-07再次核对远端main仍为原完整SHA。GLOSSARY和本文先前未提交内容均为本Session需求确认记录，已保留。
- 新增POST型私信引用，沿用原可靠文字命令路径与dm-text额度，JSON kind为POST、text仅canonical post ID；缺省kind保持旧文字序列化及指纹不变。服务端检查既有身份对已互回、发送权限、原帖当前可见性及最终C Gate，不产生帖内身份绑定。待投引用在ACK/撤回/删除时按旧机制清除；本机加密聊天只保存引用，不保存标题/正文/图片快照。
- 新增受保护的最小卡片预览GET，仅postId/title/channelId/channelName；前端按权限代次丢弃迟到响应，离线/失效无旧预览。外部Android intent filter已撤下，默认入口不接收外链；旧链路实现/显式注入单元测试保留为延期兼容证据，不算首版功能。
- 实现/验证进行中：Go host test/build/vet与完整私信OpenAPI初检PASS；真实SQL卡片发收、互回限制、重复核对、ACK清除与旧治理链路PASS，旧迁移夹具对34的固定断言已随新0035明确更新并复验中。Flutter四项引用/存储/去重测试已PASS，选择与预览界面专项正在收敛；未构建或更新设备包，不提升新版本验收结论。

### 构建前验证（历史阶段，最新回执见下节）

- 本地Go host test/build/vet PASS：[日志](E:/Hnuhole-env/android-v1-acceptance-01/cards-go-host.log)。真实PG/HTTPS/race包含卡片命令/去重/互回限制、引用ACK清除、举报原引用/伪造拒绝、拉黑/撤回、101张卡片不阻塞旧客户端文字分页、新旧能力头兼容，以及旧DM治理/文字/图片HTTP与Goose fresh/upgrade/down拒绝，均实际PASS：[日志](E:/Hnuhole-env/android-v1-acceptance-01/cards-real-sql-https.log)。新迁移0035无新增角色授权或表，运行时要求对应kind约束；旧文字请求不传kind时指纹不变。
- App完整回归1173 PASS/4既有SKIP：[最终完整日志](E:/Hnuhole-env/android-v1-acceptance-01/cards-flutter-final.log)。最后补充不可用原帖禁选后，卡片8项与分享入口10项共18项聚焦实际PASS：[聚焦日志](E:/Hnuhole-env/android-v1-acceptance-01/cards-focused-final.log)。这部分是H；引用持久化/重启/未知去重测试使用真实加密SQLite与网络替身，界面测试明确使用presentation double。最终analyze零问题，完整OpenAPI及私信契约PASS。网页admin展示POST仅为“帖子卡片引用”，[核心13项](E:/Hnuhole-env/android-v1-acceptance-01/cards-admin-core.log)PASS，不能替代网页浏览器验收。
- 第一轮Goose固定34断言失败保留于此前工具输出与本记录摘要；原临时fixture日志在WSL整体退出后已不可用，不声称仍有其原始文件。更新为实际35后的fresh/upgrade与down拒绝均真实PASS，最终日志已保存在上述外部证据目录。早期Widget测试将动画等待与真实SQLite异步混用产生fixture等待失败，后改为明确展示替身，存储/恢复单独验证；并修正确认期间不应显示发送进度的UI问题。没有将早期失败运行改记为通过。
- 老客户端能力协商：HTTP不带`X-DM-Post-Cards: v1`时目录省略canShare，并在SQL分页前过滤POST；支持该头的生产Dart HTTP适配器读取新类型。发送权限仍由最终事务决定，能力头不授予权限。原安装包读取旧文字/图片不受新字段影响；POST等待支持版本补收。
- ADB复核已无在线设备，因此本次新包安装及正常App真实点击链路BLOCKED；原2026110702装机证据不外推新增卡片。继续完成可独立执行的构建及真实生产Dart/HTTPS联合探针，不要求用户当前配合。日常包/日常后端不改。

| 新场景 | 已确认预期 | 环境/数据 | 最新结果 |
| --- | --- | --- | --- |
| PC01 入口/选择 | 首页、详情及菜单分享进入站内；仅已互回会话；显示双方身份并确认；取消不发送 | D+R/H/S；A/B已有会话及非互回会话 | PASS：D实际入口、可分享身份对列表、双方身份确认、取消及单次发送；首联/互回/最终权限S边界PASS。 |
| PC02 投递/草稿 | 同一稳定命令核对未知，原次重试；发送后留阅读页，真实结果提示；不动聊天草稿 | D+R/H/S/真实SQLite；丢响应/重启 | PASS：D真实SENT后丢响应→发送中结束进程→冷启原命令恢复，真实SQL无多发；实际发送后留原阅读页，聊天草稿跨分享/取消/升级保留。完整故障组合H/S，未逐项D注入。 |
| PC03 最新卡片 | 只读最新标题/分类，不存正文图片/旧预览；原帖点击、返回及前台恢复刷新 | D+R/H/S；编辑及缺失目标 | PASS：D发送方/接收方卡片、原帖点击/返回、回前台读取已编辑标题；离线通用占位且不显示旧标题；仅引用存储/最小字段S及真实Dart PASS。 |
| PC04 失效与迟到 | 删除/下架不可读；不可用原帖不能再发；切号/失权迟到不展示 | D+R/H/S；合成失效帖/挂起响应 | PASS：D原帖正常删除后通用不可用占位、点击不展开旧内容；下架及切号/失权迟到H/S PASS，未称D逐项故意挂起迟到响应。 |
| PC05 治理/通知 | 卡片沿原撤回、举报、拉黑、禁言、免打扰/默认隐私规则；无UUID正文预览 | D+R/H/S；原引用、伪造引用、同一会话 | PASS（分层）：D真实撤回、单条POST授权举报与真实C原引用留存、默认通知无正文/ID、点击正确身份对、重复恢复不重复提醒。卡片专属禁言/拉黑/DND完整组合S/H及原D治理证据按各自版本保留，未重复D全部组合。 |
| PC06 升级/兼容 | C34→35保留文字/图片/回执；旧客户端不解析/ACK卡片，后续文字不被卡片分页阻塞 | S；fresh/upgrade、101引用 | PASS（S）；新旧HTTP能力头与分页、迁移保留和down拒绝实际通过 |
| PC07 构建/装机 | 独立包正常main、同测试签名、摘要与最终源一致；真机正常入口复验 | Windows/Android arm64；realme目标 | PASS：最终baa817e、2026110705正常main/profile/arm64、原测试签名；实际base.apk摘要一致；卡片/目录“分享”、举报选择器/固定预览D04最终真机通过。 |

- 旧L01–L03按用户已确认的新范围改为SKIP，原系统分享/外链证据与自动审批拒绝历史不抹去；该阶段旧热榜FAIL、网页审核BLOCKED及其他外部缺口保留；后续网页已按末节补验关闭，热榜FAIL仍保留。

## 最新冻结与交付结论（站内私信分享）

**实现已完成，验证有必要缺口，整体验收仍FAIL／暂不具备交付条件。** 外部分享与外链唤起已按用户明确确认延期，旧L01–L03不再作为当前首版分享交付门槛；站内卡片和网页审核的正常App/浏览器完整链路正在用户另轮跟进。热榜既有持续负载FAIL、其他原有外部边界及修复候选远程产品CI NOT_RUN继续保留。本轮未执行Push、PR、合并、日常安装或正式发布。

- 最新代码候选 **`481fcd9f6a9eb2df521f036d29df4fe758e9dccf`**；产品实现提交 **`6483ac119c97ce17c3f4f360c68bc229cccef066`**。后续提交仅更新Feed/头像迁移测试的0035完整链断言（不是放宽），产品树无差异；[源码等价回执](E:/Hnuhole-env/android-v1-acceptance-01/cards-source-equivalence.json)。最终远端main核对仍为`6b722f071f07cbd94d96095734499f8cdd061641`。
- 新APK **2026110703 / `0.1.0-android-v1-dm-share`**，正常`lib/main.dart`、profile/arm64，独立包`org.hnuhole.hnuhole_mobile.androidv1`，59,754,305字节，SHA256 **`6d11a19252a5f7490f1deb602984c14b4466fc7d15dccc70ee71b8e5129b0ac6`**。构建源6483ac1；仅包名/可见标签包装，defines摘要仍`c0df5ca0a03a304e1fc013811ff632f95947ad429a1ff882fea7e83c128bdd4e`，现有debug测试签名摘要仍`1538fb309499d651d7d12d7711a646c4a80fde4b1397857a9e39ce672b3dc9ae`，不是正式发布签名。
- [安装包](E:/Hnuhole-env/android-v1-acceptance-01/SpeechFUL-android-v1-dm-cards-profile.apk)、[包回执](E:/Hnuhole-env/android-v1-acceptance-01/android-cards-receipt.json)、[构建](E:/Hnuhole-env/android-v1-acceptance-01/android-cards-build.log)、[签名](E:/Hnuhole-env/android-v1-acceptance-01/android-cards-signature.log)、[实际包元数据](E:/Hnuhole-env/android-v1-acceptance-01/android-cards-badging.log)、[Manifest](E:/Hnuhole-env/android-v1-acceptance-01/android-cards-manifest.log)。实际APK已核对没有外部BROWSABLE/autoVerify入口；未将仅源码修改当作打包结果。
- **新版2026110703已安装并独立核对**：[安装日志](E:/Hnuhole-env/android-v1-acceptance-01/device-cards-install-followup.log)、[本Session只读装机核对](E:/Hnuhole-env/android-v1-acceptance-01/device-cards-reconciled.json)。设备重新上线后，用户另开的“执行 Android 首版完整验收 (3)”（`01a1b401-786c-72b1-a65d-4cec4272dca3`）已按用户后续要求安装并开始站内卡片/网页验收。本Session发现该轮正在控制同一设备后停止并发UI操作，只读验证真实base.apk SHA256与本包一致、版本/机型/USB映射正确。2026110702不再是最新安装证据；完整正常App链路仍由跟进实际执行，未把仅安装/选择面板出现当作全部PC场景PASS。
- 独立C实际源6483ac1，二进制SHA256 **`3e12436cc42587741ab86c1659654c36003ca9bf86e2000e3924f53f867b30a0`**，实际迁移 **C35/V7**；V仍main6b722f0。构建及首轮联测C配置摘要`3263ffe2b17961b83dc492bb8ebbb7254341148b0965bb7636033a53c487372a`，origins、严格CA/mTLS、Redis和权限配置不变；[后端回执](E:/Hnuhole-env/android-v1-acceptance-01/backend-cards-receipt.json)以181个生产Go输入逐一核对绑定构建源，覆盖旧C34后端回执的当前版本。
- 检测到原WSL进程均退出后，按原`resume`/watch流程恢复，**未recover/重建Gate/改钟/改Gate行**；C/V均OPEN generation1、各RECOVER审计仍只有初始化的1条。[普通恢复回执](E:/Hnuhole-env/android-v1-acceptance-01/lab-cards-resume.json)、[最终真实服务/权限/ACK核对](E:/Hnuhole-env/android-v1-acceptance-01/cards-final-service-proof.json)。启动仅本任务隐藏WSL持有进程以避免CLI结束导致实验室退出，[进程归属回执](E:/Hnuhole-env/android-v1-acceptance-01/lab-keeper-receipt.json)；原实验室和新包仍有后续依赖，未清理。
- 生产Dart原生可执行通过实际HTTP适配器、严格任务CA、真实C35最小权限runtime/PG完成：最新最小预览、可分享会话、稳定命令重复核对、POST引用补收、ACK及不可变原回执。[结果](E:/Hnuhole-env/android-v1-acceptance-01/cards-dart-real.json)、[编译](E:/Hnuhole-env/android-v1-acceptance-01/cards-dart-build.log)。仅合成C/B账号的正常社区API创建会话与互回，无正式数据；没有替代真机或原生SQLite证据。SQL另确认该POST已ACK且body=NULL，runtime无kind/sender UPDATE或messages DELETE权限。
- 追加实际补验：[Feed迁移6种基线](E:/Hnuhole-env/android-v1-acceptance-01/cards-migration-compat.log)及[头像fresh/upgrade、DM最小权限并发首发、九图与设置/撤回生命周期](E:/Hnuhole-env/android-v1-acceptance-01/cards-runtime-compat.log)PASS。最后的诊断文案仅将“want34”同步为35，不影响已通过断言。最终[App analyze](E:/Hnuhole-env/android-v1-acceptance-01/cards-final-analyze.log)零问题、完整1173 PASS/4 SKIP，加最新8个卡片/10个分享入口聚焦18 PASS，区别于上一阶段1172项；最后新增的不可用原帖禁选用例在18项聚焦中通过，不伪称已包含在1173项完整运行内。
- [完整OpenAPI与DM契约](E:/Hnuhole-env/android-v1-acceptance-01/cards-openapi.log)PASS；适用direct-messages CI已纳入新SQL/HTTP、Flutter场景，远程实际运行NOT_RUN。合并/正式部署仍需本任务对应明确授权，本文不产生授权。

剩余必要工作：由正在使用设备的跟进继续复验入口/身份确认/取消与单次发送/原阅读位置、冷启卡片补收、最新标题/分类/离线失效、草稿/通知/撤回/举报和换号隔离；沿原暂停边界处置热榜性能；补实际网页审核及已列外部条件；获得授权后运行远程产品CI、审查合并，再按授权更新日常环境和正式发布。本轮源码、构建、H/S/真实Dart验证和只读装机核对已完成；不重复安装同摘要的2026110703，不抢占正在使用的设备，不替跟进填写尚未取得的业务结论。


- 跟进环境已有配置增量：[网页挂载回执](E:/Hnuhole-env/android-v1-acceptance-01/web-followup-environment.json)将同源adminDirectory启用，C二进制仍为上述6483ac1/3e12436c，当前C配置SHA256变为 **`feb2241d75dcd266c748b57e339c0e49c04203cda7b4723abcb82d63b4ccc409`**。本Session只读重算实际配置摘要及四个静态资产摘要，均与该回执、冻结源码一致；未覆盖该轮配置。原3263ffe摘要只适用于先前构建/首轮联测。网页处理/申诉等完整UI结论待该轮后续证据，HTTP200挂载不等于网页业务PASS。
- 模式仍为常规，本Session未派出子Agent；上述另轮工作由用户在另一聊天直接发起。本轮仅归档自己执行或独立读回的事实，完整任务状态继续由本唯一记录维护，不创建平行状态文档。
- [本轮证据摘要清单](E:/Hnuhole-env/android-v1-acceptance-01/cards-evidence-manifest.json)校验所有本文本机链接存在并记录摘要；阶段/版本按本文明确边界使用，不将旧日志提升为新版本结果。[装机及跟进配置独立读回](E:/Hnuhole-env/android-v1-acceptance-01/cards-followup-readback.json)确认本轮记录的版本组合。

## 网页审核及站内分享补验（当前跟进，2026-11-07）

- 用户本轮要求继续原清单第3/4项，随后明确选择“继续站内卡片验收”，不恢复已延期的外链范围；手机已重新连接。另明确要求手机上“帖子分享”改为至多“分享”，属确定文案调整，无剩余产品取舍。常规模式，不委派。
- 核对本任务分支已到`c6f9789`，含站内卡片实现6483ac1与C35迁移测试修正481fcd9；保留这些其他轮次的已提交/未提交工作，不重建或回退任务Worktree。最终被测C仍6483ac1、C35/V7，当前配置增量见上述网页挂载回执。
- **网页补验PASS（真实浏览器+真实服务）**：内置浏览器实际加载同源/admin；审核员688348登录→核对工单2证据→领取→禁言一次性合成账号1天；原处理人打开申诉明确被回避；独立管理员563089登录→接受申诉、对应处罚撤销；两账号正常退出。新合成账号、帖子、举报和申诉由正常严格CA HTTPS API准备，未直接SQL修改业务事实。用户先前误开的URL包含后续中文，改为准确/admin后可达；实验室原缺adminDirectory亦已显式配置，不改浏览器证书检查或Gate。
- [网页处理](E:/Hnuhole-env/android-v1-acceptance-01/36-web-case-ended.png)、[原处理人回避](E:/Hnuhole-env/android-v1-acceptance-01/37-web-original-actor-recusal.png)、[独立申诉通过](E:/Hnuhole-env/android-v1-acceptance-01/38-web-appeal-accepted.png)、[真实服务最终核对](E:/Hnuhole-env/android-v1-acceptance-01/web-followup-result.json)：处罚已撤销、申诉ACCEPTED、原帖恢复可见、普通账号审核入口403；用户有处理/撤销/申诉结果通知。此处不将API准备冒充新工单的App点击；旧App举报/申诉证据仍按原版本使用，新版App通知回看继续。
- 2026110703真机已验证：正常分享入口、双方身份确认、取消回选择器；A实际发送POST，B普通登录并冷启补收后显示最新卡片、正确原帖打开/返回；原A私人备注未串给B。B带未发送聊天草稿进入卡片/分享取消后，返回仍保留原草稿；A通过正常本人编辑命令改题为AV1 card edited，B回前台实际读到新标题。后续离线/删除/治理及最终包复验继续。
- 手机被另一publictrial任务多次抢前台，已暂停依赖点击并加前台包名检查，阻止向其他包输入；uiautomator137及草稿检查无目标控件均为资源冲突，不记产品缺陷。用户已授权本轮独占，等待实际停止冲突；40-card-current-title.png在冲突窗口捕获，不作为本链证据。
- 文案最小调整：卡片标题、会话列表/本地预览和开启正文预览时的通知统一复用既有四语言“分享”翻译，移除不用的“帖子分享”翻译键；不改变引用/发送/权限/通知隐私协议。analyze零问题、现有卡片/分享入口/通知导航/多语言共30项PASS：[analyze](E:/Hnuhole-env/android-v1-acceptance-01/share-label-analyze.log)、[测试](E:/Hnuhole-env/android-v1-acceptance-01/share-label-tests.log)。统一新包构建及装机回执待后续补录，未提前宣称手机文案已更新。
- **文案包已构建/安装，未完成最终可见状态复验**：代码`503c8fd8bef1cc355694b6776c6482d5dd68fe61`，2026110704、`0.1.0-android-v1-share-label`、profile/arm64、正常main；59,754,301字节，APK SHA256 **`6dd613253465db39a9fdb7c3bbd94fa0e966b63d418cb36075ffda971e3f544d`**。独立任务包用户0安装，实际base.apk摘要一致；既有测试签名、defines及C35后端不变。[构建](E:/Hnuhole-env/android-v1-acceptance-01/android-share-label-build.log)、[包回执](E:/Hnuhole-env/android-v1-acceptance-01/android-share-label-receipt.json)、[装机摘要](E:/Hnuhole-env/android-v1-acceptance-01/device-share-label-receipt.json)。没有替换publictrial或日常包。
- 用户最新明确指示：“不行，等他做完你再做”。据此不向另一个聊天发消息，不再启动/点击手机应用；等待“执行 Android 首版完整验收 (2)”（publictrial）结束后继续本站内卡片及文案最终D复验。只是等待共享设备，网页和源码证据已经完成的部分保持结果；不把站内全部场景提前改PASS，也不恢复延期外链。
- 补验工具纠错：新夹具最初标签超过10字、标题超过15簇，分别收到MALFORMED_REQUEST和明确POST_CONTENT_INVALID；权威GET确认原命令REJECTED后才用新命令发布合法短标题，没有重发结果未知任务。自有处罚通过`/sanctions/{id}`读取，通知撤销类型为SANCTION/state=REVOKED；准备脚本误用列表路径/枚举已纠正，不记产品缺陷或绕过服务端规则。

### 设备释放后补验与D04

- 另一个聊天已通知停止ADB/UI/装机并释放realme，本轮按用户等待要求再继续，未向其发送消息、未改publictrial包/后端。2026110704真机确认卡片和目录均为“分享”；B实际发回卡片，发送完成留原阅读页，回聊天保留未发送草稿；原帖标题修改后回前台读取最新；只断本任务C的USB映射后显示“联网后查看”且不残留旧标题，恢复直连后恢复；B两分钟内撤回、正常A本人删除该合成原帖后通用“帖子已不可用”、点击不泄露内容均通过。[最终标签](E:/Hnuhole-env/android-v1-acceptance-01/41-share-label-current-card.png)、[发送后原页](E:/Hnuhole-env/android-v1-acceptance-01/42-share-returns-reading.png)、[离线](E:/Hnuhole-env/android-v1-acceptance-01/43-card-offline-placeholder.png)、[撤回](E:/Hnuhole-env/android-v1-acceptance-01/44-card-recalled.png)、[删除](E:/Hnuhole-env/android-v1-acceptance-01/45-card-deleted-placeholder.png)。
- 新WebOwner正常App密码登录后，实际收到处理/撤销/申诉结果三条系统通知，点击读取“申诉通过”和处罚已撤销详情。[新通知](E:/Hnuhole-env/android-v1-acceptance-01/46-web-notifications-native.png)、[申诉详情](E:/Hnuhole-env/android-v1-acceptance-01/47-web-appeal-native.png)。新工单举报及申诉的准备仍为正常API，不改写成App提交证据。
- 卡片真实丢回包：仅A、指定POST原帖引用、单个PUT经严格CA代理送到真实C并SENT后丢响应；App仍发送中时结束进程。恢复直连、正常冷启后原命令/同messageId恢复已发送；B正常登录补收、默认通知仅SpeechFUL/你有一条新私信、点击进入B身份与A会话；SQL确认该引用ACK后body=NULL，原会话POST总数始终3（含两条先前手动发送，一条已撤回），未因未知结果多发。[丢响应](E:/Hnuhole-env/android-v1-acceptance-01/card-unknown-before-restart.json)、[冷启核对](E:/Hnuhole-env/android-v1-acceptance-01/card-unknown-after-restart.json)、[接收ACK](E:/Hnuhole-env/android-v1-acceptance-01/card-unknown-recipient-ack.json)、[恢复界面](E:/Hnuhole-env/android-v1-acceptance-01/49-card-unknown-recovered.png)、[默认通知](E:/Hnuhole-env/android-v1-acceptance-01/notifications-card-restored-received.json)、[通知目标](E:/Hnuhole-env/android-v1-acceptance-01/50-card-notification-target.png)。代理已停、故障规则终态committed_response_dropped、USB恢复C55183/V60331直连、Gate保持OPEN/1。
- **D04/P2（本轮新发现，首次修复后待统一包；最终复验见末节）**：卡片举报的聊天区间选择器和固定证据预览直接显示POST引用UUID，撤回卡片在选择器误标为图片。最小修复只按POST显示已确认的“分享”、按撤回显示既有“消息已撤回”；不改变固定snapshot/签名/原引用/提交负载，不读取或保存旧标题。新增Widget回归在旧实现实际FAIL（引用UUID被渲染），修复后analyze零问题、53 PASS/1专用真实TLS/PG fixture SKIP；[失败](E:/Hnuhole-env/android-v1-acceptance-01/card-report-preview-before.log)、[修复后](E:/Hnuhole-env/android-v1-acceptance-01/card-report-after.log)、[analyze](E:/Hnuhole-env/android-v1-acceptance-01/card-report-analyze.log)。展示修复不以此H测试冒充真实网络；现有direct-messages CI已包含dm_governance_test.dart，最新远程运行仍NOT_RUN。
- 真机已用B选取并明确授权仅第21条真实收到的POST卡片，在正常App提交举报；真实C中恰一工单PENDING，仍保存原POST引用，未对该工单作处罚。[真实提交核对](E:/Hnuhole-env/android-v1-acceptance-01/card-report-native.json)。提交发生于2026110704，适用于其未改动的构造/提交协议；D04新展示需最终统一包另验，不将旧显示FAIL抹去。

### 本次第3/4项最终交付

- **第3项PASS：实际网页审核/独立申诉复核已补齐**，新通知在正常App读回。原处理人回避、不同管理员复核、普通账号403、一次且仅一次的一天处罚及撤销、原帖恢复均有真实服务/只读SQL核对；没有绕过浏览器警告，网页/API/真机证据分别归属明确。
- **第4项按用户新确认的站内卡片范围PASS（分层）**：PC01–PC07结果以上述最新矩阵为准。外部系统分享/HTTPS唤起仍SKIP，不把延期称为修复通过。D完成入口/确认/取消/双向发送/冷启/未知原命令/草稿/最新标题/离线/删除/撤回/举报/默认通知及点击；其余权限竞态、全部DND/拉黑/禁言组合和旧客户端升级由已列H/S/生产Dart证据覆盖，未伪称每个子场景同次真机。
- **D04最终真机PASS**：2026110705的选择器第19/21条显示“分享”、第20条显示“消息已撤回”，固定证据预览只显示“分享”、没有UUID；取消新预览未重复提交举报。[选择器](E:/Hnuhole-env/android-v1-acceptance-01/52-card-report-picker-fixed.png)、[固定证据预览](E:/Hnuhole-env/android-v1-acceptance-01/53-card-report-preview-fixed.png)、[最终聊天](E:/Hnuhole-env/android-v1-acceptance-01/54-final-share-card.png)。原D04 FAIL截图/测试仍保留历史；没有为隐藏引用而改写举报负载。
- 最终App代码/构建源 **`baa817e4083293a9fc0ecfb294ff58b573cd0909`**；2026110705、`0.1.0-android-v1-card-report`、正常main/profile/arm64；APK **59,754,305字节**，SHA256 **`f3d3d4b6566c9b360922cf5072fb25fb7de2f5a8bae74ea95114bedfdea9cb55`**。同独立包、同测试签名及defines，realme Android14用户0实际安装摘要一致。[构建](E:/Hnuhole-env/android-v1-acceptance-01/android-card-report-build.log)、[签名](E:/Hnuhole-env/android-v1-acceptance-01/android-card-report-signature.log)、[包](E:/Hnuhole-env/android-v1-acceptance-01/android-card-report-receipt.json)、[设备](E:/Hnuhole-env/android-v1-acceptance-01/device-card-report-receipt.json)。
- C仍 **6483ac119c97ce17c3f4f360c68bc229cccef066**、二进制3e12436c，V仍main6b722f0、C35/V7；当前C配置SHA256 **`feb2241d75dcd266c748b57e339c0e49c04203cda7b4723abcb82d63b4ccc409`**。相对该C构建只改Go测试，最新App与实际构建产品树一致，[源码等价回执](E:/Hnuhole-env/android-v1-acceptance-01/followup-source-equivalence.json)。53项针对回归/1专用真实fixture SKIP及零analyze适用于D04源；新包未重跑全量1173项，不把旧完整运行提升为最新源全量。
- 最终独立实验室严格TLS健康；C/V Gate均OPEN/1，各RECOVER审计仍只有初始化1次，角色仍无kind/sender UPDATE或messages DELETE；POST 19/20/21均已ACK清body、20已撤回，原命令回执保留，未多发。故障代理停止、C/V两条任务USB映射直连，实验室保留供已装包使用。[最终服务核对](E:/Hnuhole-env/android-v1-acceptance-01/followup-final-service.json)、[最后重复恢复通知0](E:/Hnuhole-env/android-v1-acceptance-01/notifications-card-final-dedup.json)。旧lab-final-check历史回执已恢复原摘要，新故障收尾另存lab-followup-final-check，不覆盖旧版本事实。
- 手机操作已结束，回到系统首页；未修改publictrial/日常包及对应后端，未重启Windows/WSL。合成新工单2已完成处罚撤销；卡片举报工单仅PENDING、未处罚，均非正式用户。截图/日志/私有运行材料不提交，本文本机证据链接及摘要见[本次证据清单](E:/Hnuhole-env/android-v1-acceptance-01/followup-34-evidence-manifest.json)。
- **整体首版仍不具备交付条件**：本次已关闭网页缺口及新范围站内分享待验，不消除Q06已有持续负载FAIL，也不替代最新本地修复的远程产品CI/审查/合并与正式发布。其他原生Passkey、旧Android权限分支、第二物理设备及iOS原延期/缺口维持；公网试用、真实邮件/电脑恢复另按PUBLIC-TRIAL-ACCESS-01其独立候选记录，不以本实验室替代。实现本地完成；本项验证完成（明确分层）；未Push/PR/合并；独立安装完成；日常安装未执行；正式发布未执行。

## PR与合并执行（2026-11-07）

- 用户明确授权：“把这次验收修复和站内分享一起推上去提 PR，跑完 CI，没问题就合并到 main。”本轮授权覆盖该任务分支Push、PR及检查通过后的正常合并；不覆盖日常包/后端更新、正式部署，不绕过分支保护或成员审查。
- 再核对实际根目录/分支/远端及干净Worktree，fetch后origin/main仍6b722f071f07cbd94d96095734499f8cdd061641；任务产品候选baa817e及上述构建/真机证据保持适用。整包差异51文件，包含四项验收缺陷、站内分享/C35、兼容与对应验证/契约；不包含实验室凭据、APK、日志或其他任务改动。
- 已推送并创建[PR #113](https://github.com/zewbby/SpeechFUL/pull/113)，目标main，产品树仍baa817e。作者自检覆盖最终授权/互回限制、可靠命令、旧客户端能力过滤、只存引用、举报快照与迁移，未发现新增阻断问题。当前无独立GitHub成员review或未解决review thread，不将作者自检算成员批准。
- 远程CI进行中；最终PR head、适用产品检查及合并回执在本节追加。actual-process-acceptance为workflow_dispatch专用SKIP；其余以当前head实际checks为准。既有Q06持续负载FAIL和其暂停边界保留，正常代码合并不代表首版整体交付通过或正式发布。

### PR113最终回执

- 已完成Push、PR及正常Squash Merge。被检查/实际合并的PR head为 **89fa1af7564e15104e9299e1ba6b7362d918272c**，产品树与Android构建源baa817e相同；[全部CI](https://github.com/zewbby/SpeechFUL/pull/113/checks)共26项，**25 success／1按workflow_dispatch条件skipped**，无失败或运行中项。[原始检查回执](E:/Hnuhole-env/android-v1-acceptance-01/pr113-ci-final.json)。包含私信真实SQL/Android、完整契约、Go/PG、头像、评论、治理、限流、Feed、候选构建与升级演练；协作检查不冒充产品验证。
- 合并前再次核对PR head未移动、base仍6b722f0、mergeable=true；无成员review或未解决review thread。遵循用户维护者授权正常调用GitHub合并，未请求作者自批、未解除或绕过保护。[PR #113](https://github.com/zewbby/SpeechFUL/pull/113)实际merged=true，2026-11-07 12:33:49 +08完成。
- 合并SHA **314162a17ae2736eae41af230fdddd038af1471a**。fetch后origin/main实际为该SHA；与已通过CI的89fa1af完整Git tree无差异。本任务之外所有Worktree/已有改动保留，未切换或重置共享main工作区。
- 本最终状态记录单独提交并保留在任务分支，未另开仅同步状态的文档PR；其与main的差异仅本文回执，不改变已合并产品，也不将归档文档提交冒充经产品CI检查的head。实现/适用CI/合并完成；日常包/后端更新和正式部署未执行。既有热榜30分钟FAIL、其他延期/外部缺口与证据边界仍保留，整体首版发布验收结论不因本次合并改为PASS。

## 用户追加第2/3项：真实开户与公网包统一（2026-11-07，进行中）

- 用户明确“做2，3”，对应最新缺口清单的真实校园验证码提交/开户，以及将最新修复统一到公网试用包；允许独立publictrial同包升级与正常操作，不覆盖日常包/正式发布。沿用既有PUBLIC-TRIAL-ACCESS-01隔离资源和任务分支，部署专项详细证据续写[该唯一专项记录](E:/Hnuhole-env/source/SpeechFUL-public-trial-access-01/docs/tasks/PUBLIC-TRIAL-ACCESS-01.md)，本节保留Android整体验收权威结论与对应关系；未派出子Agent。
- 最新main已实际到 **e399fd34453ad294b04b56489ac86716c6779404**（PR113产品＋PR114文档）。先完成2026110706同源公网构建/装机，实际保留既有合成账号及3帖、正常公网分享空态/取消；旧包/证据不覆盖，日常包不变。
- **D05/P1新发现**：真实用户OTP输入失败后，核对返回NOT_COMMITTED时客户端误删仍有效的原OTP申请，导致下一步变灰。用户截图与合成测试复现相符（旧实现期望otpRequested、实际idle）；已修复为仅清除已确定未提交的确认key并保留原flow/bootstrap；REVERIFY_REQUIRED仍结束验证，未知结果不换key/不自动发码，不放宽服务端认证/Gate。新增控制器及完整Widget改码恢复回归，App analyze零问题、认证七文件146 PASS。D05尚未伪称已在真实用户账号故意输错/穷举复验。
- 新本地产品候选 **97ee00f998bae7f9880f76ecb16543bd852f524e**，承载在专项分支`codex/chore/public-trial-access-01`；主线之上产品只改auth_flows.dart，两项关联测试另列。**新修复远程CI NOT_RUN、未Push/PR/合并**；PR113既有25成功/1跳过保持原适用版本。热榜旧FAIL不变。
- **当前公网包2026110707** / 正常main/profile/arm64 / 原publictrial独立包和测试签名，APK59,754,317字节，SHA256 **0f58c903d9e2bacfbf77728baa559105e309c03d5faca978c3ed67d6dda7b6bb**；realme Android14用户0实际base.apk摘要一致，install-r且firstInstallTime不变。C仍6483ac1/3e12436c、C35/V7、Gate OPEN C1/V2；未修改后端产品或恢复Gate。[新包及源码/设备指针](E:/Hnuhole-env/public-trial-access-01/current-public-package.json)。原2026110705验收包未替换，其旧D/H/S证据按各自范围适用。
- 第2项真实开户仍进行中：新版正常App于13:18:26向既定批准邮箱发码，真实服务SENT/ACTIVE、0失败，有效至13:23:26；已交用户在手机自行完成账号/密码、恢复码及首次身份，不收集真实凭据。第3项同源/新包/签名/装机通过，最新版最终公网业务复验等待该链路完成；不能把测试替身或旧包结果提升为新版真实开户PASS。后续真实服务/脱敏页面完成结果将在此归档。

### 第2/3项关闭回执

- **第2项PASS**：用户明确“已进入首页”；在2026110707正常App完成真实校园新码确认、账号/密码、恢复码及首次身份。随后真实服务只读确认该邮箱OTP CONSUMED/0失败、资格已保留，C聚合账号及CONSUMED注册由1→2；不保留实名、账号ID、验证码、密码或恢复码，不跨库导出实名与匿名账号关联。[真实服务结果](E:/Hnuhole-env/public-trial-access-01/real-registration-registered.json)、[完成页脱敏布尔结果](E:/Hnuhole-env/public-trial-access-01/real-user-page-registered.json)。
- **第3项PASS**：当前公网包97ee00f/2026110707已同包更新、签名/摘要核对、正常真实开户和公网读帖；结束进程再正常冷启，原新账号无需重登且可读已有测试帖，[新包冷启结果](E:/Hnuhole-env/public-trial-access-01/real-user-page-registered-cold-start.json)。原独立验收包和日常包/后端不变；当前手机留在新账号首页。
- D05的控制器/Widget错误改码完整回归PASS，真实用户完成的是正常注册/冷启路径，没有故意向其账号注入错码，不冒称该错误分支在新包逐项D复现。新本地修复97ee00f仍须适用远程CI、审查和合并；本轮未Push/PR/合并、未正式发布。热榜既有30分钟FAIL及其他原延期/设备边界仍保留，整体Android交付仍不通过。

## 最新状态复核（2026-11-07，PR115之后）

- 用户要求再次检查；实际远端main已为 **8808d0087822f95e78672bafcb51b3f90ca11ef7**，含[热榜性能PR115](https://github.com/zewbby/SpeechFUL/pull/115)，已核对实际merged=true及最终head各项checks完成、无失败（actual-process-acceptance按条件SKIP）。本次仅状态核对，未重新压测、部署、构建或操作手机业务。
- **热榜源码/隔离性能缺口已有新PASS**：固定被测3d29500与新main的services/api无差异；新正式长测600.002秒基线＋1800.543秒后台，仍32逻辑客户端/16业务事件每RAW秒、真实五分钟周期、≤5%原阈值；计算匹配窗口搜索P95 **363.197→279.561ms（−23.028%）**，全程40764个HTTP无错误/超时、0容量丢弃，六轮定时榜及期限通过。[新性能证据](E:/Hnuhole-env/source/SpeechFUL-global-hotlist/docs/tasks/evidence/global-hotlist-performance-20261107.md)。本Session重算summary/requests/worker-events三个原始文件SHA256，与该证据一致；退出状态0。旧2026-11-06 FAIL仍按旧版本保留，不再泛称主线性能“尚未修复”。
- **部署/候选仍有缺口**：PR115明确没有部署/装机；本任务公网候选仍97ee00f/2026110707，现存公网C二进制摘要仍3e12436c（6483ac1），监控本机两个上游健康200，尚无8808新后端部署及联合业务复验回执。因此新隔离PASS不能自动提升当前公网运行环境为已通过新性能候选。
- **D05仍未进入main**：逐文件diff确认新main的auth_flows.dart仍缺97ee00f修复；远端public-trial任务分支仍354aec9，无本修复的新PR/CI/合并记录。需要将D05并入当前main，满足新head适用产品CI/审查，再按部署授权统一公网版本并聚焦复验。
- 真实校园邮箱开户、首页/冷启及站内分享/网页治理此前PASS保持各自版本；外部分享SKIP/iOS延期不重开。本次ADB无连接设备，当前手机包仅引用13:18–13:20版本7安装/业务证据，未宣称这次重新真机核对。其他原生Passkey、第二物理设备、旧Android权限与正式发布范围仍维持原边界。

## D05送审与合并执行（2026-11-07）

- 用户选中“97ee00f还缺远程CI、PR和合并”并明确“做这个”，授权本次D05修复推送、提PR、运行适用CI并在检查通过后正常合并；不包含公网/日常后端部署、安装包更新或正式发布。常规模式，无委派，不绕过保护或成员审查。
- 在干净`codex/chore/public-trial-access-01`中正常合入最新main **8808d0087822f95e78672bafcb51b3f90ca11ef7**，保留PR115全部性能修复。App/packages产品树与已装2026110707的97ee00f逐文件无差异；本次相对main只含D05一个流程文件、两项回归测试及已有任务记录。将本权威记录的最新版本串行集成到送审Worktree，原记录Worktree不并行改写，不新增任务ID或交接文档。
- 自检覆盖：只有V权威NOT_COMMITTED结果允许丢弃该确认key，仍沿用原flow/bootstrap且使用新确认key；REVERIFY_REQUIRED仍结束验证；未知/PENDING及超时不得换key，客户端不授予资格、不自动发码。原API/预算/最终Gate不变，146项关联认证测试和已记录真实注册/冷启证据按其版本适用。最新main整合后的本地复验及最终head远程状态以下列PR/检查为准；不把作者自检当GitHub独立成员批准。
- 合并前必须复核实际head、适用checks完成且无失败、未解决审查及保护状态；回执在合并后归档。不重复构建或装机，不部署新后端，本任务之外所有Worktree/数据保留。
- 最新main整合后的本地复验PASS：`flutter analyze --no-pub`零问题、七文件认证146项通过（`otp-pr-analyze.log` / `otp-pr-auth-tests.log`，原公网外部证据目录）。检查发现Auth feedback原CI只选择页面/会话等测试，现补入`auth_flows_test.dart`，让本次新增NOT_COMMITTED/REVERIFY_REQUIRED控制器回归在远程实际运行；无新增产品差异。当前提交仅两任务记录和这一行CI选择器追加，产品树仍与97ee00f/已装7一致。
