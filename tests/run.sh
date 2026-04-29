#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$ROOT_DIR/lib/detect.sh"
source "$ROOT_DIR/lib/ui.sh"

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
  test_install_requires_root
}

run_all
