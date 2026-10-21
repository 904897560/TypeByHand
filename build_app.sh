#!/bin/zsh
# 用法: ./build_app.sh [输出路径，默认 TypeByHand.app]
set -e
cd "$(dirname "$0")"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/TypeByHand"
APP="${1:-TypeByHand.app}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TypeByHand"
cp Info.plist "$APP/Contents/Info.plist"
# 图标：优先使用仓库内的 Resources/AppIcon.icns
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
codesign --force --sign - "$APP"
echo "built: $APP"
