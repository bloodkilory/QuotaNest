# Windows / macOS feature parity · 功能核对

Compared against macOS and Windows v1.9.2. “Implemented” means code plus automated tests; Windows tests use synthetic credentials and do not certify real Windows accounts.

核对基准：macOS / Windows v1.9.2。已实现与真实账号验收分开；Windows 自动化使用模拟凭据。

| Feature / 功能 | Mac | Windows v1.9.2 | Result / 差异 |
| --- | --- | --- | --- |
| Codex official model quotas / 官方模型额度 | Yes | Yes, native codex.exe | All returned model buckets are selectable; Automatic keeps main quota / 全部返回模型可选，自动保留主额度口径 |
| Claude official subscription / 官方套餐 | Yes | Added | Existing subscription OAuth; 5h, 7d, Sonnet, Opus; reset time / 本轮新增各额度组、重置时间 |
| Claude credentials / 登录读取 | Desktop account first; verified same-account/organization CLI backup | Native `.credentials.json`; absolute `CLAUDE_CONFIG_DIR` supported | Platform storage differs; no API key/helper/refresh-token execution / 存储方式随平台不同，不代替官方客户端更新登录 |
| CC Switch saved connections | Schema 18–20, read-only | Same | Claude Code/Codex connections; fixed official DeepSeek endpoint / 同一数据范围与固定余额端点 |
| API vs subscription source | Single selector | Same, Claude added | No change to client routing / 不修改客户端实际路由 |
| Decimal CNY/USD balance breakdown | Yes | Yes | No currency sum or fake percentage / 不混算币种，不生成余额百分比 |
| Quota model, period and currency choice | Per-source saved | Per-source model radio + period/currency choice | Automatic uses lowest remaining; an explicit model supplies the number, ring and reset / 自动取最低剩余；指定模型后数字、环和重置时间使用同一额度 |
| Startup/manual/120s data refresh | Yes | Yes | Mac additionally listens for system wake; Windows timer resumes after sleep / Mac 有显式唤醒事件，Windows 恢复后由轮询刷新 |
| Temporary failure | Stale reading + ! | Same | Changed Claude/DeepSeek credentials discard previous values / 官方/API 凭据变化清除旧数据 |
| Codex transient reconnect | One retry in 30s | One bounded attempt | Remaining transport difference / 仍有一次重连差异 |
| Concurrent fetch | Per-provider coordinator | One global worker | Source switch queues new source after bounded previous request / Windows 旧请求完成后立即查询新来源 |
| 中英 / English / system language | Yes | Yes | Tray menu uses bilingual labels; detail/settings switch language / Windows 托盘菜单部分使用双语标签 |
| Glass appearance | System NSPopover backdrop/arrow/corners; inner glass-style cards | WebView CSS glass | Similar visual language; Windows does not implement macOS Liquid Glass / 平台材质不同 |
| Compact always-visible value | 64-point menu-bar capsule | Dynamic numeric ring icon; hover usage; click controls | Windows uses a compact numeric icon and hover card, no desktop capsule / Windows 使用数字环形托盘和悬停卡片 |
| Launch at sign-in | macOS login item | Per-user HKCU Run | Windows installer update preserves preference and Run entry / 按平台实现，升级保留 |
| App updates | Formal GitHub Release + DMG + SHA256; admin if needed | Formal GitHub Release + EXE + SHA256; per-user NSIS | Startup/click checks only; no beta auto-update feed / 内测附件不作为正式更新推送 |
| Local status diagnostic file | `status.json` | Not implemented | Windows CI keeps fixture evidence only / 尚未提供用户诊断文件 |
| WSL logins | N/A | Not supported | Native Windows accounts only / 仅原生登录 |

## Remaining official providers / 其余官方平台

The following sources exist in Mac and are **not implemented on Windows**. They are not shown as selectable Windows sources. Existing Mac experimental labels remain in force.

以下项目在 Windows 尚未适配，不会在来源列表中冒充可用；Mac 的实验适配标记保持原状。

| Provider | Mac implementation reference | Required Windows work / 具体缺口 |
| --- | --- | --- |
| Antigravity | `Sources/OfficialProviders.swift` | Verify native `agy.exe` packaging/version and noninteractive `/usage` command; remove Unix `/usr/bin/env` and browser blocker assumptions / 原生 CLI 与无交互命令验证 |
| Kimi Code (experimental) | `Sources/KimiQuotaClient.swift` | Verify Windows OAuth storage for `.kimi-code`/`.kimi`, then port token expiry and grouped coding/total usage / Windows 登录文件与分组额度解析 |
| ZCode (experimental) | `Sources/ChinaLoginClients.swift` | Verify Windows official credential storage/encryption, project exchange and Start Plan device metadata / 验证登录存储解密、项目会话及免费套餐设备信息 |
| MiniMax Code (experimental) | `Sources/ChinaLoginClients.swift` | Verify Windows data-dir/official OAuth format and signed CN usage requests / 数据目录、OAuth 格式和国内签名请求 |
| Qoder (experimental) | `Sources/QoderQuotaClient.swift` | Windows npm/Node discovery and exact verified WASM helper compatibility; native build unsupported in Mac too / npm 路径、WASM 版本兼容性 |
| CodeBuddy (experimental) | `Sources/CodeBuddyQuotaClient.swift` | Port VS Code Windows secret storage/DPAPI; Mac Keychain/PBKDF decryption cannot be copied / Windows VS Code 凭据解密 |

## Release validation / 发布验证

CI builds/installs the actual x64 NSIS package, upgrades with saved preferences and sign-in registration, drives the installed WebView2, verifies Claude/Codex/API source separation, model radio selection, model/period/currency retention, native Sonnet/Opus tray readings, Chinese/English and uninstall. Claude HTTP tests assert official headers, retry/auth/redirect/429 behavior using synthetic OAuth only.

真实 Windows 11 用户仍需验证：官方 Claude/Codex 登录和订阅权限、CC Switch 真实版本、Clash TUN/代理、睡眠恢复、100/125/150% 缩放、多显示器和登录启动。应用不自动替换官方客户端凭据，也不索要账号 Token。

v1.9.2 差异：macOS 新增 Claude 桌面端优先、同账号及组织的 CLI 备用；Windows 仍使用 Claude Code 登录文件。

v1.9.2: macOS adds Claude Desktop priority with same-account/organization CLI backup. Windows still uses Claude Code credentials.
