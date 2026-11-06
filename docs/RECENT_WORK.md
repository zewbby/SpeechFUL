# 近期工作

近期工作集中在本文维护，README 仅保留入口。各项实现、验证、合并与发布状态以链接中的任务记录及 PR 为准；新增工作放在列表顶部，详细进度继续写入对应任务记录。

## 工作索引

原有条目迁自 README 的 Related Work；相关任务扩展时更新对应入口，其他条目保留迁移时的描述与顺序。

- [帖子自定义标签](tasks/CUSTOM-TAGS-01.md)：本地分支已接入添加、复用、编辑、独立标签结果和关键词搜索；每帖最多三个、每个最多十字，验证及发布状态见任务记录。

- [帖子分享与原帖链接](tasks/POST-SHARE-01.md)：后端已合并；App 分支接入系统分享、冷／热启动及认证后恢复原帖，验证与交付状态见任务记录。

- [开发环境旧启动入口修复](branches/fix-development-runtime-resume.md)：三个原入口已统一版本绑定恢复器，C28/V7与三Redis冷启、重复执行验证通过，PR状态见任务。

- [隔夜关机会话恢复](branches/docs-session-overnight-acceptance.md)：单台 vivo 2702 隔夜恢复限定验证通过；C28/V7 与 Redis 恢复说明已整理，文档合并状态见任务PR。

- [欢迎图案与启动衔接](branches/codex-feat-welcome-mascot-logo.md)：[PR #88](https://github.com/zewbby/SpeechFUL/pull/88) 实现浅黑深白轮廓、黑底白标桌面图标及欢迎控件入场；实现与验证见任务记录，合并状态见 PR。

- [PR #84](https://github.com/zewbby/HnuHole/pull/84)：主线默认Redis新建与双读，标准启动配置接通，缺快照配置明确报错。
- [PR #83](https://github.com/zewbby/HnuHole/pull/83)：同步Redis快照合并和开发启用回执，保留历史验收边界。
- [PR #80](https://github.com/zewbby/HnuHole/pull/80)：评论Redis分页快照、局部恢复与Publish优化已合入main；同机开发已启用，生产未发布。
- [PR #82](https://github.com/zewbby/HnuHole/pull/82)：补充通知主线构建、同机开发后端与vivo冒烟交付回执，完整体验待用户试用。
- [PR #81](https://github.com/zewbby/HnuHole/pull/81)：四分类通知、跨模块身份同步与统一发帖导航已合入主线，主线包和同机开发服务已更新。
