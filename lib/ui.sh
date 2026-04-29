#!/usr/bin/env bash

parse_whiptail_checklist_output() {
  local raw_output="${1:-}"
  local normalized

  normalized="${raw_output//\"/}"
  for item in $normalized; do
    printf '%s\n' "$item"
  done
}

UI_TTY_DEVICE="${UI_TTY_DEVICE:-/dev/tty}"
UI_STDIN_PREPARED=0

ui_has_usable_tty() {
  [[ -t 0 || -r "$UI_TTY_DEVICE" ]]
}

ui_terminfo_exists() {
  local term_name="${1:-}"

  [[ -n "$term_name" ]] || return 1

  if command -v infocmp >/dev/null 2>&1; then
    infocmp "$term_name" >/dev/null 2>&1
    return $?
  fi

  case "$term_name" in
    xterm|xterm-256color|screen|screen-256color|linux|vt100)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

ui_resolve_whiptail_term() {
  local current_term="${TERM:-}"
  local fallback_term

  case "$current_term" in
    ""|dumb|unknown)
      current_term=""
      ;;
  esac

  if ui_terminfo_exists "$current_term"; then
    printf '%s\n' "$current_term"
    return 0
  fi

  for fallback_term in xterm xterm-256color screen screen-256color linux vt100; do
    if ui_terminfo_exists "$fallback_term"; then
      printf '%s\n' "$fallback_term"
      return 0
    fi
  done

  return 1
}

ui_run_whiptail() {
  local whiptail_term

  if ! whiptail_term="$(ui_resolve_whiptail_term)"; then
    if declare -F log_error >/dev/null 2>&1; then
      log_error "未找到可用的终端类型，无法启动 whiptail。请安装 terminfo 数据或在兼容终端中重试。"
    else
      printf '%s\n' "未找到可用的终端类型，无法启动 whiptail。请安装 terminfo 数据或在兼容终端中重试。" >&2
    fi
    return 1
  fi

  TERM="$whiptail_term" whiptail "$@"
}

ui_prepare_stdin() {
  if [[ "$UI_STDIN_PREPARED" -eq 1 ]]; then
    return 0
  fi

  if [[ -t 0 ]]; then
    UI_STDIN_PREPARED=1
    return 0
  fi

  if [[ -r "$UI_TTY_DEVICE" ]]; then
    exec <"$UI_TTY_DEVICE"
    UI_STDIN_PREPARED=1
    return 0
  fi

  if declare -F log_error >/dev/null 2>&1; then
    log_error "未检测到可交互终端，whiptail 无法正常工作。请直接在 SSH 终端中运行，或先下载脚本后再执行。"
  else
    printf '%s\n' "未检测到可交互终端，whiptail 无法正常工作。请直接在 SSH 终端中运行，或先下载脚本后再执行。" >&2
  fi

  return 1
}

ui_checklist() {
  local title="$1"
  local prompt="$2"
  shift 2

  ui_run_whiptail --title "$title" --checklist "$prompt" 22 86 14 "$@" 3>&1 1>&2 2>&3
}

ui_menu() {
  local title="$1"
  local prompt="$2"
  shift 2

  ui_run_whiptail --title "$title" --menu "$prompt" 22 86 14 "$@" 3>&1 1>&2 2>&3
}

ui_input() {
  local title="$1"
  local prompt="$2"
  local default_value="${3:-}"

  ui_run_whiptail --title "$title" --inputbox "$prompt" 12 86 "$default_value" 3>&1 1>&2 2>&3
}

ui_yesno() {
  local title="$1"
  local prompt="$2"

  ui_run_whiptail --title "$title" --yesno "$prompt" 12 86
}

ui_confirm() {
  local title="$1"
  local prompt="$2"

  ui_run_whiptail --title "$title" --yesno "$prompt" 24 86
}

ui_message() {
  local prompt="$1"

  ui_run_whiptail --title "Ubuntu VPS 首装脚本" --msgbox "$prompt" 24 86
}
