#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THEME_FILE="$ROOT_DIR/.codex-theme"
VOICES_DIR="$ROOT_DIR/sounds-library/voices"

usage() {
  cat <<'EOF_USAGE'
Usage:
  set-theme.sh <theme>
  set-theme.sh --show
  set-theme.sh --list
  set-theme.sh --list-groups

`<theme>` must be a folder theme path like:
- ELVEN UNITS/Lorien Archers
EOF_USAGE
}

list_groups() {
  if [[ ! -d "$VOICES_DIR" ]]; then
    return 1
  fi

  find "$VOICES_DIR" -mindepth 1 -maxdepth 1 -type d -print \
    | sed "s#^$VOICES_DIR/##" \
    | sort
}

list_folder_themes() {
  if [[ ! -d "$VOICES_DIR" ]]; then
    return 1
  fi

  find "$VOICES_DIR" -mindepth 2 -maxdepth 2 -type d -print \
    | sed "s#^$VOICES_DIR/##" \
    | sort
}

list_themes() {
  list_folder_themes || true
}

default_theme() {
  local theme
  theme="$(list_folder_themes | head -n1 || true)"
  if [[ -n "$theme" ]]; then
    printf '%s\n' "$theme"
    return 0
  fi
  return 1
}

read_stored_theme() {
  local value=""

  if [[ -f "$THEME_FILE" ]]; then
    IFS= read -r value <"$THEME_FILE" || true
    # Trim only leading/trailing whitespace, keep internal spaces.
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    if [[ -n "$value" && -d "$VOICES_DIR/$value" ]]; then
      printf '%s\n' "$value"
      return
    fi
  fi

  default_theme || true
}

theme_exists() {
  [[ -d "$VOICES_DIR/$1" ]]
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" || $# -eq 0 ]]; then
  usage
  exit 0
fi

if [[ "${1:-}" == "--list" ]]; then
  list_themes
  exit 0
fi

if [[ "${1:-}" == "--list-groups" ]]; then
  list_groups
  exit 0
fi

if [[ "${1:-}" == "--show" ]]; then
  read_stored_theme
  exit 0
fi

THEME="$1"
if ! theme_exists "$THEME"; then
  echo "Unknown theme: $THEME" >&2
  echo "Run: $0 --list" >&2
  exit 1
fi

printf '%s\n' "$THEME" >"$THEME_FILE"
echo "Theme saved: $THEME"
