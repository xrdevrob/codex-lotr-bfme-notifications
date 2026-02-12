#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SET_THEME="$ROOT_DIR/scripts/set-theme.sh"
PLAY_SOUND="$ROOT_DIR/scripts/play-theme-sound.sh"
CODEX_WRAP="$ROOT_DIR/scripts/codex-with-sound.sh"
NOTIFY_SCRIPT="$ROOT_DIR/scripts/codex-notify.sh"
VOICES_DIR="$ROOT_DIR/sounds-library/voices"
CODEX_CONFIG_FILE="${CODEX_CONFIG_FILE:-$HOME/.codex/config.toml}"

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

list_child_dirs() {
  local parent="$1"
  find "$parent" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sort
}

choose_option_arrow() {
  local title="$1"
  shift
  local -a options=("$@")
  local selected=0
  local key=""
  local extra=""
  local i

  if [[ ${#options[@]} -eq 0 ]]; then
    return 1
  fi

  echo "$title" >&2
  echo "Use Up/Down arrows and Enter." >&2

  while true; do
    for i in "${!options[@]}"; do
      if (( i == selected )); then
        echo "  > ${options[i]}" >&2
      else
        echo "    ${options[i]}" >&2
      fi
    done

    IFS= read -rsn1 key
    if [[ "$key" == $'\x1b' ]]; then
      IFS= read -rsn2 extra || true
      key+="$extra"
    fi

    case "$key" in
      $'\x1b[A')
        selected=$(( (selected - 1 + ${#options[@]}) % ${#options[@]} ))
        ;;
      $'\x1b[B')
        selected=$(( (selected + 1) % ${#options[@]} ))
        ;;
      ""|$'\n'|$'\r')
        printf '\033[%dA' "${#options[@]}" >&2
        printf '\033[J' >&2
        echo "  Selected: ${options[selected]}" >&2
        echo >&2
        printf '%s\n' "$selected"
        return 0
        ;;
      *)
        ;;
    esac

    printf '\033[%dA' "${#options[@]}" >&2
  done
}

choose_option_numeric() {
  local title="$1"
  shift
  local -a options=("$@")
  local input=""
  local option
  local i

  if [[ ${#options[@]} -eq 0 ]]; then
    return 1
  fi

  echo "$title" >&2
  i=1
  for option in "${options[@]}"; do
    echo "  $i) $option" >&2
    i=$((i + 1))
  done
  echo >&2

  while [[ -z "$input" ]]; do
    read -r -p "Enter number (1-${#options[@]}): " input
    if [[ ! "$input" =~ ^[0-9]+$ ]] || (( input < 1 || input > ${#options[@]} )); then
      echo "Invalid selection. Try again." >&2
      input=""
    fi
  done

  echo >&2
  printf '%s\n' "$((input - 1))"
}

choose_option_index() {
  local title="$1"
  shift
  local -a options=("$@")

  if [[ -t 0 && -t 2 ]]; then
    choose_option_arrow "$title" "${options[@]}"
  else
    choose_option_numeric "$title" "${options[@]}"
  fi
}

pick_theme_from_folders() {
  local -a groups=()
  local -a leaves=()
  local -a labels=()
  local group_dir
  local leaf_dir
  local selection_idx
  local back_idx

  while IFS= read -r group_dir; do
    [[ -n "$group_dir" ]] && groups+=("$group_dir")
  done < <(list_child_dirs "$VOICES_DIR")

  if [[ ${#groups[@]} -eq 0 ]]; then
    echo "No voice category folders found under: $VOICES_DIR" >&2
    return 1
  fi

  while true; do
    labels=()
    for group_dir in "${groups[@]}"; do
      labels+=("$(basename "$group_dir")")
    done

    selection_idx="$(choose_option_index "Choose a voice category:" "${labels[@]}")"
    group_dir="${groups[selection_idx]}"

    leaves=()
    while IFS= read -r leaf_dir; do
      [[ -n "$leaf_dir" ]] && leaves+=("$leaf_dir")
    done < <(list_child_dirs "$group_dir")

    if [[ ${#leaves[@]} -eq 0 ]]; then
      printf '%s\n' "${group_dir#"$VOICES_DIR/"}"
      return 0
    fi

    labels=()
    for leaf_dir in "${leaves[@]}"; do
      labels+=("$(basename "$leaf_dir")")
    done
    labels+=("Back")
    back_idx=${#leaves[@]}

    selection_idx="$(choose_option_index "Choose a voice folder in $(basename "$group_dir"):" "${labels[@]}")"
    if (( selection_idx == back_idx )); then
      continue
    fi

    leaf_dir="${leaves[selection_idx]}"
    printf '%s\n' "${leaf_dir#"$VOICES_DIR/"}"
    return 0
  done
}

echo "Codex LOTR Sound Setup"
echo
echo "This wizard sets your notification theme for task completion."
echo

if [[ ! -d "$VOICES_DIR" ]]; then
  echo "Voices folder not found: $VOICES_DIR" >&2
  exit 1
fi

current_theme="$($SET_THEME --show 2>/dev/null || true)"
if [[ -z "$current_theme" ]]; then
  current_theme="<not set>"
fi
echo "Current theme: $current_theme"
echo

choice="$(pick_theme_from_folders)"

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
