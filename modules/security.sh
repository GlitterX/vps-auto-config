#!/usr/bin/env bash

SECURITY_OPTIONS=(
  "security:ufw|UFW 防火墙|按端口与协议配置防火墙规则"
  "security:fail2ban|Fail2ban|配置 SSH 暴力破解防护"
  "security:ssh_auth|SSH 认证配置|配置 PermitRootLogin / PubkeyAuthentication / PasswordAuthentication"
  "security:ssh_change_port|修改 SSH 端口|需要输入新的 SSH 端口"
  "security:auto_updates|自动安全更新|启用 unattended-upgrades"
)

security_show_menu() {
  local args=()
  local entry
  local tag
  local title
  local desc

  for entry in "${SECURITY_OPTIONS[@]}"; do
    IFS='|' read -r tag title desc <<<"$entry"
    args+=("$tag" "$title - $desc" "OFF")
  done

  ui_checklist "安全基线" "选择要配置的安全项" "${args[@]}"
}

security_collect_ufw_rules() {
  local ssh_port
  local preset_raw
  local custom_raw=""
  local rules=()
  local item
  local port
  local protocol

  ssh_port="$(get_ssh_port)"

  preset_raw="$(ui_checklist "UFW 规则" "选择预设放行规则" \
    "preset:${ssh_port}:tcp" "当前 SSH 端口 ${ssh_port}/tcp" "ON" \
    "preset:80:tcp" "HTTP 80/tcp" "OFF" \
    "preset:443:tcp" "HTTPS 443/tcp" "OFF")" || return 1

  while IFS= read -r item; do
    [[ -n "$item" ]] || continue
    port="$(printf '%s' "$item" | cut -d: -f2)"
    protocol="$(printf '%s' "$item" | cut -d: -f3)"
    rules+=("${port}/${protocol}")
  done < <(parse_whiptail_checklist_output "$preset_raw")

  custom_raw="$(ui_input "UFW 自定义规则" "可选：输入额外规则，格式为 port/proto,port/proto，例如 8080/tcp,6000/udp" "")" || true

  if [[ -n "$custom_raw" ]]; then
    custom_raw="${custom_raw// /}"
    IFS=',' read -r -a custom_items <<<"$custom_raw"
    for item in "${custom_items[@]}"; do
      [[ -n "$item" ]] || continue
      port="${item%/*}"
      protocol="${item#*/}"

      if ! validate_port "$port" || ! validate_protocol "$protocol"; then
        ui_message "检测到非法规则：$item"
        return 1
      fi

      rules+=("${port}/${protocol}")
    done
  fi

  if [[ ${#rules[@]} -eq 0 ]]; then
    rules+=("${ssh_port}/tcp")
  fi

  printf '%s\n' "$(IFS=,; printf '%s' "${rules[*]}")"
}

security_collect_fail2ban_config() {
  local maxretry
  local findtime
  local bantime

  maxretry="$(ui_input "Fail2ban 参数" "maxretry（默认 5）" "5")" || return 1
  findtime="$(ui_input "Fail2ban 参数" "findtime（默认 10m）" "10m")" || return 1
  bantime="$(ui_input "Fail2ban 参数" "bantime（默认 1h）" "1h")" || return 1

  printf '%s;%s;%s\n' "$maxretry" "$findtime" "$bantime"
}

security_collect_ssh_port() {
  local port

  while true; do
    port="$(ui_input "SSH 端口" "请输入新的 SSH 端口" "2222")" || return 1
    if validate_port "$port"; then
      printf '%s\n' "$port"
      return 0
    fi
    ui_message "端口必须在 1-65535 之间。"
  done
}

get_sshd_config_value() {
  local config_file="$1"
  local key="$2"
  local default_value="$3"
  local value=""

  [[ -f "$config_file" ]] || {
    printf '%s\n' "$default_value"
    return 0
  }

  value="$(grep -E "^[[:space:]#]*${key}[[:space:]]+" "$config_file" | tail -n 1 | sed -E "s/^[[:space:]#]*${key}[[:space:]]+([^[:space:]]+).*$/\\1/" || true)"

  if [[ -z "$value" ]]; then
    printf '%s\n' "$default_value"
  else
    printf '%s\n' "$value"
  fi
}

security_tag_is_selected() {
  local raw_selection="$1"
  local target_tag="$2"
  local selected_tag

  while IFS= read -r selected_tag; do
    [[ -n "$selected_tag" ]] || continue
    if [[ "$selected_tag" == "$target_tag" ]]; then
      return 0
    fi
  done < <(parse_whiptail_checklist_output "$raw_selection")

  return 1
}

security_build_ssh_toggle_actions() {
  local raw_selection="$1"
  local pubkey_value="no"
  local password_value="no"

  if security_tag_is_selected "$raw_selection" "ssh:pubkey_auth"; then
    pubkey_value="yes"
  fi

  if security_tag_is_selected "$raw_selection" "ssh:password_auth"; then
    password_value="yes"
  fi

  printf 'PubkeyAuthentication=%s\n' "$pubkey_value"
  printf 'PasswordAuthentication=%s\n' "$password_value"
}

security_collect_ssh_auth_settings() {
  local config_file="${1:-/etc/ssh/sshd_config}"
  local permit_root_current
  local pubkey_current
  local password_current
  local checklist_raw
  local root_login_mode
  local toggle_actions
  local pubkey_value
  local password_value

  permit_root_current="$(get_sshd_config_value "$config_file" "PermitRootLogin" "prohibit-password")"
  pubkey_current="$(get_sshd_config_value "$config_file" "PubkeyAuthentication" "yes")"
  password_current="$(get_sshd_config_value "$config_file" "PasswordAuthentication" "yes")"

  checklist_raw="$(ui_checklist "SSH 认证配置" "勾选要启用的 SSH 认证方式" \
    "ssh:pubkey_auth" "PubkeyAuthentication" "$([[ "$pubkey_current" == "yes" ]] && echo ON || echo OFF)" \
    "ssh:password_auth" "PasswordAuthentication" "$([[ "$password_current" == "yes" ]] && echo ON || echo OFF)")" || return 1

  root_login_mode="$(ui_menu "PermitRootLogin" "选择 root 登录模式" \
    "yes" "允许 root 使用所有认证方式登录" \
    "prohibit-password" "允许 root 使用密钥登录，禁止密码登录" \
    "no" "完全禁止 root 登录")" || return 1

  toggle_actions="$(security_build_ssh_toggle_actions "$checklist_raw")"
  pubkey_value="$(printf '%s\n' "$toggle_actions" | awk -F= '/^PubkeyAuthentication=/{print $2}')"
  password_value="$(printf '%s\n' "$toggle_actions" | awk -F= '/^PasswordAuthentication=/{print $2}')"

  if [[ "$pubkey_value" == "no" && "$password_value" == "no" ]]; then
    ui_message "PubkeyAuthentication 和 PasswordAuthentication 不能同时关闭。"
    return 1
  fi

  printf 'PermitRootLogin=%s;PubkeyAuthentication=%s;PasswordAuthentication=%s\n' \
    "$root_login_mode" "$pubkey_value" "$password_value"
}

security_plan_actions() {
  local raw_selection="$1"
  local selected_tag
  local payload

  while IFS= read -r selected_tag; do
    [[ -n "$selected_tag" ]] || continue

    case "$selected_tag" in
      security:ufw)
        payload="$(security_collect_ufw_rules)" || continue
        printf 'security|security:ufw|配置 UFW 防火墙规则|%s\n' "$payload"
        ;;
      security:fail2ban)
        payload="$(security_collect_fail2ban_config)" || continue
        printf 'security|security:fail2ban|安装并配置 Fail2ban|%s\n' "$payload"
        ;;
      security:ssh_auth)
        payload="$(security_collect_ssh_auth_settings)" || continue
        if [[ "$payload" == *"PasswordAuthentication=no"* ]]; then
          if detect_authorized_key "/root"; then
            ui_yesno "SSH 确认" "已检测到 root 公钥，确认按当前勾选结果更新 SSH 认证配置吗？" || continue
          else
            ui_yesno "SSH 风险确认" "未检测到 root 的 authorized_keys，且当前配置会关闭密码登录，确认继续吗？" || continue
          fi
        else
          ui_yesno "SSH 确认" "确认按当前勾选结果更新 SSH 认证配置吗？" || continue
        fi
        printf 'security|security:ssh_auth|更新 SSH 认证配置|%s\n' "$payload"
        ;;
      security:ssh_change_port)
        payload="$(security_collect_ssh_port)" || continue
        ui_yesno "SSH 确认" "确认将 SSH 端口修改为 $payload 吗？请确保防火墙规则同步放行。" || continue
        printf 'security|security:ssh_change_port|修改 SSH 端口为 %s|%s\n' "$payload" "$payload"
        ;;
      security:auto_updates)
        printf 'security|security:auto_updates|启用自动安全更新|enabled\n'
        ;;
    esac
  done < <(parse_whiptail_checklist_output "$raw_selection")
}

security_replace_config_value() {
  local file_path="$1"
  local key="$2"
  local value="$3"

  upsert_line_if_needed "$file_path" "^[[:space:]#]*${key}[[:space:]]+" "${key} ${value}"
}

security_apply_sshd_value() {
  local file_path="$1"
  local key="$2"
  local desired_value="$3"
  local current_value

  current_value="$(get_sshd_config_value "$file_path" "$key" "__missing__")"

  if [[ "$current_value" == "$desired_value" ]]; then
    return 1
  fi

  security_replace_config_value "$file_path" "$key" "$desired_value"
  return 0
}

security_reload_ssh_service() {
  if has_command sshd; then
    sshd -t
  fi

  if has_command systemctl; then
    systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
  fi
}

security_run_ufw() {
  local payload="$1"
  local item
  local port
  local protocol

  apt_install_packages ufw

  IFS=',' read -r -a rules <<<"$payload"
  for item in "${rules[@]}"; do
    port="${item%/*}"
    protocol="${item#*/}"
    ufw allow "${port}/${protocol}" >/dev/null
  done

  ufw --force enable >/dev/null
  printf 'success|UFW 已启用并写入规则\n'
}

security_run_fail2ban() {
  local payload="$1"
  local maxretry
  local findtime
  local bantime
  local desired_content

  IFS=';' read -r maxretry findtime bantime <<<"$payload"

  apt_install_packages fail2ban
  desired_content="$(cat <<EOF
[DEFAULT]
bantime = ${bantime}
findtime = ${findtime}
maxretry = ${maxretry}

[sshd]
enabled = true
backend = systemd
EOF
)"

  if ! write_file_with_backup_if_changed /etc/fail2ban/jail.local "$desired_content"; then
    printf 'skip|Fail2ban 配置已是目标状态\n'
    return 0
  fi

  if has_command systemctl; then
    systemctl enable fail2ban >/dev/null 2>&1 || true
    systemctl restart fail2ban >/dev/null 2>&1 || true
  fi

  printf 'success|Fail2ban 已安装并完成配置\n'
}

security_run_ssh_update() {
  local key="$1"
  local value="$2"
  local changed=0

  if security_apply_sshd_value /etc/ssh/sshd_config "$key" "$value"; then
    backup_file /etc/ssh/sshd_config
    security_replace_config_value /etc/ssh/sshd_config "$key" "$value"
    changed=1
  fi

  if [[ "$changed" -eq 0 ]]; then
    printf 'skip|SSH 配置已是目标值：%s=%s\n' "$key" "$value"
    return 0
  fi

  security_reload_ssh_service
  printf 'success|SSH 配置已更新：%s=%s\n' "$key" "$value"
}

security_run_auto_updates() {
  local desired_content

  apt_install_packages unattended-upgrades
  desired_content="$(cat <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
)"

  if ! write_file_with_backup_if_changed /etc/apt/apt.conf.d/20auto-upgrades "$desired_content"; then
    printf 'skip|自动安全更新配置已是目标状态\n'
    return 0
  fi

  printf 'success|自动安全更新已启用\n'
}

security_run_ssh_auth() {
  local payload="$1"
  local permit_root
  local pubkey_auth
  local password_auth
  local changed=0

  permit_root="$(printf '%s' "$payload" | tr ';' '\n' | awk -F= '/^PermitRootLogin=/{print $2}')"
  pubkey_auth="$(printf '%s' "$payload" | tr ';' '\n' | awk -F= '/^PubkeyAuthentication=/{print $2}')"
  password_auth="$(printf '%s' "$payload" | tr ';' '\n' | awk -F= '/^PasswordAuthentication=/{print $2}')"

  if [[ "$(get_sshd_config_value /etc/ssh/sshd_config "PermitRootLogin" "__missing__")" != "$permit_root" ]] || \
     [[ "$(get_sshd_config_value /etc/ssh/sshd_config "PubkeyAuthentication" "__missing__")" != "$pubkey_auth" ]] || \
     [[ "$(get_sshd_config_value /etc/ssh/sshd_config "PasswordAuthentication" "__missing__")" != "$password_auth" ]]; then
    backup_file /etc/ssh/sshd_config
    security_replace_config_value /etc/ssh/sshd_config "PermitRootLogin" "$permit_root"
    security_replace_config_value /etc/ssh/sshd_config "PubkeyAuthentication" "$pubkey_auth"
    security_replace_config_value /etc/ssh/sshd_config "PasswordAuthentication" "$password_auth"
    changed=1
  fi

  if [[ "$changed" -eq 0 ]]; then
    printf 'skip|SSH 认证配置已是目标状态\n'
    return 0
  fi

  security_reload_ssh_service

  printf 'success|SSH 认证配置已更新：PermitRootLogin=%s, PubkeyAuthentication=%s, PasswordAuthentication=%s\n' \
    "$permit_root" "$pubkey_auth" "$password_auth"
}

security_run_action() {
  local action_id="$1"
  local payload="$2"

  case "$action_id" in
    security:ufw)
      security_run_ufw "$payload"
      ;;
    security:fail2ban)
      security_run_fail2ban "$payload"
      ;;
    security:ssh_auth)
      security_run_ssh_auth "$payload"
      ;;
    security:ssh_change_port)
      security_run_ssh_update "Port" "$payload"
      ;;
    security:auto_updates)
      security_run_auto_updates
      ;;
    *)
      printf 'failed|未知安全动作：%s\n' "$action_id"
      return 1
      ;;
  esac
}
