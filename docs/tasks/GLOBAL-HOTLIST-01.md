# GLOBAL-HOTLIST-01 — 分类术语与搜索全站热榜

- 模式：常规；负责人／状态维护人：当前 Session。
- 分支／Worktree：`codex/refactor/categories-global-hotlist`，`E:/Hnuhole-env/source/SpeechFUL-global-hotlist`；实际 main 基线 `e9bfa80595cd05621ff86bd9da8fade284150110`。
- 授权依据与边界：2026-11-06 用户同意将产品中的“通道”统一为“分类”，要求搜索只维护全站总榜，并明确指定 GPT 6-Astra／xhigh 独立审查算法、实现及性能优化收益。本轮授权本地实现、隔离验证和独立 AI 审查；未授权本任务合并或正式部署。
- 需求确认：用户分别确认两项具体场景：任何分类搜索的空输入展示同一全站“大家都在看”并注明全站范围，关键词结果仍限定选中分类，榜单点击按帖子的真实分类进入详情，个人屏蔽及当前可见性仍生效；分类选择器固定目录顺序，推荐第一，取消分类活跃度统计和动态排序。无未决产品取舍。
- 模型：当前 Session 负责实现；独立只读审查指定 `gpt-6-astra`、`xhigh`。
- 更新日期：2026-11-06。
- 本轮追加授权：用户要求继续解决持续流量下算榜停滞，并明确确认以32个持续请求客户端、逐级探测64并发、正式持续压测至少30分钟验收；同一固定请求速率比较搜索P95增幅≤5%，同时记录错误率、完成吞吐和实际并发。真实五分钟更新，每轮一分钟内完成，榜单年龄小于六分钟。沿用本分支／记录，本轮基线 `06ca6fa0380abdfcfd3d31bcac71cbbb14cb41bc`，保留最终C Safety Gate。授权本地实现、一次性合成数据压测及沿用GPT 6-Astra／xhigh只读审查；不合并、不部署。
- 状态：业务修复 `072234c`、RAW验收工具 `8af7b08` 已本地提交，真实SQL回归／host tests／vet／独立静态审查 PASS。用户随后要求“尽快结束”，按尽快收口处理并结束新启动的验收；有效30分钟长测与搜索P95增幅≤5%仍待验，不宣称性能目标完成。此前长测计时失真作废。产品CI／本轮真机 NOT_RUN；未合并、未发布。
- 暂停／恢复：用户要求停止后端及WSL供其使用电脑，已停止并核对无运行发行版；用户随后明确“继续”，恢复本任务所需隔离验收。没有恢复其他历史延期业务。

## 目标与范围

统一首页、发帖、设置、搜索及相关多语言界面的分类用语；搜索空输入显示纯文字全站帖子热榜，切换搜索分类不重新维护分类帖子榜。分类导航固定顺序。保留既有帖子归属、搜索历史范围、关键词搜索、会话及最终 C Safety Gate。

审查现有算法和 PostgreSQL／Redis 实现，分别记录已确认问题、规模风险、优化建议与测量范围。旧任务 [CHANNEL-RANKINGS-01](CHANNEL-RANKINGS-01.md) 的性能数据只证明其原始低并发负载，不外推本次总榜或高并发收益。

## 接口与依赖

- 依赖已合并的 PR #106 排名、搜索和最终可见性校验链路。
- `GET /api/v1/feed/hot-posts` 返回 `{asOf,items:[{postId,channelId,title,viewCount}]}`，最多20条。`channelId` 为各帖真实分类；旧的分类帖子榜及热度顺序接口撤下，OpenAPI升至0.4.0，客户端与服务端同步升级。
- 对外只维护一个帖子榜单。内部保留七个失效分片以复用未变数据，64项不可变块保留完整排序键；单个全站Redis排序集合合并各片首64，最多448个候选。常态先取精确全站前64；不足时验证分片覆盖并深块补位。
- 上线前由部署流程应用0032、重跑 `infra/postgres/grant-community.sql`，Redis ACL允许 `~hnuhole:channel-rankings:v2:<environment>:*`；滚动兼容期保留v1授权及旧表。新版本不再生成旧分类榜；本任务没有连接或更改正式环境。
- 后台优先等待20ms空闲，但每次让行最多100ms，启动及七个脏片合计显式让行最多约800ms；私有快照提交前不再等待前台清空，消除持续流量导致的无限推迟。单连接worker及跨进程事务锁仍限制同时计算；脏片完整重算和主库资源竞争仍需实测，不把64项存储块冒充计算微批。初始独立审查见[审查与性能证据](evidence/global-hotlist-astra-review-20261106.md)。
- 搜索候选准备使用已识别C PostgreSQL Gate的签名、锚点、代次、可信时间及冻结校验后回滚，避免准备阶段写授权检查点；未知Gate保留原Snapshot。最终CommitAuthorized、会话代次／状态、当前内容可见性、历史写入和续期均保留，最终游标同时校验过期和完整TTL上界。

## 验收标准

- 用户可见“通道”统一为“分类”，四种界面语言含义一致。
- 所有分类的空输入均展示全站范围的同一排序来源；关键词结果仍服从当前分类；点击异分类榜单帖子进入其正确详情。
- 榜单仅含文字；个人屏蔽、删除、下架、到期和会话变化均生效，并按总榜顺序补位。
- 分类选择器采用稳定目录顺序，推荐第一；不再请求活跃度顺序。
- 无变化时避免重算；Redis 故障的已有顺序兜底、最终 Gate 和版本发布竞态有适用验证。
- 性能报告标注数据量、负载、被测版本、计算是否真正完成和快照年龄；估算和实测分别列出。
- 追加验收：持续流量下后台取得进展，不以无限推迟换前台P95；真实RunRankings及真实五分钟周期在正式30分钟长测产出新版本，持续互动进入新榜。每轮≤60s、运行中榜龄<6min；同固定到达率的基线／后台搜索P95增幅≤5%，报告原始样本、错误／超时／丢弃和实际并发。容量探测及短周期诊断不代替长测。

## 当前进度与证据

| 项目 | 被测版本／环境 | 结果与证据 |
| --- | --- | --- |
| 需求与基线 | main `e9bfa80`；用户两项明确答复 | PASS，需求如上，分支初始无已有改动。 |
| 实现 | `b41482e8c0d44e5c521c587df6d943b72e9c7df8`，基于main `e9bfa80` | 分类术语、固定导航、全站总榜、分片精确合并及分块补位完成。 |
| 独立审查 | GPT 6-Astra／xhigh，两轮；原始main及本轮产品差异 | PASS（静态范围）。修复前缀失效掩盖深处高分帖、权限任意／全部语义及缺块检测，静态复核无新增阻塞问题。详见[审查证据](evidence/global-hotlist-astra-review-20261106.md)；不计GitHub成员批准。 |
| Go host | WSL2 Linux文件系统、Go1.22，`go test ./...`、`go build ./...`、`go vet ./...` | PASS，外部 `go-host-final.log`。 |
| 真实SQL／Redis／HTTPS | 一次性PG16双库及独立Redis，`FEED_RANKINGS_REDIS=1 sh authlab/run-feed-isolated.sh`，含race | PASS，`go-sql-final.log`。覆盖作者排除、讨论去重、复用、未来／到期边界、深块补位、全站排序反例、屏蔽、删帖、Gate冻结／恢复、迁移白名单、最小权限及v2 ACL升级。 |
| Dart真实协议联调 | 编译生产HttpPostApi探针，实际C HTTPS＋PG＋Redis，同一隔离runner，`TestRealHTTPSFeedRankingsDartPostgres` | PASS，`dart-live-build.log`、`dart-live-sql.log`。覆盖全站榜解析、实际分类详情、分类／全站关键词搜索、历史及账户游标边界。首次fixture将旧服务地址与新证书配对，修正初始化顺序后PASS。 |
| Flutter | 锁定依赖，`flutter analyze --no-pub`，六个受影响test文件 | PASS，118项；`flutter-analyze-final.log`、`flutter-tests-final.log`。包括固定分类、搜索范围、单次全站请求、跨分类详情、迟到响应、弱网、纯文字、小屏大字、深色及减少动态效果。依赖锁无变化。 |
| 契约／协作 | `python packages/openapi/check-specs.py`、`python tools/check-community-text-contract.py`，差异检查 | PASS，12份OpenAPI及既有保护契约；协作检查随实现提交记录。 |
| Android构建 | Windows Flutter，Profile ARM64，`flutter build apk --profile --target-platform android-arm64 --no-pub` | PASS，`android-build.log`；APK SHA256 `79461403468fe6eee3293c7f8200789e6644dfd70cea97c8d377ef81ed268a80`。本轮未装机，不能复用旧包真机752ms结论。 |
| 真实接口负载 | 30,001帖／3,000赞／3,000藏；64组交替，最大2请求在途；每环境512详情／256搜索 | PASS，`performance-global.log`。热榜P95 12.57ms；搜索154.53→153.25ms（−0.8%），详情25.80→24.52ms（−5.0%）。每次刷新有25s预算且实际完成；不是持续高并发验证。 |
| 分块SQL与规模对照 | 实际rankBlockSQL、3万帖；另独立简化SQL模型1万／10万／100万候选，0%／80%失效 | PASS，真实查询0.476ms，主键索引7次、FunctionScan 64×7＝448项。简化模型10万无失效161.76→0.307ms；只证明候选查询形状收益，不等同接口加速。详见[证据及边界](evidence/global-hotlist-astra-review-20261106.md)。 |
| 未覆盖 | 本任务远程产品CI、真机可见时间、公网、持续30min高负载、多进程及生产配置容量 | NOT_RUN。代码／本地检查完成不等于合并或发布；旧任务性能数据不外推这些范围。 |

上述外部日志、探针、独立fixture脚本、EXPLAIN JSON与构建产物保存在 `E:/Hnuhole-env/global-hotlist-validation-20261106`；逐文件核对22个变更产品文件，被测Linux副本与实现提交 `b41482e` 字节一致。该提交新增Dart探针／联调回归另有真实PASS。仅证据文档更新不改变被测产品；Android包未包含独立探针文件，本轮未装机。

## 阻碍与下一步

无产品未决事项。按用户“尽快结束”收口，不自动重启验收。后续如继续性能验收，使用冻结版本 `8af7b08` 的RAW发生器，以32客户端、固定48业务事件／RAW秒作10分钟基线和至少30分钟后台长测，再判断5%／60s／6min指标；保持真实UTC、默认fsync和最终Gate。探索性容量已达到实际64在途，但不替代长测。版本、方法及限制见[持续负载证据](evidence/global-hotlist-sustained-20261106.md)。
