# QuotaNest Windows

The Windows client is independent of the Swift/AppKit macOS app. Target: **Windows 11 x64**. No Windows ARM64 or WSL login discovery yet.

Windows 客户端与现有 Mac 版独立，面向 **Windows 11 x64**。本轮不支持 Windows ARM64、WSL 内的登录以及除 Codex / Claude 外其他平台的官方套餐额度。

## Install / 安装

Download `QuotaNest-1.9.2-windows-x64-setup.exe` and `SHA256SUMS.txt` from the [v1.9.2 Release](https://github.com/bloodkilory/QuotaNest/releases/tag/v1.9.2). Check the installer against its matching line in the checksum file, which also lists the Mac DMG, then run the installer. Installation is per user and does not require writing to Program Files.

从上述正式 Release 下载 Windows EXE 和 `SHA256SUMS.txt`，按文件名找到对应摘要，核对 SHA-256 后运行安装程序。校验清单同时包含 Mac DMG。按当前用户安装。安装包没有 Windows 代码签名证书，系统可能显示 SmartScreen 提示；不自动关闭或绕过它。

```powershell
Get-FileHash .\QuotaNest-1.9.2-windows-x64-setup.exe -Algorithm SHA256
```

## Use / 使用

- **Dynamic tray / 动态托盘:** centered remaining number with a hollow progress ring, both in the selected platform color (Codex teal / Claude terracotta / DeepSeek blue). Hover opens compact 240 × 110 read-only usage with inline quota rows; move into the card to keep it open. Left-click opens source/settings/update controls; close or focus loss hides controls. No floating capsule. API balances use a currency symbol without a fake percentage; complete amounts appear on hover. / 数字与进度环随来源刷新，悬停看额度，点击管理来源、设置与更新。
- **Codex:** install the official native Windows CLI and sign in there. QuotaNest invokes `codex.exe app-server` directly, without cmd/PowerShell shell interpolation. Standard PATH and the official npm package's native vendor path are searched. It never falls back to WSL or invokes an unknown `.cmd` shim. If not detected, add the directory containing the official `codex.exe` to PATH and restart QuotaNest.
- **Claude:** select **Claude · Subscription quota / Claude · 套餐余量**. Sign in with `claude auth login` in native Windows Claude Code first. Reads `%USERPROFILE%\.claude\.credentials.json`, or `.credentials.json` under an absolute `CLAUDE_CONFIG_DIR`. Existing subscription OAuth only; API keys and CC Switch tokens do not supply Claude subscription quota. Shows 5-hour, total weekly, Sonnet/Opus weekly groups and reset times. Expired or missing `user:profile` permission requires re-login in the original client; QuotaNest does not refresh or overwrite credentials.
- **DeepSeek:** Settings → CC Switch data directory → Read saved connections; then choose an official DeepSeek connection in the single Display source selector. Existing schema 18–20 Claude Code/Codex configurations are supported. 不手动添加 Key，不改 CC Switch 的任何配置，不声称配置就是实际会话路由。
- Only `https://api.deepseek.com/user/balance` is queried, using the selected saved official credential. Third-party/localhost proxy endpoints are recognized as unsupported rather than sent a balance request. Keys stay in the Rust backend and are not sent to the WebView.
- Startup/manual/every-minute refresh; transient errors keep a marked stale reading. Credential/source changes clear old balances; unknown is never shown as zero.
- **Tray reading / 托盘读数:** click the tray icon, then **Back / 返回** to the detail card. Choose **Automatic / 自动** or any returned model group (Codex models, Claude total, Sonnet, or Opus) with radio buttons, plus the quota period (or wallet currency). Automatic keeps the lowest remaining percentage in the chosen period. Model and period choices are remembered independently per source across refreshes and restarts. If a model has no selected period, its shortest available period is shown; a missing model visibly falls back to Automatic while retaining the saved preference. Unknown selected-model quota stays unknown. Codex lists every returned model bucket and Automatic stays on its main quota; Claude Automatic considers known usage across its groups. / 点击托盘后点返回，在详情中单选显示模型；周期选择保留，数字、进度环、重置时间来自同一模型与周期。
- Language: follow system / English / 中文. Settings include launch at sign-in and manual update. Update checks run on startup and click only. Only formal GitHub Releases with the exact Windows x64 installer and matching SHA-256 are accepted; Mac-only Releases yield no Windows update.

## Verification / 验证边界

CI uses synthetic credentials and database fixtures. It builds the actual Windows installer, runs Rust/frontend tests, installs the app in the runner, drives the native WebView2 with Microsoft Edge WebDriver, saves English/Chinese screenshots, and uninstalls it. Successful CI does **not** prove real account querying or the complete Windows 11 desktop experience.

Release acceptance still needs Windows users to verify: real CC Switch versions/accounts, native Codex login, Clash/proxy behavior, tray position and overflow, 100%/125%/150% DPI, multiple monitors, sign-in startup and upgrade from an earlier installed build. Do not send keys, tokens, full databases, or unredacted account screenshots in bug reports.

## Development / 开发

```sh
cd windows
npm ci --ignore-scripts
npm test
npm run build
cargo test --locked --no-default-features --manifest-path src-tauri/Cargo.toml
npm run tauri dev
# On Windows, with official Tauri prerequisites installed:
npm run tauri build -- --bundles nsis
```

`npm run dev` opens a credential-free UI preview outside Tauri; synthetic data is clearly labeled. Native `QuotaNest.exe --demo` is also fixture-only and does not modify preferences, autostart, or real account configuration. The normal app does not set this flag.

Full comparison with Mac / 与 Mac 逐项差异：[Feature parity](feature-parity.md).
