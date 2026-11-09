# 连接与额度字段契约（拟新增）

2026-10-23；配套[设计草案](../superpowers/specs/2026-10-23-connected-accounts-design.md)。这是本地 Swift DTO 约定，不是已实现 API，不向外暴露秘密字段。

## 对象

| 对象 | 字段 | 语义与约束 |
| --- | --- | --- |
| ConfigSource | id, kind, locationReference, sourceVersion, compatibility | kind=ccSwitch / officialClient；路径留在本机，不写公开报告 |
| ToolConnection | id, sourceID, upstreamConnectionID, harness, profileID, mode, configuredRoutes[], generation, observation? | mode=direct / routing / aggregation / unknown；已配置与最近观测分别记录，observation 无证据则空 |
| ConfiguredRoute | accountID?, poolIDs[], providerLabel, endpointOrigin, modelLabel?, evidence | 聚合模式可多条；providerLabel 不由模型名推断；evidence=config / observed / unknown |
| CredentialReference | sourceID, connectionID, locator, generation | 不包含 Key/token 明文；解析出的秘密只在查询执行上下文中短暂存在，禁止进入 Codable 缓存/诊断 |
| BillingAccount | id, serviceID, region?, upstreamAccountID?, organizationID?, projectID?, displayName, identityConfidence | identityConfidence=verified / sourceLocal / ambiguous；无证据时不能跨来源合并；国内与国际平台分开识别 |
| QuotaPool | id, accountID, upstreamPoolID?, productID?, parentPoolID?, aggregationRole, scope, metricKind, currency?, unit, period?, resetsAt?, expiresAt?, sharingEvidence | scope=account / organization / project / key / product；metricKind=subscriptionPercent / money / credits / requests / usageOnly；aggregationRole=reportedTotal / component / independent；总额与组成项不得重复相加 |
| QuotaMeasurement | poolID, remaining?, used?, limit?, fetchedAt, sourceUpdatedAt?, status, accuracy, coverage?, generation | 金额/credits 用 Decimal；百分比限 0–100；accuracy=reported / estimated；coverage 标注仅此工具/此设备等可见范围 |

金额必须带 ISO 4217 币种，credits 保留厂商单位。金额或积分没有 limit 就没有进度百分比；`unlimited` 只有上游明确返回时可展示，不因 limit 缺失推导。滚动窗口重置与赠送额度过期分别存储。来源时间缺失时显示查询时间，不伪造来源时间。

DeepSeek 官方按 currency 分池，total_balance 是已包含 granted_balance 与 topped_up_balance 的可用总额；组成项只作明细。Kimi API 的 available_balance 为官方可用余额，cash_balance 可为负、voucher_balance 非负，不把 cash 一律截零，不将 API 钱包与 Kimi Code 套餐合并。GLM API 按量 / Coding Plan / ZCode 官方登录分别识别产品和鉴权能力；第三方平台转售的国产模型仍归属第三方计费账户。只有接口明确返回稳定身份时才跨连接去重。

## 方法

| 方法 | 请求 | 响应 | 状态与行为 |
| --- | --- | --- | --- |
| discover() | 无；用户已主动启动连接流程 | 来源与脱敏候选连接列表 | 不解析/返回凭据；重复发现不自动启用新账户 |
| resolve(reference) | 已选来源/连接引用 | 当前 generation、路由、CredentialReference | schema 不兼容或来源删除返回明确错误；不降级为读取所有配置 |
| fetch(context) | pool、generation、凭据解析能力、deadline | 一个或多个同 generation 的 measurement | 最大 30 秒预算；401/403 不立即重试；429 遵循 Retry-After；未知接口不试发推理请求 |
| map(snapshot, context) | 现有 QuotaSnapshot + 明确来源身份 | 旧平台对应池与 measurement | 不通过百分比猜总金额；保持现有 Codex 主桶、Antigravity Gemini  |

## 状态

- `available`：受支持查询成功，值可用于展示；真实剩余 0 仍属于成功。
- `stale`：曾成功，本轮失败/超出适配器有效期；保留数值、时间与灰色失败提示。
- `discoveredOnly`：仅发现配置，尚未启用或缺查询适配器；不自动轮询。
- `unsupportedQuery`：已连接但没有可验证查询方法；显示能力限制，不能展示假余额。
- `permissionRequired`：已有凭据不足以读此范围，去原工具设置；不是网络错误。
- `reauthRequired`：原工具登录过期；由原工具重新登录，本项目不改写授权状态。
- `sourceRemoved` / `incompatibleSource`：来源删除或格式不兼容；停止查询，保留清晰提示。

生成规则：结果的 generation 必须与当前连接一致；否则丢弃。相同 verified pool 的多个工具视图共享一份 measurement。账号池与 Key 预算即使金额相同也不能合并。余额变化不等于本工具消耗；来源不覆盖其他设备/工具时必须标范围。

## 首批验收场景

1. Claude / Codex 同源引用同一个钱包：单次查询、两处引用；不同组织则两次且分开。
2. 两个不同 Key 同账户但无账户 ID：保持独立，不自动汇总。
3. 同域名两个账户、同模型两家服务、local proxy 占位 Key：均不因外观相似误合并。
4. A 查询中切换到 B：A 的返回不能覆盖 B；固定到 A 的菜单栏不偷偷切成 B。
5. Key 仅能查预算：显示“Key 预算”，不冒充账户余额；缺权限引导原工具。
6. 钱包无总额、赠送额度即将过期、不同币种、没有余额接口：各自准确呈现。
7. 路由/聚合配置只能证明候选服务：不声称全部会话实际使用同一家。
8. 来源数据库忙锁/版本不兼容/删除、401、429、查询失败：各状态可复现，保留的官方套餐平台不受影响。
9. 自定义脚本、命令型凭据 helper：不执行；不访问任意跨域余额地址。
10. Kilo BYOK 的平台侧 $0：明确上游计费，不能标免费；Kiro / Grok 共用范围只采用实测返回的身份与池标识。
11. DeepSeek 的 total 与充值/赠送组成项：总计一次；Claude 推理 `/anthropic` 不用于拼接余额查询地址。
12. Kimi API 现金负数、代金券与可用余额：保留官方语义；不同区域 Key 不混用；不冒充 Kimi Code 登录额度。
13. GLM 名称或 OpenAI-compatible 协议不足以证明 Coding Plan/钱包查询能力；缺查询契约只识别配置，不试发计费推理请求。

## 已实现：DeepSeek Harness 本机登录余额

2026-11-09。此节是当前 macOS 实现；前文通用 DTO 仍为设计约定。

| 接口编号 | 接口名称 | 接口简介 | 接口url |
| --- | --- | --- | --- |
| QN-H01 | Harness 官方钱包查询 | 新增：只读已有 Harness 登录，分别展示充值和赠送钱包；与 CC Switch API 余额独立 | `GET https://platform.deepseek.com/api/v0/users/get_user_summary` |

- 本地来源 `DisplaySource.harness`；持久化使用 `selectedHarness`。套餐来源保留 `codex`、`claude`、`antigravity`、`zcode`，删除 Kimi、MiniMax、Qoder、CodeBuddy；旧选择无法识别时回到 Codex。ZCode 不再带实验性标签。
- 登录文件默认 `~/.dsh/.credentials.yaml`，支持应用启动环境的 `DSH_HOME`。安全 YAML 解析只接受 `version: 1` 的 `records["deepseek-account-platform/default"]`，`kind: grant`，payload 含 `version: 1`、非空 token、固定 issuer `https://platform.deepseek.com`。不读写其他服务授权，不更新令牌。
- 请求头 `x-dsh-auth-token`；固定 HTTPS 主机和 GET 路径，不允许重定向，不请求模型或赠送领取接口。响应只接受 `code == 0`、`data.biz_code == 0`，余额取 `data.biz_data.normal_wallets` 与 `bonus_wallets` 的 `currency`、`balance`。
- 充值与赠送金额使用 Decimal，按 CNY/USD 分开展示，不相加；空钱包显示未知，实际返回零显示零。胶囊只显示充值余额，赠送余额在详情另列。切换或移除登录后清除旧读数；网络失败显示上次成功金额及过期提示。
- 实现依据为本机 `/Applications/DeepSeek Harness.app/Contents/Resources/app.asar` 的官方包 `@deepseek-ai/dsh-deepseek-account-platform`、`dsh-credentials-local`、`dsh-client-ui-settings-account`。当前不向 Windows 添加此来源。
