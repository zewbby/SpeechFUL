# PUBLIC-TRIAL-ACCESS-01 — 个人电脑公网业务域名接入

- 模式：常规；负责人／状态维护人：当前Session，无委派。
- 分支／Worktree：`codex/chore/public-trial-access-01`；`E:/Hnuhole-env/source/SpeechFUL-public-trial-access-01`。
- 运行候选最初依赖基线（历史）：`9bdbb4fa0012ec9006d2e04c530de0710c034eec`，包含Android验收本地修复；远端main仍为`6b722f071f07cbd94d96095734499f8cdd061641`。原验收Worktree中正在进行的站内分享改动全部保留，不打包或提交其未完成内容。
- 授权依据：用户明确“自己电脑＋向日葵（或其他）”、用于App业务公网接入；已确认“先让少量用户公网试用”“先用穿透服务提供的域名”“固定地址，配合登录穿透服务账号”。用户已亲自登录花生壳和ngrok。
- 范围：独立公网试用环境及接入准备；不改日常后端、正式数据和验收实验室；不购买套餐/域名、不开启付费续费；本轮用户明确“先把已经做了的提交合并”，授权本任务 Push/PR/合并；不正式发布。外部分享已取消，公网App Links不再作为这个接入目标。
- 需求确认：公网地址是App连接业务/认证后端的地址；现有C/V独立HTTPS origin及所有认证/Gate保留。来源`apps/mobile/lib/src/auth/http_auth_api.dart`与`services/api/internal/authprivacyruntime/config.go`；不为省一个地址而放宽隔离。域名固定不等于永久免费/无限流量。
- 更新日期：2026-11-07。
- 状态（以下及文末复验为当前权威状态，早期调查按历史快照阅读）：公网最小链路 PASS；真实校园邮箱投递 PASS；首页发布自动显示 PASS；登录 Windows 后自动启动已配置，任务资源冷启动/故障恢复 PASS；整机重启首轮 FAIL 保留，修复后第二次真实重启自动恢复 PASS（Windows 登录后）；合并状态以 [PR #114](https://github.com/zewbby/SpeechFUL/pull/114) 实时结果为准；独立试用包已安装；日常包未覆盖；正式发布未发布。

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


## 三项跟进与最终复验（2026-11-07）

- 用户明确要求解决真实验证码、电脑重启自动恢复、首页帖子显示，并报告未通过项；维持同一常规任务分支，产品二进制/APK均未改动，不重复构建。当前运行配置和部署脚本变更以[复验回执](E:/Hnuhole-env/public-trial-access-01/followup-validation.json)中摘要绑定。
- 用户随后明确暂不整机重启，保留待验；并授权向“执行 Android 首版完整验收 (3)”通知手机释放。已向该会话发送通知，之后停止所有 ADB/UI/截图/装机操作。本轮不再占用设备，也未重启 Windows、WSL 或其他环境。

| 场景 | 结果 | 证据及边界 |
| --- | --- | --- |
| 真实校园邮箱投递 | PASS | 复用此前已配置的 QQ SMTP，严格 TLS/账号认证通过；独立 V 仅复制任务私有凭据，文件 0600，日常配置不变。正常手机 App 经公网发起一次 OTP，任务 outbox=SENT，用户回答“已收到验证码”。真实邮箱的确认码提交/开户 NOT_RUN；未向聊天输出验证码/发件凭据，也未自动重发未知结果。 |
| 首页已有列表发布 | PASS | 合成账号发布 `AV1 pub2`，无需手动刷新自动显示；已有帖子仍可读。 |
| 空分类发布首帖 | PASS | 科技分类先确认空态，再正常发布 `AV1 first`，约 7.8 秒自动进入首页，无手动刷新。[机器回执](E:/Hnuhole-env/public-trial-access-01/first-post-autorefresh.json)、[脱敏 UI 序列](E:/Hnuhole-env/public-trial-access-01/ui-dumps)。初次短时空态未复现为持续缺陷，保留原观察；没有为此修改产品语义。 |
| 持久自动启动 | PASS（配置/当前启动） | Windows 任务 `SpeechFUL-PublicTrial-Access-01` 使用当前用户交互登录触发，不保存 Windows 密码。隐藏监控持有任务专属 WSL 前台 keepalive，启动两个已 enable 的持久 systemd 单元、检查并重启本任务连接器。使用互斥锁和 PID/启动时间/路径核对，不依赖另一验收任务维持 WSL。该方案在 Windows 用户登录后启动，登录前服务不承诺可用。 |
| 服务/连接器退出后恢复 | PASS | 仅停止任务服务及已校验身份的连接器，监控自动拉起；新的连接器 PID 已核对。未停止其他会话资源。 |
| 修正停机顺序后完整冷启动 | PASS | 连续两轮停止任务 API/watch/Redis/代理及两个 PostgreSQL，再由已注册监控自动启动；健康入口均 200，C/V Gate 保持 OPEN，代次分别 1/2。[最终健康回执](E:/Hnuhole-env/public-trial-access-01/runtime-health.json)、[当前监控回执](E:/Hnuhole-env/public-trial-access-01/resume-status.json)。该结果不等价 Windows/WSL 整机重启。 |
| 真实 Windows 重启 | PASS（最新第二轮） | 首轮失败与后续人工恢复保留；第二轮于 12:26:16.5 开机，在任何 WSL/服务干预前已自动恢复，手机冷启/刷新 PASS；详见文末第二轮证据。 |
| 最终公网 HTTPS | PASS（PC 探针） | 两个域名 `/health/ready` 均 200，使用公共 DoH 实际 A 记录固定连接地址并保留正常域名/证书验证。本机默认假 IP DNS/代理路径曾出现 TLS/403，未修改系统网络配置；手机公网业务证据为上文版本范围，最终电脑探针不冒充新的真机业务回归。 |
| 部署配置校验 | PASS | Python AST、PowerShell parser、`systemd-analyze verify`；不把这些检查当作 Go/Flutter 产品 CI。 |

### 本轮恢复失败、原因与处理

- 保留真实 FAIL：先前 systemd 默认 `KillMode=control-group` 会同时发送终止信号给宿主、API/watch 和 PostgreSQL。最后一轮全资源停止时，V 外部锚高水位领先数据库约 62 毫秒；安全 Gate 正常检测 `SNAPSHOT_OR_ANCHOR_MISMATCH` 并冻结。早先多次人工启停也触发 `start-limit-hit`，只清除任务服务的 systemd 启动计数，未借此操作认证 Gate。
- 最小运维修复：持久单元改 `KillMode=mixed`，宿主先等待证据维护进程退出，再停 API、Mailpit/Redis，最后使用原任务 PG 路径和 PID 归属校验正常停止两个库。重启时不对复用 PID 发信号；保留 boot ID，丢弃已失效的进程回执。普通路径仍只 resume/watch；签名/外部锚/Gate 最终检查未变。
- 在独立 V 私有数据库和锚备份后，用户明确回答“允许独立认证后端签名恢复”。只执行一次正常签名 V recovery，代次 1→2；C 保持 1。既有未完成 V 验证失效，不修改原库/代次，不删除失败记录，不在启动器加入自动 recover。随后两轮同门槛冷启动成功，未再冻结。
- 运维脚本位于 `E:/Hnuhole-env/public-trial-access-01/`，只用于本任务资源；可审阅的[监控](E:/Hnuhole-env/public-trial-access-01/resume-public-trial.ps1)、[宿主](E:/Hnuhole-env/public-trial-access-01/host-lab.py)、[持久单元安装器](E:/Hnuhole-env/public-trial-access-01/install-services.py)及摘要见复验回执。私有配置、日志、数据库备份和凭据不提交 Git。

### 剩余未通过或待验

- 本任务：整机重启已完成第二轮自动恢复 PASS（见文末）；真实校园验证码确认/真实开户 NOT_RUN，仅实际投递与收信 PASS；登录前启动、掉电/强杀后的安全恢复、广泛外网和长期在线运行未验。系统安全检测到不一致时仍应冻结，不能承诺异常断电后必定自动解冻。
- Android 完整候选：沿用[原唯一记录](E:/Hnuhole-env/source/SpeechFUL-android-v1-acceptance-01/docs/tasks/ANDROID-V1-ACCEPTANCE-01.md)的适用版本和结论。热榜旧 30 分钟持续负载 FAIL（窗口搜索 P95 +77.8335%、2 次 503、40 次 capacity drop）未修复、未重测；本次接入不关闭它。站内卡片和网页治理完整真机/网页复验由“执行 Android 首版完整验收 (3)”继续，结果以其后续证据为准，不抢写其记录。
- 修复候选远程产品 CI 未运行，未 Push/PR/合并；仍为独立 profile 试用包与独立后端，未覆盖日常包/数据、未正式发布。外部分享及链接关联按用户取消范围，不重新列为首版接入阻断；iOS 保留延期。


## 真实重启复验（2026-11-07 12:18 后，覆盖前述延期）

- 用户明确告知电脑已重启，随后授权本会话重新使用手机。Windows 实测启动时间为 **2026-11-07 12:18:53.5 +08:00**。本次实际无人干预恢复为 **FAIL**：登录触发任务存在，但监控回执仍为旧启动时间，12:19–12:21 持续记录恢复失败，无新 keepalive/连接器回执。
- 保留干预边界：调查时运行 WSL 查询启动了原已停止的发行版，并在修改启动器后重新启动计划任务，不能将之后的成功冒称本次无人干预重启 PASS。原错误日志缺异常详情，不能证明其精确异常类型；根据失败发生于更新进程回执之前，补强旧 PID/不可读取进程信息处理，作为修复和下次启动的诊断保障。
- 修复：统一 `Test-OwnedProcess` 捕获进程不存在、启动时间不符、权限不可读等失效回执，均返回非本任务进程，不发信号；真实本任务进程仍核对名称、启动时间和命令路径。增加 keepalive/services/connector/health 阶段和异常类型日志，详细原因仅保存在任务私有日志。受保护 PID=4、缺失 PID、错误启动时间和真实 keepalive 识别专项均 PASS。
- 手动重新触发后：任务持续 Running，监控于 12:22:31、12:23:31 更新，boot UTC 与本次 Windows 开机一致，两个入口均 200。C/V Gate 保持 OPEN、代次 1/2，没有再次 recover，也未更改其他任务资源。
- 真机复验 PASS（本次已获用户授权）：realme 7e0660f1，独立公网包 2026110701；两个公网域名严格 TLS 健康检查均 200，首页下拉刷新可读旧测试帖；force-stop 本任务包后正常冷启恢复原合成账号，推荐页读回原有三帖。未操作其他安装包、真实账号或清除数据。
- [本次回执](E:/Hnuhole-env/public-trial-access-01/reboot-validation.json)绑定修复后启动器 SHA256、Windows 开机时间和当前监控数据。该运维修复没有修改 App/Go 产品代码，不重复构建；本地语法及进程归属专项与实际恢复验证不替代产品 CI。
- 结论：**目前服务与 App 已恢复可用；修复后再次真实、无人干预 Windows 重启仍 NOT_RUN**。原热榜负载 FAIL、候选远程 CI/合并/发布及其他验收会话负责的缺口不因本次恢复而关闭。


## 第二次真实 Windows 重启：自动恢复 PASS（2026-11-07）

- 用户再次明确“已重启”。本次实测 Windows 开机时间 **12:26:16.5 +08:00**，计划任务最近触发 **12:26:26**，任务宿主进程创建 **12:26:29.761561**；本任务 systemd 两单元进入 running **12:26:58**，Cloudflare 连接器创建 **12:27:01.514945**。监控回执 boot UTC 与本次开机一致，两个健康入口均 200，任务持续 Running，未出现本次开机后的新恢复失败日志。
- 先只读取 Windows 记录和已有监控文件，保存[干预前启动证据](E:/Hnuhole-env/public-trial-access-01/reboot-second-startup.json)，之后才执行只读 WSL 状态/Gate 查询；本轮没有手动启动 WSL、后端或代理，没有重启计划任务、没有 recovery、没有修改部署脚本。不能将首轮人为恢复混入本轮自动恢复结论。
- 外部 HTTPS：电脑使用实际 Cloudflare A 地址及原域名正常 TLS 验证，社区/认证健康均 200；真机直接访问两个公开域名也均 200。
- 用户上一轮已明确允许使用手机，本轮 realme `7e0660f1`、独立包 `org.hnuhole.hnuhole_mobile.publictrial` / 2026110701 / 原 APK 摘要不变。仅 force-stop 本任务包再由正常入口冷启，无需重新登录；首页加载及下拉刷新后读回 `AV1 first`、`AV1 pub2`、`AV1 a`。C/V Gate 均 OPEN，代次 **C=1、V=2**，无本轮代次变化。
- [完整第二轮回执](E:/Hnuhole-env/public-trial-access-01/reboot-second-validation.json)保存 Windows/任务/监控时间、部署脚本摘要、干预边界和设备结果；脱敏 UI 在原任务 ui-dumps。实现与 APK 无新增变化，本轮只更新本地证据及任务文档，无 Push/PR/合并/正式发布。
- **结论：本任务“Windows 重启并登录后自动恢复原独立公网服务及 App 会话/数据”PASS，可以关闭该缺口。** 登录前可用、非正常断电/强杀后恢复、长期运行和广泛外网仍不在此次 PASS 范围。首轮 FAIL 原证据保留；热榜旧负载 FAIL、真实校园码确认/开户、候选远程产品 CI 及其他会话负责的验收结论继续按原记录处理，不提升整体验收或正式发布状态。


## 提交与合并（2026-11-07）

- 用户明确授权“先把已经做了的提交合并”。此次仅提交本任务公网接入记录及近期工作索引；Cloudflare、systemd、Windows 计划任务和私有运行配置已在本机生效，凭据、个人配置、日志及 APK 不进入 Git。
- 核对旧分支原本继承未合并 Android 修复；保留原提交引用后，将本任务 7 个记录提交移到实际最新 `origin/main` **6b722f071f07cbd94d96095734499f8cdd061641**，只提取本任务差异，未带入另一会话的产品改动、任务记录或其当前工作区。运行中的 App/C/V 来源仍按前述精确版本，不因文档分支变基而改变。
- 本 PR 是文档归档与交付状态记录，不能称作公网配置/运行脚本已进入主线，也不授予正式发布或日常数据迁移许可。远程 Collaboration CI 仅用于文档协作规范，前述真实服务和设备证据仍为原被测版本。
- 本地差异/凭据检查、协作检查通过；PR 与远程检查状态随本轮核对更新。首版产品整体热榜 FAIL 和其他未完成验收不因本次记录合并关闭。

- PR：[SpeechFUL #114](https://github.com/zewbby/SpeechFUL/pull/114)。提交后 main 已合并另一任务 #113（314162a），已合入最新主线并保留近期工作中双方条目；相对当前 main 仍只修改本任务记录和索引。该同步不修改运行环境，不将另一任务的功能或验收记为本 PR 实现。适用远程文档 CI 待当前 head 核对。

- 文档检查回执：[Collaboration](https://github.com/zewbby/SpeechFUL/actions/runs/42339207984) 在归档前 head 3f8eec4 PASS；本地 19 项协作回归 PASS。最终合并状态与最新 head 检查以 [PR #114](https://github.com/zewbby/SpeechFUL/pull/114) 为实时依据。无 GitHub 成员批准记录，不将维护者授权合并或本地复核表述为独立成员批准。
