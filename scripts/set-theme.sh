#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THEME_FILE="$ROOT_DIR/.codex-theme"

usage() {
  cat <<'EOF'
Usage:
  set-theme.sh <theme>
  set-theme.sh --show
  set-theme.sh --list

Themes:
  elves, men, dwarves, aragorn, legolas
EOF
}

list_themes() {
  cat <<'EOF'
elves
men
dwarves
aragorn
legolas
EOF
}

theme_exists() {
  case "$1" in
    elves|men|dwarves|aragorn|legolas) return 0 ;;
    *) return 1 ;;
  esac
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" || $# -eq 0 ]]; then
  usage
  exit 0
fi

if [[ "${1:-}" == "--list" ]]; then
  list_themes
  exit 0
fi

if [[ "${1:-}" == "--show" ]]; then
  if [[ -f "$THEME_FILE" ]]; then
    tr -d '[:space:]' <"$THEME_FILE"
    echo
  else
    echo "elves"
  fi
  exit 0
fi

THEME="$1"
if ! theme_exists "$THEME"; then
  echo "Unknown theme: $THEME" >&2
  echo "Valid themes: $(list_themes | tr '\n' ',' | sed 's/,$//')" >&2
  exit 1
fi

printf '%s\n' "$THEME" >"$THEME_FILE"
echo "Theme saved: $THEME"
