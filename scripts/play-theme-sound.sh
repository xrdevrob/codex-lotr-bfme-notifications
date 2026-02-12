#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THEME_FILE="$ROOT_DIR/.codex-theme"
CACHE_DIR="$ROOT_DIR/.codex-cache"
OS_NAME="$(uname -s 2>/dev/null || echo unknown)"

usage() {
  cat <<'EOF'
Usage:
  play-theme-sound.sh [theme]
  play-theme-sound.sh --list
  play-theme-sound.sh --prime-cache [theme]
  play-theme-sound.sh --refresh-cache [theme]

Plays a random sound bite from the selected theme.
If [theme] is omitted, the value in .codex-theme is used.
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

resolve_theme() {
  if [[ -n "${1:-}" ]]; then
    printf '%s\n' "$1"
    return
  fi

  if [[ -f "$THEME_FILE" ]]; then
    tr -d '[:space:]' <"$THEME_FILE"
    return
  fi

  printf 'elves\n'
}

theme_dirs() {
  local theme="$1"
  case "$theme" in
    elves)
      printf '%s\n' \
        "$ROOT_DIR/sounds-library/voices/ELVEN HEROES" \
        "$ROOT_DIR/sounds-library/voices/ELVEN UNITS"
      ;;
    men)
      printf '%s\n' \
        "$ROOT_DIR/sounds-library/voices/MEN OF THE WEST HEROES" \
        "$ROOT_DIR/sounds-library/voices/MEN OF THE WEST UNITS"
      ;;
    dwarves)
      printf '%s\n' \
        "$ROOT_DIR/sounds-library/voices/DWARVEN HEROES" \
        "$ROOT_DIR/sounds-library/voices/DWARVEN UNITS"
      ;;
    aragorn)
      printf '%s\n' \
        "$ROOT_DIR/sounds-library/voices/MEN OF THE WEST HEROES/Aragorn"
      ;;
    legolas)
      printf '%s\n' \
        "$ROOT_DIR/sounds-library/voices/ELVEN HEROES/Legolas"
      ;;
    *)
      return 1
      ;;
  esac
}

available_players() {
  # On macOS, prefer a converted PCM path to avoid ADPCM decode/player issues.
  if [[ "$OS_NAME" == "Darwin" ]]; then
    if command -v ffmpeg >/dev/null 2>&1 && command -v afplay >/dev/null 2>&1; then
      printf '%s\n' "afplay_pcm"
    fi
    if command -v afplay >/dev/null 2>&1; then
      printf '%s\n' "afplay"
    fi
    if command -v ffplay >/dev/null 2>&1; then
      printf '%s\n' "ffplay"
    fi
  else
    if command -v paplay >/dev/null 2>&1; then
      printf '%s\n' "paplay"
    fi
    if command -v aplay >/dev/null 2>&1; then
      printf '%s\n' "aplay"
    fi
    if command -v play >/dev/null 2>&1; then
      printf '%s\n' "play"
    fi
    if command -v ffplay >/dev/null 2>&1; then
      printf '%s\n' "ffplay"
    fi
  fi
}

hash_file() {
  local file="$1"
  if command -v md5 >/dev/null 2>&1; then
    md5 -q "$file"
    return
  fi
  if command -v md5sum >/dev/null 2>&1; then
    md5sum "$file" | awk '{print $1}'
    return
  fi
  shasum -a 1 "$file" | awk '{print $1}'
}

converted_file_for_source() {
  local theme="$1"
  local source_file="$2"
  local file_hash
  file_hash="$(hash_file "$source_file")"
  printf '%s\n' "$CACHE_DIR/converted/$theme/$file_hash.wav"
}

ensure_converted_pcm() {
  local source_file="$1"
  local converted_file="$2"

  mkdir -p "$(dirname "$converted_file")"
  if [[ -s "$converted_file" && "$source_file" -ot "$converted_file" ]]; then
    return 0
  fi

  ffmpeg -v error -y -i "$source_file" -acodec pcm_s16le -ac 1 -ar 44100 "$converted_file" >/dev/null 2>&1
}

ffplay_with_validation() {
  local file="$1"
  local err_file
  local rc

  err_file="$(mktemp "${TMPDIR:-/tmp}/codex-ffplay.XXXXXX")"
  ffplay -nodisp -autoexit -loglevel error "$file" >/dev/null 2>"$err_file"
  rc=$?

  if grep -qiE 'audio open failed|failed to open file|no more combinations' "$err_file"; then
    rc=1
  fi

  if [[ "${CODEX_SOUND_DEBUG:-0}" == "1" && "$rc" -ne 0 ]]; then
    echo "ffplay error for: $file" >&2
    sed -n '1,120p' "$err_file" >&2
  fi

  rm -f "$err_file"
  return "$rc"
}

play_file() {
  local player="$1"
  local file="$2"
  local theme="$3"
  local converted
  case "$player" in
    afplay_pcm)
      converted="$(converted_file_for_source "$theme" "$file")"
      ensure_converted_pcm "$file" "$converted" || return 1
      afplay "$converted" >/dev/null 2>&1
      ;;
    ffplay)
      ffplay_with_validation "$file"
      ;;
    afplay)
      afplay "$file" >/dev/null 2>&1
      ;;
    paplay)
      paplay "$file" >/dev/null 2>&1
      ;;
    aplay)
      aplay "$file" >/dev/null 2>&1
      ;;
    play)
      play -q "$file" >/dev/null 2>&1
      ;;
    *)
      return 1
      ;;
  esac
}

cache_file_for_theme() {
  printf '%s\n' "$CACHE_DIR/candidates-$1.txt"
}

build_candidates_raw() {
  local theme="$1"
  local -a dirs=()
  local dir
  local all_files
  local preferred_all
  local preferred_regex='(voisel|voiseb|voisal|select)'

  while IFS= read -r dir; do
    [[ -n "$dir" ]] && dirs+=("$dir")
  done < <(theme_dirs "$theme")

  if [[ ${#dirs[@]} -eq 0 ]]; then
    return 1
  fi

  all_files="$(find "${dirs[@]}" -type f \( -iname '*.wav' -o -iname '*.mp3' \) 2>/dev/null || true)"
  if [[ -z "$all_files" ]]; then
    return 1
  fi

  preferred_all="$(printf '%s\n' "$all_files" | grep -Ei "$preferred_regex" || true)"
  if [[ -n "$preferred_all" ]]; then
    printf '%s\n' "$preferred_all"
  else
    printf '%s\n' "$all_files"
  fi
}

prime_cache_for_theme() {
  local theme="$1"
  local cache_file
  local candidates

  mkdir -p "$CACHE_DIR"
  cache_file="$(cache_file_for_theme "$theme")"
  candidates="$(build_candidates_raw "$theme" || true)"
  if [[ -z "$candidates" ]]; then
    return 1
  fi

  printf '%s\n' "$candidates" | awk 'NF' >"$cache_file"
  [[ -s "$cache_file" ]]
}

load_cache_file() {
  local theme="$1"
  local refresh_cache="$2"
  local cache_file

  cache_file="$(cache_file_for_theme "$theme")"
  if [[ "$refresh_cache" == "1" || ! -s "$cache_file" ]]; then
    prime_cache_for_theme "$theme" || return 1
  fi

  printf '%s\n' "$cache_file"
}

pick_random_from_cache() {
  local cache_file="$1"
  local count
  local idx

  count="$(wc -l <"$cache_file" | tr -d '[:space:]')"
  if [[ -z "$count" || "$count" -eq 0 ]]; then
    return 1
  fi

  idx=$(( (RANDOM % count) + 1 ))
  sed -n "${idx}p" "$cache_file"
}

REFRESH_CACHE="0"
PRIME_ONLY="0"
THEME_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --list)
      list_themes
      exit 0
      ;;
    --refresh-cache)
      REFRESH_CACHE="1"
      shift
      ;;
    --prime-cache)
      PRIME_ONLY="1"
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ -z "$THEME_ARG" ]]; then
        THEME_ARG="$1"
      else
        echo "Unexpected argument: $1" >&2
        usage >&2
        exit 1
      fi
      shift
      ;;
  esac
done

THEME="$(resolve_theme "$THEME_ARG")"
if ! theme_exists "$THEME"; then
  echo "Unknown theme: $THEME" >&2
  echo "Valid themes: $(list_themes | tr '\n' ',' | sed 's/,$//')" >&2
  exit 1
fi

CACHE_FILE="$(load_cache_file "$THEME" "$REFRESH_CACHE" || true)"
if [[ -z "$CACHE_FILE" || ! -s "$CACHE_FILE" ]]; then
  echo "No audio files found for theme: $THEME" >&2
  exit 1
fi

if [[ "$PRIME_ONLY" == "1" ]]; then
  echo "Primed cache for theme: $THEME" >&2
  exit 0
fi

PLAYERS="$(available_players || true)"
if [[ -z "$PLAYERS" ]]; then
  echo "No supported audio player found." >&2
  exit 1
fi

echo "Theme: $THEME" >&2

MAX_ATTEMPTS=8
ATTEMPT=1
while [[ "$ATTEMPT" -le "$MAX_ATTEMPTS" ]]; do
  CHOSEN_FILE="$(pick_random_from_cache "$CACHE_FILE" || true)"
  if [[ -z "$CHOSEN_FILE" ]]; then
    break
  fi

  if [[ "$ATTEMPT" -eq 1 ]]; then
    echo "Playing: ${CHOSEN_FILE#$ROOT_DIR/}" >&2
  fi

  while IFS= read -r player; do
    if [[ -n "$player" ]] && play_file "$player" "$CHOSEN_FILE" "$THEME"; then
      if [[ "$ATTEMPT" -gt 1 ]]; then
        echo "Playing fallback: ${CHOSEN_FILE#$ROOT_DIR/}" >&2
      fi
      exit 0
    fi
  done < <(printf '%s\n' "$PLAYERS")

  ATTEMPT=$((ATTEMPT + 1))
done

echo "Failed to play a sound after $MAX_ATTEMPTS attempts." >&2
exit 1
