# CHANNEL-RANKINGS-01 — 通道热度与帖子热榜

- 模式：常规。负责人：当前 Session。
- 分支：`codex/feat/channel-rankings`，独立 Worktree `E:/Hnuhole-env/source/SpeechFUL-channel-rankings`，GitHub main 基线 `7edccf24a4dfe35f508efcea5c7ba5eace804999`。
- 授权：2026-11-05 用户要求「你重新做计划，要性能优先，要用户体验优先」，随后「拉分支做，选你认为合适的模型」，完成本地开发和验证后明确要求「合并吧」。本次授权覆盖该任务分支 Push、创建 PR 和检查通过后的合并。正式部署单独验收。
- 需求确认：沿用 HEAT-03/04/06/08/09 及最新搜索行为。按用户对计划的开做指令，采用提出的首版默认值：滚动 168 小时，点赞 1、收藏 2、讨论人数 3、半衰期 48 小时；通道按参与账号人数、新帖数、目录顺序排序，旧帖的近期有效评论计入。只影响浏览通道选择器。具体分类的空关键词显示热榜，全部分类维持历史。
- 更新日期：2026-11-05。
- 用户追加标题要求：页面中的「通道热榜」改为「大家都在看」，四语言文案和独立 Android 验收包同步更新。
- 追加优化授权：2026-11-05 用户要求「继续优化，把后台算榜时搜索耗时的增幅压到5%以内。还有热榜不要有任何的图片」。从本任务提交 `ce77dbd38c4e34a70d8cbf071d127df8919a9707` 继续，热榜展示仅保留编号、标题和浏览量文字，移除标题趋势图标、浏览量图标和行尾箭头。
- 用户追加视觉要求：搜索页做得更好看并加入动画。沿用现有蓝色和深浅主题，采用圆角输入框与聚焦过渡、胶囊历史词、历史展开动画、榜单卡片淡入及轻微位移。动画 180–220ms，系统减少动态效果或无障碍导航启用时收敛为即时展示。确定性视觉调整沿用既有搜索范围、输入、排序和导航含义。
- 模型选择：使用当前 GPT-6.1 Sol 执行开发与验证，常规单 Session。
- 设备授权：用户已确认解锁 RMX3366，并明确要求重新安装「这轮热榜独立验收包」。验收应用 ID 为 `org.hnuhole.hnuhole_mobile.channelrankings20261105`。
- 状态：实现已完成；验证 PASS（本轮本地功能、性能和真机范围，其他环境另列）；合并状态见 [PR #106](https://github.com/zewbby/SpeechFUL/pull/106)；发布未发布。

## 接口与依赖

- C 服务读取既有社区数据，每五分钟产生一版 PostgreSQL 排序快照，并发布到独立 Redis。在线优先 Redis，故障时读已算好的 PostgreSQL 顺序。
- API 最终复核同一会话、通道屏蔽和当前内容可见性。Flutter 在分类搜索和浏览通道选择器中使用，复用现有搜索和详情入口。
- `GET /api/v1/feed/channel-order` 返回版本时间与通道 UUID 顺序。`GET /api/v1/channels/{channelId}/hot-posts` 返回版本时间、通道及至多 20 条帖子 ID、标题与浏览量。客户端按返回位置连续编号。
- 应用 0031 后重新执行 `infra/postgres/grant-community.sql`。独立 Redis 仅用于排名前缀与版本指针，线上热路径读取每通道前 64 个候选。大量下架或 Redis 故障时从 PostgreSQL 已排序快照补位。最终事务不调用 Redis。
- 后台只生成私有候选，计算和候选写入不进入前台业务的最终 Gate 事务。一轮开始时通过既有 `RecheckForCommit` 在短只读事务内校验签名证据、独立检查点、代次与时间，成功后回滚该读事务。后台由此取得可信计算时间，避免额外写授权检查点和同步磁盘。检测失败仍执行既有 Abort 流程持久化独立冻结。公开读取仍须经过 `withPostSessionAt` 的最终 C Gate、会话和可见性复核。与恢复竞态产生的旧代次候选不能对外授权。
- 在线准备阶段只读取会话及数据库中已持久的 Gate 检查点来定位私有候选；检查点不裁决当前权限、时间或会话续期。所有对外结果与续期仍由最终 C Gate 的独立可信时间及会话检查裁决。缺榜时同样先通过最终认证裁决，避免掩盖已撤销会话。
- PostgreSQL 以语句级触发器记录通道输入修订。无变更且未到窗口边界时，新快照只引用原来的不可变通道数据。新发布、赞藏变更、评论发表／删除／下架和到期边界会重算受影响通道。指数衰减的排序采用数学等价的对数分，时间公共项不影响顺序，因此可安全复用；参数版本变化也触发重算。
- 私有通道数据的复用以相同代次、输入修订、公式版本和下一变化时间为依据，先建立新版本引用再清理旧公开快照，避免延迟一轮后反复全量重算。公开快照的 15 分钟时效仍在最终可信时间处裁决。准备阶段允许挑选比旧公开检查点更新的私有候选；缓存版本不满足最终时间窗口时，使用已验证时间定位 SQL 镜像并再次经过最终业务校验。
- 同一 C 进程内，搜索、既有帖子读取和热榜读取登记前台活动，HTTP 层覆盖完整帖子响应，业务方法也支持直接调用者。后台启动、聚合查询和提交前等待连续 20ms 无前台活动的空隙，前台请求仅登记并释放计数。五分钟触发、单轮 25 秒预算和失败后重试沿用既有规则；持续繁忙时重算可能延后，公开版本仍受既有时效校验约束。

本地 C 运行时启用示例。省略 `rankings` 保持功能关闭，已有服务配置可继续使用。

```json
"rankings": {
  "redisAddress": "127.0.0.1:6387",
  "passwordFile": "private/rankings-redis.password",
  "weights": {"like": 1, "favorite": 2, "discussion": 3, "halfLifeHours": 48}
}
```

独立 Redis 只绑定回环地址，ACL 用户名 `c_rankings`。限制键为 `~hnuhole:channel-rankings:v1:dev:*`，允许 GET、SET、ZRANGE、ZADD、EXPIRE、MULTI、EXEC、DISCARD、EVAL、EVALSHA 等本功能调用。密码保存在受限文件。应用只在新版本完整写好后切换指针，陈旧超过 15 分钟的服务端版本不再签发，客户端当前页按旧榜保留规则处理。C/V Gate、共享限流和评论快照实例的配置独立保留。

## 验收标准

- 作者排除、按账号去重、取消赞藏及评论删除、窗口与稳定排序均符合公式。删除、下架及屏蔽在展示前生效并补位。
- 输入和历史不依赖热榜。分类切换与迟到响应隔离。热榜刷新、回帖返回与弱网行为符合 HEAT-08。首页选择器打开后顺序稳定，发帖选择与设置顺序不变。
- 优先验证真实 PostgreSQL、Redis 和 HTTPS。同一并发环境测接口 P95 ≤250ms、算榜期间既有业务 P95 增幅 ≤5%，正常网络 Android 真机首条可见 P95 ≤800ms。目标与实测分开登记。

## 当前进度与证据

被测内容以 main 基线 `7edccf24a4dfe35f508efcea5c7ba5eace804999` 加本任务提交承载的实现差异定位。验证脚本、隔离构建、日志和截图保存在 `E:/Hnuhole-env/channel-rankings-validation-20261105`，正式源码只保留实现、回归和本记录。

| 项目 | 环境和命令 | 结果及证据 |
| --- | --- | --- |
| Go 静态与单元 | WSL2 Ubuntu 24.04 Linux 文件系统、Go 1.22；`go test ./...`、`go build ./...`、`go vet ./...` | PASS。`go-host-final.log` 和 `go-full-and-sql-final.log` 的 host 部分。无 DSN 的 host 结果仅证明该范围。 |
| 真实数据与权限 | 一次性 PostgreSQL 16 双库、独立 Redis Unix socket；`FEED_RANKINGS_REDIS=1 sh authlab/run-feed-isolated.sh`，启用 race | 帖子／搜索／赞藏／转发／评论文字／Gate／迁移／真实 HTTPS／排名缓存与运行时权限回归通过。首次全量日志中两项测试失败，随后更新 schema 白名单并修正窗口测试的五分钟桶边界预期，两项在 `go-sql-regressions-final.log` 聚焦复验 PASS。窗口测试覆盖尚未进入桶、进入桶、未到期及到期后的失效，无变更通道复用也有真实锁表验证。 |
| 评论图片附带回归 | 同一 SQL runner，未配置该项图片验证器 fixture | SKIP。`TestCommentBusinessMediaDeleteLikesNoticesPostgres` 和 `TestCommentBusinessHTTPSPostgres`，其余文字评论和榜单链路另有 PASS 证据。 |
| API 契约 | `python packages/openapi/check-specs.py`、`python tools/check-community-text-contract.py` | PASS，全部 12 份规范及既有契约检查。 |
| Flutter | Windows Flutter；`flutter analyze --no-pub`，`flutter test --no-pub test/post_search_test.dart test/post_api_test.dart test/feed_ui_test.dart test/community_localization_test.dart` | PASS，analyze 无问题，83 项测试通过。证据 `flutter-all-affected-final2.log`。覆盖迟到榜单、切分类、屏蔽后隐藏、可选榜单 503 保留会话与搜索、详情返回失败保留旧榜、小屏大字号、深色和减少动态效果。小屏用例聚焦搜索屏幕，既有首页筛选控件在 320px 宽度溢出已另行识别，未列入本次搜索验收通过范围。 |
| Android 构建与安装 | Profile、ARM64、RMX3366 Android 14；外部隔离 application ID，`adb install -r` 返回 Success | PASS。`android-visible-profile.log`，APK SHA256 `ff85550c46d25f868575c152a1c2fb16fe4f8ebca611916533df3cbae046b893`。构建时同步最终 `apps/mobile/lib`，搜索源码与构建副本的 SHA256 均为 `46c289c877b2c7967e8352d87d39d12efc4e60b5bfa2e11ccf95124275b63a00`。 |
| 首版 Android 操作与可见时间 | 真机＋USB loopback＋真实 HTTPS、SQL、Redis，一次性合成账号和帖子；无 Go race、每轮等前页彻底销毁，首条必须 `hitTestable()` | PASS。12 次为 651、270、250、277、220、528、294、294、292、243、316、324ms，首轮和 P95 均 651ms。`android-visible-live.log` 覆盖输入、分类切换、榜单详情返回，首版截图保存在 `device-screen-ce77dbd.png`。测试后删除私有认证 fixture、释放设备租约与本任务 reverse。USB 本地链路未覆盖公网网络抖动。早期旧探针存在退出动画污染的 3–18ms 样本，仅保留为历史日志。 |
| 接口性能 | 无 race，30,001 帖、3,000 赞、3,000 藏；120 次真实 TLS 顺序热榜读，后台独立单连接池 | PASS，P95 72.45ms，目标 ≤250ms。`performance-uninstrumented.log`。 |
| 首版算榜并发影响 | `ce77dbd`，同一数据下交替 16 组基线／重算窗口；每组 8 次详情和 4 次搜索，重算前事务变更赞；详情 128、搜索 64 个样本／环境 | FAIL，详情 P95 234.10→184.29ms（−21.3%），搜索 391.62→462.77ms（+18.2%），超过 ≤5% 目标。`performance-uninstrumented.log`。早期 race 压测同样未达到增幅目标，保留在 `performance-*.log`。该旧测试程序只断言了热榜接口阈值。 |
| 本轮 Go 最终检查 | `ce77dbd` 加本轮源码差异；Go 1.22、Linux 文件系统；`go test ./...`、`go test -race ./internal/rankings`、`go build ./...`、`go vet ./...`、相关 gofmt | PASS。`go-followup-final-host.log`。涵盖前台调度的等待、并发读计数与取消；真实数据库、Redis 和 HTTPS 另见 `go-followup-final-sql.log`。Gate 取消、冻结及恢复的额外回归见 `go-optimized-correctness-02.log`。 |
| 本轮客户端与无图展示 | 最终 Dart 源码；analyze 和相同四个 Flutter test 文件 | PASS，83 项。`flutter-text-only.log`。热榜标题和记录均无 Icon、Image、RawImage，API 投影继续仅含帖子 ID、标题与浏览量。 |
| 本轮大样本性能第 1 轮 | 无 race；30,001 帖、3,000 赞、3,000 藏；64 组交替基线／重算窗口；每组 8 次详情、4 次搜索；每个环境详情 512、搜索 256 个样本 | PASS。`performance-final64-01.log`。搜索 P95 297.57→306.32ms（+2.9%），详情 150.97→150.73ms（−0.2%）；120 次热榜读 P95 47.96ms。测试程序分别断言搜索和详情增幅 ≤5%，并断言热榜 P95 ≤250ms。 |
| 本轮大样本性能第 2 轮 | 相同最终源码与负载，重新创建独立 PostgreSQL、Redis、服务及合成数据 | PASS。`performance-final64-02.log`。搜索 P95 276.42→282.97ms（+2.4%），详情 142.69→140.37ms（−1.6%）；120 次热榜读 P95 50.71ms。两轮均无请求错误，`performance-final64-status.log` 两次 exit=0。 |
| 性能迭代历史 | 先定位后台检查点写入和跨周期全通道重算，再加入前台优先调度，最后覆盖完整 HTTP 响应 | 早期方案复测 FAIL，见 `performance-optimized-02.log`（搜索 +35.2%）、`performance-priority-01.log`（搜索 +4.7%、详情 +6.8%）、`performance-priority64b-01.log`（搜索 +1.9%、详情 +5.7%）。修正 HTTP 登记范围后，上述最终两轮通过。`performance-priority64-01.log` 在工具会话更新中被中断，只有部分样本，不能作为通过证据。最终长测由一次性 systemd 单元以 hnuhole 用户运行，完成后自动回收单元。 |
| 本轮 Android 构建与装机 | Profile ARM64，隔离 package；构建副本中的搜索源码与最终源码 SHA256 均为 `f2977813c8d737634cc74867324961dcd5dc2776cd85f9c7a717a98d9f6a8f1c` | PASS。`android-text-only-profile.log`、`adb install -r` Success。APK SHA256 `4d6c3f5bf27befde616b41b48707094f44f95765a1e05f583c5fef297beeb37b`。 |
| 本轮 Android 完整操作 | 用户再次解锁后，RMX3366 Android 14，USB loopback＋实际 HTTPS、SQL、Redis；最终后端和纯文字热榜 | PASS。`android-text-only-live.log`。输入、切分类、详情返回和无图片／图标检查通过；12 次首条可见为 752、251、297、252、240、211、280、316、286、243、327、350ms，P95 752ms。`device-screen.png` 已目视核对。隔离验收包已更新，私有认证 fixture 和本任务 reverse 已清理，设备租约已释放。 |
| 远程产品 CI | [PR #106 当前 head 的 Checks](https://github.com/zewbby/SpeechFUL/pull/106/checks)，GitHub 使用最新 main 的测试合并结果 | 以该链接的实际结果为准。合并前必须核对适用产品 CI 全部通过；本地结果只证明各自范围。 |
| 独立审查 | 常规单 Session；PR 作者本人 | NOT_RUN。未提交 GitHub 成员批准或独立审查证据。 |

## 阻碍与下一步

- 本轮用户要求已完成。上述性能结论适用于记录中的同一 C 进程、负载和设备环境；前台繁忙时算榜等待空隙，并沿用既有预算与重试。
- 公网网络下 Android P95 保持待验，评论图片附带回归及其他模块远程验收以 PR Checks 实际覆盖为准。可交付本地分支、已更新的独立自动验收包与实测截图；合并结果与提交以 PR #106 为准。
