# PUBLIC-TRIAL-ACCESS-01 — 个人电脑公网业务域名接入

- 模式：常规；负责人／状态维护人：当前Session，无委派。
- 分支／Worktree：`codex/chore/public-trial-access-01`；`E:/Hnuhole-env/source/SpeechFUL-public-trial-access-01`。
- 基线：`9bdbb4fa0012ec9006d2e04c530de0710c034eec`，包含Android验收本地修复；远端main仍为`6b722f071f07cbd94d96095734499f8cdd061641`。原验收Worktree中正在进行的站内分享改动全部保留，不打包或提交其未完成内容。
- 授权依据：用户明确“自己电脑＋向日葵（或其他）”、用于App业务公网接入；已确认“先让少量用户公网试用”“先用穿透服务提供的域名”“固定地址，配合登录穿透服务账号”。用户已亲自登录花生壳和ngrok。
- 范围：独立公网试用环境及接入准备；不改日常后端、正式数据和验收实验室；不购买套餐/域名、不开启付费续费；不Push/PR/合并/正式发布。外部分享已取消，公网App Links不再作为这个接入目标。
- 需求确认：公网地址是App连接业务/认证后端的地址；现有C/V独立HTTPS origin及所有认证/Gate保留。来源`apps/mobile/lib/src/auth/http_auth_api.dart`与`services/api/internal/authprivacyruntime/config.go`；不为省一个地址而放宽隔离。域名固定不等于永久免费/无限流量。
- 更新日期：2026-11-07。
- 状态（以下为当前权威状态，后文早期调查按历史快照阅读）：两个公网路由已启用；独立测试后端和隧道运行中；手机 HTTPS 健康检查 PASS；合成账号公网注册和发帖读回 PASS；真实邮箱 BLOCKED；正式发布未发布。

## 目标与范围

先用独立数据打通公网HTTPS业务入口，核对注册/登录/阅读等实际API链路，再与完成站内分享调整后的App构建绑定。原Android候选验收结论以[原唯一记录](ANDROID-V1-ACCEPTANCE-01.md)为准，本记录仅负责新提出的公网部署任务，不复制其场景矩阵。

## 历史调查快照（下列旧状态已被后文最新进度取代）

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

### 自有域名接入准备回报

- 用户已亲自登录Cloudflare；实际管理页确认speechful.dpdns.org在当前账号、Full DNS/Free plan、域名已激活；隧道列表0条。
- 已准备名为speechful-pc的隧道创建表单，未提交。创建持续连接凭据的当次确认已提出，待用户回答；尚无DNS/公网路由改动。
- [公网路由草稿](E:/Hnuhole-env/public-trial-access-01/cloudflare-route-draft.json)已保存，不含任何令牌。后续主域社区/auth子域认证，数据库、Redis和内部mTLS不公开。
- 本地托管修正：任务专用隐藏WSL宿主持续持有会话，原PID身份检查后重启任务进程；仅对既有OPEN Gate执行resume/watch，不再次recover。启动后独立第二次health PASS，未修改日常或旧验收实例。当前尚非系统开机自启服务，电脑重启后恢复流程仍待验证。

### 隧道连接与本地上游验证

- 用户已授权创建`speechful-pc`隧道，并明确要求连接电脑。Cloudflare实际显示Healthy、一个连接、无路由。官方cloudflared 2026.10.7连接器使用任务私有令牌文件，权限0600；未提交令牌。连接器为隐藏进程，开机自动恢复尚未配置。
- 本任务独立本地Nginx代理C/V分别使用不同回环端口，上游经任务CA严格验证；通过两个代理访问`/health/ready`均HTTP 200。公网路由和DNS尚未提交。
- 后端当前对外origin仍是本机回环地址，真实邮箱供应商未配置；直接映射不代表公网App可用。需先配置两个域名的规范origin，保持C/V独立、Gate和内部mTLS，完成真实业务验证。
- 当前无连接Android设备；站内分享尚有未提交改动，不能将旧客户端冒充符合新需求的日常包。


## 最新公网接入进度（2026-11-07，覆盖上述历史状态）

- 用户确认使用自有域名、只保留站内分享，明确授权创建 `speechful-pc` 隧道及分别启用社区和认证公网路由。Cloudflare 显示隧道 Healthy，两条路由已添加并创建 DNS；证书覆盖主域和子域且状态 Active。
- 社区 `https://speechful.dpdns.org` 和认证 `https://auth.speechful.dpdns.org` 分别经隧道到本机独立代理及各自后端；代理严格校验本地上游 CA，数据库、Redis、内部 mTLS 不开放公网。隧道和代理为任务专属进程；后端为任务专属 systemd 临时单元，重启后的自动恢复尚未验证。
- 独立后端采用合成资源，C 数据库已从 C34 升级到 C35，V 数据库 V7；C 二进制源码 `6483ac119c97ce17c3f4f360c68bc229cccef066`，其 SHA256 `3e12436cc42587741ab86c1659654c36003ca9bf86e2000e3924f53f867b30a0`。Gate 保持既有安全检查。
- realme 设备 `7e0660f1` 在 Wi-Fi 上分别以系统 TLS 访问两个公网 `/health/ready`，均 HTTP 200，属网络健康检查，不能替代 App 业务验收。本机一条网络路径访问主域 TLS 握手失败，需另行定位。
- 真实校园邮箱验证码：BLOCKED；当前独立环境连接 Mailpit 测试邮箱，不能给真实用户投递。公网注册、登录、内容业务链路和正式部署仍待验证；不能据此认定可供真实用户日常使用。
- 独立 Android 安装包源 `481fcd9f6a9eb2df521f036d29df4fe758e9dccf`，profile/arm64，应用 ID `org.hnuhole.hnuhole_mobile.publictrial`，后端地址写入两个公网 HTTPS origin；已构建并独立安装启动，不覆盖既有验收包。APK SHA256 `a7b5695d50c567001654e6030c0a5d63a395ceda10455151f733780a822e48c8`，版本码 2026110701，构建信息见 `E:/Hnuhole-env/public-trial-access-01/android-receipt.json`。
- 现有日常开发环境版本 `b46244d023cb0c3a2b847ef0855082c0cade9a01`、C34/V7，与本次独立后端及客户端不是同一环境；未修改该环境或正式数据。原 Android 完整验收、产品 CI、合并和正式发布仍以原任务记录及实际证据为准。

- 手机经正常 App 入口及两个公网 HTTPS origin，使用隔离 Mailpit 接收验证码，完成合成账号注册、恢复码确认、首次身份设置和首页空态；发布一条合成文字帖后，在“我的”帖子中读回 PASS。发布后分类首页仍显示空态，尚未排查刷新或可见条件，标记 NOT_RUN，不能认定首页同步通过。脱敏 UI 证据位于 `E:/Hnuhole-env/public-trial-access-01/ui-dumps`；合成凭据独立私有保存，不提交。
- 该最小链路不替代全场景回归、独立产品 CI、真实邮箱投递、持续服务和重启恢复验证；也不代表日常包已覆盖安装、合并或正式发布。
