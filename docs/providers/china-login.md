# ZCode 官方登录适配证据

本实现只复用官方客户端已有登录，不提供 API Key / PAT 输入，不写入或刷新官方凭据。当前支持个人套餐；不自动创建账号、项目或长期 API Key。ZCode Start Plan 已使用本机已有免费账号验证；ZCode 付费 Coding Plan 的验证范围仍为官方源码与合成 测试数据、编译及传输边界测试。

## ZCode / BigModel（国内个人 Coding Plan）

核对官方 zai-org/ZCode，提交 `aac4755666d09fdcd70272fcf063c077a639015f`，仓库版本 3.15.1。

- [官方用户文档](https://zcode.z.ai/cn/docs/configuration)：BigModel 可通过账号授权绑定套餐，独立于 API Key 接入模式。
- [存储路径](https://github.com/zai-org/ZCode/blob/aac4755666d09fdcd70272fcf063c077a639015f/packages/services/src/paths.ts) 与 [credentialService](https://github.com/zai-org/ZCode/blob/aac4755666d09fdcd70272fcf063c077a639015f/packages/services/src/credential/credentialService.ts)：`<ZCODE_DATA_BASE_DIR 或 home>/.zcode/v2/credentials.json`，读取 `oauth:bigmodel:access_token`。
- [加密格式](https://github.com/zai-org/ZCode/blob/aac4755666d09fdcd70272fcf063c077a639015f/packages/services/src/credential/providers/credentialCipherProvider.ts)：`enc:v1:<iv>.<tag>.<ciphertext>`，均 base64url；AES-256-GCM，key=SHA256(`ZCODE_CREDENTIAL_SECRET` 或 `zcode-credential-fallback:darwin:<homedir>:<username>`)。未加密旧值也被官方兼容。
- [账户请求鉴权](https://github.com/zai-org/ZCode/blob/aac4755666d09fdcd70272fcf063c077a639015f/packages/services/src/model-provider/accountProviderRequestAuthService.ts)：旧属性名 apiKey 不表示用户输入的长期 Key；登录套餐在请求时使用短期 Project Access Token。
- [ProjectAccessTokenClient](https://github.com/zai-org/ZCode/blob/aac4755666d09fdcd70272fcf063c077a639015f/packages/shared/src/project-access-token-client.ts)：GET `https://bigmodel.cn/api/biz/customer/getCustomerInfo`（Authorization 原始 login token），选择非团队项目，优先默认机构/默认项目；GET `/api/biz/v1/organization/{org}/projects/{project}/api_keys` 寻找已有 `name:zcode-api-key` 的 `apiKey` 标识。**本应用删去官方缺失时 POST 创建 Key 的分支，缺失即提示先在 ZCode 完成初始化。** 仅 POST `/api_keys/{id}/access_tokens`，Bearer login token、JSON 中 `clientType:"zcode"`、`clientVersion` 使用已安装 App 版本（缺失时 3.16.3）。不创建或修改长期 Key，不持久化收到的短期 token。
- [短期 token 响应](https://github.com/zai-org/ZCode/blob/aac4755666d09fdcd70272fcf063c077a639015f/packages/shared/src/project-access-token.ts)：code `0` 或 `200`（允许字符串），data 含 `accessToken`, `tokenType:Bearer`, `expiresIn`, `expiresAt`（**秒**），`enable:false` 拒绝。
- [额度端点](https://github.com/zai-org/ZCode/blob/aac4755666d09fdcd70272fcf063c077a639015f/packages/services/src/usage-stats/providers/bigmodelUsageQuotaProvider.ts)：GET `https://bigmodel.cn/api/monitor/usage/quota/limit`，`authorization:<short-lived project token>`，不加 Bearer。
- [额度 UI 语义](https://github.com/zai-org/ZCode/blob/aac4755666d09fdcd70272fcf063c077a639015f/packages/ui/src/lib/codingPlanQuotaPresentation.ts)：data.limits 中 percentage 是**已用**占比；TOKENS_LIMIT/CREDIT_LIMIT 的 unit=3,number=5 表示 5 小时，unit=6 表示周；TIME_LIMIT unit=5,number=1 是月工具额度。nextResetTime 为毫秒。自然月仅显示月标签，不换算为固定 30 天。

适配器只读个人套餐，未适配 Team Plan 或 Z.ai 海外分支；它们的 token/额度来源不同。登录过期、缺少官方已初始化项目、token 签发关闭会失败并提示在 ZCode 检查，不回退到 API Key 鉴权。


### ZCode 3.16.3 Start Plan

已核对本机安装的官方 3.16.3 `app.asar` 中 `out/host/index.js` 的 Start Plan 实现，并用本机已有免费账号成功查询。先保留上面的付费路径，失败后复用 `credentials.json` 中的 `zcodejwttoken` 和同目录 `telemetry-state.json.deviceMid`。数据目录继续遵循 `ZCODE_DATA_BASE_DIR`。不依据设置中的 `individual-coding-plan` 排除 Start Plan；不改登录、不领取套餐、不缓存 token 或响应。

只发 GET `https://zcode.z.ai/api/v1/zcode-plan/billing/balance?app_version=<已安装版本>`，Bearer 为现有 ZCode JWT。发送官方客户端的版本、平台、`X-Device-Mid`、语言、时区和客户端归属 headers；版本来自已安装 App Info，缺失时用 3.16.3。查询前后核对现有 OAuth、JWT 和 deviceMid 未变化才接收结果。

仅解析关联 active 且未到期的 plan 下实际返回的有效 balances，按套餐/活动名与模型分别展示 `remaining_units / total_units`，真实零保留为 0%，未知计数不生成百分比。`server_time`、`period_end`、`expires_at` 均为秒。daily 映射每日 1440 分钟并显示 `1d`；one_time 保留账期和到期时间，不声称会重置。未来 entitlements 或没有 balances 的活动不会依据 `grant_units` 生成额度。内部关联 ID 不写入展示或诊断快照。

## 本地验证

`Tests/ChinaLogin/main.swift` 使用人工构造且不含真实凭据的 测试数据，覆盖已用语义、周期单位、毫秒/秒边界、失败响应、加密解码、损坏凭据、HTTP header 注入、redirect 拒绝、超过 1 MiB 响应拒绝，以及请求 allowlist 禁止创建长期 Key。请求使用 ephemeral session，无 cookie/cache/credential storage，流式响应最大 1 MiB，单请求有超时；登录文件最大 1 MiB。错误不输出 token、响应体或 credential 文件内容。
