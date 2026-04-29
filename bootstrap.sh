#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_REF="${BOOTSTRAP_REF:-main}"
BOOTSTRAP_GITHUB_REPO="${BOOTSTRAP_GITHUB_REPO:-}"
BOOTSTRAP_ARCHIVE_URL="${BOOTSTRAP_ARCHIVE_URL:-}"

log() {
  printf '[bootstrap] %s\n' "$*" >&2
}

has_command() {
  command -v "$1" >/dev/null 2>&1
}

resolve_archive_url() {
  if [[ -n "$BOOTSTRAP_ARCHIVE_URL" ]]; then
    printf '%s\n' "$BOOTSTRAP_ARCHIVE_URL"
    return 0
  fi

  if [[ -n "$BOOTSTRAP_GITHUB_REPO" ]]; then
    printf 'https://codeload.github.com/%s/tar.gz/refs/heads/%s\n' "$BOOTSTRAP_GITHUB_REPO" "$BOOTSTRAP_REF"
    return 0
  fi

  if has_command git && git -C "$SCRIPT_DIR" config --get remote.origin.url >/dev/null 2>&1; then
    local remote
    local repo

    remote="$(git -C "$SCRIPT_DIR" config --get remote.origin.url)"
    repo="$(printf '%s' "$remote" | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')"
    if [[ -n "$repo" && "$repo" == */* ]]; then
      printf 'https://codeload.github.com/%s/tar.gz/refs/heads/%s\n' "$repo" "$BOOTSTRAP_REF"
      return 0
    fi
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
  if [[ -f "$SCRIPT_DIR/install.sh" && -d "$SCRIPT_DIR/lib" && -d "$SCRIPT_DIR/modules" ]]; then
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

main "$@"
