#!/usr/bin/env bash

SYSTEM_CONFIG_OPTIONS=(
  "system_config:swap|swap 配置|创建或重配 swapfile"
  "system_config:hostname|hostname|修改系统主机名"
  "system_config:timezone|时区|设置系统时区"
)

TIMEZONE_PRESETS=(
  "Asia/Shanghai|中国上海"
  "Asia/Tokyo|日本东京"
  "Asia/Singapore|新加坡"
  "Europe/London|英国伦敦"
  "Europe/Berlin|德国柏林"
  "America/New_York|美国纽约"
  "America/Los_Angeles|美国洛杉矶"
  "UTC|协调世界时"
)

system_config_show_menu() {
  local args=()
  local entry
  local tag
  local title
  local desc

  for entry in "${SYSTEM_CONFIG_OPTIONS[@]}"; do
    IFS='|' read -r tag title desc <<<"$entry"
    args+=("$tag" "$title - $desc" "OFF")
  done

  ui_checklist "系统配置" "选择要修改的系统项" "${args[@]}"
}

system_config_collect_swap_size() {
  local selected
  local custom

  selected="$(ui_menu "Swap 大小" "选择 swap 大小" \
    "1G" "1 GB" \
    "2G" "2 GB" \
    "4G" "4 GB" \
    "custom" "自定义大小")" || return 1

  if [[ "$selected" == "custom" ]]; then
    custom="$(ui_input "自定义 Swap" "请输入 swap 大小，格式如 512M 或 8G" "2G")" || return 1
    normalize_size_to_mb "$custom" >/dev/null || {
      ui_message "swap 大小格式不正确。"
      return 1
    }
    printf '%s\n' "$custom"
    return 0
  fi

  printf '%s\n' "$selected"
}

system_config_collect_hostname() {
  local hostname_value

  while true; do
    hostname_value="$(ui_input "Hostname" "请输入新的主机名" "$(hostname)")" || return 1
    if validate_hostname "$hostname_value"; then
      printf '%s\n' "$hostname_value"
      return 0
    fi
    ui_message "主机名只允许字母、数字、连字符，且不能以连字符开头或结尾。"
  done
}

system_config_collect_timezone() {
  local args=()
  local entry
  local timezone
  local label
  local selected
  local custom

  for entry in "${TIMEZONE_PRESETS[@]}"; do
    IFS='|' read -r timezone label <<<"$entry"
    args+=("$timezone" "$label")
  done
  args+=("custom" "自定义输入")

  selected="$(ui_menu "时区设置" "选择时区" "${args[@]}")" || return 1

  if [[ "$selected" == "custom" ]]; then
    custom="$(ui_input "时区设置" "请输入时区，例如 Asia/Shanghai" "UTC")" || return 1
    printf '%s\n' "$custom"
    return 0
  fi

  printf '%s\n' "$selected"
}

system_config_plan_actions() {
  local raw_selection="$1"
  local selected_tag
  local payload

  while IFS= read -r selected_tag; do
    [[ -n "$selected_tag" ]] || continue

    case "$selected_tag" in
      system_config:swap)
        payload="$(system_config_collect_swap_size)" || continue
        printf 'system_config|system_config:swap|配置 swapfile 大小为 %s|%s\n' "$payload" "$payload"
        ;;
      system_config:hostname)
        payload="$(system_config_collect_hostname)" || continue
        printf 'system_config|system_config:hostname|设置 hostname 为 %s|%s\n' "$payload" "$payload"
        ;;
      system_config:timezone)
        payload="$(system_config_collect_timezone)" || continue
        printf 'system_config|system_config:timezone|设置时区为 %s|%s\n' "$payload" "$payload"
        ;;
    esac
  done < <(parse_whiptail_checklist_output "$raw_selection")
}

system_config_apply_timezone() {
  local timezone="$1"
  local current_timezone

  current_timezone="$(get_current_timezone)"
  if [[ "$current_timezone" == "$timezone" ]]; then
    printf 'skip|时区已是目标值：%s\n' "$timezone"
    return 0
  fi

  if has_command timedatectl; then
    timedatectl set-timezone "$timezone"
  else
    [[ -f "/usr/share/zoneinfo/$timezone" ]] || {
      printf 'failed|目标时区不存在：%s\n' "$timezone"
      return 1
    }
    ln -sf "/usr/share/zoneinfo/$timezone" /etc/localtime
    write_file_with_backup_if_changed /etc/timezone "$timezone"$'\n' || true
  fi

  printf 'success|时区已更新为：%s\n' "$timezone"
}

system_config_set_runtime_hostname() {
  local hostname_value="$1"
  local command_output
  local current_hostname=""

  if has_command hostnamectl; then
    if command_output="$(hostnamectl set-hostname "$hostname_value" 2>&1)"; then
      current_hostname="$(hostname 2>/dev/null || true)"
      if [[ "$current_hostname" == "$hostname_value" ]]; then
        return 0
      fi
    fi
  fi

  if command_output="$(hostname "$hostname_value" 2>&1)"; then
    return 0
  fi

  printf 'failed|更新运行中 hostname 失败：%s\n' "${command_output:-未获取到错误信息}"
  return 1
}

system_config_apply_hostname() {
  local hostname_value="$1"
  local changed=0
  local current_hostname_file=""

  if [[ -f /etc/hostname ]]; then
    current_hostname_file="$(tr -d '\r\n' < /etc/hostname)"
  fi

  if [[ "$current_hostname_file" != "$hostname_value" ]]; then
    backup_file /etc/hostname
    printf '%s\n' "$hostname_value" > /etc/hostname
    changed=1
  fi

  if [[ "$(hostname)" != "$hostname_value" ]]; then
    system_config_set_runtime_hostname "$hostname_value" || return 1
    changed=1
  fi

  if upsert_line_with_backup_if_needed /etc/hosts '^127\.0\.1\.1[[:space:]]+' "127.0.1.1 ${hostname_value}"; then
    changed=1
  fi

  if [[ "$changed" -eq 0 ]]; then
    printf 'skip|hostname 相关配置已是目标值：%s\n' "$hostname_value"
    return 0
  fi

  printf 'success|hostname 已更新为：%s\n' "$hostname_value"
}

system_config_apply_swap() {
  local size="$1"
  local swap_type
  local size_mb
  local desired_fstab_line="/swapfile none swap sw 0 0"
  local changed=0

  swap_type="$(detect_swap_type)"
  if [[ "$swap_type" == "partition" ]]; then
    printf 'skip|检测到分区型 swap，第一版仅提示状态，不自动修改。\n'
    return 0
  fi

  size_mb="$(normalize_size_to_mb "$size")"
  if [[ -f /swapfile ]]; then
    local current_swap_size_mb
    current_swap_size_mb="$(( $(stat -c %s /swapfile 2>/dev/null || echo 0) / 1024 / 1024 ))"
    if [[ "$swap_type" == "swapfile" && "$current_swap_size_mb" -eq "$size_mb" ]] && swapon --show | grep -q '/swapfile'; then
      if ! upsert_line_with_backup_if_needed /etc/fstab '^/swapfile[[:space:]]+' "$desired_fstab_line"; then
        printf 'skip|swapfile 已是目标状态：%s\n' "$size"
        return 0
      fi
    fi
  fi

  swapoff /swapfile >/dev/null 2>&1 || true
  rm -f /swapfile

  if has_command fallocate; then
    fallocate -l "${size_mb}M" /swapfile
  else
    dd if=/dev/zero of=/swapfile bs=1M count="$size_mb" status=none
  fi

  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  changed=1

  if upsert_line_with_backup_if_needed /etc/fstab '^/swapfile[[:space:]]+' "$desired_fstab_line"; then
    changed=1
  fi

  [[ "$changed" -eq 1 ]] || {
    printf 'skip|swapfile 已是目标状态：%s\n' "$size"
    return 0
  }

  printf 'success|swapfile 已配置为：%s\n' "$size"
}

system_config_run_action() {
  local action_id="$1"
  local payload="$2"

  case "$action_id" in
    system_config:swap)
      system_config_apply_swap "$payload"
      ;;
    system_config:hostname)
      system_config_apply_hostname "$payload"
      ;;
    system_config:timezone)
      system_config_apply_timezone "$payload"
      ;;
    *)
      printf 'failed|未知系统配置动作：%s\n' "$action_id"
      return 1
      ;;
  esac
}
