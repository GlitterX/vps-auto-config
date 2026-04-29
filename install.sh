#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$ROOT_DIR/lib/log.sh"
source "$ROOT_DIR/lib/detect.sh"
source "$ROOT_DIR/lib/backup.sh"
source "$ROOT_DIR/lib/config.sh"
source "$ROOT_DIR/lib/ui.sh"
source "$ROOT_DIR/lib/apt.sh"
source "$ROOT_DIR/modules/system_tools.sh"
source "$ROOT_DIR/modules/security.sh"
source "$ROOT_DIR/modules/system_config.sh"
source "$ROOT_DIR/modules/ops_helpers.sh"

PLANNED_ACTIONS=()
SUCCESS_RESULTS=()
SKIPPED_RESULTS=()
FAILED_RESULTS=()

TOP_LEVEL_OPTIONS=(
  "system_tools|系统工具|常用软件包与命令行工具"
  "security|安全基线|防火墙、SSH、Fail2ban 与自动安全更新"
  "system_config|系统配置|swap、hostname 与时区"
  "ops_helpers|运维辅助|MOTD 与少量通用 alias"
)

collect_plan_lines() {
  local module_name="$1"
  local raw_selection="$2"
  local line

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    PLANNED_ACTIONS+=("$line")
  done < <("${module_name}_plan_actions" "$raw_selection")
}

show_top_level_menu() {
  local args=()
  local entry
  local id
  local title
  local desc

  for entry in "${TOP_LEVEL_OPTIONS[@]}"; do
    IFS='|' read -r id title desc <<<"$entry"
    args+=("$id" "$title - $desc" "OFF")
  done

  ui_checklist "Ubuntu VPS 首装脚本" "选择要配置的功能组" "${args[@]}"
}

plan_group_actions() {
  local group="$1"
  local selection

  selection="$("${group}_show_menu")" || return 0
  [[ -n "$selection" ]] || return 0
  collect_plan_lines "$group" "$selection"
}

build_execution_plan() {
  local groups_raw
  local group

  groups_raw="$(show_top_level_menu)" || return 1

  while IFS= read -r group; do
    [[ -n "$group" ]] || continue
    plan_group_actions "$group"
  done < <(parse_whiptail_checklist_output "$groups_raw")

  return 0
}

render_plan_preview() {
  local preview=""
  local action_line
  local module_name
  local action_id
  local summary
  local payload

  if [[ ${#PLANNED_ACTIONS[@]} -eq 0 ]]; then
    ui_message "未选择任何安装项，本次不执行任何操作。"
    return 1
  fi

  for action_line in "${PLANNED_ACTIONS[@]}"; do
    IFS='|' read -r module_name action_id summary payload <<<"$action_line"
    preview+="* $summary"$'\n'
  done

  if has_high_risk_actions; then
    preview+=$'\n''注意：本次计划包含高风险操作，执行前会再次确认。'
  fi

  ui_confirm "执行计划预览" "$preview"
}

has_high_risk_actions() {
  local action_line
  local module_name
  local action_id
  local summary
  local payload

  for action_line in "${PLANNED_ACTIONS[@]}"; do
    IFS='|' read -r module_name action_id summary payload <<<"$action_line"
    case "$action_id" in
      security:ssh_*|security:ufw|system_config:swap)
        return 0
        ;;
    esac
  done

  return 1
}

confirm_high_risk_actions() {
  if ! has_high_risk_actions; then
    return 0
  fi

  ui_yesno "高风险确认" "本次执行包含 SSH、防火墙或 swap 相关高风险操作，确认继续执行吗？"
}

record_result() {
  local state="$1"
  local message="$2"

  case "$state" in
    success)
      SUCCESS_RESULTS+=("$message")
      ;;
    skip)
      SKIPPED_RESULTS+=("$message")
      ;;
    failed)
      FAILED_RESULTS+=("$message")
      ;;
  esac
}

execute_planned_actions() {
  local action_line
  local module_name
  local action_id
  local summary
  local payload
  local result
  local status_code
  local state
  local message

  for action_line in "${PLANNED_ACTIONS[@]}"; do
    IFS='|' read -r module_name action_id summary payload <<<"$action_line"
    log_info "执行：$summary"

    set +e
    result="$("${module_name}_run_action" "$action_id" "$payload")"
    status_code=$?
    set -e

    if [[ $status_code -ne 0 ]]; then
      record_result "failed" "$summary"
      log_error "失败：$summary"
      continue
    fi

    IFS='|' read -r state message <<<"$result"
    record_result "$state" "$message"

    case "$state" in
      success)
        log_success "$message"
        ;;
      skip)
        log_warn "$message"
        ;;
      failed)
        log_error "$message"
        ;;
    esac
  done
}

show_summary() {
  local summary=""
  local item

  summary+="成功：${#SUCCESS_RESULTS[@]}"$'\n'
  for item in "${SUCCESS_RESULTS[@]}"; do
    summary+="  - $item"$'\n'
  done

  summary+=$'\n'"跳过：${#SKIPPED_RESULTS[@]}"$'\n'
  for item in "${SKIPPED_RESULTS[@]}"; do
    summary+="  - $item"$'\n'
  done

  summary+=$'\n'"失败：${#FAILED_RESULTS[@]}"$'\n'
  for item in "${FAILED_RESULTS[@]}"; do
    summary+="  - $item"$'\n'
  done

  ui_message "$summary"
}

run_preflight() {
  local ubuntu_version

  require_root
  ui_prepare_stdin
  ensure_apt_available
  ubuntu_version="$(get_ubuntu_version "/etc/os-release")"

  if ! is_supported_ubuntu_version "$ubuntu_version"; then
    log_error "仅支持 Ubuntu 22.04 和 24.04，当前版本：${ubuntu_version:-unknown}"
    exit 1
  fi

  ensure_whiptail
}

main() {
  run_preflight

  if ! build_execution_plan; then
    log_warn "已取消操作。"
    exit 0
  fi

  if ! render_plan_preview; then
    exit 0
  fi

  if ! confirm_high_risk_actions; then
    log_warn "已取消高风险操作执行。"
    exit 0
  fi

  execute_planned_actions
  show_summary
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
