# POST-SEARCH-01 — 按分类搜索帖子

- 模式为指挥，当前 Session 负责需求、契约、集成与联合验收。用户在确认纳入完整账号历史后允许使用 orchestrator 并行开发。
- 集成分支为 `codex/feat/post-search`，Worktree 为 `E:/Hnuhole-env/source/SpeechFUL-post-search`，已核实的 GitHub main 基线为 `663adbca992f03cd15de5bd4f4455f8db4adbabf`。主源码根为 `E:/Hnuhole-env/source/HnuHole`，配置远端旧地址 `zewbby/HnuHole.git`，当前项目地址为 `zewbby/SpeechFUL.git`。
- 本轮规则为基线中的 AGENTS.md、CONTRIBUTING.md、orchestrator Skill 及派单与交付协议。
- 授权覆盖本地调查、独立工作区、开发、验证及必要提交。Push、PR、合并、部署需另行授权。
- 更新日期为 2026-11-04。实现进行中，验证 NOT_RUN，未合并，未发布。

## 需求确认

- 主线现状。推荐与具体通道使用同一首页组件，范围分别是全部与单通道；放大镜仅弹提示。首页筛选是账号级通道屏蔽。现有列表使用受保护服务端接口、发布序号上界和游标。
- 用户澄清通道在搜索中是帖子分类。推荐与分类页均点放大镜直达同一搜索页并聚焦输入。推荐默认全部分类，分类页预选当前分类，可在搜索页切换，返回保持原信息流范围和位置。依据为本会话对修订后默认范围的确认。
- 依原任务和 [SEARCH-01–03](../design/modules/navigation.md) 匹配标题和正文，结果展示帖子，默认相关度并可切最新，同相关度较新优先。全部分类沿用按分类分组和组内排序规则。登录、可见性和账号通道屏蔽继续生效。标签和热榜延期。
- 用户明确将 [SEARCH-04–05](../design/modules/navigation.md) 完整历史纳入。全部分类与各分类各自保存，账号下身份共享，跨设备读取服务端权威历史，正式注销清除，重新注册为空。仅记录已提交词、复搜去重并置顶、每范围最多 20 条、默认两行可展开、复用、单条删除和确认清空。新进入或清空关键词时获取当前范围历史，服务不可用提供重试。
- 分类无结果的独立快捷按钮存在前后两份相反回答，等待以最新单题为准。范围控件始终可切全部。该未决仅影响空状态 UI。
- 入口参考 [X 帮助中心](https://help.x.com/en/using-x/x-search) 和 [欧委会留存的 Instagram Explore 截图](https://ec.europa.eu/competition/antitrust/cases1/202513/AT_40684_10582539_13405_4.pdf#page=59)。

## 接口与依赖

- `POST /api/v1/post-search` 使用 JSON 请求 `{keyword, channelId?, sort?, cursor?, limit?, recordHistory?}`，返回现有 `FeedPage`（公开卡片 `items` 和可空 `nextCursor`），关键词放在请求体。省略 `channelId` 表示全部。默认 `sort=relevance`，另一选项为 `latest`；默认 `limit=20`，上限 50。关键词去掉首尾空白，要求 1–100 Unicode 字符且无控制字符。标题完全匹配、标题包含、仅正文包含依次降权，文字匹配按不区分大小写的字面子串；再按首次发布时间及唯一发布序号降序。全部分类按每组的首条命中顺序排组，各分类连续，客户端跨页继续同组。分页使用首次请求的发布上界和固定组序，游标绑定账号、范围、关键词、排序、页大小和屏蔽版本。续页重新判断内容可见性。被屏蔽的分类不会命中。
- `recordHistory` 默认为 false。仅明确提交关键词或点选历史词的第一页请求设为 true。排序、范围切换、刷新结果、翻页不记历史；带游标的请求拒绝 true。查询成功或无命中都在同一 C Gate 事务记录已提交词，整笔失败无部分写入。
- `GET /api/v1/me/post-search-history` 接受可选 `channelId`。同路径 `POST` 使用 `{action, channelId?, keyword?}`，`action` 为 `remove` 或 `clear`，只有 remove 需要 keyword。两种方法均返回 `{items: string[]}`（非空 JSON 数组类型，允许零项，最近优先）。以账号和范围隔离，同词大小写不区分，显示最近提交形式。设备通过重新进入、切范围或重试读取最新状态。服务端串行化同账号写操作，Flutter 仅保留当前路由的内存状态。
- 新接口复用帖子 HTTP 边界与 `withPostSession`，包括最终授权、会话 fence、持久化续期、标准错误和 no-store。新数据由 PostgreSQL 迁移安装，沿现有最小权限和正式注销生命周期清理。
- Go 公共契约见 `services/api/internal/posts/search.go`。查询执行组实现 `Community.SearchPosts(ctx, bearer, query posts.SearchQuery)`。历史执行组实现 `Community.ReadPostSearchHistory(ctx, bearer, channelID string)`、`Community.ChangePostSearchHistory(ctx, bearer, input posts.SearchHistoryChange)` 和事务辅助 `recordPostSearchHistory(ctx, tx, account, channelID, keyword, at)`。入口 Session 接 HTTP/OpenAPI、在集成时调用事务辅助，并负责验证。
- Flutter 使用独立搜索路由及查询状态，复用现有帖子详情和会话 fence。结果列表是卡片标题等既有公开字段。路由返回保留关键词、分类、排序、游标和滚动位置；重新点击放大镜开始新搜索。错误可在原范围和排序重试，过期游标重新取第一页。

## 验收标准

- 两种首页范围进入、预选和直接输入；切换分类与排序后结果和选中态一致；原信息流范围与位置恢复。
- 标题及正文命中，跨分类组序和组内顺序，真实空结果，重复词和两个排序，同时间稳定分页，分页期间的新帖、删除或下架不造成泄露或重复；登录与屏蔽隔离、错误重试。
- 详情打开与返回保留结果位置。历史按账号、分类和全部范围隔离，跨设备与身份共享，重复词置顶、20 项上限、删除／确认清空和正式注销清除。

## 当前进度与证据

| 项目 | 被测版本／环境 | 结果与证据 |
| --- | --- | --- |
| 基线 | GitHub SpeechFUL main 与任务分支同为 `663adbc` | PASS；主仓库 detached HEAD `af272dc`，状态干净，其他 Worktree 和已有改动保留。 |
| 工具准备 | Windows Flutter 3.47.5 / Dart 3.13.4；WSL2 Go 1.22.2 与 PostgreSQL 16 | 已定位。完整产品验证待集成。 |
| 产品验证 | 待集成提交 | NOT_RUN。 |

## 阻碍与下一步

冻结接口后并行实现搜索 SQL、历史持久化和 Flutter；空状态快捷按钮在最新确认前单独待定。
