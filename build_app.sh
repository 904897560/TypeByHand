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
# 图标可选：本地放一个 AppIcon.icns 即可
if [ -f AppIcon.icns ]; then
  cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
codesign --force --sign - "$APP"
echo "built: $APP"
