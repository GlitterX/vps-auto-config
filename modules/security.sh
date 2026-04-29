#!/usr/bin/env bash

SECURITY_OPTIONS=(
  "security:ufw|UFW 防火墙|按端口与协议配置防火墙规则"
  "security:fail2ban|Fail2ban|配置 SSH 暴力破解防护"
  "security:ssh_disable_password|禁用 SSH 密码登录|需要先确认公钥状态"
  "security:ssh_disable_root|禁用 root SSH 直登|修改 PermitRootLogin"
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
      security:ssh_disable_password)
        if detect_authorized_key "/root"; then
          ui_yesno "SSH 确认" "已检测到 root 公钥，确认禁用 SSH 密码登录吗？" || continue
        else
          ui_yesno "SSH 风险确认" "未检测到 root 的 authorized_keys。继续禁用 SSH 密码登录可能导致无法登录，确认继续吗？" || continue
        fi
        printf 'security|security:ssh_disable_password|禁用 SSH 密码登录|PasswordAuthentication=no\n'
        ;;
      security:ssh_disable_root)
        ui_yesno "SSH 确认" "确认禁用 root SSH 直登吗？" || continue
        printf 'security|security:ssh_disable_root|禁用 root SSH 直登|PermitRootLogin=no\n'
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

  if grep -Eq "^[#[:space:]]*${key}[[:space:]]+" "$file_path"; then
    sed -i -E "s|^[#[:space:]]*${key}[[:space:]]+.*|${key} ${value}|" "$file_path"
  else
    printf '%s %s\n' "$key" "$value" >> "$file_path"
  fi
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

  IFS=';' read -r maxretry findtime bantime <<<"$payload"

  apt_install_packages fail2ban
  backup_file /etc/fail2ban/jail.local

  cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = ${bantime}
findtime = ${findtime}
maxretry = ${maxretry}

[sshd]
enabled = true
backend = systemd
EOF

  if has_command systemctl; then
    systemctl enable fail2ban >/dev/null 2>&1 || true
    systemctl restart fail2ban >/dev/null 2>&1 || true
  fi

  printf 'success|Fail2ban 已安装并完成配置\n'
}

security_run_ssh_update() {
  local key="$1"
  local value="$2"

  backup_file /etc/ssh/sshd_config
  security_replace_config_value /etc/ssh/sshd_config "$key" "$value"
  security_reload_ssh_service
  printf 'success|SSH 配置已更新：%s=%s\n' "$key" "$value"
}

security_run_auto_updates() {
  apt_install_packages unattended-upgrades
  backup_file /etc/apt/apt.conf.d/20auto-upgrades

  cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

  printf 'success|自动安全更新已启用\n'
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
    security:ssh_disable_password)
      security_run_ssh_update "PasswordAuthentication" "no"
      ;;
    security:ssh_disable_root)
      security_run_ssh_update "PermitRootLogin" "no"
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
