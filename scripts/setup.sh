#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SET_THEME="$ROOT_DIR/scripts/set-theme.sh"
PLAY_SOUND="$ROOT_DIR/scripts/play-theme-sound.sh"
CODEX_WRAP="$ROOT_DIR/scripts/codex-with-sound.sh"
NOTIFY_SCRIPT="$ROOT_DIR/scripts/codex-notify.sh"
CODEX_CONFIG_FILE="${CODEX_CONFIG_FILE:-$HOME/.codex/config.toml}"

themes=(
  "elves"
  "men"
  "dwarves"
  "aragorn"
  "legolas"
)

ensure_notify_hook() {
  local config_file="$1"
  local hook_path="$2"

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$config_file" "$hook_path" <<'PY'
from pathlib import Path
import re
import sys

config_path = Path(sys.argv[1]).expanduser()
hook_path = sys.argv[2]


def escape_string(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def unescape_basic(value: str) -> str:
    return value.replace(r'\"', '"').replace(r'\\', '\\')


config_path.parent.mkdir(parents=True, exist_ok=True)
text = config_path.read_text(encoding="utf-8") if config_path.exists() else ""

if not text.strip():
    config_path.write_text(f'notify = ["{escape_string(hook_path)}"]\n', encoding="utf-8")
    print("added")
    raise SystemExit(0)

pattern = re.compile(r'(?ms)^notify\s*=\s*\[(.*?)\]')
match = pattern.search(text)

if match is None:
    if not text.endswith("\n"):
        text += "\n"
    text += f'notify = ["{escape_string(hook_path)}"]\n'
    config_path.write_text(text, encoding="utf-8")
    print("added")
    raise SystemExit(0)

inner = match.group(1)
raw_paths = re.findall(r'"((?:\\.|[^"\\])*)"', inner)
paths = [unescape_basic(item) for item in raw_paths]

if hook_path in paths:
    print("present")
    raise SystemExit(0)

paths.append(hook_path)
quoted_paths = ", ".join(f'"{escape_string(item)}"' for item in paths)
replacement = f"notify = [{quoted_paths}]"

updated = text[:match.start()] + replacement + text[match.end():]
config_path.write_text(updated, encoding="utf-8")
print("updated")
PY
    return
  fi

  mkdir -p "$(dirname "$config_file")"
  touch "$config_file"

  if grep -Fq "$hook_path" "$config_file"; then
    echo "present"
    return
  fi

  if grep -Eq '^notify[[:space:]]*=' "$config_file"; then
    echo "manual"
    return
  fi

  printf 'notify = ["%s"]\n' "$hook_path" >>"$config_file"
  echo "added"
}

echo "Codex LOTR Sound Setup"
echo
echo "This wizard sets your notification theme for task completion."
echo

current_theme="$("$SET_THEME" --show 2>/dev/null || echo "elves")"
echo "Current theme: $current_theme"
echo

echo "Choose a theme:"
i=1
for t in "${themes[@]}"; do
  echo "  $i) $t"
  i=$((i + 1))
done
echo

choice=""
while [[ -z "$choice" ]]; do
  read -r -p "Enter number (1-${#themes[@]}): " input
  if [[ "$input" =~ ^[0-9]+$ ]] && (( input >= 1 && input <= ${#themes[@]} )); then
    choice="${themes[input-1]}"
  else
    echo "Invalid selection. Try again."
  fi
done

"$SET_THEME" "$choice"
if "$PLAY_SOUND" --prime-cache "$choice" >/dev/null 2>&1; then
  echo "Cached theme audio for faster notifications."
fi

hook_status="$(ensure_notify_hook "$CODEX_CONFIG_FILE" "$NOTIFY_SCRIPT")"
config_display="$CODEX_CONFIG_FILE"
if [[ "$config_display" == "$HOME/"* ]]; then
  config_display="~/${config_display#"$HOME/"}"
fi

case "$hook_status" in
  added)
    echo "Installed Codex notify hook in $config_display."
    ;;
  updated)
    echo "Added this repo hook to notify list in $config_display."
    ;;
  present)
    echo "Codex notify hook already configured in $config_display."
    ;;
  manual)
    echo "Detected an existing notify setting in $config_display."
    echo "Add this hook path manually if needed:"
    echo "  $NOTIFY_SCRIPT"
    ;;
esac
echo

read -r -p "Play a test sound now? [Y/n]: " test_now
test_now_lc="$(printf '%s' "${test_now:-}" | tr '[:upper:]' '[:lower:]')"
if [[ -z "${test_now:-}" || "$test_now_lc" == "y" || "$test_now_lc" == "yes" ]]; then
  if ! "$PLAY_SOUND"; then
    echo "Warning: test playback failed."
    echo "Run: CODEX_SOUND_DEBUG=1 $PLAY_SOUND"
  fi
fi

echo
echo "Setup complete."
echo
echo "How to use with Codex:"
echo "1) Run Codex normally (recommended):"
echo "   codex \"your codex prompt\""
echo
echo "2) Optional wrapper mode (plays once when Codex exits):"
echo "   $CODEX_WRAP \"your codex prompt\""
echo
echo "3) Optional shell alias for wrapper mode:"
echo "   alias codexn='$CODEX_WRAP'"
echo "   codexn \"your codex prompt\""
echo
echo "4) Run diagnostics any time:"
echo "   $ROOT_DIR/scripts/doctor.sh"
echo
echo "No background server is needed."
echo "By default, sound plays at each agent turn completion via Codex notify hook."
echo "Optional async wrapper mode: CODEX_SOUND_ASYNC=1 $CODEX_WRAP \"your prompt\""
