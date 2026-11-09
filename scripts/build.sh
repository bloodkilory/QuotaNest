#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/.build/QuotaNest.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" .build/bin
SDK="$(xcrun --sdk macosx --show-sdk-path)"
APP_FLAGS=(-swift-version 5 -O -whole-module-optimization)
for ARCH in arm64 x86_64; do
    swiftc -swift-version 5 -O -whole-module-optimization -sdk "$SDK" -target "$ARCH-apple-macosx13.0" Sources/Localization.swift Sources/UpdateModels.swift Sources/UpdateHelperContract.swift Sources/UpdateReplacement.swift Helpers/Update/main.swift -o ".build/bin/QuotaNestUpdateHelper-$ARCH"
done
cp -R Resources/*.lproj "$APP/Contents/Resources/"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp assets/PROVIDER-MARKS.md "$APP/Contents/Resources/PROVIDER-MARKS.md"
# Older installed update validators require this resource; it contains no adapter code.
printf '%s\n' '// Compatibility resource for older QuotaNest update validators.' > "$APP/Contents/Resources/qoder-usage.cjs"
lipo -create .build/bin/QuotaNestUpdateHelper-arm64 .build/bin/QuotaNestUpdateHelper-x86_64 -output "$APP/Contents/Resources/quotanest-update-helper"
codesign --force --sign "${SIGNING_IDENTITY:--}" "$APP/Contents/Resources/quotanest-update-helper"
HELPER_DIGEST=$(shasum -a 256 "$APP/Contents/Resources/quotanest-update-helper" | awk '{print $1}')
printf 'enum BundledUpdateHelperIdentity { static let sha256 = "%s" }\n' "$HELPER_DIGEST" > .build/UpdateHelperIdentity.swift
for ARCH in arm64 x86_64; do
    swiftc "${APP_FLAGS[@]}" -sdk "$SDK" -target "$ARCH-apple-macosx13.0" -framework AppKit Sources/*.swift .build/UpdateHelperIdentity.swift -o ".build/bin/QuotaNest-$ARCH"
done
lipo -create .build/bin/QuotaNest-arm64 .build/bin/QuotaNest-x86_64 -output "$APP/Contents/MacOS/QuotaNest"
cp -R assets/provider-marks "$APP/Contents/Resources/"
cp LICENSE "$APP/Contents/Resources/LICENSE"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.codexquota</string>
<key>CFBundleName</key><string>QuotaNest</string>
<key>CFBundleDisplayName</key><string>余度 QuotaNest</string>
<key>CFBundleExecutable</key><string>QuotaNest</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.10.0</string>
<key>CFBundleVersion</key><string>17</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hans</string></array>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 QuotaNest contributors. MIT License.</string>
</dict></plist>
PLIST
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"
echo "$APP"
