#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_HOOK_PATH="$ROOT_DIR/scripts/codex-notify.sh"
CONFIG_FILE="${CODEX_CONFIG_FILE:-$HOME/.codex/config.toml}"
HOOK_PATH="$DEFAULT_HOOK_PATH"
PURGE_LOCAL=0

usage() {
  cat <<'EOF'
Usage: scripts/uninstall.sh [options]

Removes this repository's Codex notify hook from config.

Options:
  --config PATH      Use a custom Codex config path (default: ~/.codex/config.toml)
  --hook PATH        Remove a specific hook path (default: this repo's scripts/codex-notify.sh)
  --purge-local      Also remove .codex-theme and .codex-cache from this repo
  -h, --help         Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --config" >&2
        exit 2
      fi
      CONFIG_FILE="$2"
      shift 2
      ;;
    --hook)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --hook" >&2
        exit 2
      fi
      HOOK_PATH="$2"
      shift 2
      ;;
    --purge-local)
      PURGE_LOCAL=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

remove_hook_from_config() {
  local config_file="$1"
  local hook_path="$2"

  if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is required for automatic uninstall editing." >&2
    echo "Manual step: remove this path from notify in $config_file" >&2
    echo "  $hook_path" >&2
    return 3
  fi

  python3 - "$config_file" "$hook_path" <<'PY'
from pathlib import Path
import re
import sys

config_path = Path(sys.argv[1]).expanduser()
hook_path = str(Path(sys.argv[2]).expanduser())


def escape_string(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def unescape_basic(value: str) -> str:
    return value.replace(r'\"', '"').replace(r'\\', '\\')


def normalize(value: str) -> str:
    return str(Path(value).expanduser())


if not config_path.exists():
    print("missing-config")
    raise SystemExit(0)

text = config_path.read_text(encoding="utf-8")
if not text.strip():
    print("missing-notify")
    raise SystemExit(0)

pattern = re.compile(r"(?ms)^notify\s*=\s*\[(.*?)\]")
match = pattern.search(text)
if match is None:
    print("missing-notify")
    raise SystemExit(0)

inner = match.group(1)
raw_paths = re.findall(r'"((?:\\.|[^"\\])*)"', inner)
paths = [unescape_basic(item) for item in raw_paths]

hook_norm = normalize(hook_path)
kept = [item for item in paths if normalize(item) != hook_norm]

if len(kept) == len(paths):
    print("not-present")
    raise SystemExit(0)

if kept:
    quoted_paths = ", ".join(f'"{escape_string(item)}"' for item in kept)
    replacement = f"notify = [{quoted_paths}]"
    updated = text[:match.start()] + replacement + text[match.end():]
else:
    # Remove notify entry entirely when this was the last hook.
    updated = text[:match.start()] + text[match.end():]
    updated = re.sub(r"\n{3,}", "\n\n", updated)
    if updated.startswith("\n"):
        updated = updated.lstrip("\n")

if updated and not updated.endswith("\n"):
    updated += "\n"

config_path.write_text(updated, encoding="utf-8")
print("removed")
PY
}

status="$(remove_hook_from_config "$CONFIG_FILE" "$HOOK_PATH")"
exit_code=$?
if [[ $exit_code -ne 0 ]]; then
  exit $exit_code
fi

case "$status" in
  removed)
    echo "Removed notify hook from $CONFIG_FILE"
    ;;
  missing-config)
    echo "No Codex config found at $CONFIG_FILE (nothing to remove)."
    ;;
  missing-notify)
    echo "No notify entry found in $CONFIG_FILE (nothing to remove)."
    ;;
  not-present)
    echo "Notify hook was not present in $CONFIG_FILE."
    ;;
  *)
    echo "Unexpected result while editing $CONFIG_FILE: $status" >&2
    exit 1
    ;;
esac

if [[ "$PURGE_LOCAL" -eq 1 ]]; then
  rm -rf "$ROOT_DIR/.codex-cache" "$ROOT_DIR/.codex-theme"
  echo "Removed local state: $ROOT_DIR/.codex-cache and $ROOT_DIR/.codex-theme"
fi

echo "Uninstall complete."
