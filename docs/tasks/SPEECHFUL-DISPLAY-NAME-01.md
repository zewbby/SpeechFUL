# SPEECHFUL-DISPLAY-NAME-01 — 应用显示名称

- 模式：常规；负责人：当前 Session
- 分支／Worktree：`codex/chore/speechful-display-name`，`E:/Hnuhole-env/source/SpeechFUL-display-name`；基线 `06bee794257fd25b9e3221b01ffcd181752c7a79`（origin/main）
- 授权与需求确认：用户要求名称改为 SpeechFUL，并明确确认保留安装标识与现有数据兼容，只改可见名称；随后要求合并发布。
- 更新日期：2026-11-04
- 状态：实现已完成；验证待设备验收；合并未合并；发布未发布

## 目标与验收

Android 和 iOS 应用名称、应用标题、通知及刷新控件的无障碍名称使用 SpeechFUL；保留安装标识和存储、认证协议标识。覆盖升级及设备显示仍需设备验收。

## 当前进度与证据

- 实现：以上基线加本任务未提交差异。
- PASS：Windows 环境运行 `flutter analyze`、`flutter test test/app_navigation_test.dart` 和 `flutter build apk --debug`；`aapt dump badging` 显示名称 SpeechFUL，包标识 `org.hnuhole.hnuhole_mobile`。离线依赖解析使用缓存中版本（部分与基线锁文件不同）；生成的锁文件变化已恢复，验证不代表基线锁定依赖的完整产品 CI。
- PASS：解析 Android manifest 和 iOS plist，核对显示名称；Android 和 iOS 标识配置文件与基线一致；`git diff --check`。
- NOT_RUN：iOS 构建、设备上的名称显示和覆盖升级／原有数据验收、产品 CI。
