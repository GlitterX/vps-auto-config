#!/usr/bin/env bash

SYSTEM_TOOLS_ITEMS=(
  "pkg:curl|curl|下载与归档|curl 命令行下载工具"
  "pkg:wget|wget|下载与归档|wget 下载工具"
  "pkg:zip|zip|下载与归档|zip 压缩工具"
  "pkg:unzip|unzip|下载与归档|unzip 解压工具"
  "pkg:vim|vim|编辑与会话|vim 文本编辑器"
  "pkg:nano|nano|编辑与会话|nano 文本编辑器"
  "pkg:tmux|tmux|编辑与会话|tmux 会话管理"
  "pkg:git|git|编辑与会话|git 版本管理"
  "pkg:htop|htop|监控与诊断|htop 资源监控"
  "pkg:btop|btop|监控与诊断|btop 资源监控"
  "pkg:tree|tree|监控与诊断|tree 目录查看"
  "pkg:lsof|lsof|监控与诊断|lsof 进程与文件查看"
  "pkg:net-tools|net-tools|网络基础|ifconfig/netstat 工具集"
  "pkg:dnsutils|dnsutils|网络基础|dig/nslookup 工具集"
  "pkg:traceroute|traceroute|网络基础|traceroute 网络诊断"
  "pkg:rsync|rsync|网络基础|rsync 文件同步"
)

system_tools_show_menu() {
  local args=()
  local entry
  local tag
  local package_name
  local group
  local desc

  for entry in "${SYSTEM_TOOLS_ITEMS[@]}"; do
    IFS='|' read -r tag package_name group desc <<<"$entry"
    args+=("$tag" "[$group] $package_name - $desc" "OFF")
  done

  ui_checklist "系统工具" "选择要安装的软件包" "${args[@]}"
}

system_tools_plan_actions() {
  local raw_selection="$1"
  local selected_tag
  local entry
  local tag
  local package_name
  local group
  local desc

  while IFS= read -r selected_tag; do
    [[ -n "$selected_tag" ]] || continue
    for entry in "${SYSTEM_TOOLS_ITEMS[@]}"; do
      IFS='|' read -r tag package_name group desc <<<"$entry"
      if [[ "$tag" == "$selected_tag" ]]; then
        printf 'system_tools|%s|安装系统工具：%s|%s\n' "$tag" "$package_name" "$package_name"
      fi
    done
  done < <(parse_whiptail_checklist_output "$raw_selection")
}

system_tools_run_action() {
  local action_id="$1"
  local package_name="$2"

  if is_package_installed "$package_name"; then
    printf 'skip|系统工具已安装：%s\n' "$package_name"
    return 0
  fi

  apt_install_packages "$package_name"
  printf 'success|系统工具安装完成：%s\n' "$package_name"
}
