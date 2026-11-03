# QuotaNest 1.9.1

- Mac 与 Windows 的常规额度/余额查询从每分钟调整为每 2 分钟，中英文界面提示同步。
- 修复 Mac Claude 额度查询收到 HTTP 429 后仍持续请求的问题：优先遵守服务端 `Retry-After`；没有有效等待时间时依次等待 2、4、8、15 分钟，成功后恢复。手动刷新不能绕过等待。
- 查询受限时保留当前进程已有的额度读数，并显示具体重试时间。该调整减少重复请求，不保证服务端限流立即解除。Windows 原有的服务端等待机制保留，本次没有新增递增等待。
- 提供 macOS 通用 DMG、Windows x64 安装包及统一 `SHA256SUMS.txt`。

已在本机 Mac 使用真实 Claude Pro 登录确认安装后的定时查询恢复成功；模拟响应验证了限流等待、重试到期和成功重置。Windows 自动构建使用模拟账号，不代替真实 Windows 11 账号、代理及多屏环境验证。

## English

- Normal quota/balance refresh now runs every 2 minutes on Mac and Windows, with matching Chinese and English UI text.
- Fixed repeated Mac Claude usage requests after HTTP 429: honor `Retry-After`; without a valid delay, wait 2, 4, 8, then 15 minutes. A successful query resets the wait. Manual refresh cannot bypass the cooldown.
- Keep readings already available in the current process and show the retry time while rate limited. This reduces repeat requests; it does not guarantee immediate recovery of the upstream service. Windows retains its existing server-directed wait behavior; increasing fallback waits are Mac-only in this release.
- Includes a universal macOS DMG, a Windows x64 installer, and one combined `SHA256SUMS.txt`.

Verified scheduled query recovery on a local Mac with a real Claude Pro account, plus simulated rate-limit responses. Windows CI uses synthetic accounts; real Windows 11 accounts, proxies and multiple displays still need user validation.

macOS 13+ (Intel / Apple Silicon); Windows 11 x64. Community builds retain ad-hoc/unsigned distribution status.

[中文说明](https://github.com/bloodkilory/QuotaNest/blob/v1.9.1/README.md) · [English documentation](https://github.com/bloodkilory/QuotaNest/blob/v1.9.1/README.en.md)
