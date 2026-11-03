# QuotaNest 1.9.2

- **Mac 优先跟随 Claude 桌面端当前账号**，读取桌面端已有的官方 OAuth 登录查询额度；没有桌面账号的机器保留原 Claude Code 查询方式。
- 桌面凭据过期或被官方拒绝时，只有经过官方身份接口确认是同一账号、同一组织，才使用 Claude Code 登录作为备用。不同账号或组织不会混用额度。
- 切换桌面账号或组织时清除旧读数；在途请求若已不属于当前选择则丢弃。详情显示“Claude 桌面端”或“Claude Code 同账号备用”。
- 保留两分钟刷新及共享限流等待。429 不触发凭据轮换，不通过备用来源绕过等待；登录缓存和令牌只读，不发送模型请求。
- **Windows 本次仍使用 Claude Code 登录文件，未新增桌面凭据接入。** 同时提供更新版本号的 Windows x64 安装包、Mac 通用 DMG 和统一 `SHA256SUMS.txt`。

本机 Mac 已使用真实 Claude Desktop 账号验证启动和下一轮自动额度查询。账号/组织隔离、凭据失效和备用切换使用合成数据及模拟 HTTP 验证，未人为破坏真实登录。Windows CI 使用模拟账号验证构建、安装和界面流程，不代替真实 Windows 11 账号及多屏验证。

## English

- **Mac follows the current Claude Desktop account first**, using its existing official OAuth login for usage queries. Machines without a desktop account retain the existing Claude Code path.
- Expired or rejected desktop credentials can use Claude Code only after the official profile confirms the same account and organization. Different accounts or organizations never share readings.
- Switching the desktop account or organization clears old readings and rejects stale in-flight responses. Details show Claude Desktop or Claude Code backup as the active source.
- Two-minute refresh and shared rate-limit waits remain. HTTP 429 never rotates credentials or bypasses cooldown. Official login data stays read-only; no model requests are sent.
- **Windows still uses Claude Code credential files; desktop sign-in integration is Mac-only.** Includes a Windows x64 installer, a universal Mac DMG and one combined `SHA256SUMS.txt`.

A real Claude Desktop account was verified on a local Mac at startup and the next automatic refresh. Account/organization isolation and backup behavior use synthetic credentials and simulated HTTP responses, without invalidating real logins. Windows CI uses synthetic accounts for build/install/UI checks; real Windows 11 accounts and multiple displays remain outside that validation.

macOS 13+ (Intel / Apple Silicon), Windows 11 x64. Community builds remain ad-hoc signed on Mac and commercially unsigned on Windows.

[中文说明](https://github.com/bloodkilory/QuotaNest/blob/v1.9.2/README.md) · [English documentation](https://github.com/bloodkilory/QuotaNest/blob/v1.9.2/README.en.md) · [桌面登录详情](https://github.com/bloodkilory/QuotaNest/blob/v1.9.2/docs/providers/claude-desktop.md)
