#!/usr/bin/env bash

write_file_if_changed() {
  local target_file="$1"
  local desired_content="$2"
  local tmpfile

  tmpfile="$(mktemp)"
  printf '%s' "$desired_content" > "$tmpfile"

  if [[ -f "$target_file" ]] && cmp -s "$target_file" "$tmpfile"; then
    rm -f "$tmpfile"
    return 1
  fi

  cat "$tmpfile" > "$target_file"
  rm -f "$tmpfile"
  return 0
}

write_file_with_backup_if_changed() {
  local target_file="$1"
  local desired_content="$2"
  local tmpfile

  tmpfile="$(mktemp)"
  printf '%s' "$desired_content" > "$tmpfile"

  if [[ -f "$target_file" ]] && cmp -s "$target_file" "$tmpfile"; then
    rm -f "$tmpfile"
    return 1
  fi

  if [[ -f "$target_file" ]]; then
    backup_file "$target_file"
  fi

  cat "$tmpfile" > "$target_file"
  rm -f "$tmpfile"

  return 0
}

upsert_line_if_needed() {
  local target_file="$1"
  local match_regex="$2"
  local desired_line="$3"
  local tmpfile

  tmpfile="$(mktemp)"

  if [[ -f "$target_file" ]]; then
    grep -Ev "$match_regex" "$target_file" > "$tmpfile" || true
  fi

  printf '%s\n' "$desired_line" >> "$tmpfile"

  if [[ -f "$target_file" ]] && cmp -s "$target_file" "$tmpfile"; then
    rm -f "$tmpfile"
    return 1
  fi

  cat "$tmpfile" > "$target_file"
  rm -f "$tmpfile"
  return 0
}

upsert_line_with_backup_if_needed() {
  local target_file="$1"
  local match_regex="$2"
  local desired_line="$3"
  local tmpfile

  tmpfile="$(mktemp)"

  if [[ -f "$target_file" ]]; then
    grep -Ev "$match_regex" "$target_file" > "$tmpfile" || true
  fi

  printf '%s\n' "$desired_line" >> "$tmpfile"

  if [[ -f "$target_file" ]] && cmp -s "$target_file" "$tmpfile"; then
    rm -f "$tmpfile"
    return 1
  fi

  if [[ -f "$target_file" ]]; then
    backup_file "$target_file"
  fi

  cat "$tmpfile" > "$target_file"
  rm -f "$tmpfile"

  return 0
}
