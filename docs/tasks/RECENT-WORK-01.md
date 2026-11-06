# RECENT-WORK-01 — 将近期工作移出 README

- 模式：常规
- 负责人／状态维护人：当前 Session
- 分支／Worktree／PR：`codex/docs/recent-work`；`E:/Hnuhole-env/source/SpeechFUL-recent-work`；[PR #110](https://github.com/zewbby/SpeechFUL/pull/110)；基线 `be6d07ab2c35c859d7176569e1a99b5e1ec74de5`（origin/main）
- 授权依据与边界：用户要求将近期工作移出 README，并于后续消息明确授权“提交并推送，创建 PR，检查通过后合并”；授权覆盖本任务提交、推送、PR 和通过检查后的合并，不涉及部署。
- 需求确认：删除 README 的 Related Work 进展列表，迁移到独立 Markdown 文档；README 保留稳定入口；无未决取舍。
- 更新日期：2026-11-06
- 状态：实现 已完成；验证 PASS；合并 未合并；发布 未发布

## 目标与范围

将原有 10 条工作条目迁入 `docs/RECENT_WORK.md`，修正相对链接，保留原描述与顺序。README 仅保留文档入口；CONTRIBUTING 明确后续工作索引维护位置。近期工作文档作为索引，各任务记录继续作为权威状态来源。

## 验收标准

- README 不再含 Related Work 标题或进展条目，并可进入近期工作文档。
- 原有条目完整迁移，文档内本地链接可解析。
- 协作规则明确近期工作的维护位置，不改变任何产品验收结论。

## 当前进度与证据

| 项目 | 被测版本／环境 | 结果与证据 |
| --- | --- | --- |
| 实现 | 基线 SHA 加 README、CONTRIBUTING、近期工作文档及本任务记录差异 | 已完成内容迁移和维护规则更新 |
| 验证 | Windows / Python；上述基线加本任务文档差异 | PASS：Python 对比原列表确认 10 条内容与顺序保留，README 已无 Related Work，README 与近期工作文档的本地链接均存在；`git diff --check`、`python tools/check-collaboration.py --staged` 通过；纯文档改动，无需产品测试 |

## 阻碍与下一步

已提交并推送，PR #110 已创建；在适用检查通过后按用户授权合并。实时 CI 与最终合并状态见 PR，本文保留送审时状态，不提前宣告合并。
