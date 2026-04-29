#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$ROOT_DIR/lib/detect.sh"
source "$ROOT_DIR/lib/config.sh"
source "$ROOT_DIR/lib/ui.sh"
source "$ROOT_DIR/modules/security.sh"
source "$ROOT_DIR/modules/system_config.sh"
source "$ROOT_DIR/bootstrap.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'PASS: %s\n' "$1"
}

assert_equals() {
  local expected="$1"
  local actual="$2"
  local label="$3"

  if [[ "$expected" != "$actual" ]]; then
    fail "$label (expected: $expected, actual: $actual)"
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"

  if [[ "$haystack" != *"$needle"* ]]; then
    fail "$label (missing: $needle)"
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"

  if [[ "$haystack" == *"$needle"* ]]; then
    fail "$label (unexpected: $needle)"
  fi
}

assert_success() {
  local label="$1"
  shift

  if ! "$@"; then
    fail "$label"
  fi
}

assert_failure() {
  local label="$1"
  shift

  if "$@"; then
    fail "$label"
  fi
}

test_validate_hostname() {
  assert_success "hostname accepts letters, numbers and hyphen" validate_hostname "vps-prod-01"
  assert_failure "hostname rejects empty string" validate_hostname ""
  assert_failure "hostname rejects underscore" validate_hostname "bad_name"
  assert_failure "hostname rejects leading hyphen" validate_hostname "-vps"
  pass "validate_hostname"
}

test_detect_supported_ubuntu() {
  local supported
  local unsupported

  supported="$(get_ubuntu_version "$ROOT_DIR/tests/fixtures/os-release-22.04")"
  unsupported="$(get_ubuntu_version "$ROOT_DIR/tests/fixtures/os-release-unsupported")"

  assert_equals "22.04" "$supported" "reads Ubuntu 22.04 version"
  assert_equals "20.04" "$unsupported" "reads unsupported version"
  assert_success "22.04 is supported" is_supported_ubuntu_version "$supported"
  assert_failure "20.04 is unsupported" is_supported_ubuntu_version "$unsupported"
  pass "detect_supported_ubuntu"
}

test_parse_checklist_output() {
  local parsed

  parsed="$(parse_whiptail_checklist_output '"pkg:curl" "security:ufw"')"
  assert_contains "$parsed" "pkg:curl" "parses first checklist item"
  assert_contains "$parsed" "security:ufw" "parses second checklist item"
  pass "parse_checklist_output"
}

test_build_github_archive_url() {
  local archive_url

  archive_url="$(build_github_archive_url "GlitterX/vps-auto-config" "main")"
  assert_equals "https://codeload.github.com/GlitterX/vps-auto-config/tar.gz/refs/heads/main" "$archive_url" "builds GitHub archive URL"
  pass "build_github_archive_url"
}

test_resolve_script_dir() {
  local resolved

  resolved="$(resolve_script_dir "$ROOT_DIR/bootstrap.sh")"
  assert_equals "$ROOT_DIR" "$resolved" "resolves script directory from file path"

  assert_failure "empty script path is rejected" resolve_script_dir ""
  pass "resolve_script_dir"
}

test_bootstrap_should_run_main() {
  assert_success "runs main for stdin execution" bootstrap_should_run_main "" ""
  assert_success "runs main for file execution" bootstrap_should_run_main "./bootstrap.sh" "./bootstrap.sh"
  assert_failure "skips main when sourced" bootstrap_should_run_main "$ROOT_DIR/bootstrap.sh" "$ROOT_DIR/tests/run.sh"
  pass "bootstrap_should_run_main"
}

test_resolve_archive_url() {
  local original_script_dir="$SCRIPT_DIR"
  local original_archive_url="$BOOTSTRAP_ARCHIVE_URL"
  local original_repo="$BOOTSTRAP_GITHUB_REPO"
  local original_default_repo="$BOOTSTRAP_DEFAULT_GITHUB_REPO"
  local tmpdir
  local archive_url

  tmpdir="$(mktemp -d)"
  SCRIPT_DIR="$tmpdir"

  BOOTSTRAP_ARCHIVE_URL="https://example.com/archive.tar.gz"
  archive_url="$(resolve_archive_url)"
  assert_equals "https://example.com/archive.tar.gz" "$archive_url" "prefers explicit archive URL"

  BOOTSTRAP_ARCHIVE_URL=""
  BOOTSTRAP_GITHUB_REPO="ExampleOrg/example-repo"
  archive_url="$(resolve_archive_url)"
  assert_equals "https://codeload.github.com/ExampleOrg/example-repo/tar.gz/refs/heads/main" "$archive_url" "uses explicit GitHub repo"

  BOOTSTRAP_GITHUB_REPO=""
  BOOTSTRAP_DEFAULT_GITHUB_REPO="GlitterX/vps-auto-config"
  archive_url="$(resolve_archive_url)"
  assert_equals "https://codeload.github.com/GlitterX/vps-auto-config/tar.gz/refs/heads/main" "$archive_url" "falls back to default GitHub repo"

  SCRIPT_DIR="$original_script_dir"
  BOOTSTRAP_ARCHIVE_URL="$original_archive_url"
  BOOTSTRAP_GITHUB_REPO="$original_repo"
  BOOTSTRAP_DEFAULT_GITHUB_REPO="$original_default_repo"
  rm -rf "$tmpdir"
  pass "resolve_archive_url"
}

test_ui_has_usable_tty() {
  local original_ui_tty_device="$UI_TTY_DEVICE"
  local tmpfile

  tmpfile="$(mktemp)"
  UI_TTY_DEVICE="$tmpfile"
  assert_success "readable fallback tty device is accepted" ui_has_usable_tty

  UI_TTY_DEVICE="$tmpfile.missing"
  if [[ -t 0 ]]; then
    pass "ui_has_usable_tty"
  else
    assert_failure "missing tty device is rejected when stdin is not a tty" ui_has_usable_tty
    pass "ui_has_usable_tty"
  fi

  UI_TTY_DEVICE="$original_ui_tty_device"
  rm -f "$tmpfile"
}

test_ui_menu_falls_back_to_xterm_for_unknown_term() {
  local resolved_term
  local tmpfile

  tmpfile="$(mktemp)"
  resolved_term="$(
    TERM="xterm-kitty"

    infocmp() {
      [[ "$1" == "xterm" ]]
    }

    whiptail() {
      printf '%s\n' "$TERM" >"$tmpfile"
    }

    ui_menu "标题" "提示" "value" "label"
  )"

  resolved_term="$(cat "$tmpfile")"
  rm -f "$tmpfile"
  assert_equals "xterm" "$resolved_term" "falls back to xterm when current TERM is unsupported"
  pass "ui_menu_falls_back_to_xterm_for_unknown_term"
}

test_ui_menu_keeps_supported_term() {
  local resolved_term
  local tmpfile

  tmpfile="$(mktemp)"
  resolved_term="$(
    TERM="xterm-256color"

    infocmp() {
      [[ "$1" == "xterm-256color" ]]
    }

    whiptail() {
      printf '%s\n' "$TERM" >"$tmpfile"
    }

    ui_menu "标题" "提示" "value" "label"
  )"

  resolved_term="$(cat "$tmpfile")"
  rm -f "$tmpfile"
  assert_equals "xterm-256color" "$resolved_term" "keeps supported TERM for whiptail"
  pass "ui_menu_keeps_supported_term"
}

test_ui_menu_fails_when_no_usable_term_exists() {
  local output

  output="$(
    TERM="xterm-kitty"

    infocmp() {
      return 1
    }

    whiptail() {
      fail "whiptail should not run without a usable TERM"
    }

    ui_menu "标题" "提示" "value" "label" 2>&1 || true
  )"

  assert_contains "$output" "未找到可用的终端类型" "fails clearly when no compatible TERM exists"
  pass "ui_menu_fails_when_no_usable_term_exists"
}

test_ui_menu_resets_terminal_for_interactive_tty() {
  local events
  local tmpfile

  tmpfile="$(mktemp)"
  (
    TERM="xterm"
    UI_TEST_EVENTS_FILE="$tmpfile"

    ui_has_interactive_stdin() {
      return 0
    }

    infocmp() {
      [[ "$1" == "xterm" ]]
    }

    stty() {
      printf 'stty:%s\n' "$*" >>"$UI_TEST_EVENTS_FILE"
    }

    whiptail() {
      printf 'whiptail:%s\n' "$TERM" >>"$UI_TEST_EVENTS_FILE"
    }

    ui_menu "标题" "提示" "value" "label"
  )

  events="$(cat "$tmpfile")"
  rm -f "$tmpfile"
  assert_contains "$events" "stty:sane" "resets terminal state before whiptail on interactive tty"
  assert_contains "$events" "whiptail:xterm" "continues to launch whiptail after terminal reset"
  pass "ui_menu_resets_terminal_for_interactive_tty"
}

test_ui_menu_skips_terminal_reset_without_interactive_tty() {
  local events
  local tmpfile

  tmpfile="$(mktemp)"
  (
    TERM="xterm"
    UI_TEST_EVENTS_FILE="$tmpfile"

    ui_has_interactive_stdin() {
      return 1
    }

    infocmp() {
      [[ "$1" == "xterm" ]]
    }

    stty() {
      printf 'stty:%s\n' "$*" >>"$UI_TEST_EVENTS_FILE"
    }

    whiptail() {
      printf 'whiptail:%s\n' "$TERM" >>"$UI_TEST_EVENTS_FILE"
    }

    ui_menu "标题" "提示" "value" "label"
  )

  events="$(cat "$tmpfile")"
  rm -f "$tmpfile"
  assert_not_contains "$events" "stty:sane" "skips terminal reset without interactive tty"
  assert_contains "$events" "whiptail:xterm" "still launches whiptail when term is usable"
  pass "ui_menu_skips_terminal_reset_without_interactive_tty"
}

test_set_runtime_hostname_fallback() {
  local result

  result="$(
    has_command() {
      [[ "$1" == "hostnamectl" ]]
    }

    hostnamectl() {
      printf '%s\n' ": unknown option" >&2
      return 1
    }

    hostname() {
      if [[ $# -eq 0 ]]; then
        printf '%s\n' "old-host"
        return 0
      fi

      if [[ "$1" == "aliyun-zhazha" ]]; then
        return 0
      fi

      return 1
    }

    system_config_set_runtime_hostname "aliyun-zhazha"
  )"

  assert_equals "" "$result" "falls back to hostname when hostnamectl fails"
  pass "set_runtime_hostname_fallback"
}

test_set_runtime_hostname_fallback_when_hostnamectl_is_noisy() {
  local result
  local hostname_state_file

  hostname_state_file="$(mktemp)"
  printf '%s\n' "old-host" >"$hostname_state_file"

  result="$(
    has_command() {
      [[ "$1" == "hostnamectl" ]]
    }

    hostnamectl() {
      printf '%s\n' ": unknown option"
      return 0
    }

    hostname() {
      local current_hostname
      current_hostname="$(cat "$hostname_state_file")"

      if [[ $# -eq 0 ]]; then
        printf '%s\n' "$current_hostname"
        return 0
      fi

      if [[ "$1" == "aliyun-zhazha" ]]; then
        printf '%s\n' "$1" >"$hostname_state_file"
        return 0
      fi

      return 1
    }

    system_config_set_runtime_hostname "aliyun-zhazha"
    printf 'runtime=%s\n' "$(cat "$hostname_state_file")"
  )"

  rm -f "$hostname_state_file"
  assert_equals "runtime=aliyun-zhazha" "$result" "falls back when hostnamectl is noisy and runtime hostname stays unchanged"
  pass "set_runtime_hostname_fallback_when_hostnamectl_is_noisy"
}

test_set_runtime_hostname_failure() {
  local result

  result="$(
    has_command() {
      return 1
    }

    hostname() {
      if [[ $# -eq 0 ]]; then
        printf '%s\n' "old-host"
        return 0
      fi

      printf '%s\n' "permission denied" >&2
      return 1
    }

    system_config_set_runtime_hostname "aliyun-zhazha" || true
  )"

  assert_contains "$result" "failed|更新运行中 hostname 失败" "reports hostname update failure clearly"
  assert_contains "$result" "permission denied" "includes hostname command error output"
  pass "set_runtime_hostname_failure"
}

test_get_sshd_config_value() {
  local config_file="$ROOT_DIR/tests/fixtures/sshd_config-sample"
  local root_value
  local password_value
  local pubkey_value

  root_value="$(get_sshd_config_value "$config_file" "PermitRootLogin" "yes")"
  password_value="$(get_sshd_config_value "$config_file" "PasswordAuthentication" "yes")"
  pubkey_value="$(get_sshd_config_value "$config_file" "PubkeyAuthentication" "no")"

  assert_equals "prohibit-password" "$root_value" "reads PermitRootLogin current value"
  assert_equals "no" "$password_value" "reads PasswordAuthentication current value"
  assert_equals "yes" "$pubkey_value" "reads PubkeyAuthentication current value"
  pass "get_sshd_config_value"
}

test_build_ssh_toggle_actions() {
  local raw_selection='"ssh:pubkey_auth"'
  local plan_output

  plan_output="$(security_build_ssh_toggle_actions "$raw_selection")"
  assert_contains "$plan_output" "PubkeyAuthentication=yes" "selected pubkey stays enabled"
  assert_contains "$plan_output" "PasswordAuthentication=no" "unselected password auth becomes disabled"
  pass "build_ssh_toggle_actions"
}

test_apply_sshd_value() {
  local tmpfile
  local current_value

  tmpfile="$(mktemp)"
  cat > "$tmpfile" <<'EOF'
Port 21212
PasswordAuthentication no
EOF

  security_apply_sshd_value "$tmpfile" "PasswordAuthentication" "yes"
  current_value="$(get_sshd_config_value "$tmpfile" "PasswordAuthentication" "missing")"
  assert_equals "yes" "$current_value" "updates existing sshd config value"

  security_apply_sshd_value "$tmpfile" "PubkeyAuthentication" "yes"
  current_value="$(get_sshd_config_value "$tmpfile" "PubkeyAuthentication" "missing")"
  assert_equals "yes" "$current_value" "appends missing sshd config value"

  if security_apply_sshd_value "$tmpfile" "PubkeyAuthentication" "yes"; then
    fail "security_apply_sshd_value should skip when value is unchanged"
  fi
  current_value="$(get_sshd_config_value "$tmpfile" "PubkeyAuthentication" "missing")"
  assert_equals "yes" "$current_value" "keeps same value when already configured"

  rm -f "$tmpfile"
  pass "apply_sshd_value"
}

test_write_file_if_changed() {
  local tmpfile
  local content_one="hello"
  local content_two="world"

  tmpfile="$(mktemp)"

  write_file_if_changed "$tmpfile" "$content_one"
  assert_equals "$content_one" "$(cat "$tmpfile")" "writes missing file content"

  if write_file_if_changed "$tmpfile" "$content_one"; then
    fail "write_file_if_changed should skip when content is unchanged"
  fi

  write_file_if_changed "$tmpfile" "$content_two"
  assert_equals "$content_two" "$(cat "$tmpfile")" "rewrites file when content changes"

  rm -f "$tmpfile"
  pass "write_file_if_changed"
}

test_upsert_line_if_needed() {
  local tmpfile

  tmpfile="$(mktemp)"
  cat > "$tmpfile" <<'EOF'
127.0.0.1 localhost
127.0.1.1 old-host
EOF

  upsert_line_if_needed "$tmpfile" '^127\.0\.1\.1[[:space:]]+' '127.0.1.1 new-host'
  assert_contains "$(cat "$tmpfile")" "127.0.1.1 new-host" "replaces existing matching line"

  if upsert_line_if_needed "$tmpfile" '^127\.0\.1\.1[[:space:]]+' '127.0.1.1 new-host'; then
    fail "upsert_line_if_needed should skip when line is unchanged"
  fi

  upsert_line_if_needed "$tmpfile" '^/swapfile[[:space:]]+' '/swapfile none swap sw 0 0'
  assert_contains "$(cat "$tmpfile")" "/swapfile none swap sw 0 0" "appends missing line"

  rm -f "$tmpfile"
  pass "upsert_line_if_needed"
}

test_install_requires_root() {
  local output
  local status=0

  set +e
  output="$(bash "$ROOT_DIR/install.sh" 2>&1)"
  status=$?
  set -e

  if [[ $EUID -eq 0 ]]; then
    assert_equals "0" "$status" "root environment should allow install.sh preflight"
  else
    if [[ $status -eq 0 ]]; then
      fail "install.sh should fail for non-root user"
    fi
    assert_contains "$output" "请使用 sudo 或 root 用户执行该脚本" "non-root message"
  fi

  pass "install_requires_root"
}

run_all() {
  test_validate_hostname
  test_detect_supported_ubuntu
  test_parse_checklist_output
  test_build_github_archive_url
  test_resolve_script_dir
  test_bootstrap_should_run_main
  test_resolve_archive_url
  test_ui_has_usable_tty
  test_ui_menu_falls_back_to_xterm_for_unknown_term
  test_ui_menu_keeps_supported_term
  test_ui_menu_fails_when_no_usable_term_exists
  test_ui_menu_resets_terminal_for_interactive_tty
  test_ui_menu_skips_terminal_reset_without_interactive_tty
  test_set_runtime_hostname_fallback
  test_set_runtime_hostname_fallback_when_hostnamectl_is_noisy
  test_set_runtime_hostname_failure
  test_get_sshd_config_value
  test_build_ssh_toggle_actions
  test_apply_sshd_value
  test_write_file_if_changed
  test_upsert_line_if_needed
  test_install_requires_root
}

run_all
