#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_FILE="$ROOT_DIR/Config/Version.xcconfig"

usage() {
  cat <<'EOF'
用法：
  ./scripts/version.sh current
  ./scripts/version.sh set <major.minor.patch> [build]
  ./scripts/version.sh bump <major|minor|patch>
  ./scripts/version.sh verify-tag [v<major.minor.patch>]

set 未指定 build 时会把构建号加 1；bump 会更新语义版本并把构建号加 1。
EOF
}

read_setting() {
  local key="$1"
  awk -F '=' -v key="$key" '
    $1 ~ "^[[:space:]]*" key "[[:space:]]*$" {
      value = $2
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      print value
      exit
    }
  ' "$VERSION_FILE"
}

write_versions() {
  local version="$1"
  local build="$2"
  local temporary
  temporary="$(mktemp "${TMPDIR:-/tmp}/ai-monitor-version.XXXXXX")"
  awk -v version="$version" -v build="$build" '
    /^[[:space:]]*MARKETING_VERSION[[:space:]]*=/ {
      print "MARKETING_VERSION = " version
      next
    }
    /^[[:space:]]*CURRENT_PROJECT_VERSION[[:space:]]*=/ {
      print "CURRENT_PROJECT_VERSION = " build
      next
    }
    { print }
  ' "$VERSION_FILE" > "$temporary"
  mv "$temporary" "$VERSION_FILE"
}

validate_version() {
  local version="$1"
  if [[ ! "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    echo "版本号必须是 major.minor.patch 格式：$version" >&2
    exit 1
  fi
}

validate_build() {
  local build="$1"
  if [[ ! "$build" =~ '^[1-9][0-9]*$' ]]; then
    echo "构建号必须是正整数：$build" >&2
    exit 1
  fi
}

current_version="$(read_setting MARKETING_VERSION)"
current_build="$(read_setting CURRENT_PROJECT_VERSION)"

if [[ -z "$current_version" || -z "$current_build" ]]; then
  echo "无法从 $VERSION_FILE 读取版本信息。" >&2
  exit 1
fi

command="${1:-current}"
case "$command" in
  current)
    if (( $# > 1 )); then usage >&2; exit 1; fi
    echo "$current_version ($current_build)"
    ;;
  set)
    if (( $# < 2 || $# > 3 )); then usage >&2; exit 1; fi
    next_version="$2"
    next_build="${3:-$((current_build + 1))}"
    validate_version "$next_version"
    validate_build "$next_build"
    write_versions "$next_version" "$next_build"
    echo "版本已更新为 $next_version ($next_build)"
    ;;
  bump)
    if (( $# != 2 )); then usage >&2; exit 1; fi
    IFS=. read -r major minor patch <<< "$current_version"
    case "$2" in
      major) next_version="$((major + 1)).0.0" ;;
      minor) next_version="$major.$((minor + 1)).0" ;;
      patch) next_version="$major.$minor.$((patch + 1))" ;;
      *) usage >&2; exit 1 ;;
    esac
    next_build="$((current_build + 1))"
    write_versions "$next_version" "$next_build"
    echo "版本已更新为 $next_version ($next_build)"
    ;;
  verify-tag)
    if (( $# > 2 )); then usage >&2; exit 1; fi
    tag="${2:-${GITHUB_REF_NAME:-}}"
    if [[ -z "$tag" ]]; then
      echo "未提供 Git 标签。" >&2
      exit 1
    fi
    if [[ "$tag" != "v$current_version" ]]; then
      echo "Git 标签 $tag 与应用版本 v$current_version 不一致。" >&2
      exit 1
    fi
    echo "版本校验通过：$tag ($current_build)"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
