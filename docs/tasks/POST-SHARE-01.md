# POST-SHARE-01 — 帖子分享与链接打开原帖

- 模式：常规；负责人／状态维护人：当前 Session。
- 分支／Worktree／PR：后端 [PR #108](https://github.com/zewbby/SpeechFUL/pull/108) 已合并为 `4a3115dad4c0ecd257afc85f3abaea3a8ea3de69`。App 使用 `codex/feat/post-sharing-mobile`、`E:/Hnuhole-env/source/SpeechFUL-post-sharing`，初始基线 `4a3115d`，整合主线标签 `be6d07a`，产品／测试最终提交为 `ce20d2e98df4603f3cec2f815ca91c45bd72326c`；已推送并创建 [PR #111](https://github.com/zewbby/SpeechFUL/pull/111)。
- 授权依据与边界：后端按原先授权合并完成；用户继续要求 App 分享及原帖恢复，并在本地实现交付后明确要求“推送合并”，授权本 App 分支推送、创建 PR 和适用产品 CI 全部通过后的合并。没有部署授权；未更新日常 App、业务服务或现有数据库。
- 需求确认：使用 `grill-with-docs` 及其 `grilling`、`domain-modeling` 依赖核实代码和文档，再收敛 Q1–Q5；用户均明确确认推荐方案，无未决产品取舍。
- 更新日期：2026-11-06。
- 状态：后端 实现已完成／验证 PASS／已合并／未部署。App 实现已完成／本地适用验证 PASS，iOS 与公网 HTTPS 关联待验／已送审／未发布。记录提交时 CI 运行中，最终 CI 与合并状态以 PR #111 实时结果为准。

## 目标与范围

- Q1–Q3：向微信等外部应用分享固定的每帖 HTTPS 链接，与本人私人“转帖”归档独立；分享材料只含 SpeechFUL 和 URL。未登录者和外部预览仅见通用引导，登录后读取最新公开原帖；删除／下架后不可读，不增加分享者追踪、到期或分享计数。
- Q4：运行中打开链接，在原页面上展示原帖，返回保留此前页面和位置；冷启动或登录／注册完成后，在首页上展示原帖，返回回首页。
- Q5：登录／注册／基础身份设置期间以最后点击的一篇为准；目标仅保留在本次运行内，取消登录保留，再次点同一链接可重新登录；主动退出清除，重启需重新点链接。Android 最近任务重放的旧 VIEW Intent 不作为新点击。
- 基线中的首页分享空操作、详情“暂未开放”已接入系统分享。覆盖首页卡片、详情底部、详情菜单；同帖各入口共享忙碌状态，注销／换账号／离开页面后的迟到请求不会弹出系统面板，取消面板不提示“发送成功”。
- Flutter 在启动引导页之前接收完整平台 URI，验证固定 C origin、规范 ID、无额外参数；只保存目标，登录、注册收尾及基础身份 Gate 完成后才请求解析。会话失效后可重新登录返回同一目标；无效链接不请求内容，不可用原帖显示既有错误／重试状态。
- 已整合主线自定义标签：列表与详情保留标签和标签导航；分享解析通过同一 `X-Post-Tags: v1` 读取最新正文、标签和编辑元数据。既有图片、评论、浏览行为继续使用详情组件。

## 接口与依赖

- `GET /api/v1/posts/{postId}/share`：当前 Bearer，返回闭合 DTO `{postId,url,shareText}`，文字精确为 `SpeechFUL\n` 加当前 C origin 的 `/s/posts/{postId}` URL。
- `POST /api/v1/post-links/resolve`：当前 Bearer、JSON `{url}`，返回最新 `{post}` 与授权／编辑元数据；拒绝外站、附加参数及非规范 URL，不远程抓取链接。
- `GET|HEAD /s/posts/{postId}`：不查帖子存在性的通用引导页，不含内容、作者、图片或会话续期；按钮为 `speechful://posts/{postId}`。完整契约见 [post-share-api.yaml](../../packages/openapi/post-share-api.yaml)。
- 获取和解析沿用最终 C Safety Gate、会话代次及可见性检查，不新增转帖、阅读计数或帖内身份绑定；实际详情阅读继续遵守既有 views 机制。
- Android 使用平台 `ACTION_SEND`、iOS 使用 `UIActivityViewController`，只传后端验证后的文字；没有新增依赖或修改锁文件。Flutter 同时处理规范 HTTPS 和 `speechful://posts/{postId}`，平台分享完成仅表示面板关闭。

## 平台配置与交付边界

- Android 的 HTTPS intent filter host 从 `AUTH_COMMUNITY_BASE_URL` build define 提取，与 Dart 指向同一 C origin；scheme 入口已接线。发布时需在实际公开 C 域的 `/.well-known/assetlinks.json` 配置真实 application ID 与签名证书 SHA-256。
- iOS 已加入 URL scheme、Flutter deep linking、系统分享及可选 Associated Domains。默认不要求新的签名能力；具备相应 provisioning profile 时，在 Xcode／构建配置设置 `POST_SHARE_HOST` 为实际 C 域、`POST_SHARE_ENTITLEMENTS=Runner/PostSharing.entitlements`，并部署匹配实际 Team ID、`org.hnuhole.hnuholeMobile` 和 `/s/posts/*` 的 AASA。
- 当前默认域为 `.invalid`。公网域名关联／已安装 App 自动打开 HTTPS 仍 BLOCKED，需拥有的公开 HTTPS 域、真实签名及关联文件；显式 Intent、scheme、配置文件或 APK 构建均不证明域名验证成功。本轮没有部署。
- iOS 构建及设备链路 NOT_RUN：本机没有 macOS／Xcode／iOS 设备；仅完成源码接线和 plist／entitlements 解析，不能视为 iOS 验收通过。
- 平台依据：[完整 URI 路由通知](https://api.flutter.dev/flutter/widgets/WidgetsBindingObserver/didPushRouteInformation.html)、[初始路由](https://api.flutter.dev/flutter/widgets/WidgetsApp/initialRoute.html)、[Android App Links](https://docs.flutter.dev/cookbook/navigation/set-up-app-links)、[iOS Universal Links](https://docs.flutter.dev/cookbook/navigation/set-up-universal-links)。

## 验收与证据

App 最终产品及测试为 `ce20d2e`（实现 `f3e8d3c`，主线整合 `da4601b`，接口探针 `6b2972e`）；之后仅更新文档，含整合主线纯文档调整 `d7db2c9`，将分享入口迁至近期工作索引。62 项聚焦、178 项回归及真实 SQL 绑定 `6b2972e`；最终差异仅为取消登录后重点击同一链接的意图代次与测试，10 项分享场景、分析、bundle 和 Android 在最终提交复验，接口／SQL 代码未变。证据目录：`E:/Hnuhole-env/post-sharing-mobile-validation-20261106`。Windows Flutter 3.47.5／Dart、JDK 17、Android API 36；WSL2 Go 1.22.2／PostgreSQL 16.15／Goose 3.22.1。所有 SQL fixture 都在新建 Linux 私有集群，未接触业务库。

| 验证 | 版本／命令与范围 | 结果及证据 |
| --- | --- | --- |
| 静态分析 | 最终代码；`flutter analyze --no-pub` | PASS，零问题。[final-analysis.log](E:/Hnuhole-env/post-sharing-mobile-validation-20261106/final-analysis.log)。 |
| 分享及接口聚焦 | `6b2972e`; `flutter test --no-pub test/post_sharing_test.dart test/post_api_test.dart test/post_tags_test.dart test/post_tag_layout_test.dart test/post_edit_screen_test.dart` | PASS，62 项。覆盖冷／热导航与返回、取消登录及最新目标、基础身份 Gate、会话失效重登、注销清除及迟到响应、三处分享和取消、错误重试、伪造 URL／泄漏 DTO 拒绝及标签兼容。[integrated-focused.log](E:/Hnuhole-env/post-sharing-mobile-validation-20261106/integrated-focused.log)。 |
| 授权与页面回归 | `6b2972e`; `flutter test --no-pub` 加 `post_controller_test`、`post_screens_test`、`feed_ui_test`、`login_home_navigation_test`、`identity_initial_gate_test`、`auth_session_controller_test`、`auth_flows_test`、`community_localization_test`、`app_localizations_test`、`startup_entry_test` | PASS，178 项。[integrated-regression.log](E:/Hnuhole-env/post-sharing-mobile-validation-20261106/integrated-regression.log)。 |
| 生产入口 bundle | `flutter build bundle --debug --no-pub`，真实 `main.dart` 入口 | PASS。[final-bundle.log](E:/Hnuhole-env/post-sharing-mobile-validation-20261106/final-bundle.log)。 |
| Dart → 真实 C HTTPS／SQL | `6b2972e` 源码 tar SHA-256 `7edd90235f3db7426c78c3782cd13a5feaced0697d8e70f67340fc954dde7e19`；Linux `/home/hnuhole/post-share-mobile.5L8qul`；编译 `integration/post_share_live_probe.dart`，`go test ./internal/authprivacyhttp`、`go vet ./internal/authprivacyhttp`；`POST_SHARE_DART_PROBE=... FEED_TEST_PATTERN='^TestRealHTTPSPostShare' sh authlab/run-feed-isolated.sh` | PASS，3 项真实 HTTPS／SQL／race 用例。新 Dart 探针分三阶段读取已发表、实际编辑正文及标签、已删除原帖；公开引导无内容／会话续期，账号交互表无写入；另覆盖既有生命周期、撤销会话与 C Gate。无 DSN 的 Go 测试不计 SQL 证据。[integrated-live.log](E:/Hnuhole-env/post-sharing-mobile-validation-20261106/integrated-live.log)、[runner](E:/Hnuhole-env/post-sharing-mobile-validation-20261106/run-integrated-live.sh)。 |
| Android 构建 | 最终源码副本，仅额外 `debug applicationIdSuffix=.postshareverify`；`flutter build apk --debug --no-pub --target-platform android-x64 --target integration_test/post_sharing_device_test.dart --dart-define=AUTH_COMMUNITY_BASE_URL=https://unused.invalid` | PASS。APK SHA-256 `71b824c8cc8ce42024f82099eabc599b4857f7f6f09844148c988e930c1ab278`；逐字节核对源码与副本，只有声明的测试包名差异。[final-android-build.log](E:/Hnuhole-env/post-sharing-mobile-validation-20261106/final-android-build.log)。 |
| Android 系统链路 | API 36 x86_64 read-only AVD、1080×2400／density 420、独立包 `org.hnuhole.hnuhole_mobile.postshareverify`；真实平台 Intent、真实导航与系统分享面板；认证／帖子数据使用明确的内存替身 | PASS，冷启动、登录后打开、最近任务防重放三场景，含热启动返回此前个人页、取消系统分享后忙碌解除与无发送成功提示；系统预览仅品牌和 URL，无框架异常。此项不证明原生认证存储、真实设备或与 SQL 的组合链路。[device-results.json](E:/Hnuhole-env/post-sharing-mobile-validation-20261106/final-device/device-results.json)、[系统面板](E:/Hnuhole-env/post-sharing-mobile-validation-20261106/final-device/postshare-cold-share.png)。 |
| 首轮失败与修正 | 早期 host／native 记录保留，非最终结果 | FAIL 后已复验 PASS：修正测试返回按钮定位、失效会话目标恢复，以及 Kotlin Gradle Java 类型导入；设备测试初始路由受测试 binding 重置，改读真实 engine route。默认图形后端启动失败后改用任务只读 AVD／SwiftShader；320dp 基线页头溢出不作为当前 411dp 验收结果。见同目录早期 `focused-*.log`、`android-build-r1.log`、`postshare-cold-failure.log`、`emulator-*.log`。 |
| 配置／政策 | plist、entitlements、Android manifest 解析；锁文件无差异；`git diff --check`、`python -X utf8 tools/check-collaboration.py --staged` | PASS，仅证明对应结构与提交政策，不代替 iOS、设备或产品 CI。 |
| 远端 CI／审查 | Feed UI CI 新增分享 host 测试及真实 Dart 分享探针，与主线标签探针并存；Android 原生构建由适用平台 workflow 处理 | 已送审 [PR #111 检查](https://github.com/zewbby/SpeechFUL/pull/111/checks)，此记录提交时运行中，合并前须核对最终 head 的全部适用产品 CI 成功。无独立成员批准证据，不将本地通过记作远端 CI 通过。 |
| 清理 | 本任务资源 | PASS：SQL runner 自动停止并清理私有集群；移除本任务独立测试包并关闭任务 read-only 模拟器，保留原 AVD、缓存和现有应用。[cleanup.log](E:/Hnuhole-env/post-sharing-mobile-validation-20261106/cleanup.log)。 |

最终 `ce20d2e` 的 [10 项分享场景](E:/Hnuhole-env/post-sharing-mobile-validation-20261106/same-link-fixed.log)复验 PASS；新增的“取消登录后重点击同一 URL”场景先[复现 FAIL](E:/Hnuhole-env/post-sharing-mobile-validation-20261106/same-link-before-fix.log)，修正意图去重后通过。最终 Android 三场景使用不指定 Activity、按 manifest intent filter 解析的 scheme Intent；另[无包名限制的系统解析](E:/Hnuhole-env/post-sharing-mobile-validation-20261106/implicit-resolution.log)也指向本任务 Activity。这仍不证明公网 HTTPS 域名验证通过。

后端已完成的证据保留在 [PR #108](https://github.com/zewbby/SpeechFUL/pull/108)：所有 13 个适用 workflow 成功，24 个 job 成功，另有仅 workflow_dispatch 的 job 跳过，随后 squash 合并为 `4a3115d`。本地最终源码快照 SHA-256 `df88a030e61aebad4e6ab1c9857ff86f7c5901e23fe85c4b29e6d57d50a43936` 的 Go test／build／vet 全包通过，6 项真实 SQL／HTTPS 用例及 13 份完整 OpenAPI、23 项旧契约检查通过；日志位于 `E:/Hnuhole-env/post-sharing-validation-20261106`（`host.log`、`sql.log`、`openapi.log`、`legacy-contract.log`）。后端合并不等于部署。

## 阻碍与下一步

App 已完成本地实现和上述可执行验证，并按最新授权推送、创建 PR #111。持续核对最终 head 的全部适用产品 CI，全部成功后 squash 合并；最终合并时间及 SHA 以 PR 实时结果为准。iOS 构建／设备、公网 HTTPS 域关联仍待对应环境验收。未更新用户日常安装包或部署服务；当前日常后端版本也未由本任务推进。当前无需新的产品取舍。
