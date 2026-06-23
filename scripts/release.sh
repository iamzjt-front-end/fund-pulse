#!/usr/bin/env bash
set -euo pipefail

DEFAULT_REPO="iamzjt-front-end/fund-pulse"
PACKAGE_SCRIPT="package"
RELEASE_DIR="release/swift"
APP_BUNDLE="dist/fund-pulse.app"

REPO="$DEFAULT_REPO"
VERSION=""
VERSION_MODE=""
TAG=""
NOTES_FILE=""
ASSUME_YES=0
DRY_RUN=0
SKIP_TESTS=0
COMMIT_ALL=0
ALLOW_DIRTY=0
TASK_STARTED=0
CANCELED=0
LOG_DIR=""
LOG_INDEX=0
TEMP_FILES=()

RELEASE_STEPS=(
  "前置检查"
  "版本目标"
  "质量验证"
  "提交推送"
  "构建打包"
  "生成说明"
  "发布上传"
  "校验同步"
)
CURRENT_STEP=0

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RESET=$'\033[0m'
  BOLD=$'\033[1m'
  DIM=$'\033[2m'
  RED=$'\033[38;5;203m'
  GREEN=$'\033[38;5;149m'
  BLUE=$'\033[38;5;81m'
  YELLOW=$'\033[38;5;221m'
  MUTED=$'\033[38;5;245m'
  BG_BLUE=$'\033[48;5;81m\033[38;5;236m'
  BG_GREEN=$'\033[48;5;149m\033[38;5;236m'
else
  RESET=""
  BOLD=""
  DIM=""
  RED=""
  GREEN=""
  BLUE=""
  YELLOW=""
  MUTED=""
  BG_BLUE=""
  BG_GREEN=""
fi

usage() {
  cat <<'EOF'
Usage: scripts/release.sh [options]

Options:
  --version VERSION      使用指定版本，并写入 package.json
  --bump patch|minor|major
                         基于 package.json 自动升级版本
  --tag TAG              指定发布 tag；默认 v<package.json version>
  --repo OWNER/REPO      GitHub 仓库；默认 iamzjt-front-end/fund-pulse
  --notes-file FILE      使用自定义 release notes
  --commit-all           将当前工作区改动一并提交后发布
  --allow-dirty          允许未提交改动存在，但不提交；谨慎使用
  --skip-tests           跳过 swift test
  --yes                  跳过交互确认
  --dry-run              只预览流程，不改文件、不提交、不打包、不发布
  -h, --help             显示帮助

脚本会执行：
  1. 前置检查：仓库、工具、GitHub 登录、签名环境
  2. 版本目标：确定版本、tag、资源名称
  3. 质量验证：swift test、git diff --check
  4. 提交推送：可选提交全部改动，推送 main
  5. 构建打包：调用 npm run package 生成 zip/dmg，并生成 latest-mac.yml
  6. 生成说明：从 git log 和资源摘要生成 release notes
  7. 发布上传：创建 tag/GitHub Release 并上传 zip/dmg/latest-mac.yml
  8. 校验同步：验证远端 asset digest、下载 latest-mac.yml、同步 tags

推荐：
  npm run release:dry
  npm run release -- --bump patch --commit-all
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2:-}"
      VERSION_MODE="explicit"
      shift 2
      ;;
    --bump)
      VERSION_MODE="${2:-}"
      shift 2
      ;;
    --tag)
      TAG="${2:-}"
      shift 2
      ;;
    --repo)
      REPO="${2:-}"
      shift 2
      ;;
    --notes-file)
      NOTES_FILE="${2:-}"
      shift 2
      ;;
    --commit-all)
      COMMIT_ALL=1
      shift
      ;;
    --allow-dirty)
      ALLOW_DIRTY=1
      shift
      ;;
    --skip-tests)
      SKIP_TESTS=1
      shift
      ;;
    --yes)
      ASSUME_YES=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

task_start() {
  TASK_STARTED=1
  printf '\n%s%s fund-pulse release start %s\n' "$BG_BLUE" "$BOLD" "$RESET"
}

task_end() {
  printf '\n%s%s fund-pulse release end %s\n' "$BG_GREEN" "$BOLD" "$RESET"
}

progress_bar() {
  local index=0 marker color
  printf '\n%sRelease progress [%s/%s]%s\n' "$BOLD" "$CURRENT_STEP" "${#RELEASE_STEPS[@]}" "$RESET"
  for label in "${RELEASE_STEPS[@]}"; do
    index=$((index + 1))
    if (( index < CURRENT_STEP )); then
      marker="✓"
      color="$GREEN"
    elif (( index == CURRENT_STEP )); then
      marker="◇"
      color="$BLUE"
    else
      marker="○"
      color="$MUTED"
    fi
    printf '  %s%s%s %s\n' "$color" "$marker" "$RESET" "$label"
  done
}

set_step() {
  CURRENT_STEP="$1"
  progress_bar
}

step_note() {
  printf '%s│%s  %s%s%s\n' "$DIM" "$RESET" "$BLUE" "$1" "$RESET"
}

print_box() {
  local title="$1"
  local body="$2"
  printf '%s│%s\n' "$DIM" "$RESET"
  printf '%s◇%s %s%s%s\n' "$GREEN" "$RESET" "$BOLD" "$title" "$RESET"
  printf '%s┌────────────────────────────────────────%s\n' "$DIM" "$RESET"
  while IFS= read -r line; do
    printf '%s│%s  %s%s%s\n' "$DIM" "$RESET" "$BLUE" "${line:- }" "$RESET"
  done <<< "$body"
  printf '%s└────────────────────────────────────────%s\n' "$DIM" "$RESET"
}

ensure_log_dir() {
  if [[ -z "$LOG_DIR" ]]; then
    LOG_DIR="$(mktemp -d -t fund-pulse-release-logs.XXXXXX)"
  fi
}

slugify_label() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-' | sed 's/^-//;s/-$//'
}

print_log_tail() {
  local log_file="$1"
  printf '%s│%s  %s日志：%s%s\n' "$DIM" "$RESET" "$MUTED" "$log_file" "$RESET" >&2
  if [[ -s "$log_file" ]]; then
    printf '%s│%s  %s最近 100 行输出：%s\n' "$DIM" "$RESET" "$MUTED" "$RESET" >&2
    tail -n 100 "$log_file" >&2
  fi
}

run_dry() {
  printf '+'
  printf ' %q' "$@"
  printf '\n'
}

run_progress() {
  local running_label="$1"
  local done_label="$2"
  shift 2

  if [[ "$DRY_RUN" == 1 ]]; then
    printf '%s│%s  %s◇%s %s%s%s\n' "$DIM" "$RESET" "$GREEN" "$RESET" "$BOLD" "$running_label" "$RESET"
    run_dry "$@"
    return 0
  fi

  ensure_log_dir

  local slug log_file pid status frame_index frame
  slug="$(slugify_label "$running_label")"
  [[ -z "$slug" ]] && slug="command"
  LOG_INDEX=$((LOG_INDEX + 1))
  log_file="${LOG_DIR}/$(printf '%02d' "$LOG_INDEX")-${slug}.log"

  printf '%s│%s\n' "$DIM" "$RESET"

  set +e
  "$@" >"$log_file" 2>&1 &
  pid=$!

  if [[ -t 1 ]]; then
    local frames=("-" "\\" "|" "/")
    frame_index=0
    while kill -0 "$pid" >/dev/null 2>&1; do
      frame="${frames[$frame_index]}"
      printf '\r\033[K%s◇%s %s%s%s %s%s%s' "$GREEN" "$RESET" "$BLUE" "$frame" "$RESET" "$BOLD" "$running_label" "$RESET"
      frame_index=$(((frame_index + 1) % ${#frames[@]}))
      sleep 0.12
    done
  else
    printf '%s◇%s %s...%s %s%s%s\n' "$GREEN" "$RESET" "$BLUE" "$RESET" "$BOLD" "$running_label" "$RESET"
  fi

  wait "$pid"
  status=$?
  set -e

  if [[ "$status" == 0 ]]; then
    if [[ -t 1 ]]; then
      printf '\r\033[K%s◇%s %s✓%s %s%s%s\n' "$GREEN" "$RESET" "$GREEN" "$RESET" "$BOLD" "$done_label" "$RESET"
    else
      printf '%s│%s  %s✓%s %s%s%s\n' "$DIM" "$RESET" "$GREEN" "$RESET" "$BOLD" "$done_label" "$RESET"
    fi
    return 0
  fi

  if [[ -t 1 ]]; then
    printf '\r\033[K%s◇%s %s✕%s %s%s%s\n' "$RED" "$RESET" "$RED" "$RESET" "$BOLD" "$running_label" "$RESET" >&2
  else
    printf '%s│%s  %s✕%s %s%s%s\n' "$DIM" "$RESET" "$RED" "$RESET" "$BOLD" "$running_label" "$RESET" >&2
  fi
  print_log_tail "$log_file"
  return "$status"
}

confirm() {
  local prompt="$1"
  if [[ "$ASSUME_YES" == 1 || "$DRY_RUN" == 1 ]]; then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    echo "非交互环境请加 --yes。" >&2
    exit 1
  fi
  printf '%s│%s\n' "$DIM" "$RESET"
  printf '%s■%s %s%s%s\n' "$YELLOW" "$RESET" "$BOLD" "$prompt" "$RESET"
  read -r -p "  Continue? [y/N] " reply
  [[ "$reply" == "y" || "$reply" == "Y" ]]
}

cancel_release() {
  CANCELED=1
  exit 0
}

cleanup_and_finish() {
  local status=$?
  local file

  for file in "${TEMP_FILES[@]:-}"; do
    [[ -n "$file" ]] && rm -f "$file"
  done

  if [[ -n "$LOG_DIR" ]]; then
    if [[ "$status" == 0 || "$CANCELED" == 1 ]]; then
      rm -rf "$LOG_DIR"
    else
      printf '%sRelease logs: %s%s\n' "$MUTED" "$LOG_DIR" "$RESET" >&2
    fi
  fi

  if [[ "$TASK_STARTED" == 1 ]]; then
    if [[ "$CANCELED" == 1 ]]; then
      printf '\n%sOperation canceled%s\n' "$RED" "$RESET"
    elif [[ "$status" != 0 ]]; then
      printf '\n%sRelease task failed%s\n' "$RED" "$RESET"
    fi
    task_end
  fi
}

trap cleanup_and_finish EXIT

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

package_version() {
  node -p "require('./package.json').version"
}

validate_version() {
  local value="$1"
  [[ "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]
}

bump_version() {
  local current="$1"
  local mode="$2"
  node - "$current" "$mode" <<'NODE'
const current = process.argv[2];
const mode = process.argv[3];
const parts = current.split(".");
if (parts.length < 3 || parts.some((part, index) => index < 3 && !/^\d+$/.test(part))) {
  throw new Error(`Unsupported version: ${current}`);
}
let [major, minor, patch] = parts.slice(0, 3).map(Number);
if (mode === "major") {
  major += 1; minor = 0; patch = 0;
} else if (mode === "minor") {
  minor += 1; patch = 0;
} else if (mode === "patch") {
  patch += 1;
} else {
  throw new Error(`Unsupported bump mode: ${mode}`);
}
console.log(`${major}.${minor}.${patch}`);
NODE
}

write_package_version() {
  local next_version="$1"
  node - "$next_version" <<'NODE'
const fs = require("fs");
const path = "package.json";
const nextVersion = process.argv[2];
const pkg = JSON.parse(fs.readFileSync(path, "utf8"));
pkg.version = nextVersion;
fs.writeFileSync(path, `${JSON.stringify(pkg, null, 2)}\n`);
NODE
}

tag_exists() {
  local candidate="$1"
  git rev-parse -q --verify "refs/tags/$candidate" >/dev/null 2>&1 && return 0
  git ls-remote --exit-code --tags origin "refs/tags/$candidate" >/dev/null 2>&1 && return 0
  gh release view "$candidate" --repo "$REPO" >/dev/null 2>&1 && return 0
  return 1
}

tracked_dirty() {
  [[ -n "$(git status --porcelain --untracked-files=no)" ]]
}

any_dirty() {
  [[ -n "$(git status --porcelain)" ]]
}

release_notes_from_git() {
  local last_tag="$1"
  local range="$2"
  local version="$3"
  local zip_name="$4"
  local zip_sha="$5"
  local dmg_name="$6"
  local dmg_sha="$7"
  local feed_name="$8"
  local feed_sha="$9"
  local changelog

  if [[ -n "$range" ]]; then
    changelog="$(git log "$range" --pretty=format:'- %s（%h）' --no-merges || true)"
  else
    changelog="$(git log --pretty=format:'- %s（%h）' --no-merges || true)"
  fi

  {
    echo "## 更新内容"
    echo
    if [[ -n "$last_tag" ]]; then
      echo "自 ${last_tag} 以来的变更："
      echo
    fi
    if [[ -n "$changelog" ]]; then
      echo "$changelog"
    else
      echo "- 本次发布包含重新打包和发布产物更新。"
    fi
    echo
    echo "## 构建信息"
    echo
    echo "- App 版本：${version}"
    echo "- ZIP：${zip_name}"
    echo "- ZIP SHA-256：${zip_sha}"
    echo "- DMG：${dmg_name}"
    echo "- DMG SHA-256：${dmg_sha}"
    echo "- 更新索引：${feed_name}"
    echo "- 更新索引 SHA-256：${feed_sha}"
  }
}

asset_digest() {
  local path="$1"
  if [[ "$DRY_RUN" == 1 ]]; then
    printf 'dry-run\n'
  else
    shasum -a 256 "$path" | awk '{print $1}'
  fi
}

remote_asset_digest() {
  local tag="$1"
  local name="$2"
  gh release view "$tag" --repo "$REPO" --json assets --jq ".assets[] | select(.name == \"${name}\") | .digest" 2>/dev/null || true
}

task_start

set_step 1
require_cmd git
require_cmd gh
require_cmd node
require_cmd npm
require_cmd swift
require_cmd shasum
require_cmd codesign

if [[ ! -d .git || ! -f package.json || ! -f Package.swift ]]; then
  echo "请在 fund-pulse 仓库根目录运行 scripts/release.sh。" >&2
  exit 1
fi

current_branch="$(git branch --show-current)"
if [[ -z "$current_branch" ]]; then
  echo "当前处于 detached HEAD，不能发布。" >&2
  exit 1
fi

if [[ "$VERSION_MODE" != "" && "$VERSION_MODE" != "explicit" && "$VERSION_MODE" != "patch" && "$VERSION_MODE" != "minor" && "$VERSION_MODE" != "major" ]]; then
  echo "不支持的 --bump 类型：$VERSION_MODE" >&2
  exit 1
fi

if [[ -n "$NOTES_FILE" && ! -f "$NOTES_FILE" ]]; then
  echo "notes 文件不存在：$NOTES_FILE" >&2
  exit 1
fi

run_progress "检查 GitHub 登录" "GitHub 登录正常" gh auth status
run_progress "同步远端标签" "远端标签已同步" git fetch origin --tags --prune --prune-tags

if [[ "$DRY_RUN" != 1 && -z "$(security find-identity -p codesigning -v | sed -n 's/.*\"\(Developer ID Application:[^\"]*\)\".*/\1/p; s/.*\"\(Apple Development:[^\"]*\)\".*/\1/p' | head -n 1)" ]]; then
  echo "未找到可用签名证书，script/package_swift.sh 会无法生成发布包。" >&2
  exit 1
fi

set_step 2
current_version="$(package_version)"
target_version="$current_version"

if [[ "$VERSION_MODE" == "explicit" ]]; then
  target_version="$VERSION"
elif [[ "$VERSION_MODE" == "patch" || "$VERSION_MODE" == "minor" || "$VERSION_MODE" == "major" ]]; then
  target_version="$(bump_version "$current_version" "$VERSION_MODE")"
fi

if ! validate_version "$target_version"; then
  echo "版本号格式不合法：$target_version" >&2
  exit 1
fi

target_tag="${TAG:-v${target_version}}"
arch="$(uname -m)"
zip_path="${RELEASE_DIR}/fund-pulse-${target_version}-${arch}-swift.zip"
dmg_path="${RELEASE_DIR}/fund-pulse-${target_version}-${arch}-swift.dmg"
feed_path="${RELEASE_DIR}/latest-mac.yml"
zip_name="$(basename "$zip_path")"
dmg_name="$(basename "$dmg_path")"
feed_name="$(basename "$feed_path")"

if tag_exists "$target_tag"; then
  echo "tag 或 release 已存在：$target_tag" >&2
  exit 1
fi

if [[ "$target_version" != "$current_version" ]]; then
  if [[ "$DRY_RUN" == 1 ]]; then
    step_note "DRY-RUN: package.json version ${current_version} -> ${target_version}"
  else
    if any_dirty && [[ "$COMMIT_ALL" != 1 && "$ALLOW_DIRTY" != 1 ]]; then
      echo "切版本前存在未提交改动；请先提交，或使用 --commit-all。" >&2
      git status --short >&2
      exit 1
    fi
    write_package_version "$target_version"
  fi
fi

last_release_tag="$(gh release list --repo "$REPO" --limit 1 --json tagName --jq '.[0].tagName' 2>/dev/null || true)"
if [[ -z "$last_release_tag" || "$last_release_tag" == "null" ]]; then
  last_release_tag="$(git describe --tags --abbrev=0 2>/dev/null || true)"
fi
release_range=""
if [[ -n "$last_release_tag" ]] && git rev-parse -q --verify "${last_release_tag}^{commit}" >/dev/null 2>&1; then
  release_range="${last_release_tag}..HEAD"
fi

print_box "Release target" "Repo:    $REPO
Branch:  $current_branch
Version: $target_version
Tag:     $target_tag
Range:   ${release_range:-<all commits>}
ZIP:     $zip_name
DMG:     $dmg_name"

if any_dirty && [[ "$COMMIT_ALL" != 1 && "$ALLOW_DIRTY" != 1 ]]; then
  echo "存在未提交改动。要让脚本一并提交请加 --commit-all；只允许脏工作区请加 --allow-dirty。" >&2
  git status --short >&2
  exit 1
fi

confirm "确认发布 ${target_tag}？" || cancel_release

set_step 3
if [[ "$SKIP_TESTS" == 1 ]]; then
  step_note "已跳过 swift test"
else
  run_progress "运行测试" "测试通过" swift test
fi
run_progress "检查 diff 空白" "diff 检查通过" git diff --check

set_step 4
if any_dirty && [[ "$COMMIT_ALL" == 1 ]]; then
  run_progress "暂存当前改动" "改动已暂存" git add -A
  if [[ "$DRY_RUN" == 1 ]]; then
    step_note "DRY-RUN: 将提交当前工作区改动"
  elif ! git diff --cached --quiet; then
    run_progress "提交发布改动" "发布改动已提交" git commit -m "chore: release ${target_tag}"
  else
    step_note "没有需要提交的改动"
  fi
else
  step_note "没有提交步骤需要执行"
fi

if [[ "$DRY_RUN" == 1 ]]; then
  run_progress "推送 ${current_branch}" "${current_branch} 已推送" git push origin "$current_branch"
else
  run_progress "推送 ${current_branch}" "${current_branch} 已推送" git push origin "$current_branch"
fi

set_step 5
if [[ "$DRY_RUN" == 1 ]]; then
  run_progress "构建发布包" "发布包已生成" npm run "$PACKAGE_SCRIPT"
else
  run_progress "构建发布包" "发布包已生成" npm run "$PACKAGE_SCRIPT"
fi

release_date="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if [[ "$DRY_RUN" == 1 ]]; then
  step_note "DRY-RUN: 写入 ${feed_path}"
else
  cat >"$feed_path" <<EOF
version: ${target_version}
files:
  - url: ${zip_name}
releaseDate: '${release_date}'
EOF
fi

for artifact in "$zip_path" "$dmg_path" "$feed_path"; do
  if [[ "$DRY_RUN" != 1 && ! -f "$artifact" ]]; then
    echo "缺少发布产物：$artifact" >&2
    exit 1
  fi
done

if [[ "$DRY_RUN" != 1 ]]; then
  run_progress "校验 app 签名" "app 签名有效" codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
  run_progress "校验 dmg 签名" "dmg 签名有效" codesign --verify --verbose=2 "$dmg_path"
fi

zip_sha="$(asset_digest "$zip_path")"
dmg_sha="$(asset_digest "$dmg_path")"
feed_sha="$(asset_digest "$feed_path")"

set_step 6
notes_tmp="$(mktemp -t fund-pulse-release-notes.XXXXXX.md)"
TEMP_FILES+=("$notes_tmp")
if [[ -n "$NOTES_FILE" ]]; then
  cp "$NOTES_FILE" "$notes_tmp"
else
  release_notes_from_git "$last_release_tag" "$release_range" "$target_version" "$zip_name" "$zip_sha" "$dmg_name" "$dmg_sha" "$feed_name" "$feed_sha" >"$notes_tmp"
fi
print_box "Release notes preview" "$(cat "$notes_tmp")"

set_step 7
if [[ "$DRY_RUN" == 1 ]]; then
  run_progress "创建 tag" "tag 已创建" git tag -a "$target_tag" -m "fund-pulse ${target_tag}"
  run_progress "推送 tag" "tag 已推送" git push origin "$target_tag"
  run_progress "发布 GitHub Release" "GitHub Release 已发布" gh release create "$target_tag" "$zip_path" "$dmg_path" "$feed_path" --repo "$REPO" --target "$current_branch" --title "fund-pulse ${target_tag}" --notes-file "$notes_tmp" --latest
else
  run_progress "创建 tag" "tag 已创建" git tag -a "$target_tag" -m "fund-pulse ${target_tag}"
  run_progress "推送 tag" "tag 已推送" git push origin "$target_tag"
  run_progress "发布 GitHub Release" "GitHub Release 已发布" gh release create "$target_tag" "$zip_path" "$dmg_path" "$feed_path" --repo "$REPO" --target "$current_branch" --title "fund-pulse ${target_tag}" --notes-file "$notes_tmp" --latest
fi

set_step 8
run_progress "同步本地标签" "本地标签已同步" git fetch origin --tags --prune --prune-tags

release_url=""
if [[ "$DRY_RUN" != 1 ]]; then
  release_url="$(gh release view "$target_tag" --repo "$REPO" --json url --jq '.url')"
  remote_zip_digest="$(remote_asset_digest "$target_tag" "$zip_name")"
  remote_dmg_digest="$(remote_asset_digest "$target_tag" "$dmg_name")"
  remote_feed_digest="$(remote_asset_digest "$target_tag" "$feed_name")"

  if [[ "$remote_zip_digest" != "sha256:${zip_sha}" ]]; then
    echo "远端 ZIP SHA 不一致：${remote_zip_digest} != sha256:${zip_sha}" >&2
    exit 1
  fi
  if [[ "$remote_dmg_digest" != "sha256:${dmg_sha}" ]]; then
    echo "远端 DMG SHA 不一致：${remote_dmg_digest} != sha256:${dmg_sha}" >&2
    exit 1
  fi
  if [[ "$remote_feed_digest" != "sha256:${feed_sha}" ]]; then
    echo "远端 latest-mac.yml SHA 不一致：${remote_feed_digest} != sha256:${feed_sha}" >&2
    exit 1
  fi

  verify_dir="$(mktemp -d -t fund-pulse-release-verify.XXXXXX)"
  TEMP_FILES+=("${verify_dir}/latest-mac.yml")
  gh release download "$target_tag" --repo "$REPO" --pattern "$feed_name" --dir "$verify_dir" --clobber >/dev/null
  if ! grep -q "version: ${target_version}" "${verify_dir}/${feed_name}"; then
    echo "远端 latest-mac.yml 版本不正确。" >&2
    cat "${verify_dir}/${feed_name}" >&2
    exit 1
  fi
fi

CURRENT_STEP="${#RELEASE_STEPS[@]}"
progress_bar

echo
echo "发布完成：${target_tag}"
if [[ -n "$release_url" ]]; then
  echo "Release：${release_url}"
fi
echo "ZIP：${zip_path}"
echo "ZIP SHA-256：${zip_sha}"
echo "DMG：${dmg_path}"
echo "DMG SHA-256：${dmg_sha}"
