#!/usr/bin/env bash

OPS_HELPER_OPTIONS=(
  "ops_helpers:motd|MOTD 主机摘要|登录后显示主机状态摘要"
  "ops_helpers:aliases|通用 alias|写入少量通用 alias"
)

ops_helpers_show_menu() {
  local args=()
  local entry
  local tag
  local title
  local desc

  for entry in "${OPS_HELPER_OPTIONS[@]}"; do
    IFS='|' read -r tag title desc <<<"$entry"
    args+=("$tag" "$title - $desc" "OFF")
  done

  ui_checklist "运维辅助" "选择要安装的辅助项" "${args[@]}"
}

ops_helpers_plan_actions() {
  local raw_selection="$1"
  local selected_tag

  while IFS= read -r selected_tag; do
    [[ -n "$selected_tag" ]] || continue

    case "$selected_tag" in
      ops_helpers:motd)
        printf 'ops_helpers|ops_helpers:motd|安装 MOTD 主机摘要|motd\n'
        ;;
      ops_helpers:aliases)
        printf 'ops_helpers|ops_helpers:aliases|写入少量通用 alias|aliases\n'
        ;;
    esac
  done < <(parse_whiptail_checklist_output "$raw_selection")
}

ops_helpers_install_motd() {
  local motd_script="/etc/update-motd.d/99-vps-auto-config"
  local desired_content

  if [[ ! -d /etc/update-motd.d ]]; then
    desired_content="$(cat <<'EOF'
Ubuntu VPS 已由 vps-auto-config 初始化。
可使用 hostname、ip addr、free -h、df -h 查看主机状态。
EOF
)"
    if ! write_file_with_backup_if_changed /etc/motd "$desired_content"; then
      printf 'skip|静态 MOTD 已是目标状态\n'
      return 0
    fi
    printf 'success|静态 MOTD 已写入 /etc/motd\n'
    return 0
  fi

  desired_content="$(cat <<'EOF'
#!/usr/bin/env bash

HOSTNAME_VALUE="$(hostname)"
IP_VALUE="$(hostname -I 2>/dev/null | xargs)"
MEMORY_VALUE="$(free -h | awk '/Mem:/ {print $3 "/" $2}')"
DISK_VALUE="$(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')"
LOAD_VALUE="$(uptime | sed -E 's/.*load average: //')"
SWAP_VALUE="$(free -h | awk '/Swap:/ {print $3 "/" $2}')"

cat <<SUMMARY
Host: ${HOSTNAME_VALUE}
IP: ${IP_VALUE:-N/A}
Memory: ${MEMORY_VALUE}
Disk(/): ${DISK_VALUE}
Load: ${LOAD_VALUE}
Swap: ${SWAP_VALUE}
SUMMARY
EOF
)"
  if ! write_file_with_backup_if_changed "$motd_script" "$desired_content"; then
    chmod +x "$motd_script"
    printf 'skip|动态 MOTD 已是目标状态\n'
    return 0
  fi
  chmod +x "$motd_script"
  printf 'success|动态 MOTD 已写入 %s\n' "$motd_script"
}

ops_helpers_install_aliases() {
  local alias_file="/etc/profile.d/vps-auto-config.sh"
  local desired_content

  desired_content="$(cat <<'EOF'
alias ll='ls -alF'
alias la='ls -A'
alias grep='grep --color=auto'
alias dfh='df -h'
alias duh='du -sh'
EOF
)"
  if ! write_file_with_backup_if_changed "$alias_file" "$desired_content"; then
    chmod 644 "$alias_file"
    printf 'skip|通用 alias 已是目标状态\n'
    return 0
  fi
  chmod 644 "$alias_file"
  printf 'success|通用 alias 已写入 %s\n' "$alias_file"
}

ops_helpers_run_action() {
  local action_id="$1"
  local payload="$2"

  case "$action_id" in
    ops_helpers:motd)
      ops_helpers_install_motd
      ;;
    ops_helpers:aliases)
      ops_helpers_install_aliases
      ;;
    *)
      printf 'failed|未知运维辅助动作：%s\n' "$action_id"
      return 1
      ;;
  esac
}
