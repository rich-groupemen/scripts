#!/usr/bin/env bash
#
# lib/common.sh — Shared logging and helper functions.
# Sourced by bin/ scripts; never executed directly.
#
# shellcheck shell=bash

# Guard against double-sourcing.
[[ -n "${_COMMON_SH_LOADED:-}" ]] && return 0
_COMMON_SH_LOADED=1

log_info() {
  printf '[INFO] %s\n' "$*" >&2
}

log_warn() {
  printf '[WARN] %s\n' "$*" >&2
}

log_error() {
  printf '[ERROR] %s\n' "$*" >&2
}

# require_cmd COMMAND... — exit 1 if any command is missing.
require_cmd() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "${cmd}" > /dev/null 2>&1; then
      log_error "Required command not found: ${cmd}"
      return 1
    fi
  done
}
