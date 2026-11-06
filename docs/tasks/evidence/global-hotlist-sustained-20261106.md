# 持续流量下热榜与搜索验收

唯一任务状态：[GLOBAL-HOTLIST-01](../GLOBAL-HOTLIST-01.md)。此处仅保存证据与适用边界。

## 版本与实现

业务基线 `06ca6fa0380abdfcfd3d31bcac71cbbb14cb41bc`，修复提交 `072234c918b83485d386a58394e8f0dd9aeed99b`：优先等待20ms空闲，每次最多让行100ms，启动加七片显式让行最多约800ms；私有快照提交前取消无限等待。worker单连接、事务级advisory lock、25s预算、5min周期和15s重试保留。完整脏片仍重算，64项块不是计算微批。`max_parallel_workers_per_gather=0`只防护后续只读查询，当前写CTE原本已串行，不宣称CPU收益。

搜索候选准备采用已识别C Gate的签名／锚点／代次／可信时间／冻结验证后回滚，减少一次检查点写入；未知Gate沿用Snapshot。最终CommitAuthorized、会话代次、权限、当前可见性、历史及续期不变；最终游标同时检查过期及完整TTL上界。此后改动只涉及压测与证据。

## 计时与负载方法

- WSL2 Ubuntu24.04，Go1.22、PG16、隔离Redis，12逻辑CPU、约15.8GiB内存。PG shared_buffers16MB、max_connections40，默认fsync／同步提交；前台池12、worker池1。Redis TCP使用c_rankings ACL、pool8、40ms超时。HTTPS复用连接，5s客户端超时保留为实际受测约束。
- 只连接marker及归属检查通过的一次性双库／Redis。30,001帖、30,000条合法状态链评论、3,000赞、3,000收藏；独立合成账户。导入时临时receipt索引在约束检查后删除，不改变测量schema。
- 本环境曾测得Go elapsed3.0266s而RAW2.7938s，且墙钟相对计时多次校正。此前Go计时容量、长测结果不用于5%结论；停止的长测只保留为测量无效记录。
- 发生器due、实际派发、请求起止、耗时、phase、总账、并发积分、窗口、canary排除、catchup及持续时长统一使用同一进程CLOCK_MONOTONIC_RAW原点。Go timer只作最长50ms的可重试sleep，醒后重读RAW。RAW读失败立即使测试失败，不返回0继续等。Go／墙钟偏差仅作诊断，不要求两钟速率一致。
- 唯一保留的20ms Go ticker用于模拟原worker空闲条件；其span、采样间隔和前向25s证据均记录RAW，不控制负载或性能期限。采样间隔>40ms断开证据；要求span从该次refresh启动向后覆盖25s，末尾等待已记录的完整证据，不伪造foreground注册。
- UTC不作性能运算，但独立检查每个实际观察到的bucket在bucket+60s内发布，以及final Server-Time−asOf<6min。前跳跨桶不跳过应验桶；另以首次观察RAW+60s限制含重试的等待。系统NTP、真实授权时间及业务timer没有修改；非0 advanceClock直接拒绝。
- 固定到达率，70%搜索、20%详情、8%热榜、2%互动（先读版本、再条件写）；客户端满即记drop，不降低负载掩盖失败。停止仍派发所有已到期事件并等待请求完成；planned=dispatched+dropped核对。完成吞吐按真实RAW End落窗，另列计划到达cohort完成量和实际派发量，峰值与平均实际并发分别记录。
- 正式采用32持续客户端，固定16业务事件／RAW秒：48档的持续基线发生掉队后保留失败记录，正式两阶段同用16档。10min关闭worker基线、10s连续过渡、真实RunRankings追赶、至少30min后台流量及尾随观察。真实五分钟UTC周期、签名证据每真实分钟更新，不加速时间。每轮canary经实际API改变七片，记录提交revision，核对快照覆盖及公共榜单on/off。合法dataVersion复用不等同于未计算。
- 整场与实际refresh／aggregate窗口分别比较P95；基线按1400事件周期匹配相同类型／分类／互动相位，使用同一交叠规则，保留跨phase在途请求、去重，并避开canary前后5s。主要窗口合计各至少50搜索样本，增幅≤5%；尾段计算也纳入。
- 搜索必须返回20项、正确分类和nextCursor；详情postId正确；热榜仅四个文字字段。所有HTTP／语义错误、超时、drop、证据I/O失败均不算通过。结束时join全部生产／观察／发生器／授时goroutine。

## 证据与状态

外部目录：`E:/Hnuhole-env/hotlist-sustained-validation-20261106`。不提交JSONL、运行日志、密钥、数据库或构建物。

| 项目 | 结果 | 适用范围 |
| --- | --- | --- |
| 业务安全／SQL／Redis／HTTPS race回归 | PASS | `sql-regression-current.log`：准备不写SQL／锚点、临时禁令结束、最终checkpoint推进、游标上下界、从OPEN检测过期证据后SQL／锚点持久冻结、新Gate实例拒绝、会话撤销／恢复、分页／屏蔽及热榜最小权限。C／V取消检查不误冻。 |
| RAW迁移后host tests／vet | PASS | `go-host-clock-fixed.log`、`go-vet-clock-fixed.log`、`clock-invariants.log`；墙钟±20s不改变总账／窗口／P95，UTC或RAW迟发仍失败；RAW wait不早于期限且支持取消。没有DSN的host检查不代表SQL。 |
| GPT6-Astra／xhigh独立静态复核 | PASS | 用户指定模型只读审查；修正尾段覆盖、完成吞吐口径、RAW时钟迁移与观察边界。不是GitHub成员批准，也不是长测通过。 |
| 探索性RAW容量 | 已完成探测，非正式长测 | 64客户端，16..64业务事件／秒均无错无drop；64档峰值30，搜索P95约371ms。96档达到实际64在途，有738次drop，FAIL。`capacity-raw-64.log`；最终冻结版本须复验并绑定SHA。 |
| 冻结版本容量复验（历史） | 未完成 | `8af7b08` 曾启动容量复验，用户要求“尽快结束”后收口；`raw-final-capacity.log`不作容量通过依据。 |
| 用户限定的30min／5%正式验收 | FAIL | 后续用户明确“只做30分钟长测及搜索增幅≤5%”，同一 `8af7b08aa8f81c28b96395a4002b2561daea7363` 归档完成本节下述长测。时长达标，计算窗口增幅与负载错误未达标；没有继续修改业务或自动重跑。 |
| API／协作检查 | PASS（既有范围） | 12份完整OpenAPI、23个保护操作文字契约、明确暂存路径协作检查；当前提交另验。 |
| 远程产品CI／多进程／生产／公网／本轮装机 | NOT_RUN | 旧低并发及旧APK不外推此范围；未合并、未发布。 |

当前主容量成本仍包含C Gate行锁、锚点fsync及数据库提交。没有关闭fsync、改用内存盘、延长热榜业务预算或绕过最终Gate。最初夹具状态链错误、加速诊断触发安全冻结、Windows worktree路径不能在WSL git直接归档等记录均保留；它们不算产品验收或负载通过。

## 2026-11-06 有效长测结果

固定被测SHA `8af7b08aa8f81c28b96395a4002b2561daea7363`，Linux副本 `/home/hnuhole/hotlist-raw-final-20261106.MUGNNG`。结束后逐一核对压测harness、worker、search、cache四个关键源码SHA256，与当前工作树一致；后续只更新证据文档。RAW clock valid=true、clock_errors=0，所有计划到达均有账，无未解释丢失。

最初systemd后台进程随WSL会话关闭被终止，尚未进入有效计时；改为前台保持的WSL CLI执行同一归档。48档基线随后出现掉队，`soak-48-baseline-failed.log`保留失败；最终同速率16档从头采集基线和后台数据，没有将不同速率混合比较。

| 指标 | 基线 | 后台30min | 判定 |
| --- | --- | --- | --- |
| RAW时长 | 600.0065s | 1800.8454s | 30min PASS；尾随观察另30.0142s。 |
| HTTP cohort完成量 | 9,960 | 29,861 | 不把业务事件数冒充HTTP数；互动含额外读写。 |
| 搜索样本 | 6,720 | 20,141 | 真实返回20项及正确分类。 |
| 整场搜索P95 | 259.6234ms | 272.0814ms | +4.7985%，单看整场≤5%。 |
| 计算重叠窗口搜索P95 | 263.4807ms／623样本 | 468.5570ms／109样本 | **+77.8335%，FAIL**；含启动追赶与定时计算，按既定同条件窗口匹配并去重。 |
| 完整refresh窗口搜索P95 | 255.9135ms／747样本 | 545.3065ms／127样本 | +113.0823%，FAIL；不是只看正常闲时平均。 |
| HTTP错误／容量丢弃 | 0／0 | 2／40 | FAIL；错误均为热榜HTTP503，丢弃均client_capacity。 |
| 计划事件／派发／丢弃 | 9600／9600／0 | 28814／28774／40 | unaccounted=0，不能降低派发量后宣称无错。 |
| 按实际End统计HTTP/s | 16.5998 | 16.5817 | 主业务实际派发15.9781/s，低于计划16/s。 |
| 实际平均／峰值在途 | 2.0492／24 | 2.2534／32 | 32为逻辑客户端数；不是全程32在途。 |

后台在30min内发布六个新版本，六轮互动revision栅栏与公共榜单均验证。六次定时refresh RAW约1.12–1.55s；UTC边界后约8.44–19.17s发布，另启动追赶约1.79s，七项发布时间双截止检查均PASS。HTTP最大榜龄318.638s，小于6min。六个定时轮次均有可信的前向25s持续忙证据；启动追赶未具备同样完整span，不能将其额外busy断言当PASS。

结论：**完整有效30min已跑完，搜索≤5%与整体负载验收未通过。** 整场+4.80%掩盖了计算期间尖峰，不能据此宣称优化达标。此为本机一次隔离环境测量，不推断所有抖动都由算榜造成，不外推生产容量；按本轮用户范围只记录结果，不继续优化或重跑。

原始文件位于外部证据目录：`soak-16-8af7b08.log`、`soak-16-8af7b08.status`（1）、`soak-16-8af7b08/summary.json`、`requests.jsonl`、`worker-events.jsonl`；runner为`run-soak16.sh`。Go test失败信息明确为负载错误／派发减少及计算窗口延迟／忙态证据，退出1不伪装PASS。
