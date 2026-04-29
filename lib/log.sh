#!/usr/bin/env bash

log_timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

log_info() {
  printf '[%s] [INFO] %s\n' "$(log_timestamp)" "$*" >&2
}

log_warn() {
  printf '[%s] [WARN] %s\n' "$(log_timestamp)" "$*" >&2
}

log_error() {
  printf '[%s] [ERROR] %s\n' "$(log_timestamp)" "$*" >&2
}

log_success() {
  printf '[%s] [OK] %s\n' "$(log_timestamp)" "$*" >&2
}
