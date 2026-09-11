#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_DIR="$ROOT_DIR/.build-dev"
APP_PATH="$DERIVED_DATA_DIR/Build/Products/Debug/AI Monitor.app"
BUNDLE_ID="com.olivia.CodexLinxDisplay"

if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "缺少 XcodeGen，请先执行：brew install xcodegen" >&2
  exit 1
fi

cd "$ROOT_DIR"
xcodegen generate

xcodebuild \
  -project CodexLinxDisplay.xcodeproj \
  -scheme CodexLinxDisplay \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  build \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=YES

if [[ ! -d "$APP_PATH" ]]; then
  echo "构建完成，但未找到应用：$APP_PATH" >&2
  exit 1
fi

# Quit either the installed build or the previous development build before
# opening the exact bundle we just compiled.
/usr/bin/osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
for _ in {1..30}; do
  if ! /usr/bin/pgrep -f "$APP_PATH/Contents/MacOS/AI Monitor" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

/usr/bin/open -n "$APP_PATH"
echo "已启动开发版本：$APP_PATH"
