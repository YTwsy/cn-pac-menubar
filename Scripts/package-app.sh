#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/.build/CNPacMenubar.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
DIRECT_DIR="$ROOT_DIR/.build/direct"

if swift build --package-path "$ROOT_DIR" -c release; then
  BUILT_EXECUTABLE="$ROOT_DIR/.build/release/CNPacMenubar"
  BUILT_CORE_DYLIB=""
else
  echo "swift build failed; falling back to direct swiftc build with explicit SDK." >&2
  SDK_PATH="$(/usr/bin/xcrun --sdk macosx --show-sdk-path 2>/dev/null || printf /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)"
  HOST_ARCH="$(/usr/bin/uname -m)"
  SWIFT_TARGET="${HOST_ARCH}-apple-macos13.0"
  mkdir -p "$DIRECT_DIR"

  core_sources=(
    "$ROOT_DIR/Sources/CNPacMenubarCore/AppSettings.swift"
    "$ROOT_DIR/Sources/CNPacMenubarCore/SettingsStore.swift"
    "$ROOT_DIR/Sources/CNPacMenubarCore/PACRewriter.swift"
    "$ROOT_DIR/Sources/CNPacMenubarCore/PACProxyResolver.swift"
    "$ROOT_DIR/Sources/CNPacMenubarCore/PACServer.swift"
    "$ROOT_DIR/Sources/CNPacMenubarCore/SystemProxyManager.swift"
    "$ROOT_DIR/Sources/CNPacMenubarCore/LauncherManager.swift"
    "$ROOT_DIR/Sources/CNPacMenubarCore/NetworkInterface.swift"
    "$ROOT_DIR/Sources/CNPacMenubarCore/VPNKeepaliveService.swift"
  )

  swiftc \
    -sdk "$SDK_PATH" \
    -target "$SWIFT_TARGET" \
    -parse-as-library \
    -emit-library \
    -emit-module \
    -module-name CNPacMenubarCore \
    -emit-module-path "$DIRECT_DIR/CNPacMenubarCore.swiftmodule" \
    -Xlinker -install_name \
    -Xlinker "@executable_path/../Frameworks/libCNPacMenubarCore.dylib" \
    -o "$DIRECT_DIR/libCNPacMenubarCore.dylib" \
    "${core_sources[@]}"

  swiftc \
    -sdk "$SDK_PATH" \
    -target "$SWIFT_TARGET" \
    -I "$DIRECT_DIR" \
    -L "$DIRECT_DIR" \
    -lCNPacMenubarCore \
    -Xlinker -rpath \
    -Xlinker "@executable_path/../Frameworks" \
    "$ROOT_DIR/Sources/CNPacMenubar/AppDelegate.swift" \
    "$ROOT_DIR/Sources/CNPacMenubar/main.swift" \
    -o "$DIRECT_DIR/CNPacMenubar"

  BUILT_EXECUTABLE="$DIRECT_DIR/CNPacMenubar"
  BUILT_CORE_DYLIB="$DIRECT_DIR/libCNPacMenubarCore.dylib"
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$FRAMEWORKS_DIR"
cp "$BUILT_EXECUTABLE" "$MACOS_DIR/CNPacMenubar"
if [[ -n "$BUILT_CORE_DYLIB" ]]; then
  cp "$BUILT_CORE_DYLIB" "$FRAMEWORKS_DIR/libCNPacMenubarCore.dylib"
fi

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>CN PAC Menubar</string>
  <key>CFBundleDisplayName</key><string>CN PAC Menubar</string>
  <key>CFBundleIdentifier</key><string>local.cn-pac-menubar</string>
  <key>CFBundleExecutable</key><string>CNPacMenubar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

chmod +x "$MACOS_DIR/CNPacMenubar"
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
echo "$APP_DIR"
