# POST-SEARCH-01 — 按分类搜索帖子

- 模式为指挥，当前 Session 负责需求、契约、集成与联合验收。用户在确认纳入完整账号历史后允许使用 orchestrator 并行开发。
- 集成分支为 `codex/feat/post-search`，Worktree 为 `E:/Hnuhole-env/source/SpeechFUL-post-search`，已核实的 GitHub main 基线为 `663adbca992f03cd15de5bd4f4455f8db4adbabf`。主源码根为 `E:/Hnuhole-env/source/HnuHole`，配置远端旧地址 `zewbby/HnuHole.git`，当前项目地址为 `zewbby/SpeechFUL.git`。
- 本轮规则为基线中的 AGENTS.md、CONTRIBUTING.md、orchestrator Skill 及派单与交付协议。
- 授权覆盖本地调查、独立工作区、开发、验证及必要提交。Push、PR、合并、部署需另行授权。
- 更新日期为 2026-11-04。实现已完成。本地验证 PASS。合并未执行。发布未执行。

## 需求确认

- 主线现状。推荐与具体通道使用同一首页组件，范围分别是全部与单通道。放大镜仅弹提示。首页筛选是账号级通道屏蔽。现有列表使用受保护服务端接口、发布序号上界和游标。
- 用户澄清通道在搜索中是帖子分类。推荐与分类页均点放大镜直达同一搜索页并聚焦输入。推荐默认全部分类，分类页预选当前分类，可在搜索页切换，返回保持原信息流范围和位置。依据为本会话对修订后默认范围的确认。
- 依原任务和 [SEARCH-01–03](../design/modules/navigation.md) 匹配标题和正文，结果展示帖子，默认相关度并可切最新，同相关度较新优先。全部分类沿用按分类分组和组内排序规则。登录、可见性和账号通道屏蔽继续生效。标签和热榜延期。
- 用户明确将 [SEARCH-04–05](../design/modules/navigation.md) 完整历史纳入。全部分类与各分类各自保存，账号下身份共享，跨设备读取服务端权威历史，正式注销清除，重新注册为空。仅记录已提交词、复搜去重并置顶、每范围最多 20 条、默认两行可展开、复用、单条删除和确认清空。新进入或清空关键词时获取当前范围历史，服务不可用提供重试。
- 分类无结果时显示“暂无相关帖子”和“搜索全部分类”。点击按钮保留关键词和排序，范围切到全部分类并从第一页查询。依据为用户在收到两轮相反答复的提示后，明确选择增加快捷按钮。
- 入口参考 [X 帮助中心](https://help.x.com/en/using-x/x-search) 和 [欧委会留存的 Instagram Explore 截图](https://ec.europa.eu/competition/antitrust/cases1/202513/AT_40684_10582539_13405_4.pdf#page=59)。

## 接口与依赖

- `POST /api/v1/post-search` 使用 JSON 请求 `{keyword, channelId?, sort?, cursor?, limit?, recordHistory?}`，返回现有 `FeedPage`（公开卡片 `items` 和可空 `nextCursor`），关键词放在请求体。省略 `channelId` 表示全部。默认 `sort=relevance`，另一选项为 `latest`。默认 `limit=20`，上限 50。关键词去掉首尾空白，要求 1–100 Unicode 字符且无控制字符。标题完全匹配、标题包含、仅正文包含依次降权，文字匹配按不区分大小写的字面子串。再按首次发布时间及唯一发布序号降序。全部分类按每组的首条命中顺序排组，各分类连续，客户端跨页继续同组。分页使用首次请求的发布上界和固定组序，游标绑定账号、范围、关键词、排序、页大小和屏蔽版本。续页重新判断内容可见性。被屏蔽的分类不会命中。
- `recordHistory` 默认为 false。仅明确提交关键词或点选历史词的第一页请求设为 true。排序、范围切换、刷新结果、翻页不记历史。带游标的请求拒绝 true。查询成功或无命中都在同一 C Gate 事务记录已提交词，整笔失败无部分写入。
- `GET /api/v1/me/post-search-history` 接受可选 `channelId`。同路径 `POST` 使用 `{action, channelId?, keyword?}`，`action` 为 `remove` 或 `clear`，只有 remove 需要 keyword。两种方法均返回 `{items: string[]}`（JSON 数组，允许零项，最近优先）。以账号和范围隔离，同词大小写不区分，显示最近提交形式。设备通过重新进入、切范围或重试读取最新状态。服务端串行化同账号写操作，Flutter 仅保留当前路由的内存状态。清空输入时先等同范围已发出的写入结束，再读服务端历史。
- 新接口复用帖子 HTTP 边界与 `withPostSession`，包括最终授权、会话 fence、持久化续期、标准错误和 no-store。新数据由 PostgreSQL 迁移安装，沿现有最小权限和正式注销生命周期清理。
- Go 公共契约见 `services/api/internal/posts/search.go`。查询执行组实现 `Community.SearchPosts(ctx, bearer, query posts.SearchQuery)`。历史执行组实现 `Community.ReadPostSearchHistory(ctx, bearer, channelID string)`、`Community.ChangePostSearchHistory(ctx, bearer, input posts.SearchHistoryChange)` 和事务辅助 `recordPostSearchHistory(ctx, tx, account, channelID, keyword, at)`。入口 Session 接 HTTP/OpenAPI、在集成时调用事务辅助，并负责验证。
- Flutter 使用独立搜索路由及查询状态，复用现有帖子详情和会话 fence。结果列表是卡片标题等既有公开字段。路由返回保留关键词、分类、排序、游标和滚动位置。重新点击放大镜开始新搜索。错误可在原范围和排序重试，过期游标重新取第一页。

## 验收标准

- 两种首页范围进入、预选和直接输入。切换分类与排序后结果和选中态一致。原信息流范围与位置恢复。
- 标题及正文命中，跨分类组序和组内顺序，真实空结果，重复词和两个排序，同时间稳定分页，分页期间的新帖、删除或下架不造成泄露或重复。登录与屏蔽隔离、错误重试。
- 详情打开与返回保留结果位置。历史按账号、分类和全部范围隔离，跨设备与身份共享，重复词置顶、20 项上限、删除／确认清空和正式注销清除。

## 当前进度与证据

被测产品提交为 `ec1699aff2bee0abc7700faf2d1f6e7bd447554f`。Go 与 SQL 在 `7e2cd7080e398c1d1583720b840fe165904a5f65` 测试，两版之间仅改 Flutter 搜索页及其 widget 测试，Go、迁移、OpenAPI 与真实 HTTPS 测试源码一致。验证脚本和原始日志位于本机 `E:/Hnuhole-env/post-search-validation-20261104`。

| 项目 | 被测版本／环境 | 结果与证据 |
| --- | --- | --- |
| 基线 | GitHub SpeechFUL main 与建分支基线同为 `663adbc` | PASS。主仓库 `E:/Hnuhole-env/source/HnuHole` 的 detached HEAD `af272dc` 及既有 Worktree 保留。 |
| 集成 | 查询 `73992f6`、历史 `b252338`、Flutter `873f686`、历史竞态修复 `c391d9a` | 本地集成完成。生产数据库上线时需应用 `0029_post_search_history.sql`。 |
| Go | `7e2cd70`，WSL2 非 root，Go 1.22.2 | PASS。 `run-go.sh <SHA>` 执行适用文件 `gofmt -l`、`go test -mod=readonly ./...`、`go build -mod=readonly ./...` 和 `go vet -mod=readonly ./...`。日志 `go-7e2cd70.log`。 |
| 真实 PostgreSQL／Go HTTPS | `7e2cd70`，独立私有 socket，PostgreSQL 16.15 ICU／Goose 3.22.1 | PASS。 `run-go.sh <SHA>` 调用 `sh authlab/run-feed-isolated.sh`，8 项选定顶层用例及迁移子项通过。覆盖 0028→0029、授权及最小权限、搜索排序和稳定游标、删除／下架／屏蔽、正式注销、换设备登录和 HTTPS 事务。一次性集群由 runner 停止并清理。日志 `postgres-7e2cd70.log`。 |
| Dart → HTTPS → PostgreSQL | `ec1699a`，WSL2 Dart 3.13.4，Go 1.22.2 | PASS。 `run-flutter.sh <SHA>` 用 `dart compile exe` 编译应用网络层探针，运行 `TestRealHTTPSPostSearchDartPostgres` 和既有 `TestRealHTTPSFeedDartPostgres`。覆盖两种排序、分类及全部范围、详情读取、空结果、游标及历史隔离和删除。日志 `dart-postgres-ec1699a.log`。 |
| Flutter 界面联合验收 | `ec1699a`，WSL2 Flutter 3.47.5，真实 C HTTPS 与一次性 PostgreSQL | PASS。 `run-widget.sh <SHA>` 将测试装载到独立 Linux 源码副本，使用 `LiveTestWidgetsFlutterBinding` 和真实会话／目录／帖子 API。走通推荐搜索、切排序、打开详情并返回、分类内无命中后扩大、回到原分类以及复读并清空历史。日志 `live-widget.log`，验收脚本保存在同一证据目录。 |
| Flutter | `ec1699a`，WSL2 Flutter 3.47.5，原锁文件 | PASS。 `flutter pub get --offline --enforce-lockfile`、`flutter analyze --no-pub` 和 10 个相关测试文件共 203 项。测试文件及命令见 `run-flutter.sh`。覆盖原信息流和详情返回位置、无结果扩大、错误重试、会话和历史晚到响应。首次运行缺 `libsqlite3.so` 库名，验证目录链接系统 `libsqlite3.so.0` 后通过。日志 `flutter-ec1699a.log`。此日志末尾的 WSL bundle 缺 Android SDK，Windows 同版本构建通过。 |
| Android 构建 | `ec1699a`，Windows Flutter 3.47.5，JDK 17／SDK 36 | PASS。 `flutter build apk --debug --target-platform android-arm64 --no-pub`、`apksigner verify --verbose` 与 `flutter build bundle --debug --target-platform android-arm64 --no-pub`。Kotlin daemon 权限失败后 Gradle 回退编译。APK SHA-256 `371c4b4032e78a43dd8519a2f46800afb71c1f9f148bdb6c8dc6d38e24f93bec`。日志 `android-ec1699a.log`、`bundle-ec1699a.log`。 |
| OpenAPI 与协作 | `ec1699a`，仓库锁定的 Python 验证环境 | PASS。 `python packages/openapi/check-specs.py`、`python tools/check-community-text-contract.py`、`python -m unittest discover -s tools/tests -p test_collaboration.py -v` 和 `git diff --check`。 |
| 独立审查 | GPT-6 Astra `xhigh` 核对 `73992f6`／`b252338`，GPT-6.1 Terra `high` 核对 `7e2cd70` | 后端静态复核无阻断。Flutter 发现提交后立即清空会读取旧历史，修复于 `ec1699a`，新增两个回归。审查为本地只读复核。 |
| 产品 CI／设备 | Feed backend、Feed UI | NOT_RUN。CI 定义已加入适用回归。实体设备、iOS 构建和部署验证尚未执行。 |

## 性能与体验复修

- 2026-11-04 用户要求修复 Astra High 审查的 P1 与 P2，在一次性 PostgreSQL 对比搜索和普通读取的并发表现，补慢网重复提交回归，并在 Android 实体设备操作搜索、翻页、详情返回和历史。最终由 Astra High 复审。本轮只本地交付。
- 集成从 `6701e842b6d7c6a78b26a4b5c2c9385a282d19d7` 续作，原 `origin/main` 为 `663adbca992f03cd15de5bd4f4455f8db4adbabf`。此前界面联合验证为宿主环境，真机尚未验收。
- P1 将内容规模相关的候选匹配与排名移出全局授权锁。交付结果、读取私有历史及写入搜索历史继续以 C Gate 最终事务为唯一授权点。最终重新核对会话和 Gate 代次、屏蔽版本、候选帖子可见性。保留字面子串、两种排序、分类分组及游标约束。需复验预检后撤权／下架与多账号并发。
- P2 合并同一关键词、范围、排序和游标的在途重复提交。现有请求晚到隔离、显式重试、历史写入和返回语义保持。回归模拟请求在慢网期间未完成时重复提交。
- 本轮无产品取舍待确认。选择合成账号、一次性服务与独立测试包做真机操作。验证状态在本节追加。

产品复验提交为 `2976098c9a02928730d7a321eac12e3833b8b91d`。Go 文件与 `721e57dd0f95598cdd820e95faf9f26324f877ca` 一致。Flutter 与依赖文件同 `fb7d6532df181ec3f6d6182dfa4306b0fbbe81b2`。本地证据目录为 `E:/Hnuhole-env/post-search-followup-20261104`。工作期间共享 `origin/main` 更新到 `55663f0`，本次复验沿用任务基线。

| 项目 | 被测版本／环境 | 结果与证据 |
| --- | --- | --- |
| P1 实现 | Sol `xhigh`，`721e57d`，集成于 `2976098` | 锁外扫描只返回候选键与排序元数据。最终 C Gate 重新校验同一会话／代次、屏蔽版本和有界的候选可见性，并原子提交历史及续期。最多复核 50 张卡、1 条续页候选和 7 个分组首条。候选失效可锁外重查一次。保留现有字面匹配与游标规则，未新增索引或迁移。 |
| P1 Go 与真实 SQL／HTTPS | Go 1.22.2，WSL2 非 root，PostgreSQL 16.15／Goose 3.22.1 | PASS。 `gofmt`、`go test ./...`、`go build ./...`、`go vet ./...` 及 10 个聚焦真实数据库用例。覆盖搜索被表锁阻塞时另一账号通过 C Gate、撤权／换代、下架、删除、屏蔽 ABA 及分页补齐。日志 `E:/Hnuhole-env/post-search-perf-verification-20261104/host-721e57d.log` 和 `final-721e57d.log` 的 SQL／HTTPS 部分。首次 host 运行继承迁移变量导致缺 fixture，隔离变量后全过。 |
| P2 Flutter | Terra `high`，执行提交 `1df2691`、`f526c70`，集成于 `fb7d653` | PASS。Flutter 3.47.5，原锁离线解析。 `flutter analyze --no-pub lib/src/posts/post_search_screen.dart test/post_search_test.dart` 与 `flutter test --no-pub --reporter expanded test/post_search_test.dart` 共 9 项。慢网按钮与键盘连点只发一笔请求并展示首个响应。自动刷新在途时，显式提交仍独立记录历史。 |
| 搜索与普通读取并发 | `6701e84` 对 `2976098`，一次性 PostgreSQL 16.15，真实 HTTPS，3 万条合成帖子／7 分类，4 搜索账号并发，三轮每轮 40 次普通详情读取 | PASS。运行 `bash run-followup.sh <完整 SHA> load`。普通详情并发 p95 从 2.97–3.57 秒降至 675–859 毫秒。搜索 p95 从 2.96–3.56 秒降至 1.38–1.71 秒，两版均零请求错误。扫描计算仍占用数据库资源。证据 `load-6701e84.log`、`load-2976098.log`，脚本和合成 seed 同目录。 |
| Android 实体设备 | realme RMX3366／Android 14／ARM64，APK 客户端 `fb7d653`，API `2976098` | PASS。 `build-device.ps1 -Revision <完整 SHA>` 构建并验签独立 `org.hnuhole.hnuhole_mobile.postsearchverify` 包。APK SHA-256 `1a6146aed3ec1d070d8ce366e0dd2ab76d00b00135fb62fc39e83d2e8b995763`。 `bash run-followup.sh <完整 SHA> android` 使用测试输入、原生安全存储、USB 转发、真实 HTTPS 和一次性 PostgreSQL。实测搜索、加载第二页、打开第二页帖子再返回并保持关键词与位置、复用并清空历史。日志 `android-2976098.log`。 |
| Astra High 独立复审 | `gpt-6-astra`／`high`，审查 `6701e84 → 2976098` | PASS。确认原 P1／P2 已修复，无新增阻断。核对最终授权、撤权及屏蔽 ABA、候选可见性和分页、慢网重复提交与历史写入，并核对 Go、负载和真机证据。字面扫描仍与普通读共用数据库连接池。更大规模与连接池饱和未实测。 |

复修状态为实现已完成、本地及 Android 真机验证 PASS。真机临时转发和验收包已清理，隔离库由 runner 关闭。产品 CI 和 iOS 本轮 NOT_RUN。未推送、未合并、未发布。

## PR 集成验证

- 用户授权推送任务分支、创建 PR，并在相关产品 CI 通过后合并。本轮选择通过 PR Squash Merge 交付。发布未执行。[PR 与实时检查](https://github.com/zewbby/SpeechFUL/pull/101/checks)
- 将当时最新的 `origin/main` `55663f020ff7cacad87c684544c42a3b7f8a341b` 合入任务分支 `9cbb29dfc330a327e9209de6e9245d4724f024e3`，保留双方 Feed UI 回归，为搜索入口、筛选、结果和历史接入现有四语言文案。聚焦回归发现主线注销预计完成时间的日语译文与断言不符，统一为同一表达。
- PASS。Windows Flutter 3.47.5，`flutter pub get --offline --enforce-lockfile`、`flutter analyze --no-pub`、`flutter test --no-pub --reporter expanded test/post_search_test.dart test/feed_ui_test.dart test/feed_scroll_refresh_test.dart test/community_localization_test.dart test/app_localizations_test.dart test/login_home_navigation_test.dart test/profile_settings_flow_test.dart`，共 71 项。覆盖 Feed、搜索、分页和返回、历史、设置及语言切换。日志为复修证据目录中的 `flutter-main-integration.log`。被测代码为本节所述合并内容。
- PASS。Windows 仓库验证环境运行 `python packages/openapi/check-specs.py`、`python tools/check-community-text-contract.py`、`python -m unittest discover -s tools/tests -p test_collaboration.py` 和 `git diff --check origin/main`。Go、SQL、权限脚本与 OpenAPI 和已通过实体设备／真实数据库验证的 `2976098` 一致。四语言整合版以本地 Flutter 回归及 PR CI 验证。

- PR #101 的首轮 CI 在 `22636c8` 发现契约回归仍断言 16 个受保护操作。更新为 19 个，覆盖搜索和历史新增的 3 个操作。Windows Python 验证环境运行 `python -m unittest discover -s tools/tests -p test_community_text_contract.py -v`，9 项 PASS。
