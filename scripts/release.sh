#!/usr/bin/env bash
set -euo pipefail

DEFAULT_REPO="iamzjt-front-end/fund-pulse"
PACKAGE_SCRIPT="package"
RELEASE_DIR="release/swift"
APP_BUNDLE="dist/fund-pulse.app"
FRAGMENTS_DIR=".release-notes"
CHANGELOG_PATH="CHANGELOG.md"

REPO="$DEFAULT_REPO"
VERSION=""
VERSION_MODE=""
TAG=""
NOTES_FILE=""
ALLOW_EMPTY_NOTES=0
ASSUME_YES=0
DRY_RUN=0

TASK_STARTED=0
CANCELED=0
LOG_DIR=""
LOG_INDEX=0
TEMP_PATHS=()
PACKAGE_BACKUP=""
METADATA_BACKUP_DIR=""
PACKAGE_CHANGED=0
METADATA_APPLIED=0
RELEASE_COMMITTED=0
REMOTE_REFS_PUSHED=0
DRAFT_CREATED=0

RELEASE_STEPS=(
  "前置检查"
  "版本目标"
  "说明校验"
  "质量验证"
  "构建打包"
  "发布提交"
  "Draft 发布"
  "远端校验"
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
  --notes-file FILE      覆盖 GitHub Release 正文；片段仍写入 Changelog
  --allow-empty-notes    显式允许没有变更片段的纯重新打包发布
  --yes                  跳过交互确认
  --dry-run              完整校验和预览，但不改文件、不构建、不发布
  -h, --help             显示帮助

发布要求：
  - 必须在 main 分支，工作区完全干净，并与 origin/main 一致
  - 业务代码必须提前独立提交，发布脚本不会代为提交业务改动
  - 默认从 .release-notes/*.md 生成中文更新说明
  - 发布提交只包含 package.json、CHANGELOG.md 和已消费的说明片段
  - GitHub Release 先创建为 Draft，远端校验通过后才正式发布

推荐：
  npm run release:dry
  npm run release -- --yes
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      [[ $# -ge 2 ]] || { echo "Missing value for --version" >&2; exit 2; }
      VERSION="$2"
      VERSION_MODE="explicit"
      shift 2
      ;;
    --bump)
      [[ $# -ge 2 ]] || { echo "Missing value for --bump" >&2; exit 2; }
      VERSION_MODE="$2"
      shift 2
      ;;
    --tag)
      [[ $# -ge 2 ]] || { echo "Missing value for --tag" >&2; exit 2; }
      TAG="$2"
      shift 2
      ;;
    --repo)
      [[ $# -ge 2 ]] || { echo "Missing value for --repo" >&2; exit 2; }
      REPO="$2"
      shift 2
      ;;
    --notes-file)
      [[ $# -ge 2 ]] || { echo "Missing value for --notes-file" >&2; exit 2; }
      NOTES_FILE="$2"
      shift 2
      ;;
    --allow-empty-notes)
      ALLOW_EMPTY_NOTES=1
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
  local index=0 marker color label
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

run_validation_progress() {
  local DRY_RUN=0
  run_progress "$@"
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

restore_owned_files() {
  if [[ "$RELEASE_COMMITTED" == 1 ]]; then
    return
  fi
  if [[ "$PACKAGE_CHANGED" == 1 || "$METADATA_APPLIED" == 1 ]]; then
    git restore --staged -- package.json "$CHANGELOG_PATH" "$FRAGMENTS_DIR" >/dev/null 2>&1 || true
  fi
  if [[ "$PACKAGE_CHANGED" == 1 && -n "$PACKAGE_BACKUP" && -f "$PACKAGE_BACKUP" ]]; then
    cp "$PACKAGE_BACKUP" package.json
  fi
  if [[ "$METADATA_APPLIED" == 1 && -n "$METADATA_BACKUP_DIR" ]]; then
    cp "$METADATA_BACKUP_DIR/CHANGELOG.md" "$CHANGELOG_PATH"
    if [[ -d "$METADATA_BACKUP_DIR/fragments" ]]; then
      local fragment
      for fragment in "$METADATA_BACKUP_DIR"/fragments/*.md; do
        [[ -e "$fragment" ]] || continue
        cp "$fragment" "$FRAGMENTS_DIR/$(basename "$fragment")"
      done
    fi
  fi
}

cleanup_and_finish() {
  local status=$?
  local item
  local preserve_recovery_files=0

  if [[ "$status" != 0 ]]; then
    restore_owned_files
    if [[ "$DRAFT_CREATED" == 1 || "$REMOTE_REFS_PUSHED" == 1 ]]; then
      preserve_recovery_files=1
    fi
  fi
  if [[ "$preserve_recovery_files" == 0 ]]; then
    for item in "${TEMP_PATHS[@]:-}"; do
      [[ -n "$item" ]] && rm -rf "$item"
    done
  fi
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
      if [[ "$DRAFT_CREATED" == 1 ]]; then
        printf '%sDraft Release 已保留，请检查后重试。%s\n' "$YELLOW" "$RESET" >&2
        printf '%sRelease notes：%s%s\n' "$YELLOW" "${notes_tmp:-<unknown>}" "$RESET" >&2
        printf '%sManifest：%s%s\n' "$YELLOW" "${manifest_tmp:-<unknown>}" "$RESET" >&2
      elif [[ "$REMOTE_REFS_PUSHED" == 1 ]]; then
        printf '%s发布提交和 tag 已保留，但 Draft Release 尚未创建。%s\n' "$YELLOW" "$RESET" >&2
        printf '%sRelease notes：%s%s\n' "$YELLOW" "${notes_tmp:-<unknown>}" "$RESET" >&2
        printf '%sManifest：%s%s\n' "$YELLOW" "${manifest_tmp:-<unknown>}" "$RESET" >&2
        printf '%sGitHub 恢复后可使用以上说明文件创建 Draft，再上传本次构建产物。%s\n' "$YELLOW" "$RESET" >&2
      elif [[ "$RELEASE_COMMITTED" == 1 ]]; then
        printf '%s发布提交或 tag 已生成，不执行隐式回退。%s\n' "$YELLOW" "$RESET" >&2
      fi
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
  [[ "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

bump_version() {
  local current="$1"
  local mode="$2"
  node - "$current" "$mode" <<'NODE'
const current = process.argv[2];
const mode = process.argv[3];
const parts = current.split(".");
if (parts.length !== 3 || parts.some((part) => !/^\d+$/.test(part))) {
  throw new Error(`Unsupported version: ${current}`);
}

let [major, minor, patch] = parts.map(Number);
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

version_is_greater() {
  local candidate="$1"
  local current="$2"
  node - "$candidate" "$current" <<'NODE'
const candidate = process.argv[2].split(".").map(Number);
const current = process.argv[3].split(".").map(Number);
for (let index = 0; index < 3; index += 1) {
  if (candidate[index] > current[index]) process.exit(0);
  if (candidate[index] < current[index]) process.exit(1);
}
process.exit(1);
NODE
}

write_package_version() {
  local next_version="$1"
  node - "$next_version" <<'NODE'
const fs = require("fs");
const nextVersion = process.argv[2];
const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
pkg.version = nextVersion;
fs.writeFileSync("package.json", `${JSON.stringify(pkg, null, 2)}\n`);
NODE
}

assert_clean_worktree() {
  if [[ -n "$(git status --porcelain=v1 --untracked-files=all)" ]]; then
    echo "工作区必须保持干净；请先独立提交业务代码和 release-note 片段。" >&2
    git status --short >&2
    exit 1
  fi
}

assert_main_is_synced() {
  local branch="$1"
  local local_head remote_head
  local_head="$(git rev-parse HEAD)"
  remote_head="$(git ls-remote origin "refs/heads/${branch}" | awk 'NR == 1 {print $1}')"
  if [[ -z "$remote_head" ]]; then
    echo "远端分支不存在：origin/${branch}" >&2
    exit 1
  fi
  if [[ "$local_head" != "$remote_head" ]]; then
    echo "本地 ${branch} 与 origin/${branch} 不一致，不能发布。" >&2
    echo "local:  ${local_head}" >&2
    echo "remote: ${remote_head}" >&2
    exit 1
  fi
}

tag_exists() {
  local candidate="$1"
  git rev-parse -q --verify "refs/tags/$candidate" >/dev/null 2>&1 && return 0
  git ls-remote --exit-code --tags origin "refs/tags/$candidate" >/dev/null 2>&1 && return 0
  gh release view "$candidate" --repo "$REPO" >/dev/null 2>&1 && return 0
  return 1
}

asset_digest() {
  local artifact="$1"
  shasum -a 256 "$artifact" | awk '{print $1}'
}

remote_asset_digest() {
  local tag="$1"
  local name="$2"
  gh release view "$tag" --repo "$REPO" --json assets --jq ".assets[] | select(.name == \"${name}\") | .digest" 2>/dev/null || true
}

generate_release_metadata() {
  local version="$1"
  local tag="$2"
  local previous_tag="$3"
  local zip_name="$4"
  local zip_sha="$5"
  local dmg_name="$6"
  local dmg_sha="$7"
  local feed_name="$8"
  local feed_sha="$9"
  local release_day="${10}"
  local notes_output="${11}"
  local entry_output="${12}"
  local manifest_output="${13}"

  local command=(
    node scripts/release-notes.mjs generate
    --fragments-dir "$FRAGMENTS_DIR"
    --version "$version"
    --tag "$tag"
    --repository "$REPO"
    --zip-name "$zip_name"
    --zip-sha "$zip_sha"
    --dmg-name "$dmg_name"
    --dmg-sha "$dmg_sha"
    --feed-name "$feed_name"
    --feed-sha "$feed_sha"
    --date "$release_day"
    --notes-output "$notes_output"
    --entry-output "$entry_output"
    --manifest-output "$manifest_output"
  )
  [[ -n "$previous_tag" ]] && command+=(--previous-tag "$previous_tag")
  [[ -n "$NOTES_FILE" ]] && command+=(--notes-file "$NOTES_FILE")
  [[ "$ALLOW_EMPTY_NOTES" == 1 ]] && command+=(--allow-empty)
  "${command[@]}"
}

manifest_file_names() {
  local manifest="$1"
  node - "$manifest" <<'NODE'
const fs = require("fs");
const manifest = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
if (manifest.schemaVersion !== 1 || !Array.isArray(manifest.fragments)) process.exit(2);
for (const item of manifest.fragments) console.log(item.fileName);
NODE
}

verify_fragment_manifest_unchanged() {
  local initial_manifest="$1"
  local final_manifest="$2"
  node - "$initial_manifest" "$final_manifest" <<'NODE'
const fs = require("fs");
const initial = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const final = JSON.parse(fs.readFileSync(process.argv[3], "utf8"));
if (initial.schemaVersion !== 1 || final.schemaVersion !== 1) process.exit(2);
if (JSON.stringify(initial.fragments) !== JSON.stringify(final.fragments)) {
  console.error("release-note fragments changed after initial confirmation.");
  process.exit(1);
}
NODE
}

assert_release_changes_only() {
  local manifest_names_file="$1"
  local line changed_path fragment_name
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    changed_path="${line:3}"
    case "$changed_path" in
      package.json|CHANGELOG.md)
        ;;
      .release-notes/*.md)
        fragment_name="$(basename "$changed_path")"
        if ! grep -Fqx "$fragment_name" "$manifest_names_file"; then
          echo "发布过程中出现了 manifest 之外的说明片段改动：${changed_path}" >&2
          exit 1
        fi
        ;;
      *)
        echo "发布过程中出现了非白名单改动：${changed_path}" >&2
        git status --short >&2
        exit 1
        ;;
    esac
  done < <(git status --porcelain=v1 --untracked-files=all)

  git diff --quiet -- package.json && { echo "package.json 版本未更新。" >&2; exit 1; }
  git diff --quiet -- "$CHANGELOG_PATH" && { echo "CHANGELOG.md 未更新。" >&2; exit 1; }
  return 0
}

stage_release_metadata() {
  local manifest_names_file="$1"
  local fragment_name
  git add -- package.json "$CHANGELOG_PATH"
  while IFS= read -r fragment_name; do
    [[ -n "$fragment_name" ]] || continue
    git add -- "$FRAGMENTS_DIR/$fragment_name"
  done < "$manifest_names_file"
}

assert_staged_release_paths_only() {
  local manifest_names_file="$1"
  local staged_names_file="$2"
  local changed_path fragment_name expected
  git diff --cached --name-only >"$staged_names_file"
  while IFS= read -r changed_path; do
    [[ -n "$changed_path" ]] || continue
    case "$changed_path" in
      package.json|CHANGELOG.md)
        ;;
      .release-notes/*.md)
        fragment_name="$(basename "$changed_path")"
        grep -Fqx "$fragment_name" "$manifest_names_file" || {
          echo "发布提交包含 manifest 之外的片段：${changed_path}" >&2
          exit 1
        }
        ;;
      *)
        echo "发布提交包含非白名单路径：${changed_path}" >&2
        git diff --cached --name-status >&2
        exit 1
        ;;
    esac
  done < "$staged_names_file"

  for expected in package.json "$CHANGELOG_PATH"; do
    grep -Fqx "$expected" "$staged_names_file" || { echo "发布提交缺少：${expected}" >&2; exit 1; }
  done
  while IFS= read -r fragment_name; do
    [[ -n "$fragment_name" ]] || continue
    expected="${FRAGMENTS_DIR}/${fragment_name}"
    grep -Fqx "$expected" "$staged_names_file" || { echo "发布提交缺少已消费片段：${expected}" >&2; exit 1; }
  done < "$manifest_names_file"

  if ! git diff --quiet || [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
    echo "发布提交前仍存在未暂存或未跟踪改动。" >&2
    git status --short >&2
    exit 1
  fi
}

verify_remote_release_body() {
  local tag="$1"
  local expected_file="$2"
  local actual_file="$3"
  gh release view "$tag" --repo "$REPO" --json body --jq '.body' >"$actual_file"
  node - "$expected_file" "$actual_file" <<'NODE'
const fs = require("fs");
const expected = fs.readFileSync(process.argv[2], "utf8").trimEnd();
const actual = fs.readFileSync(process.argv[3], "utf8").trimEnd();
if (expected !== actual) {
  console.error("远端 Release 正文与本地预览不一致。");
  process.exit(1);
}
NODE
}

verify_remote_tag_target() {
  local tag="$1"
  local expected_commit="$2"
  local direct peeled actual
  direct="$(git ls-remote origin "refs/tags/${tag}" | awk 'NR == 1 {print $1}')"
  peeled="$(git ls-remote origin "refs/tags/${tag}^{}" | awk 'NR == 1 {print $1}')"
  actual="${peeled:-$direct}"
  if [[ "$actual" != "$expected_commit" ]]; then
    echo "远端 tag 指向错误：${actual} != ${expected_commit}" >&2
    exit 1
  fi
}

verify_remote_assets() {
  local tag="$1"
  local zip_name="$2"
  local zip_sha="$3"
  local dmg_name="$4"
  local dmg_sha="$5"
  local feed_name="$6"
  local feed_sha="$7"
  local remote_zip remote_dmg remote_feed
  remote_zip="$(remote_asset_digest "$tag" "$zip_name")"
  remote_dmg="$(remote_asset_digest "$tag" "$dmg_name")"
  remote_feed="$(remote_asset_digest "$tag" "$feed_name")"
  [[ "$remote_zip" == "sha256:${zip_sha}" ]] || { echo "远端 ZIP SHA 不一致。" >&2; exit 1; }
  [[ "$remote_dmg" == "sha256:${dmg_sha}" ]] || { echo "远端 DMG SHA 不一致。" >&2; exit 1; }
  [[ "$remote_feed" == "sha256:${feed_sha}" ]] || { echo "远端 latest-mac.yml SHA 不一致。" >&2; exit 1; }
}

verify_remote_release() {
  local expected_draft="$1"
  local draft_state release_name prerelease_state asset_names expected_asset_names
  draft_state="$(gh release view "$target_tag" --repo "$REPO" --json isDraft --jq '.isDraft')"
  [[ "$draft_state" == "$expected_draft" ]] || { echo "远端 Draft 状态不正确：${draft_state}" >&2; exit 1; }
  release_name="$(gh release view "$target_tag" --repo "$REPO" --json name --jq '.name')"
  [[ "$release_name" == "fund-pulse ${target_tag}" ]] || { echo "远端 Release 标题不正确。" >&2; exit 1; }
  prerelease_state="$(gh release view "$target_tag" --repo "$REPO" --json isPrerelease --jq '.isPrerelease')"
  [[ "$prerelease_state" == "false" ]] || { echo "远端 Release 不应为 prerelease。" >&2; exit 1; }
  asset_names="$(gh release view "$target_tag" --repo "$REPO" --json assets --jq '.assets[].name' | sort)"
  expected_asset_names="$(printf '%s\n%s\n%s\n' "$dmg_name" "$feed_name" "$zip_name" | sort)"
  [[ "$asset_names" == "$expected_asset_names" ]] || { echo "远端 Release 资产集合不正确。" >&2; exit 1; }
  verify_remote_release_body "$target_tag" "$notes_tmp" "$remote_body_tmp"
  verify_remote_tag_target "$target_tag" "$release_commit"
  verify_remote_assets "$target_tag" "$zip_name" "$zip_sha" "$dmg_name" "$dmg_sha" "$feed_name" "$feed_sha"
}

task_start

set_step 1
for command_name in git gh node npm swift shasum codesign security plutil; do
  require_cmd "$command_name"
done

if [[ ! -d .git || ! -f package.json || ! -f Package.swift || ! -f scripts/release-notes.mjs ]]; then
  echo "请在 fund-pulse 仓库根目录运行 scripts/release.sh。" >&2
  exit 1
fi

current_branch="$(git branch --show-current)"
if [[ -z "$current_branch" ]]; then
  echo "当前处于 detached HEAD，不能发布。" >&2
  exit 1
fi
if [[ "$current_branch" != "main" ]]; then
  echo "只能从 main 分支发布，当前分支：${current_branch}" >&2
  exit 1
fi
if [[ "$VERSION_MODE" != "" && "$VERSION_MODE" != "explicit" && "$VERSION_MODE" != "patch" && "$VERSION_MODE" != "minor" && "$VERSION_MODE" != "major" ]]; then
  echo "不支持的 --bump 类型：$VERSION_MODE" >&2
  exit 1
fi
if [[ -n "$NOTES_FILE" ]]; then
  if [[ ! -f "$NOTES_FILE" ]]; then
    echo "notes 文件不存在或不是普通文件：$NOTES_FILE" >&2
    exit 1
  fi
  notes_absolute="$(cd "$(dirname "$NOTES_FILE")" && pwd)/$(basename "$NOTES_FILE")"
  fragments_absolute="$(pwd)/${FRAGMENTS_DIR}"
  case "$notes_absolute" in
    "$fragments_absolute"/*)
      echo "--notes-file 不能位于 ${FRAGMENTS_DIR} 内，避免发布时被消费。" >&2
      exit 1
      ;;
  esac
  NOTES_FILE="$notes_absolute"
fi

assert_clean_worktree
step_note "检查 GitHub 登录"
gh auth status >/dev/null
step_note "检查 main 与 origin/main"
assert_main_is_synced "$current_branch"

if [[ "$DRY_RUN" != 1 && -z "$(security find-identity -p codesigning -v | sed -n 's/.*\"\(Developer ID Application:[^\"]*\)\".*/\1/p; s/.*\"\(Apple Development:[^\"]*\)\".*/\1/p' | head -n 1)" ]]; then
  echo "未找到可用签名证书，无法生成发布包。" >&2
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
if [[ "$target_version" == "$current_version" ]]; then
  echo "目标版本必须高于当前版本；请使用 --bump 或 --version。" >&2
  exit 1
fi
if ! version_is_greater "$target_version" "$current_version"; then
  echo "目标版本必须高于当前版本：${target_version} <= ${current_version}" >&2
  exit 1
fi

target_tag="${TAG:-v${target_version}}"
if [[ "$target_tag" != "v${target_version}" ]]; then
  echo "发布 tag 必须与版本一致：v${target_version}" >&2
  exit 1
fi
if tag_exists "$target_tag"; then
  echo "tag 或 release 已存在：$target_tag" >&2
  exit 1
fi

last_release_tag="$(gh release list --repo "$REPO" --limit 1 --json tagName --jq '.[0].tagName' 2>/dev/null || true)"
if [[ -z "$last_release_tag" || "$last_release_tag" == "null" ]] || ! git rev-parse -q --verify "${last_release_tag}^{commit}" >/dev/null 2>&1; then
  last_release_tag="$(git describe --tags --abbrev=0 HEAD 2>/dev/null || true)"
fi

arch="$(uname -m)"
zip_path="${RELEASE_DIR}/fund-pulse-${target_version}-${arch}-swift.zip"
dmg_path="${RELEASE_DIR}/fund-pulse-${target_version}-${arch}-swift.dmg"
feed_path="${RELEASE_DIR}/latest-mac.yml"
zip_name="$(basename "$zip_path")"
dmg_name="$(basename "$dmg_path")"
feed_name="$(basename "$feed_path")"
release_day="$(date -u +%Y-%m-%d)"
release_timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

print_box "Release target" "Repo:      $REPO
Branch:    $current_branch
Version:   $target_version
Tag:       $target_tag
Previous:  ${last_release_tag:-<none>}
ZIP:       $zip_name
DMG:       $dmg_name"

notes_tmp="$(mktemp -t fund-pulse-release-notes.XXXXXX)"
entry_tmp="$(mktemp -t fund-pulse-changelog-entry.XXXXXX)"
manifest_tmp="$(mktemp -t fund-pulse-release-manifest.XXXXXX)"
initial_manifest_tmp="$(mktemp -t fund-pulse-initial-manifest.XXXXXX)"
manifest_names_tmp="$(mktemp -t fund-pulse-manifest-names.XXXXXX)"
staged_names_tmp="$(mktemp -t fund-pulse-staged-names.XXXXXX)"
remote_body_tmp="$(mktemp -t fund-pulse-remote-body.XXXXXX)"
TEMP_PATHS+=("$notes_tmp" "$entry_tmp" "$manifest_tmp" "$initial_manifest_tmp" "$manifest_names_tmp" "$staged_names_tmp" "$remote_body_tmp")

set_step 3
generate_release_metadata "$target_version" "$target_tag" "$last_release_tag" "$zip_name" "dry-run" "$dmg_name" "dry-run" "$feed_name" "dry-run" "$release_day" "$notes_tmp" "$entry_tmp" "$initial_manifest_tmp" >/dev/null
print_box "Release notes preview" "$(cat "$notes_tmp")"
confirm "确认发布 ${target_tag}？" || cancel_release

if [[ "$DRY_RUN" == 1 ]]; then
  set_step 4
  run_validation_progress "运行发布说明测试" "发布说明测试通过" npm run test:release:unit
  run_validation_progress "运行 Swift 测试" "Swift 测试通过" swift test
  run_validation_progress "检查 diff 空白" "diff 检查通过" git diff --check
  set_step 5
  step_note "DRY-RUN: package.json ${current_version} -> ${target_version}"
  run_progress "构建发布包" "发布包已生成" npm run "$PACKAGE_SCRIPT"
  set_step 6
  step_note "DRY-RUN: 更新 CHANGELOG.md 并消费 manifest 中的片段"
  run_dry git add -- package.json CHANGELOG.md ".release-notes/<manifest-files>"
  run_dry git commit -m "chore: release ${target_tag}"
  set_step 7
  run_dry git tag -a "$target_tag" -m "fund-pulse ${target_tag}"
  run_dry git push --atomic origin "$current_branch" "refs/tags/${target_tag}"
  run_dry gh release create "$target_tag" "$zip_path" "$dmg_path" "$feed_path" --repo "$REPO" --target "<release-commit>" --title "fund-pulse ${target_tag}" --notes-file "$notes_tmp" --draft
  set_step 8
  step_note "DRY-RUN: 校验正文、tag、三个资产和 latest-mac.yml 后正式发布"
  run_dry gh release edit "$target_tag" --repo "$REPO" --draft=false --latest
  CURRENT_STEP="${#RELEASE_STEPS[@]}"
  progress_bar
  echo
  echo "DRY-RUN 完成：${target_tag}"
  exit 0
fi

set_step 4
run_progress "运行发布说明测试" "发布说明测试通过" npm run test:release:unit
run_progress "运行 Swift 测试" "Swift 测试通过" swift test
run_progress "检查 diff 空白" "diff 检查通过" git diff --check
assert_clean_worktree

set_step 5
PACKAGE_BACKUP="$(mktemp -t fund-pulse-package-backup.XXXXXX)"
TEMP_PATHS+=("$PACKAGE_BACKUP")
cp package.json "$PACKAGE_BACKUP"
write_package_version "$target_version"
PACKAGE_CHANGED=1
run_progress "构建发布包" "发布包已生成" npm run "$PACKAGE_SCRIPT"

cat >"$feed_path" <<EOF
version: ${target_version}
files:
  - url: ${zip_name}
releaseDate: '${release_timestamp}'
EOF

for artifact in "$zip_path" "$dmg_path" "$feed_path"; do
  if [[ ! -f "$artifact" ]]; then
    echo "缺少发布产物：$artifact" >&2
    exit 1
  fi
done
run_progress "校验 app 签名" "app 签名有效" codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
run_progress "校验 dmg 签名" "dmg 签名有效" codesign --verify --verbose=2 "$dmg_path"
app_version="$(plutil -extract CFBundleShortVersionString raw -o - "$APP_BUNDLE/Contents/Info.plist")"
if [[ "$app_version" != "$target_version" ]]; then
  echo "App 版本不正确：${app_version} != ${target_version}" >&2
  exit 1
fi

zip_sha="$(asset_digest "$zip_path")"
dmg_sha="$(asset_digest "$dmg_path")"
feed_sha="$(asset_digest "$feed_path")"
generate_release_metadata "$target_version" "$target_tag" "$last_release_tag" "$zip_name" "$zip_sha" "$dmg_name" "$dmg_sha" "$feed_name" "$feed_sha" "$release_day" "$notes_tmp" "$entry_tmp" "$manifest_tmp" >/dev/null
verify_fragment_manifest_unchanged "$initial_manifest_tmp" "$manifest_tmp"
manifest_file_names "$manifest_tmp" >"$manifest_names_tmp"
print_box "Final release notes" "$(cat "$notes_tmp")"

set_step 6
METADATA_BACKUP_DIR="$(mktemp -d -t fund-pulse-release-metadata-backup.XXXXXX)"
TEMP_PATHS+=("$METADATA_BACKUP_DIR")
cp "$CHANGELOG_PATH" "$METADATA_BACKUP_DIR/CHANGELOG.md"
mkdir -p "$METADATA_BACKUP_DIR/fragments"
if [[ -d "$FRAGMENTS_DIR" ]]; then
  cp "$FRAGMENTS_DIR"/*.md "$METADATA_BACKUP_DIR/fragments/" 2>/dev/null || true
fi
step_note "写入 CHANGELOG.md 并消费已确认片段"
node scripts/release-notes.mjs apply --fragments-dir "$FRAGMENTS_DIR" --changelog "$CHANGELOG_PATH" --entry-file "$entry_tmp" --manifest-file "$manifest_tmp" --version "$target_version" >/dev/null
METADATA_APPLIED=1
step_note "校验发布改动白名单"
assert_release_changes_only "$manifest_names_tmp"
step_note "仅暂存发布元数据"
stage_release_metadata "$manifest_names_tmp"
step_note "校验发布提交精确路径"
assert_staged_release_paths_only "$manifest_names_tmp" "$staged_names_tmp"
step_note "校验已暂存差异"
git diff --cached --check
run_progress "提交发布元数据" "发布提交已创建" git commit -m "chore: release ${target_tag}"
RELEASE_COMMITTED=1
release_commit="$(git rev-parse HEAD)"
run_progress "创建发布 tag" "发布 tag 已创建" git tag -a "$target_tag" -m "fund-pulse ${target_tag}"

set_step 7
run_progress "原子推送 main 和 tag" "main 和 tag 已推送" git push --atomic origin "$current_branch" "refs/tags/${target_tag}"
REMOTE_REFS_PUSHED=1
run_progress "创建 Draft Release" "Draft Release 已创建" gh release create "$target_tag" --repo "$REPO" --target "$release_commit" --title "fund-pulse ${target_tag}" --notes-file "$notes_tmp" --draft
DRAFT_CREATED=1
run_progress "上传 Release 资产" "Release 资产已上传" gh release upload "$target_tag" "$zip_path" "$dmg_path" "$feed_path" --repo "$REPO" --clobber

set_step 8
verify_remote_release "true"
verify_dir="$(mktemp -d -t fund-pulse-release-verify.XXXXXX)"
TEMP_PATHS+=("$verify_dir")
gh release download "$target_tag" --repo "$REPO" --pattern "$feed_name" --dir "$verify_dir" --clobber >/dev/null
if ! grep -q "version: ${target_version}" "${verify_dir}/${feed_name}"; then
  echo "远端 latest-mac.yml 版本不正确。" >&2
  exit 1
fi
run_progress "正式发布 Release" "Release 已正式发布" gh release edit "$target_tag" --repo "$REPO" --draft=false --latest
verify_remote_release "false"
latest_tag="$(gh api "repos/${REPO}/releases/latest" --jq '.tag_name')"
[[ "$latest_tag" == "$target_tag" ]] || { echo "Latest Release 未指向 ${target_tag}。" >&2; exit 1; }

assert_clean_worktree
release_url="$(gh release view "$target_tag" --repo "$REPO" --json url --jq '.url')"
CURRENT_STEP="${#RELEASE_STEPS[@]}"
progress_bar

echo
echo "发布完成：${target_tag}"
echo "Release：${release_url}"
echo "Commit：${release_commit}"
echo "ZIP：${zip_path}"
echo "ZIP SHA-256：${zip_sha}"
echo "DMG：${dmg_path}"
echo "DMG SHA-256：${dmg_sha}"
