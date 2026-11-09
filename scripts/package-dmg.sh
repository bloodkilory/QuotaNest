#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' .build/QuotaNest.app/Contents/Info.plist)
STAGE=$(mktemp -d "$PWD/.build/dmg.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
cp -R .build/QuotaNest.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/安装说明 - Read me.txt" <<'TXT'
QuotaNest — AI quota, at a glance.

1. Drag QuotaNest.app to Applications. Eject this disk image.
2. Open the installed app. Look for the provider-icon quota capsule in the menu bar.
3. Choose a subscription in “Menu bar shows”. For DeepSeek Harness, sign in to the official app and select its recharge balance. For DeepSeek API balances, connect an existing CC Switch source in Settings.
4. Choose Settings → Language for English / 中文, or enable “Launch at login” in Settings.

拖动 QuotaNest.app 到 Applications 文件夹，推出磁盘，再打开已安装的应用。
应用运行在菜单栏，没有 Dock 图标。请先安装并登录所需平台支持的官方客户端。
在顶部“菜单栏显示”选择套餐余量；DeepSeek Harness 登录后可直接选择充值余额；DeepSeek API 余额先在“设置 → 连接已有工具…”连接 CC Switch 已有配置。
在“设置 → 语言”切换中文 / English；登录启动和应用更新也在设置中。

This community build is ad-hoc signed, not Apple-notarized.
If macOS blocks the first launch, use System Settings → Privacy & Security → Open Anyway for this app.
本构建未经 Apple 公证。首次打开被阻止时，可在系统设置 → 隐私与安全性中为本应用选择“仍要打开”。
Do not disable Gatekeeper globally. 不需要关闭系统的安全保护。
TXT
mkdir -p dist
DMG="dist/QuotaNest-$VERSION-universal.dmg"
hdiutil create -ov -volname QuotaNest -srcfolder "$STAGE" -format UDZO "$DMG"
hdiutil verify "$DMG"
(cd dist && shasum -a 256 "QuotaNest-$VERSION-universal.dmg" > SHA256SUMS.txt)
echo "$PWD/$DMG"
