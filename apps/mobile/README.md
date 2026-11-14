# SpeechFUL 客户端快照

本目录展示 SpeechFUL 的 Flutter 客户端源码。完整研发和服务部署在私有开发仓库进行，公开仓库按选定版本同步客户端快照。

## 代码结构

- `lib/main.dart`：客户端装配与启动。
- `lib/src`：登录、身份、信息流、帖子、评论、私信、通知、本地存储和界面状态。
- `android`、`ios`：原生平台工程。
- `../../packages/auth_vault`、`auth_passkey`、`image_viewer`、`native_media`：客户端必要插件。

## 源码与环境

声明的 Flutter/Dart 版本及依赖以 `pubspec.yaml` 和锁文件为准。字体包含 Git LFS 对象，取回源码时需要获取对应对象并保留其许可与署名。

客户端连接两个独立且固定的 HTTPS origin，构建配置名为 `AUTH_COMMUNITY_BASE_URL` 与 `AUTH_VERIFIER_BASE_URL`。默认 `.invalid` 地址是占位符。本公开快照不提供后端环境、开发账号、生产签名或服务端配置，也不声明已经过独立快照构建验收。

第三方 Flutter/Gradle/Xcode 生成文件由相应工具产生；当前代码中声明的系统能力不等于正式用户流程已经启用。密码/Passkey、通知、相册等能力仍以所用发行版、平台支持与服务端状态为准。

该展示快照不携带项目历史测试、验收 runner 和内部文档。安全、认证和隐私相关的服务端实现不包含在本仓库中；客户端插件仍属于公开客户端源码。
