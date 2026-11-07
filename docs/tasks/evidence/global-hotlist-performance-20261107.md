# 全站热榜性能续修与持续负载验收

唯一任务状态：[GLOBAL-HOTLIST-01](../GLOBAL-HOTLIST-01.md)。历史失败保留在[2026-11-06证据](global-hotlist-sustained-20261106.md)。

## 版本与改动

- 实际main基线 `e399fd3`；本轮分支 `codex/perf/global-hotlist-search-isolation`。
- 固定被测提交 `3d29500abd496fe6796e4cbd75205de6fa5dbf62`，包含前一实现提交 `ba387b5`。
- 成功的最终业务提交不再调用Abort，减少一次重新获取全局Gate行锁的事务；失败、panic、取消及独立冻结仍执行原清理。
- 搜索在启动核对两列编辑文字及非空标签数组后使用直接列查询，避免重复将整帖转换为JSON。旧schema保留原查询，候选与最终投影使用同一分支；排序、Unicode、标签、游标及最终可见性重验保留。
- 详情、互动等准备流程复用已验证签名／锚点／时间／代次的只读决策并回滚，最终业务事务独立执行CommitAuthorized。未知Gate继续Snapshot；最终检查点的锚点落盘、SQL提交、会话检查和续期保留。
- 榜单算法、真实五分钟周期、有限让行、25秒worker预算、1秒热榜读预算及Redis 40ms超时均未改变；没有新增业务迁移或客户端改动。

## 诊断与安全验证

按用户指定，深入分析和独立静态复核使用GPT‑6 Astra／xhigh，常规实现与验证由当前模型执行。独立AI审查不计GitHub成员批准。

当前基线的完整一分钟profile中，成功后冗余Abort平均约210ms、P95约677ms；后半段锁等待放大到前台池耗尽。先移除该路径后，准备连接P95约0.27ms，实际候选SQL P95约178ms，能够区分SQL成本与池排队。直接列变体后，同类诊断候选查询P95约107ms。各次诊断存在环境波动，不把这些跨次百分比当作全部代码的因果收益。

`ba387b5`的短诊断仍有3次约1秒热榜503及6次容量丢弃，均不与算榜窗口交叠。进一步减少详情／互动的重复准备检查点后，才启动本次正式对照。此前第一轮诊断曾因执行中修改runner触发重复启动而截断部分证据，残留单独保留，不作为验收依据；后续要求全新证据目录且冻结runner。

| 验证 | 结果与证明范围 |
| --- | --- |
| Go测试／vet | PASS，WSL Linux文件系统；`go-host-prepare.log`、`go-vet-prepare.log`。 |
| 真实PG／Redis／HTTPS race回归 | PASS，`sql-regression.log`；覆盖搜索／分页／互动／热榜／最小权限、C/V取消及checkpoint后SQL失败仍冻结。 |
| 最新准备及查询补验 | PASS，`sql-prepare-regression.log`；typed与兼容查询的Unicode、合法编辑、标签独占、分页结果一致；候选后移除标签在最终事务拒绝。成功／拒绝／panic／过期四路径、真实未包装Gate的详情及条件互动各一次最终检查点、准备后freeze／recover／revoke／expired均有实际SQL验证。 |
| C29兼容查询与升级 | PASS，`sql-search-regression.log`对应legacy_search子例；实际WithPosts启动及私有候选／投影SQL成功，随后前向升级。该日志内曾有非法对照fixture失败，修正后的对照见上一行；不声称C29完整HTTPS授权验收。 |
| 静态契约／协作 | PASS，25项保护操作文字契约、差异及明确暂存路径检查。 |
| 远程产品CI／合并／部署／装机 | NOT_RUN，本轮只完成本地修复及隔离验收。 |

## 固定负载与环境

- WSL2 Ubuntu24.04，Go1.22、PG16、独立Redis、实际HTTPS；12逻辑CPU、约15.8GiB内存。
- 一次性双库／私有Unix socket和loopback Redis，marker及归属检查保留。30,001帖、30,000合法评论、3,000赞、3,000收藏，合成账户。
- PG shared_buffers 16MB、max_connections 40，前台池12、worker池1；Redis池8。没有关闭fsync／同步提交，没有修改系统时钟或加速业务时间。
- 32个逻辑请求客户端，固定16业务事件／CLOCK_MONOTONIC_RAW秒，70%搜索、20%详情、8%热榜、2%互动。正式关闭可选请求trace及50ms数据库观察器。
- 10分钟worker关闭基线、持续过渡及真实追赶、至少30分钟后台流量、尾随观察。周期性真实互动令七片失效，核对revision、dataVersion及公开榜单变化。
- 负载、请求起止、时窗、账目及持续时长使用同一RAW原点；UTC单独检查桶与发布期限。计算窗口仍按原1400事件相位及同一交叠规则匹配、去重，含追赶，不过滤慢请求。

## 正式结果：PASS

`run-soak-prepared.sh`只执行一次正式长测，`soak-prepared.status=0`；Go测试 `TestRealHTTPSRankingsSustainedLoadPostgres` PASS。整体进程时间包含数据准备及新桶对齐，以下时长为实际RAW阶段。

| 指标 | 关闭worker基线 | 后台持续流量 | 判定 |
| --- | --- | --- | --- |
| RAW时长 | 600.00198秒 | 1800.54338秒，尾随另30.00958秒 | 至少30分钟PASS |
| HTTP cohort完成数 | 9,960 | 29,895 | 错误／丢弃均0 |
| 搜索样本 | 6,720 | 20,166 | 正确20项、分类及游标约束通过 |
| 整场搜索P95 | 324.676ms | 258.067ms | −20.516%，≤5% PASS |
| aggregate匹配窗口搜索P95 | 363.197ms／587样本 | 279.561ms／96样本 | −23.028%，样本数及≤5% PASS |
| refresh匹配窗口搜索P95 | 366.116ms／698样本 | 277.432ms／112样本 | −24.223%，样本数及≤5% PASS |
| 计划／派发／丢弃事件 | 9600／9600／0 | 28809／28809／0 | 各阶段unaccounted=0 |
| 按实际End完成HTTP/s | 16.59995 | 16.60388 | 未减少派发负载 |
| 实际平均／峰值在途 | 2.137／19 | 1.956／15 | 32为逻辑客户端数 |

全程错误／超时／容量丢弃为0，RAW clock valid=true、clock_errors=0。实际采样也覆盖了原20ms安静条件无法满足的持续忙段，old_quiet_25s_timeouts=98；每个受测定时刷新具备要求的前向忙态证据。

30分钟内产出六个定时新榜，六轮互动栅栏全部Verified；全部七次追赶／定时发布的双截止检查PASS。六轮均实际重算七片，不以复用或停算替代更新。定时刷新RAW约1.163–1.321秒，距UTC桶边界约1.164–1.321秒发布；追赶本身约1.383秒。最大HTTP榜龄300.206秒，小于六分钟。

GPT‑6 Astra／xhigh独立从原始记录重算后PASS：归档全部475个API跟踪文件与提交逐字节一致，70个真实／匹配窗口及六阶段到达账目逐项吻合；全程40,764个HTTP均200、failure为空。2701个RAW校准点最大漂移约0.566ms。29,895为soak cohort HTTP数，实际End落入soak区间为29,896，边界跨阶段均已记账。

负增幅表明这次固定负载对照满足上限。baseline前后五分钟P95分别为386.593／255.655ms，存在时间变化；负增幅的措辞只描述本轮比较，不归因为worker使搜索加速。本机单次隔离结果不作为所有环境或生产容量的保证；64客户端容量、真机体验及公网性能不在本轮结论中。

## 原始证据定位

外部目录：`E:/Hnuhole-env/hotlist-performance-20261107`。不提交原始JSONL、数据库、日志、配置、密钥或构建物。

- Linux固定副本 `/home/hnuhole/hotlist-soak-prepared.OenEGi`；10个变更API文件与已通过回归副本逐文件摘要一致，见`source-match.json`；独立审查另核对全部475个API跟踪文件与提交一致。
- 提交归档 `source-prepared-final.tar` SHA256：`342963ad3b82fe2834c8618935e3cf3ffcf2fcc1d0ead3fe302edf39edaa5ec0`。
- `soak-prepared/summary.json` SHA256：`7d83fa8e14b8e070cca2d6cd9080efe173ce24ec6efb2fd4bdc5a8b66b43d943`。
- `soak-prepared/requests.jsonl` SHA256：`c52422759a0c08ce2514add418dcb91e1b3610eea29ae2d2adfe61b15136773e`。
- `soak-prepared/worker-events.jsonl` SHA256：`e46d34f07b61da768e1d4a363f45c8d18ad0618619f93f0dff1282db7b022ed9`。
- 运行命令：`wsl -d HnuHole-Ubuntu-24.04 -u hnuhole -- bash /mnt/e/Hnuhole-env/hotlist-performance-20261107/run-soak-prepared.sh`。日志`soak-prepared.log`，退出状态`soak-prepared.status`。
