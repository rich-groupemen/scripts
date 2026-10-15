#!/usr/bin/env bash
#
# greet.sh — Example bash executable. Template for new bin/ scripts.
#
# Usage:
#   bin/greet.sh [--name NAME] [--shout]
#
# Examples:
#   bin/greet.sh --name World
#   bin/greet.sh --name World --shout
#
set -Eeuo pipefail

trap 'echo "greet.sh: error on line ${LINENO}" >&2' ERR

# Resolve repo root relative to this script, so it works from any cwd.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${REPO_ROOT}/lib/common.sh"

usage() {
  cat << EOF
Usage: ${0##*/} [--name NAME] [--shout] [--help]

Greet someone. Example script demonstrating repo conventions.

Options:
  --name NAME   Who to greet (default: World)
  --shout       Uppercase the greeting
  -h, --help    Show this help
EOF
}

main() {
  local name="World"
  local shout=false

  while (($# > 0)); do
    case "$1" in
      --name)
        name="${2:?--name requires a value}"
        shift 2
        ;;
      --shout)
        shout=true
        shift
        ;;
      -h | --help)
        usage
        return 0
        ;;
      *)
        log_error "Unknown option: $1"
        usage >&2
        return 2
        ;;
    esac
  done

  local message="Hello, ${name}!"
  if [[ "${shout}" == true ]]; then
    message="${message^^}"
  fi
  log_info "${message}"
}

main "$@"
