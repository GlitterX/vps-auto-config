#!/usr/bin/env bash

APT_UPDATED=0

is_package_installed() {
  dpkg -s "$1" >/dev/null 2>&1
}

apt_update_once() {
  if [[ "$APT_UPDATED" -eq 1 ]]; then
    return 0
  fi

  DEBIAN_FRONTEND=noninteractive apt-get update
  APT_UPDATED=1
}

apt_install_packages() {
  local requested=("$@")
  local missing=()
  local package_name

  [[ ${#requested[@]} -gt 0 ]] || return 0

  for package_name in "${requested[@]}"; do
    if ! is_package_installed "$package_name"; then
      missing+=("$package_name")
    fi
  done

  [[ ${#missing[@]} -gt 0 ]] || return 0

  apt_update_once
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
}

ensure_whiptail() {
  if has_command whiptail; then
    return 0
  fi

  log_info "未检测到 whiptail，开始自动安装。"
  apt_install_packages whiptail
}
