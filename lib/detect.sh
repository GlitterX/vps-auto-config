#!/usr/bin/env bash

strip_wrapping_quotes() {
  local value="$1"

  value="${value%\"}"
  value="${value#\"}"
  printf '%s' "$value"
}

has_command() {
  command -v "$1" >/dev/null 2>&1
}

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    printf '请使用 sudo 或 root 用户执行该脚本\n' >&2
    exit 1
  fi
}

ensure_apt_available() {
  if ! has_command apt-get; then
    printf '当前系统缺少 apt-get，无法继续安装。\n' >&2
    exit 1
  fi
}

get_ubuntu_version() {
  local os_release_file="${1:-/etc/os-release}"
  local distro_id=""
  local version_id=""
  local key
  local value

  [[ -f "$os_release_file" ]] || return 1

  while IFS='=' read -r key value; do
    case "$key" in
      ID)
        distro_id="$(strip_wrapping_quotes "$value")"
        ;;
      VERSION_ID)
        version_id="$(strip_wrapping_quotes "$value")"
        ;;
    esac
  done < "$os_release_file"

  if [[ "$distro_id" != "ubuntu" ]]; then
    return 1
  fi

  printf '%s\n' "$version_id"
}

is_supported_ubuntu_version() {
  case "$1" in
    22.04|24.04)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

validate_hostname() {
  local hostname_value="$1"

  [[ -n "$hostname_value" ]] || return 1
  [[ ${#hostname_value} -le 63 ]] || return 1
  [[ "$hostname_value" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]]
}

validate_port() {
  local port="$1"

  [[ "$port" =~ ^[0-9]+$ ]] || return 1
  (( port >= 1 && port <= 65535 ))
}

validate_protocol() {
  case "$1" in
    tcp|udp)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

get_ssh_port() {
  local config_file="${1:-/etc/ssh/sshd_config}"
  local port="22"
  local line

  [[ -f "$config_file" ]] || {
    printf '%s\n' "$port"
    return 0
  }

  while IFS= read -r line; do
    case "$line" in
      Port\ *)
        port="${line#Port }"
        ;;
    esac
  done < "$config_file"

  printf '%s\n' "$port"
}

detect_authorized_key() {
  local user_home="${1:-$HOME}"
  local auth_keys="$user_home/.ssh/authorized_keys"

  [[ -s "$auth_keys" ]]
}

get_current_timezone() {
  if has_command timedatectl; then
    timedatectl show --property=Timezone --value 2>/dev/null || true
    return 0
  fi

  if [[ -f /etc/timezone ]]; then
    cat /etc/timezone
    return 0
  fi

  printf 'UTC\n'
}

detect_swap_type() {
  if ! has_command swapon; then
    printf 'unknown\n'
    return 0
  fi

  local first_entry
  first_entry="$(swapon --show=NAME --noheadings 2>/dev/null | head -n 1 | xargs)"

  if [[ -z "$first_entry" ]]; then
    printf 'none\n'
    return 0
  fi

  if [[ -f "$first_entry" ]]; then
    printf 'swapfile\n'
    return 0
  fi

  printf 'partition\n'
}

normalize_size_to_mb() {
  local raw_size="$1"
  local number
  local unit

  if [[ "$raw_size" =~ ^([0-9]+)([GgMm])$ ]]; then
    number="${BASH_REMATCH[1]}"
    unit="${BASH_REMATCH[2]}"
  else
    return 1
  fi

  case "$unit" in
    G|g)
      printf '%s\n' "$((number * 1024))"
      ;;
    M|m)
      printf '%s\n' "$number"
      ;;
  esac
}
