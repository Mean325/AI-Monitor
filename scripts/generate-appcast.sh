#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="${1:-$ROOT_DIR/dist}"
VERSION_INFO="$($ROOT_DIR/scripts/version.sh current)"
VERSION="${VERSION_INFO%% *}"
TAG="${2:-v$VERSION}"
ARCHIVE_NAME="CodexLinxDisplay-v$VERSION"
TOOLS_BUILD_DIR="$ROOT_DIR/.release/sparkle-tools"
TOOLS_DIR="$TOOLS_BUILD_DIR/SourcePackages/artifacts/sparkle/Sparkle/bin"
WORK_DIR="$ROOT_DIR/.release/appcast"
DOWNLOAD_URL="https://github.com/Mean325/AI-Monitor/releases/download/$TAG/"
PROJECT_URL="https://github.com/Mean325/AI-Monitor"

if [[ -z "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  echo "缺少 SPARKLE_PRIVATE_KEY，无法签名更新包。" >&2
  exit 1
fi

if [[ ! -x "$TOOLS_DIR/generate_appcast" ]]; then
  DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
    xcodebuild \
      -resolvePackageDependencies \
      -project "$ROOT_DIR/CodexLinxDisplay.xcodeproj" \
      -scheme CodexLinxDisplay \
      -derivedDataPath "$TOOLS_BUILD_DIR"
fi

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
cp "$DIST_DIR/$ARCHIVE_NAME.zip" "$WORK_DIR/"
cp "$ROOT_DIR/CHANGELOG.md" "$WORK_DIR/$ARCHIVE_NAME.md"

printf '%s' "$SPARKLE_PRIVATE_KEY" | "$TOOLS_DIR/generate_appcast" \
  --ed-key-file - \
  --download-url-prefix "$DOWNLOAD_URL" \
  --link "$PROJECT_URL" \
  --maximum-versions 1 \
  --embed-release-notes \
  -o "$WORK_DIR/appcast.xml" \
  "$WORK_DIR"

cp "$WORK_DIR/appcast.xml" "$DIST_DIR/appcast.xml"
echo "更新清单已生成：$DIST_DIR/appcast.xml"
