# PUBLIC-TRIAL-ACCESS-01 — 个人电脑公网业务域名接入

- 模式：常规；负责人／状态维护人：当前Session，无委派。
- 分支／Worktree：`codex/chore/public-trial-access-01`；`E:/Hnuhole-env/source/SpeechFUL-public-trial-access-01`。
- 基线：`9bdbb4fa0012ec9006d2e04c530de0710c034eec`，包含Android验收本地修复；远端main仍为`6b722f071f07cbd94d96095734499f8cdd061641`。原验收Worktree中正在进行的站内分享改动全部保留，不打包或提交其未完成内容。
- 授权依据：用户明确“自己电脑＋向日葵（或其他）”、用于App业务公网接入；已确认“先让少量用户公网试用”“先用穿透服务提供的域名”“固定地址，配合登录穿透服务账号”。用户已亲自登录花生壳和ngrok。
- 范围：独立公网试用环境及接入准备；不改日常后端、正式数据和验收实验室；不购买套餐/域名、不开启付费续费；不Push/PR/合并/正式发布。外部分享已取消，公网App Links不再作为这个接入目标。
- 需求确认：公网地址是App连接业务/认证后端的地址；现有C/V独立HTTPS origin及所有认证/Gate保留。来源`apps/mobile/lib/src/auth/http_auth_api.dart`与`services/api/internal/authprivacyruntime/config.go`；不为省一个地址而放宽隔离。域名固定不等于永久免费/无限流量。
- 更新日期：2026-11-07。
- 状态：实现 进行中；验证 本地初始化PASS/持续运行待修正、公网NOT_RUN；公网开通 未完成；配套APK 未构建/未安装；正式发布 未发布。

## 目标与范围

先用独立数据打通公网HTTPS业务入口，核对注册/登录/阅读等实际API链路，再与完成站内分享调整后的App构建绑定。原Android候选验收结论以[原唯一记录](ANDROID-V1-ACCEPTANCE-01.md)为准，本记录仅负责新提出的公网部署任务，不复制其场景矩阵。

## 接口与依赖

- 花生壳账号当前2条体验映射、1GB流量、一个已开通HTTPS的固定域名；HTTPS端口443。只有一个可选HTTPS域名，两条映射不能自动当作两个独立HTTPS地址。
- ngrok已分配一个固定开发域名，用于补充另一独立HTTPS origin；额度以账户实际计费页为准。未创建API key或额外持久凭据。
- 账号登录/注册由用户自行完成，密码/OTP/令牌不进入聊天或Git；尚未提交公网映射，未公开业务数据。
- 独立证据及配置目录：`E:/Hnuhole-env/public-trial-access-01`。手机当前ADB无设备，真机公网验证BLOCKED，其他准备继续。

## 验收标准

- 两个HTTPS origin稳定且不同、证书正常，C/V内部mTLS与数据库/Redis不映射到公网。
- 只连接任务自己的新库、缓存及配置；新Gate只做一次明确初始化，不改钟、不改Gate行、不自动恢复冻结。
- 实际公网HTTPS就绪、认证及内容读取有证据；缺真实邮箱/设备时分别标记，不以健康页当业务验收。
- 未完成的站内分享实现不混入配套构建，不将本任务准备视为正式上线。

## 当前进度与证据

| 项目 | 被测版本／环境 | 结果 |
| --- | --- | --- |
| 基线/隔离 | 上述完整SHA及新Worktree | PASS；已有改动保留 |
| 固定域名/账号 | 用户亲自登录两家官方服务 | PASS（账号和域名可见，不等于映射已通） |
| 免账号临时方案 | 官方cloudflared 2026.10.7 | 已下载并核对官方SHA256；用户选择固定地址，未开启临时隧道 |
| 独立本地后端 | 新Linux任务资源 | NOT_RUN，准备中 |
| 公网业务链路 | 花生壳+ngrok | NOT_RUN |
| Android公网装机 | 无当前连接设备 | BLOCKED |

## 阻碍与下一步

以以下最新确认取代先前花生壳+ngrok组合；旧调查只作历史事实。付费或账户权限扩展不默认批准。

## 自有域名最新确认（2026-11-07）

- 用户明确已有`speechful.dpdns.org`，用作App用户日常业务访问域名，“不需要ngrok了”。停止ngrok方案；未取得/保存ngrok令牌、未启动ngrok、未开通花生壳映射。域名用途是业务API，外部分享仍取消，不重新引入App Links验收。
- 公共DNS over HTTPS核对：域名NS为`tiffany.ns.cloudflare.com`和`donovan.ns.cloudflare.com`，主域没有A记录，`api`和`auth`子域查询NXDOMAIN。[DNS回执](E:/Hnuhole-env/public-trial-access-01/dns-own-domain.json)。本机DNS曾返回198.18段地址，未把代理合成地址当公网真实解析。
- 计划固定origin：社区`https://speechful.dpdns.org:443`，认证`https://auth.speechful.dpdns.org:443`；同一Cloudflare Tunnel分别连接独立本地上游，不合并C/V权限或内部mTLS。域名/隧道尚未修改，公网未通。
- Cloudflare官方管理页已打开，待用户登录该域名管理账号；登录后核实zone、证书、现有记录及隧道，再做可审阅的路由配置。官方依据：[Tunnel接入](https://developers.cloudflare.com/tunnel/get-started/)。使用已校验SHA256的官方cloudflared 2026.10.7，无需再买域名。
- 独立环境初始构建/PG C34 V7迁移/严格TLS就绪实际PASS，`lab-receipt.json`在任务外部目录。后续检查发现CLI会话结束后其子进程未持续运行，当前health FAIL；保留原始结果，先修正进程托管再复验，不将初始化PASS视为可日常运行。数据库/密钥仍为独立合成资源，未改日常后端和验收实验室。
- Windows/ngrok/花生壳客户端均未安装为常驻服务；花生壳Linux包仅下载并展开检查，未运行安装脚本；Nginx仅从Ubuntu官方仓库下载/解包，未创建全局服务。已下载工具不代表公网部署。
- 下一步：Cloudflare登录→核对现有zone/证书→准备严格TLS上游和持久进程→审阅具体公开路由→公网实际业务测试→完成站内分享调整后构建配套包。域名用途确认不等于正式上线或日常用户数据迁移已完成。
