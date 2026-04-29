#!/usr/bin/env bash

backup_file() {
  local target="$1"
  local timestamp
  local backup_path

  [[ -e "$target" ]] || return 0

  timestamp="$(date '+%Y%m%d%H%M%S')"
  backup_path="${target}.bak.${timestamp}"
  cp -a "$target" "$backup_path"
  log_info "已备份：$target -> $backup_path"
}
