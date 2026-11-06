# ANDROID-V1-ACCEPTANCE-01 — Android 首版完整业务验收

- 模式：常规；负责人／状态维护人：当前 Session；无委派。
- 分支／Worktree／PR：`codex/test/android-v1-acceptance-01`；`E:/Hnuhole-env/source/SpeechFUL-android-v1-acceptance-01`；未创建 PR。
- 基线／候选：2026-11-06 fetch 的 `origin/main`：`6b722f071f07cbd94d96095734499f8cdd061641`。远端配置 `https://github.com/zewbby/HnuHole.git`（项目已更名 SpeechFUL）。实际共享仓库 `E:/Hnuhole-env/source/HnuHole`，detached `af272dc`、干净；外层用户目录为无提交的交接仓库，所有内容保留。既有 Worktree 未切换、未清理。
- 授权依据与边界：本次用户完整验收指令。允许隔离 Worktree、一次性 PostgreSQL/Redis、合成账号／数据、独立验收包构建和安装、正常 App／系统权限操作、确定性最小修复及必要本地提交。未获得本任务覆盖日常包／修改日常后端、Push、PR、合并、正式部署的新授权；完成可独立准备后再处理。只清理本任务明确创建且无依赖的资源。
- 需求确认：以本次指令及下列已确认任务为准；私信运行中提醒，进程结束后再次进入同步并提醒，保留权限和免打扰；iOS 延期；热榜既有30分钟持续负载 FAIL 保留，先调查适用性及交付影响，不自动长测或优化。业务取舍有歧义时使用本机 `grill-with-docs` 及依赖；当前事实调查阶段无新增取舍。
- 更新日期：2026-11-07。
- 状态：实现 验收及最小修复进行中；验证 FAIL（已发现确定性缺陷，修复待最终装机；其他场景分项记录）；合并 未合并；独立验收包 已安装；日常安装 未执行；正式发布 未发布。

## 目标与范围

判断最新 main 的 Android 首版当前已确认业务是否具备交付条件。完整覆盖用户指定的账号／会话、身份、首页阅读、发布草稿、编辑删除、搜索标签热榜、评论回复、私信、通知治理、我的设置分享。正常 App 入口的实际可见状态与真实数据结果和自动化替身证据分别登记；缺口不记 PASS。

## 接口与依赖

- 最新主线含搜索 #101/#104、编辑兼容 #102 及功能 #103、私信恢复 #105、动效 #107、自定义标签 #109、分享后端 #108／客户端 #111、全站热榜 #112。
- 已读 [POST-SEARCH-01](POST-SEARCH-01.md)、[POST-EDIT-01](POST-EDIT-01.md)、[DM-RESUME-NOTIFICATIONS-01](DM-RESUME-NOTIFICATIONS-01.md)、[CUSTOM-TAGS-01](CUSTOM-TAGS-01.md)、[POST-SHARE-01](POST-SHARE-01.md)、[GLOBAL-HOTLIST-01](GLOBAL-HOTLIST-01.md)、[TELEGRAM-MOTION-01](TELEGRAM-MOTION-01.md)。旧记录的 PASS 仅适用于所列旧版本。
- 当前日常后端／包指针来源 `b46244d023cb0c3a2b847ef0855082c0cade9a01`，C34/V7；手机安装记录为 vivo `10CEAG17RY003M7`，2026110605 profile。相对候选存在分享客户端等实质差异，不能认作最新 main 联合候选。当前 ADB 仅 realme `7e0660f1` 在线，原独占租约已于 2026-11-05 23:08 +08 到期，实际资源与包归属继续核实。
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
| 版本一致性 | 日常来源 b46244d 对候选 6b722f0 | FAIL（尚未解决）：40 个文件差异，含分享 App、原生链接、翻译和迁移审计；不沿用日常安装启动回执作完整验收。 |
| 热榜性能 | 既有 [30分钟持续负载证据](evidence/global-hotlist-sustained-20261106.md) | FAIL（历史，适用性调查中）：计算重叠窗口搜索 P95 +77.83%，2 次503、40次容量丢弃；本轮未重跑／优化。 |
| 候选构建／安装 | `6b722f0`、Flutter3.47.5/Dart3.13.4、JDK17、SDK36；realme RMX3366 Android14、1080×2400、density408 | PASS_INSTALL_AND_LAUNCH。独立 `org.hnuhole.hnuhole_mobile.androidv1`，正式 `lib/main.dart`，profile/arm64、2026110601/0.1.0-android-v1-acceptance；仅applicationId和可见标签包装差异。APK 59,754,605字节、SHA256 `52c2e7c16ebeacd459c2206367f2303637b092921f0d28c7573eed5148a5c438`；实际证书SHA256 `1538fb309499d651d7d12d7711a646c4a80fde4b1397857a9e39ce672b3dc9ae`（profile实际沿用现有debug测试证书，未使用新生成验收key，不能称独立新签名或生产签名）。[包回执](E:/Hnuhole-env/android-v1-acceptance-01/android-receipt.json)、[装机回执](E:/Hnuhole-env/android-v1-acceptance-01/device-install-receipt.json)。日常包未改。 |
| 客户端参数 | 同一候选；严格任务CA及两条loopback HTTPS origins、`AUTH_DEV_PROFILE=true` | PASS。define文件SHA256见包回执；未注入会话、fixture或测试入口。图片包iOS两个symlink在Windows构建副本展开为原目标文件，不影响Android。原始候选Git archive与Worktree产品无差异。 |
| 独立后端 | 同一候选，非root WSL2 Linux文件系统、Go1.22.2、PG16、Goose3.22.1、Pillow12.3.0；新C34/V7、独立评论与热榜Redis7 | PASS_READY，前后端候选一致。[运行回执](E:/Hnuhole-env/android-v1-acceptance-01/lab-receipt.json)。使用既有grant-community/images/moderation/comments/direct-messages；基础角色审计在DM opt-in前PASS，基础审计按设计拒绝完整DM授权，DM opt-in另由运行时严格schema/不可变列拒绝和真实DM runner验证；不删审计限制。UI实例未启用共享admission Redis，该范围另跑真实隔离runner。 |
| 环境准备失败 | 本任务一次性实例 | 已定位并修正配置：snapshot namespace必须绑定dev；Redis7.0不支持CLIENT SETINFO；初始化operator需SETNX。C启动最初漏DM专用grant，最终补精确canonical grant后启动。两新Gate各显式recover一次初始化，之后只resume/watch；无修改Gate行、改钟或再次recover。工具probe-posts在完成HTTPS动作后的受限SQL核验拒绝非其marker，记工具NOT_RUN，不算完整probe PASS。 |
| Go host／完整契约 | 候选archive，无产品修改 | PASS：`go test -mod=readonly ./...`、build、vet；完整13份OpenAPI和25个保护操作静态契约通过。`go-host.log`、`openapi.log`。全目录gofmt发现21个原有文件格式差异，未为本轮验收批量改写；适用近期产品格式检查已有CI。 |
| Flutter完整回归 | 同一候选；Windows、原锁离线解析 | PASS：App analyze零问题，1164 PASS/4 SKIP；图片包analyze零问题、138 PASS。4项SKIP依赖专用真实fixture/头像输入，不冒充真机通过。日志[App](E:/Hnuhole-env/android-v1-acceptance-01/flutter-tests.log)、[图片](E:/Hnuhole-env/android-v1-acceptance-01/viewer-tests.log)。 |
| 真实Feed系列 | 候选Linux副本，race、一次性PG/Redis/HTTPS；`run-backend.sh`固定pattern | PASS：[真实回归](E:/Hnuhole-env/android-v1-acceptance-01/feed-real-sql-redis-https.log)，覆盖搜索/历史、标签、编辑文本图片、分享、榜单排序过滤/权限、评论及迁移。依赖Dart可执行文件和专用迁移库的SKIP单列，后续补探针。 |
| 远程产品CI | [PR112最终head检查](https://github.com/zewbby/SpeechFUL/pull/112/checks)，head `084bd3e8536634922dfb2776181a212005a2017a` | PASS：实时28项check，27 success/1 actual-process-acceptance skipped，无失败；含Go/PG/HTTPS/Flutter/Android候选与升级回滚。`git diff --name-only 084bd3e HEAD`为空，合并候选完整tree一致。不是本轮真机全业务PASS，也不把协作policy当产品验收。 |
| 旧热榜FAIL适用性 | `8af7b08`→候选 | FAIL保留：worker、candidate Gate准备、runtime rankings及rankings cache无差异；搜索增加标签匹配和最终匹配复核，不能外推旧具体P95数值为本候选实测，但不存在消除既有资源争用/503/drop的新性能修复证据。本轮未长测/扩压/优化；交付风险未闭环。 |
| 六组真实专项回归 | 原候选；非root WSL2 Linux，PG16、Redis7、race；`run-other-sql.sh` | PASS：email-login、identity-avatars、dm-chat、moderation、comment-snapshot、shared-rate-limit六个runner退出0。各自创建私有一次性库，非设备证据。[退出码](E:/Hnuhole-env/android-v1-acceptance-01/other-sql-status.txt)，原始`*-real.log`同目录。尚未执行原生Passkey或真实校园邮件供应商。 |
| 五个生产Dart真实探针 | 原候选，现有锁及Linux Dart原生可执行；PG/Redis/HTTPS/race | PASS：Feed、Search、Share、Tags、Rankings五项，非替身网络层。[真实日志](E:/Hnuhole-env/android-v1-acceptance-01/dart-real-https-sql.log)。初次工具误列不存在的独立rankings探针，纠正为复用现有post_search探针后执行，没有产品改动。 |
| 编辑未知结果／冲突 | 原候选D+R；仅A及其原帖的任务专用TLS代理 | PASS：真实服务SAVED后丢响应，App显示待核对；结束进程重进本人帖子编辑，先核对并回公开版，随后正常编辑。另用原会话通过真实API保存一个同revision并发编辑，再转发原请求，真实409；App保留旧输入、提示复制和主动载新版。非伪造服务端成功。[未知](E:/Hnuhole-env/android-v1-acceptance-01/04-edit-unknown.png)、[冲突](E:/Hnuhole-env/android-v1-acceptance-01/05-edit-conflict.png)，代理事件在Linux私有runtime的`acceptance-fault-events.jsonl`。 |
| 编辑图片／标签补充 | 原候选D+R，同一原帖且已有两条评论 | PASS：删除第三张图、真实长按拖动将GIF从第二移到第一、新增ReuseV1标签并保存；原身份/分类/首次发布时间/两条评论保留。[拖动后](E:/Hnuhole-env/android-v1-acceptance-01/07-edit-reordered.png)。早期ADB draganddrop未成功操作不计PASS；独立DOWN/长按/MOVE/UP后的实际顺序已目视核实。 |
| 私信真实链路 | 原候选D+R，A正常App，B经真实SMTP/注册/恢复及正常API；32帖为B的正常发布命令生成 | PASS（已执行范围）：从真实帖子联系、身份选择、首图禁止发送、首条文字等待、B回复后文字和图片、原生本地历史；B待收接口确认A图片为IMAGE。备注、置顶、免打扰已走普通菜单；未完成项见矩阵。 |
| 私信恢复和通知 | 原候选D+R，原生POST_NOTIFICATIONS通过系统设置授权 | PASS（指定链路）：正常主页面恢复补收；force-stop期间B实际发送、PID为空且通知0；正常入口重开后原生安全存储恢复账号、补收且通知1，默认标题SpeechFUL/正文“你有一条新私信”；系统通知点击实际进入A身份与B会话且可见新消息。免打扰时消息收取、无通知。权限关闭/恢复操作已执行；完整去重/权限关闭期间ACK复核继续。[停止](E:/Hnuhole-env/android-v1-acceptance-01/notifications-process-stopped.json)、[冷启](E:/Hnuhole-env/android-v1-acceptance-01/notifications-cold-start.json)、[免打扰](E:/Hnuhole-env/android-v1-acceptance-01/notifications-muted.json)。 |

### 本轮缺陷与修复

- D01／P2：已确认删除楼中楼后，回复内容消失、帖子总评论数下降，但主评论回复计数仍为1；手动刷新后才清零。真机原候选复现；根因是`CommentPostPane._changed`移除已删除子行时没有同步其主行`replyCount`。
- 最小本地修复：仅在已加载回复被权威`runtime.deleted`确认并首次移除时，扣减对应已加载主行的数量且下界0；重复通知时子行已移除，不二次扣减；不重排楼层、不加请求、不改变删除协议或权限。
- 回归：`comment_views_test.dart`新用例真实点本人回复菜单删除，断言子行消失、主行回复数由2→1且重复notify仍1。原产品先FAIL（Expected1/Actual2），修复后PASS；证据`comment-count-before.log`／`comment-count-after.log`。聚焦analyze和完整受影响回归/最终包真机复验继续。
- 修复后完整App回归PASS：1165通过/4既有专用fixture SKIP，`flutter-after-fix.log`；聚焦analyze零问题。首个专项命令误列不存在的`comment_controller_test.dart`，其余90项通过但该命令整体不作PASS；以随后完整App回归替代，不将工具路径错误记为产品缺陷。
- 目前源码候选为原完整SHA＋`apps/mobile/lib/src/comments/comment_views.dart`及对应测试差异；已装APK仍是原候选，不把源码回归提升为手机已修复。后端未改。

## 场景矩阵

环境缩写：D＝realme Android14，正常 `lib/main.dart`、原生安全存储、任务独立包；R＝候选一次性 C34/V7、真实 PostgreSQL16、独立评论 Redis 和热榜 Redis、严格私有 CA HTTPS；H＝候选 Flutter host/widget，网络／平台替身；S＝仓库真实 SQL/HTTPS/race runner；P＝公网公开域名及发布签名。D+R 才作为联合真机业务证据。数据 A/B/C 均为任务合成账号；IP、邮箱、恢复码、私钥及令牌只在私有材料中。

以下预期来自用户本次清单及链接中的既定产品契约；关联场景共享 fixture，但执行结果分别登记。普通失败/未知结果仅对任务隔离实例注入，禁止修改日常后端。

| ID／链路 | 已确认的预期行为 | 环境／所需数据 | 结果／证据入口 |
| --- | --- | --- | --- |
| A01 校邮注册 | 固定 hainanu.edu.cn；验证码确认→账号设置→安全收尾→基础身份；失败不绕过 Gate | D+R；新 A；隔离 SMTP 捕获 | PASS（合成SMTP正常App完整链路）；`ui-dumps`及[首次首页](E:/Hnuhole-env/android-v1-acceptance-01/01-first-home.png)。真实校邮供应商另列 BLOCKED，合成 SMTP 不代表外部实际投递 |
| A02 密码／邮箱登录 | 回原账号；错误不泄露账号存在性；重登读取权威目录 | D+R；A/B、正确及错误密码 | NOT_RUN |
| A03 恢复及现有凭据 | 现有恢复码、Passkey 等入口可达；恢复流程按既有协议；原生 Passkey 单独验收 | D+R；独立恢复凭据 | NOT_RUN；公网 RP 关联条件另列 |
| A04 退出／冷启／前后台 | 退出清会话，冷启恢复有效会话，回前台校验及同步，失效不继续读写 | D+R；A 有效／撤销会话 | NOT_RUN |
| A05 换号隔离 | A 草稿、未决编辑、聊天、搜索历史与迟到响应不进入 B；返回 A 依原约定恢复 | D+R/H/S；A/B 各有不同材料 | NOT_RUN |
| A06 设备接替 | 新移动设备登录使旧会话失去在线权限；旧本地记录须原账号重登 | 两设备或独立设备密钥客户端+S；A | NOT_RUN；仅一台物理设备，第二实体设备 BLOCKED |
| I01 身份创建切换 | 至少1、最多3；同账号昵称不重名；选择、头像与实际使用身份一致 | D+R/S；A 1→3身份 | NOT_RUN |
| I02 资料／限制 | 昵称2–12字且30天冷却；头像更换；累计第三次创建后6个月，不因删除重置 | D+R/S；合成资料及边界 fixture | NOT_RUN；不改系统时钟等6个月 |
| I03 同帖身份 | 同帖首次受理后固定，帖子／评论／DM／通知归属正确，不按昵称推断身份 | D+R/S；A两身份+B同名身份 | NOT_RUN |
| I04 删除身份 | 不可删最后身份；旧公开内容占位；本人对应聊天与备注清除；未决任务核对后处理 | D+R/S；可删除合成身份 | NOT_RUN |
| F01 首页模式 | 推荐／固定分类顺序与选中态、账号屏蔽、刷新／分页、空态／重试一致 | D+R/H；7分类、足够分页、屏蔽 | NOT_RUN |
| F02 阅读返回 | 列表→详情→返回保留范围／位置，权威计数更新，失效内容不泄露 | D+R/H/S；分页内容、删／下架帖 | NOT_RUN |
| F03 图片阅读 | 图片／GIF加载、缩放、短拖回弹／长拖退出、保存原图；权限拒绝可恢复；返回系统栏正确 | D+R；合成PNG/JPEG/GIF、相册拒绝 | NOT_RUN |
| W01 发布内容 | 纯文字／纯图／组合，标题正文规则；移除／排序图片；成功首页／详情／我的一致 | D+R/S；A、三张可区分图片 | NOT_RUN |
| W02 标签／草稿 | 最多3标签各1–10字，选择面板不提前发布；草稿恢复图片顺序／标签／身份 | D+R/H；新词、复用、非法词 | NOT_RUN |
| W03 发布故障 | 明确失败可重试；连点幂等；未知先核对原命令；取消不能换键重发已受理任务 | D+R/H/S；任务隔离故障代理 | NOT_RUN |
| E01 编辑读回 | 本人菜单编辑标题正文／有序图片／标签；保存同帖并显示已编辑时间；原身份分类互动不变 | D+R/S；A有互动的已发帖 | PASS（标题正文、新增PNG/JPEG/GIF三图、原标签保留、详情读回）；[编辑详情](E:/Hnuhole-env/android-v1-acceptance-01/02-edited-detail.png)。D未证明图片拖动排序已生效，标签修改和原互动另验；S相关回归PASS |
| E02 退出／失败 | 未提交退出丢弃；明确失败旧版仍公开且当前页可重试 | D+R/H/S；合成已发帖 | NOT_RUN |
| E03 未知恢复 | 原账号同机保留原输入／命令／图片；回包丢失重进先核对；成功载入公开版，未知只核对或原次重试 | D+R/H/S；隔离代理丢响应 | NOT_RUN |
| E04 冲突／权限 | 同版先成功者生效，后者保留输入主动载新版；删除／下架后关闭编辑；举报留存当时证据 | D+R/S；两客户端、合成举报 | NOT_RUN |
| Q01 搜索状态 | 自动输入与明确提交、相关度／最新、分类范围、空结果扩大、分页与详情返回保持状态 | D+R/H/S；不同分类命中及无结果 | NOT_RUN |
| Q02 历史 | 仅明确提交词记录；同账号身份共享、按范围隔离，跨设备读取；复用置顶、删除／确认清空 | D+R/H/S；A/B 多范围历史 | NOT_RUN |
| Q03 标签结果 | 点击单标签默认全站按最新混排，可切分类；关键词匹配标签；返回来源位置 | D+R/H/S；跨分类同标签 | NOT_RUN |
| Q04 全站热榜 | 空输入统一纯文字全站榜并隐藏分类筛选；关键词恢复范围／排序；真实分类详情返回刷新 | D+R/H/S；跨分类热帖 | NOT_RUN |
| Q05 热榜可见性／失败 | 删除／下架／屏蔽过滤并补位；请求失败保留旧榜及重试，不显示过期账号旧响应 | D+R/H/S；21+排序帖、隔离Redis故障 | NOT_RUN |
| Q06 持续负载 | 沿既定30分钟、算榜窗口搜索P95增幅≤5%及零错误／容量丢弃的验收门槛 | 历史隔离负载；本轮只比对适用性 | FAIL（历史保留，未自动重跑） |
| C01 评论／回复 | 主评、楼中楼文字图片；准确回复目标定位、排序分页、点赞；同帖身份固定 | D+R/S；A/B、足够评论与图片 | NOT_RUN |
| C02 输入／删除 | 离帖清未发送输入；切换目标有输入先确认；主评删整楼、楼中楼仅删本条 | D+R/H/S；合成讨论楼 | NOT_RUN |
| C03 失败／恢复 | 失败系统通知入口，重启核对原任务；重复提交只受理一次；未知不当作失败换键 | D+R/H/S；隔离故障代理 | NOT_RUN |
| M01 首次联系 | 点帖子作者进入身份对会话；保留来源帖；对方回应前仅一条文字，不可先图 | D+R/S；A/B、双方帖子 | NOT_RUN |
| M02 发送／重试／撤回 | 文字图片本地持久化后ACK，失败原次重试，2分钟内撤回；结果未知不伪装失败 | D+R/H/S；A/B、合成图片 | NOT_RUN |
| M03 会话治理 | 备注本人可见；置顶、隐藏、删除按各自规则；拉黑按账号，解除后可联系 | D+R/S；合成身份对 | NOT_RUN |
| M04 恢复提醒 | 首页／我的／私信页回前台立即同步；进程结束后重开补收并提醒；杀进程期间无保活要求 | D+R；B真实发信，A前后台／force-stop后正常入口重开 | NOT_RUN |
| M05 权限／DND／去重 | 权限关闭／恢复和免打扰仍生效，默认隐藏正文；重复同步不重复提醒；点击进正确身份会话 | D+R；系统通知许可、合成A/B | NOT_RUN |
| N01 通知分类／身份 | 回复、点赞、系统分类及身份切换、未读与目标跳转；已删／下架目标诚实显示不可用 | D+R/S；不同身份通知、失效目标 | NOT_RUN |
| G01 举报审核 | App提交合成举报→网页审核处理→用户处理通知，权限限制真实生效；证据不随编辑改写 | D+R+网页/S；独立管理员及A/B举报 | NOT_RUN |
| G02 申诉／限制 | 从处理通知申诉；审核通过撤销对应处罚；非管理员与其他账号不越权 | D+R+网页/S；仅合成处罚／申诉 | NOT_RUN |
| P01 我的分类 | 帖子／评论／点赞／收藏／转帖现有分类刷新分页和返回；失效内容按既有状态 | D+R/H/S；A各分类数据及删除帖 | NOT_RUN |
| P02 四语言 | 简／繁／英／日即时且持久；不重置路由、用户内容、输入与阅读位；换号仍保留设备偏好 | D+R/H；多语言／重启／A→B | NOT_RUN |
| P03 外观与安全入口 | 主题字号、窄屏大字、减少动画；黑名单、当前设备／最近替代设备、账号安全入口正确 | D+R/H；系统字体、两身份、黑名单 | NOT_RUN |
| L01 系统分享 | 首页／详情／菜单共享忙态；仅品牌和规范URL；取消不提示发送成功，迟到失权不弹面板 | D+R/H；公开帖和失效会话 | NOT_RUN |
| L02 链接恢复 | 热启动在原路由上开帖，冷启动／登录注册后首页开原帖；登录中最后点击为准，退出清除，最近任务旧Intent不重放 | D+R/H/S；A/B、多个有效与无效链接 | NOT_RUN |
| L03 公网关联 | 实际公开C域HTTPS、应用ID及签名匹配assetlinks，设备验证；AASA配置单列，iOS延期 | P；当前仅loopback私有CA、缺已确认公开域及发布签名 | BLOCKED；显式Intent／scheme不等价域关联 |
| X01 iOS | 保留用户原延期边界 | 无macOS／Xcode／iOS设备 | SKIP（本次用户明确延期） |

## 阻碍与下一步

核实设备可用性、日常与候选差异及独立环境；先轻量预检与最小真实 App 链路，再批量完整回归与设备业务验收。公网 HTTPS 关联及真实校园邮箱条件待事实核实。
