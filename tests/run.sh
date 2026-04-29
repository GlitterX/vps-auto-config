#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$ROOT_DIR/lib/detect.sh"
source "$ROOT_DIR/lib/config.sh"
source "$ROOT_DIR/lib/ui.sh"
source "$ROOT_DIR/modules/security.sh"

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
  test_get_sshd_config_value
  test_build_ssh_toggle_actions
  test_apply_sshd_value
  test_write_file_if_changed
  test_upsert_line_if_needed
  test_install_requires_root
}

run_all
