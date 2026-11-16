#!/bin/bash
# build.sh — 编译并组装 SideDock.app(无需 Xcode,仅命令行工具)
set -euo pipefail
cd "$(dirname "$0")"

ROOT="$PWD"
BUILD="$ROOT/build"
APP="$BUILD/SideDock.app"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"

echo "==> swiftc 编译"
mkdir -p "$BUILD"
swiftc -O \
  -target arm64-apple-macos14.0 \
  -swift-version 5 \
  -framework AppKit -framework SwiftUI -framework Combine \
  -framework LocalAuthentication -framework QuickLookThumbnailing \
  -framework Security -framework ServiceManagement -framework UserNotifications \
  Sources/main.swift Sources/AppState.swift Sources/Panel.swift Sources/Views.swift \
  Sources/Stores.swift Sources/Downloads.swift Sources/ShelfBarController.swift \
  Sources/MusicController.swift Sources/PasteHelper.swift \
  -o "$BUILD/SideDock"

# MediaHelper 以源码分发(必须经 Apple 签名的 /usr/bin/swift 解释执行,
# 自编译二进制会被 MediaRemote 资格检查拒绝,见 MusicController.swift 注释)
cp Sources/MediaHelper.swift "$BUILD/MediaHelper.swift"

echo "==> 组装 .app"
rm -rf "$APP"
mkdir -p "$MACOS" "$RES"
cp "$BUILD/SideDock" "$MACOS/SideDock"
cp "$BUILD/MediaHelper.swift" "$RES/MediaHelper.swift"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> 生成图标(玻璃主题:make_icon 逐尺寸重绘 squircle + iconset)"
swift make_icon.swift "$BUILD"
iconutil -c icns "$BUILD/icon.iconset" -o "$RES/sidedock.icns"

echo "==> ad-hoc 签名"
codesign --force --sign - "$APP"
codesign --verify --verbose=1 "$APP"

echo
echo "完成: $APP"
