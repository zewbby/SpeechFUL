# POST-SHARE-01 — 帖子分享与链接打开原帖后端

- 模式：常规。
- 负责人／状态维护人：当前 Session。
- 分支／Worktree／PR：`codex/feat/post-sharing`；`E:/Hnuhole-env/source/SpeechFUL-post-sharing`；[PR #108](https://github.com/zewbby/SpeechFUL/pull/108)。实际基线为 2026-11-06 fetch 后的 `origin/main` `48bcbc7cf90d163597d1f8a5f5944d9a08cb3ebf`。
- 授权依据与边界：用户要求“新增 帖子分享与链接打开原帖 后端功能”，后续明确授权“推送本次分支并创建 PR，相关产品 CI 全部通过后合并”。覆盖本任务分支推送、PR 及适用产品 CI 全部通过后的合并；不包含部署，不修改现有开发／正式业务数据。
- 需求确认：用户于本会话回答 Q1–Q3 时全部选择推荐方案，确认外部链接分享、仅后端交付、登录后阅读／网页仅通用引导，以及每帖固定长期链接／打开最新公开内容。使用 `grill-with-docs` 及其 `grilling`、`domain-modeling` 依赖完成收敛，无未决产品取舍。
- 更新日期：2026-11-06。
- 状态：实现 已完成；本地验证 PASS；远端验证与合并以 [PR #108 当前 head 检查及合并记录](https://github.com/zewbby/SpeechFUL/pull/108/checks)为准；发布 未发布。

## 目标与范围

交付可复制到微信等外部应用的固定 HTTPS 帖子链接、受登录保护的原帖解析接口及不包含帖子内容的通用落地页。系统分享按钮、App 外部唤起接线、登录／注册／初始身份设置后的路由恢复和设备验证由后续前端工作完成，本轮不宣称已交付完整手机跳转链路。

### 已核实的基线事实

- 本机外层交接目录 `C:/Users/24237/Documents/ChatGPT/Hnuhole` 是无提交、无远端的独立 Git 目录；实际源码 Git 主目录为 `E:/Hnuhole-env/source/HnuHole`，detached HEAD `af272dc`，不是当前主线基线。已从 fetch 后的 `origin/main` 建立本任务独立 Worktree，保留现有工作区及他人工作。
- 实际源码配置远端为 `https://github.com/zewbby/HnuHole.git`；现有任务文档记载项目现名为 SpeechFUL。本次仅按现有远端 fetch，不修改仓库远端配置。
- Feed 中 `FeedAction.share` 无实际行为；详情显示“分享（暂未开放）”。Android/iOS 与 Flutter 未检出分享插件或外部帖子链接接入。
- 已有 `GET /api/v1/posts/{postId}`，HTTP 路由位于 `services/api/internal/authprivacyhttp/posts_endpoints.go`；通过 `ReadPosts` → `withPostSession` → `readPublicPost` 读取当前公开内容。删除、下架或不存在的原帖当前统一为 `POST_NOT_FOUND`，不返回历史正文。
- 现有“转帖”是本人身份下的私人引用归档；`docs/design/modules/post-detail.md` 和 `docs/design/post-reposts-contract.md` 明确其与复制链接／系统分享独立，系统分享不调用转帖写入接口。
- 历史规则 `DETAIL-01` 要求系统分享只包含产品名称和链接，外部预览不携带帖子标题、正文、作者身份或图片。`ACCESS-01`／`AUTH-SHARE-01` 要求登录后查看，登录／注册及基础身份设置完成后由客户端恢复原帖意图。唤起和返回栈仍待实现设计。

### 本轮确认结果

- Q1：用户选择“是，按此外部链接方案（推荐）”。外部分享与私人转帖独立；本轮交付后端接口和链接入口，App 接线延期。
- Q2：用户选择“是，登录后查看，网页仅作引导（推荐）”。公开页面及外部预览不含标题、正文、作者或图片；未安装 App 时仍仅提供通用引导，不包含网页阅读器。
- Q3：用户选择“是，固定链接并读取最新内容（推荐）”。同一环境／帖子固定链接；删除、下架后不能取回内容；无到期、单独撤销、分享者追踪或分享计数。

## 接口与依赖

- `GET /api/v1/posts/{postId}/share`：当前 Bearer；返回 `{postId,url,shareText}`，`shareText` 仅为 `SpeechFUL\n` 加链接。获取时按原帖详情检查当前可见性。
- `POST /api/v1/post-links/resolve`：当前 Bearer；JSON `{url}`；仅接受当前配置 origin 下的规范分享 URL，返回现有 `{post}` 详情及授权／编辑元数据。无远程 URL 抓取。
- `GET|HEAD /s/posts/{postId}`：通用 HTML 引导；不查数据库和帖子存在性，不返回内容及会话续期元数据。按钮目标为 `speechful://posts/{postId}`，供后续 App 接线；页面不自动跳转、不加载第三方资源。
- URL 使用既有 C runtime `publicOrigin` 加 `/s/posts/{postId}`；不读取请求 Host／Forwarded。该配置 origin 必须长期稳定；本轮不修改现有运行配置或部署。旧 HTTP 嵌入者不设置 `CommunityOptions.PublicOrigin` 时两个新 API 返回503，既有接口继续工作。
- 获取／解析均复用 `ReadPosts(PostDetail)`、最终 C Gate、会话代次、当前可见性和严格 DTO；无新增表、迁移、密钥、授权能力或写入额度。分享／解析不创建转帖、阅读计数或帖内发言绑定。
- 完整机器契约见 `packages/openapi/post-share-api.yaml`；本记录的“前端接线”章节作为使用入口。

## 验收标准

- 不同登录账号对同一公开帖子取得同一固定 URL；分享文字仅含产品名称及 URL。
- 未登录、无效／撤销会话无法获取或解析；C Gate 冻结时不能返回原帖或可用分享结果，错误不续期。
- 解析只接受当前配置 origin 的规范 HTTPS 链接，拒绝外站、用户信息、跳转参数、片段、非规范 ID 和额外／重复输入；不发起外部 HTTP 请求。
- 原帖编辑后旧链接返回最新公开内容；不存在、删除或下架时获取与解析返回 `POST_NOT_FOUND`，不返回旧文。
- 公开链接的 GET／HEAD 无需登录，存在／不存在／删除／下架目标均返回同一通用引导结构；无内容、作者、图片或帖子可用性信息，无会话续期。
- 分享与解析不创建转帖、帖内绑定或阅读计数；既有帖子读取和互动保持回归通过。

## 前端接线

1. 已登录时调用分享 GET，把 `shareText` 交给系统分享面板；不拼入标题、正文、作者或图片。
2. 接收 `https://<固定 C origin>/s/posts/{postId}` 或落地页按钮 `speechful://posts/{postId}`，仅保存目标意图。后续 App 配置 HTTPS 关联域及自定义 scheme，不把本次后端交付当作已完成唤起。
3. 未登录先登录／注册；按既有基础身份规则完成必要设置后恢复原入口，保留原目标，避免先跳其他帖子或丢失意图。
4. 用本次 URL 解析接口或既有详情接口重新授权读取，再进入原帖。错误显示不可用／重试状态；不要从分享材料恢复内容或绕过 Gate。链接解析不自动记阅读次数，实际详情阅读沿用既有 views 行为。

## 当前进度与证据

| 项目 | 被测版本／环境 | 结果与证据 |
| --- | --- | --- |
| 基线核对 | Windows PowerShell；`48bcbc7cf90d163597d1f8a5f5944d9a08cb3ebf` | PASS。已核对源码根目录、状态、分支、远端、Worktree；fetch 当前主线并创建独立任务分支。新 Worktree 初始无改动。 |
| 事实调查 | 同一基线 | 已阅读相关路由、原帖读取、Feed／详情分享占位、平台配置、转帖契约和历史登录／分享要求。 |
| 实现 | 基线 `48bcbc7` 加本任务差异；核心为 `services/api/internal/authprivacyhttp/post_share_endpoints.go`、帖子路由、C runtime origin 接线及 `packages/openapi/post-share-api.yaml` | 已完成固定链接、保护解析、无内容公开引导；C runtime 自动使用已有 `publicOrigin`，未修改实际运行环境。Feed backend CI 增加格式检查，既有隔离 SQL runner 默认纳入两个新真实 HTTPS 用例。 |
| 首轮检查及修正 | 初始快照 SHA-256 `c26e2592da1440b69f66187b6e5f85324024c4bd07f1c729a41aab1812c0ffb9`；WSL Go 1.22.2 | FAIL，聚焦编译发现一项未使用 import，删除后复跑通过。Windows OpenAPI 首次使用默认 cp1252 读取既有 UTF-8 文件失败，改为 Python `-X utf8` 后完整通过；不是 YAML 校验通过的替代。 |
| 聚焦 HTTP 边界 | 中间快照 `251e30d702ecbee738c9633fbbd177043934a5b31b7b9e4eb8fe77ae1732044e`；WSL2／Go 1.22.2；`go test -count=1 ./internal/authprivacyhttp -run '^TestPostShare' -v` | PASS，5 项。覆盖固定链接、伪造域名、受保护解析、预检、非法／重复输入、会话错误、坏 DTO、失效授权元数据、无内容 GET／HEAD 和 origin 配置拒绝。后续复核补上解析响应的 `Post-Edited-At` CORS 暴露回归，由最终全包测试覆盖。[原结果](E:/Hnuhole-env/post-sharing-validation-20261106/focused-before-cors.log)。 |
| 最终 Go 验证 | 最终源码快照 SHA-256 `df88a030e61aebad4e6ab1c9857ff86f7c5901e23fe85c4b29e6d57d50a43936`；WSL2 Linux 源码 `/home/hnuhole/post-share-validation.nBeJrK`；Go 1.22.2；`gofmt`、`go test ./...`、`go build ./...`、`go vet ./...` | PASS。[host.log](E:/Hnuhole-env/post-sharing-validation-20261106/host.log)。全包宿主测试中的无 DSN 跳过不计为 SQL 验收，真实 SQL 见下一行。 |
| 最终真实 PostgreSQL／HTTPS | 同一最终快照；WSL2 非 root、PostgreSQL 16.15、Goose 3.22.1；Linux 源码 `/home/hnuhole/post-share-validation.lBHWc2`；`FEED_TEST_PATTERN='^(TestRealHTTPSPostShare\|TestRealHTTPSPostEditPostgres\|TestRealHTTPSFeedViewsPreferencesAndCompatibilityPostgres\|TestPostGate\|TestPostAtomic)' sh authlab/run-feed-isolated.sh`，启用 `-race -count=1 -p 1` | PASS，6 项真实用例。覆盖真实会话与原帖发表、跨账号固定链接、未登录／无效／撤销会话、旧链接读取实际作者编辑后的内容、下架／删除后404、不创建转帖／阅读计数／发言绑定、C Gate 冻结及既有帖子／Feed 回归。fixture 创建私有 Unix socket PostgreSQL 集群并在退出时停止清理；未连接现有业务库。[sql.log](E:/Hnuhole-env/post-sharing-validation-20261106/sql.log)。 |
| 完整契约校验 | 最终 `packages/openapi/post-share-api.yaml`；Windows 验证环境 PyYAML 6.0.1／openapi-spec-validator 0.9.0；`python -X utf8 packages/openapi/check-specs.py`、`python -X utf8 tools/check-community-text-contract.py` | PASS，13 份 OpenAPI 完整校验和既有23项受保护契约兼容检查。[完整规范](E:/Hnuhole-env/post-sharing-validation-20261106/openapi.log)、[旧契约](E:/Hnuhole-env/post-sharing-validation-20261106/legacy-contract.log)。 |
| 最终证据对应 | `48bcbc7` 加本任务10项产品／测试／CI／契约路径差异 | PASS，已逐字节核对最终工作区这些文件与上述最终被测源码快照一致；此后仅更新任务证据记录。runner 及完整日志位于 `E:/Hnuhole-env/post-sharing-validation-20261106`。 |
| 协作与脚本检查 | 最终暂存差异；`git diff --cached --check`、`python -X utf8 tools/check-collaboration.py --staged`、`sh -n services/api/authlab/run-feed-isolated.sh` | PASS。仅证明差异空白、提交文件政策和 shell 语法，不代替产品验证。 |
| 远端及设备边界 | 本次范围 | NOT_RUN：远端产品 CI、独立成员审查、Android／iOS 外部唤起及完整登录后回帖链路。本轮已配置适用产品 CI 但未推送／创建 PR，不将本地结果记作远端 CI、设备或生产通过。 |

## 阻碍与下一步

本轮后端实现和本地验证已完成，无实现阻碍。已按授权推送并创建 PR #108；产品提交为 `c85da60`，此后仅任务文档变化，本地产品证据继续适用。提交本条记录时远端 CI 正在运行，必须核对最终 PR head 的全部适用产品 CI 成功后才 squash 合并；最终 CI、合并时间及 SHA 以本记录链接的 PR 实时证据为准，不将送审快照当作当前状态。部署未授权。App 后续按本记录接入系统分享、HTTPS／scheme 唤起和认证后恢复原入口，再单独完成设备链路验收。
