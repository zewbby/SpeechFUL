# CUSTOM-TAGS-01 — 帖子自定义标签

- 模式：常规；负责人／状态维护人：当前 Session。
- 分支／Worktree／PR：`codex/feat/custom-tags`；`E:/Hnuhole-env/source/SpeechFUL-custom-tags`；[PR #109](https://github.com/zewbby/SpeechFUL/pull/109)。初始主线基线 `48bcbc7cf90d163597d1f8a5f5944d9a08cb3ebf`，开发期间整合主线帖子分享后端 `4a3115dad4c0ecd257afc85f3abaea3a8ea3de69`。最终产品代码提交 `64fcc2b8b7128d827be92cb0e9a1fba48c3a333e`。
- 授权依据与边界：2026-11-06 用户要求「需求：新增 自定义标签 功能」，完成 Q1–Q6 后回复「可以，按这个方案实现。」；随后明确要求「推送，合并，部署」，授权本任务 Push、PR、检查通过后合并及部署到现有日常开发环境。保留其他工作区及正式数据，不将日常环境交付冒充生产发布。
- 需求确认：2026-11-06 用户逐项回复 Q1–Q5，依据见下方；Q6 已由用户最终确认，以下方案无未决取舍。
- 更新日期：2026-11-06。
- 状态：实现已完成；验证 PASS（下列本地范围，远程产品 CI 与设备验收待验）；正在推送送审，尚未合并；部署准备中，尚未发布。

## 目标与范围

为帖子增加公开主题标签。本次沿用 [AGENTS.md](../../AGENTS.md) 的需求收敛规则和 `grill-with-docs` 及其 `grilling`、`domain-modeling` 指南。

- Q1 用户确认公开主题标签：作者添加，所有读者可见；每帖零至三个，支持自定义、复用和作者编辑。
- Q2 用户确认「同意，使用独立标签面板（建议）」：发布确认页和编辑页使用底部面板，输入时提示已有词或创建新词；完成选择返回，不提交帖子。正文 `#文字` 不自动解析为标签。
- Q3 用户确认「同意，点击查看全站同标签帖子（建议）」：信息流卡片和详情展示标签；点击打开独立结果页，默认全部分类，可切分类，每次查看一个标签。现有首页「筛选」继续用于屏蔽分类。本次覆盖旧通道内多标签 AND 筛选设计。
- Q4 用户确认「同意，关键词也匹配标签（建议）」：普通搜索匹配标题、正文和标签，继续遵守所选分类、账号屏蔽及内容访问权限。
- Q5 用户要求「标签最多10个字，其他按照你来」：每个标签 1–10 字，允许中文、英文字母、数字和下划线；不含空格、换行、表情或内嵌 `#`。自动去掉首尾空格和开头 `#`；英文不分大小写，同帖重复词只算一个。
- Q6 用户回复「可以，按这个方案实现。」：独立标签结果精确匹配标签；全部分类按最新发布混排，不按分类分组，可切分类；首版无热度排序或多标签组合；返回保留原页面位置。

## 接口与依赖

- 已同步扩展草稿、创建／重试协议、公开投影、编辑与 SQL，保留原命令幂等、公开版本、会话及最终 C Safety Gate。非空标签包裹完整文字／图片命令帧，空标签保留旧摘要；旧未决编辑不补入标签字段，避免改变原提交。
- [迁移 0033](../../services/api/migrations/0033_post_tags.sql) 保存不可变发布标签、公开标签、精确检索键与已有词投影；触发器沿用 invoker 权限，删除／下架及时退出检索和提示。当前从主线到该迁移的首次安装与升级已经过一次性真实库验证；之后整合其他迁移时仍按最终链复核。
- `POST /api/v1/post-tags/posts` 使用单标签精确匹配、首次发布时间和发布序号降序；游标绑定账号、标签、分类、页大小、发布上界和屏蔽版本。`POST /api/v1/post-tags/suggestions` 只提示公开可访问词，前缀下划线按字面处理。
- 新客户端通过 `X-Post-Tags: v1` 读取标签；旧公开 DTO 继续省略该字段，旧客户端编辑省略标签时保留当前标签。分享链接解析读取原帖时传递同一协商状态。
- 当前首页「筛选」打开账号级通道屏蔽，不能直接作为已有标签筛选入口：`apps/mobile/lib/src/posts/feed_screen.dart:296`、`x_feed_controls.dart:46`。
- 基线搜索仅匹配标题和正文；本次增加标签关键词匹配，另提供独立精确标签页，不改变普通搜索分组和排序。
- [标签规则](../design/modules/tags.md) 已按 Q1–Q6 更新，旧通道内多标签 AND 筛选由本次独立单标签结果替代。
- 本地存在未合并关联分支 `codex/refactor/categories-global-hotlist`，涉及分类和全站热榜入口；尚未作为本任务基线或依赖，本任务不能把其行为当成已合并事实。

## 验收标准

- 已确认：作者可以为帖子设置零至三个公开主题标签，可以输入新词或复用已有词，仍有编辑权限时可以修改。
- 发布确认和编辑面板的选择与取消行为符合 Q2，最多三个且每个 1–10 字；校验失败不丢失已输入内容。草稿、失败发布重试和结果核对保留所选标签。
- 信息流及详情展示已保存标签；普通搜索也能命中只在标签出现的关键词，分类范围和屏蔽规则继续生效。
- 独立标签页精确匹配，默认全站按最新发布混排，可切分类；刷新、分页、详情返回及来源页返回符合 Q6，迟到响应不覆盖新范围。

## 当前进度与证据

| 项目 | 被测版本／环境 | 结果与证据 |
| --- | --- | --- |
| 仓库调查 | Windows PowerShell；主线 `48bcbc7` | PASS。已核对实际源码根、远端、分支、Worktree 和原有改动，并建立独立任务分支；原工作区未修改。 |
| 实现 | `568a8f5` 功能；`2f6e7fc` 整合主线；`64fcc2b` 完成边界修正 | 发布／重试摘要绑定、草稿与旧未决编辑、公开投影、编辑、建议词、普通搜索、独立标签页及举报证据已接入。会话代次在面板建立时固定，未操作就换会话也关闭旧面板。 |
| Flutter | Windows Flutter 3.47.5；180 项受影响基础回归，随后按最终差异聚焦标签、HTTP 和布局；`flutter analyze --no-pub` | PASS。基础结果 [flutter-final.log](E:/Hnuhole-env/custom-tags-validation-20261106/flutter-final.log)；最终图片新建／重试向量、会话变化、迟到响应、面板与 HTTP 合计 46 项通过，见 [边界回归](E:/Hnuhole-env/custom-tags-validation-20261106/flutter-final-boundaries.log)；[最终 analyze](E:/Hnuhole-env/custom-tags-validation-20261106/flutter-final-analysis.log) 无问题。最终 Flutter 产品源码与 `64fcc2b` 一致。 |
| Go 静态与单元 | `64fcc2b` 的 Git archive 解到 `/home/hnuhole/custom-tags-20261106`；Go 1.22.2；`go test ./...`、`go build ./...`、`go vet ./...` | PASS，三个命令退出码均为 0，[状态记录](E:/Hnuhole-env/custom-tags-validation-20261106/go-verified-status.json) 及同目录 `go-verified-*.log`。无 DSN 的 host 结果只证明该范围，真实 SQL 另列。 |
| SQL、迁移和安全回归 | `2f6e7fc`；WSL2 Linux 源码、一次性 PostgreSQL 16；`sh authlab/run-feed-isolated.sh`，pattern 覆盖标签、搜索、schema、Goose、Gate、注销及分享 | PASS，27 个顶层测试及其子项，见 [SQL 回归](E:/Hnuhole-env/custom-tags-validation-20261106/sql-merged-final.log)。包括六种首次／升级链、最小权限、旧模块兼容、标签修改、清空、分页／屏蔽、字面下划线、举报原标签证据及 Gate 冻结。最终相关业务和 schema 源码未改变；分享协商增量另列。 |
| 最终真实 HTTPS／Dart | `64fcc2b` Git archive；同一独立 SQL runner；`FEED_TEST_PATTERN='^(TestRealHTTPSPostTags\|TestRealHTTPSPostShare)'`；提供编译后的 `POST_TAGS_DART_PROBE` | PASS，4 项真实 HTTPS 测试，包含实际 Dart 客户端读取、搜索、建议、编辑清空和创建后任务恢复，以及分享原帖保留标签、旧客户端封闭 DTO 和无效／冻结会话。[原始日志](E:/Hnuhole-env/custom-tags-validation-20261106/sql-final-boundaries.log)、[退出码与版本](E:/Hnuhole-env/custom-tags-validation-20261106/sql-final-status.json)。 |
| API 与管理端 | `64fcc2b`；全量 OpenAPI、`tools/check-community-text-contract.py`；管理端源码与 `2f6e7fc` 相同 | PASS，13 份 OpenAPI 和 25 个受保护操作静态契约；[OpenAPI](E:/Hnuhole-env/custom-tags-validation-20261106/openapi-final-64fcc2b.log)、[契约](E:/Hnuhole-env/custom-tags-validation-20261106/contract-final-64fcc2b.log)。`node --check apps/admin/app.mjs` 及 13 项管理端测试通过，见 [管理端测试](E:/Hnuhole-env/custom-tags-validation-20261106/admin-tests.log)。 |
| 可见布局 | 最终标签组件；360×800、1.5 倍文字、深色主题，实际 Noto Sans SC 与 Material Icons 字体 | PASS，无溢出，已目视核对标签、删除图标、3/3 数量与完成按钮；[截图](E:/Hnuhole-env/source/SpeechFUL-custom-tags/apps/mobile/build/custom-tags-render/tag-picker-dark-large-text.png)。此证据属于 Flutter host 渲染。 |
| Android 构建 | 最终 Flutter 产品源码；`flutter build apk --debug --no-pub --target-platform android-arm64` | PASS，[构建日志](E:/Hnuhole-env/custom-tags-validation-20261106/android-final-boundaries.log)。本地 `apps/mobile/build/app/outputs/flutter-apk/app-debug.apk` 的 SHA256 为 `4569a9104e7c78c9b169d9fbd3a22a42abfff9635013b5fabf5b422e5c25b7a5`。未安装设备，不等同于真机验收或发布。 |
| 历史失败及修复 | 首轮本地 SQL；修正前的 pre-0015 历史夹具未移除新增标签结构 | 原始 FAIL 保留在 `sql-affected.log`，不作为通过证据。夹具已完整移除后续标签结构以模拟旧库；同名测试在上述 `2f6e7fc` SQL 回归 PASS。 |
| 产品 CI、设备与独立审查 | PR #109，首轮 head `b8a4f91`；当前仅模拟器在线 | 首轮契约 CI FAIL：接口总数预期仍为 23，实际增加两个标签接口后为 25；校正测试断言后重跑。其他产品 CI 运行中；真机、iOS 和独立审查 NOT_RUN。本地结果不冒充远程 CI、成员批准或正式发布。 |
| 远程回归发现与修正 | `d77b2a0` ＋仅测试夹具差异；WSL2、一次性 PG16、race | 身份／图片／信息流／治理 CI 暴露另一处 runtime 历史删列夹具，治理旧库夹具同样需先移除完整标签结构；私信与头像 Goose 测试仍硬编码 C31。均修正，3 项历史形状回归 PASS（[日志](E:/Hnuhole-env/custom-tags-validation-20261106/historical-fixtures-pr109.log)），私信和头像 fresh/upgrade 各 PASS（[退出码](E:/Hnuhole-env/custom-tags-validation-20261106/migration-regressions-pr109.json)）；未改变产品逻辑或迁移。最终 head 产品 CI 仍待验。 |
| 日常部署准备 | 当前固定清单 `8582593`，C30/V7；原部署用户 `hnuhole` | PASS：原环境停止，已使用固定恢复器 resume 正常启动；C/V 严格 TLS ready。Gate 保持 OPEN，C generation=11/RECOVER=11、V generation=8/RECOVER=8；未调用 recover。新版本尚未升级；待远程 CI 与合并后进行停写备份、前向迁移及清单重新固定。 |
| 发布权限审计增量 | `96a53f0` ＋明确审计差异；一次性 C/V 独立 PG 集群 | 远程发布与身份审计 FAIL 原因为矩阵未登记 `post_tag_terms` 的既有 SELECT/INSERT/DELETE 授权。精确补入该表，新增拒绝 UPDATE/REFERENCES/TRIGGER 及 recovery/business 读取的负测试。14 项 prerelease 工具与真实权限审计 PASS，见 [日志](E:/Hnuhole-env/custom-tags-validation-20261106/prerelease-role-audit-pr109.log)。该差异不扩大数据库授权。 |
| 回退边界 | C33 相对尚无标签的服务版本 | 已从旧服务严格列授权检查确认其不兼容新增 tags UPDATE；C33 down 已明确拒绝。发布演练同步为：旧源码无 0033 时，实际旧 C 进程必须拒绝启动并保持全表／sequence 摘要不变，再重新启动候选并复验原 HTTPS 业务；兼容版本仍执行原二进制回退。真实演练待最终 CI；不声称旧服务可在 C33 运行。 |

产品证据绑定上述源码提交；此后的任务记录、README 和 CI 路径触发更新不改变被测产品源码，也不提升验证范围。所有数据库与私有 CA／会话 fixture 均由任务 runner 创建和清理，未修改日常或正式业务数据。

## 阻碍与下一步

无本地开发阻碍。按用户「推送，合并，部署」继续完成远程产品 CI、合并和现有日常开发环境部署。设备状态与实际运行基线将在部署前核实；不自动推进其他未合并功能。
