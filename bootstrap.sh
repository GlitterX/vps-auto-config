#!/usr/bin/env bash

set -euo pipefail

resolve_script_dir() {
  local script_path="${1:-}"

  if [[ -z "$script_path" ]]; then
    return 1
  fi

  cd "$(dirname "$script_path")" && pwd
}

bootstrap_should_run_main() {
  local script_source="${1:-}"
  local shell_argv0="${2:-}"

  [[ -z "$script_source" || "$script_source" == "$shell_argv0" ]]
}

SCRIPT_SOURCE_PATH="${BASH_SOURCE[0]-}"
SCRIPT_DIR=""
if [[ -n "$SCRIPT_SOURCE_PATH" ]]; then
  SCRIPT_DIR="$(resolve_script_dir "$SCRIPT_SOURCE_PATH")"
fi
BOOTSTRAP_REF="${BOOTSTRAP_REF:-main}"
BOOTSTRAP_GITHUB_REPO="${BOOTSTRAP_GITHUB_REPO:-}"
BOOTSTRAP_ARCHIVE_URL="${BOOTSTRAP_ARCHIVE_URL:-}"
BOOTSTRAP_DEFAULT_GITHUB_REPO="${BOOTSTRAP_DEFAULT_GITHUB_REPO:-GlitterX/vps-auto-config}"

log() {
  printf '[bootstrap] %s\n' "$*" >&2
}

has_command() {
  command -v "$1" >/dev/null 2>&1
}

build_github_archive_url() {
  local repo="$1"
  local ref="$2"

  printf 'https://codeload.github.com/%s/tar.gz/refs/heads/%s\n' "$repo" "$ref"
}

resolve_repo_from_remote() {
  local target_dir="$1"
  local remote
  local repo

  if ! has_command git || ! git -C "$target_dir" config --get remote.origin.url >/dev/null 2>&1; then
    return 1
  fi

  remote="$(git -C "$target_dir" config --get remote.origin.url)"
  repo="$(printf '%s' "$remote" | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')"

  if [[ -z "$repo" || "$repo" != */* ]]; then
    return 1
  fi

  printf '%s\n' "$repo"
}

resolve_archive_url() {
  local repo

  if [[ -n "$BOOTSTRAP_ARCHIVE_URL" ]]; then
    printf '%s\n' "$BOOTSTRAP_ARCHIVE_URL"
    return 0
  fi

  if [[ -n "$BOOTSTRAP_GITHUB_REPO" ]]; then
    build_github_archive_url "$BOOTSTRAP_GITHUB_REPO" "$BOOTSTRAP_REF"
    return 0
  fi

  if repo="$(resolve_repo_from_remote "$SCRIPT_DIR")"; then
    build_github_archive_url "$repo" "$BOOTSTRAP_REF"
    return 0
  fi

  if [[ -n "$BOOTSTRAP_DEFAULT_GITHUB_REPO" ]]; then
    build_github_archive_url "$BOOTSTRAP_DEFAULT_GITHUB_REPO" "$BOOTSTRAP_REF"
    return 0
  fi

  return 1
}

download_archive() {
  local url="$1"
  local target="$2"

  if has_command curl; then
    curl -fsSL "$url" -o "$target"
    return 0
  fi

  if has_command wget; then
    wget -qO "$target" "$url"
    return 0
  fi

  log "未找到 curl 或 wget，无法下载脚本包。"
  return 1
}

run_local_install() {
  if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/install.sh" && -d "$SCRIPT_DIR/lib" && -d "$SCRIPT_DIR/modules" ]]; then
    log "检测到本地仓库，直接执行 install.sh"
    exec bash "$SCRIPT_DIR/install.sh" "$@"
  fi
}

main() {
  local tmpdir
  local archive
  local archive_url
  local extracted_root

  run_local_install "$@"

  if ! archive_url="$(resolve_archive_url)"; then
    log "无法推断脚本包地址，请设置 BOOTSTRAP_ARCHIVE_URL 或 BOOTSTRAP_GITHUB_REPO。"
    exit 1
  fi

  tmpdir="$(mktemp -d)"
  archive="$tmpdir/vps-auto-config.tar.gz"

  trap 'rm -rf "$tmpdir"' EXIT

  log "下载脚本包：$archive_url"
  download_archive "$archive_url" "$archive"

  tar -xzf "$archive" -C "$tmpdir"
  extracted_root="$(find "$tmpdir" -mindepth 1 -maxdepth 1 -type d | head -n 1)"

  if [[ -z "$extracted_root" || ! -f "$extracted_root/install.sh" ]]; then
    log "脚本包内容不完整，未找到 install.sh"
    exit 1
  fi

  log "启动安装脚本"
  exec bash "$extracted_root/install.sh" "$@"
}

if bootstrap_should_run_main "${BASH_SOURCE[0]-}" "$0"; then
  main "$@"
fi
