#!/usr/bin/env bash

parse_whiptail_checklist_output() {
  local raw_output="${1:-}"
  local normalized

  normalized="${raw_output//\"/}"
  for item in $normalized; do
    printf '%s\n' "$item"
  done
}

ui_checklist() {
  local title="$1"
  local prompt="$2"
  shift 2

  whiptail --title "$title" --checklist "$prompt" 22 86 14 "$@" 3>&1 1>&2 2>&3
}

ui_menu() {
  local title="$1"
  local prompt="$2"
  shift 2

  whiptail --title "$title" --menu "$prompt" 22 86 14 "$@" 3>&1 1>&2 2>&3
}

ui_input() {
  local title="$1"
  local prompt="$2"
  local default_value="${3:-}"

  whiptail --title "$title" --inputbox "$prompt" 12 86 "$default_value" 3>&1 1>&2 2>&3
}

ui_yesno() {
  local title="$1"
  local prompt="$2"

  whiptail --title "$title" --yesno "$prompt" 12 86
}

ui_confirm() {
  local title="$1"
  local prompt="$2"

  whiptail --title "$title" --yesno "$prompt" 24 86
}

ui_message() {
  local prompt="$1"

  whiptail --title "Ubuntu VPS 首装脚本" --msgbox "$prompt" 24 86
}
