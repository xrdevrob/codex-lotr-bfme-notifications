#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THEME_FILE="$ROOT_DIR/.codex-theme"
CACHE_DIR="$ROOT_DIR/.codex-cache"
VOICES_DIR="$ROOT_DIR/sounds-library/voices"
OS_NAME="$(uname -s 2>/dev/null || echo unknown)"
DEFAULT_SOUND_VOLUME="0.35"

usage() {
  cat <<'EOF_USAGE'
Usage:
  play-theme-sound.sh [theme]
  play-theme-sound.sh --list
  play-theme-sound.sh --prime-cache [theme]
  play-theme-sound.sh --refresh-cache [theme]

Plays a random sound bite from the selected theme.
If [theme] is omitted, the value in .codex-theme is used.

Themes must be folder paths like: ELVEN UNITS/Lorien Archers
EOF_USAGE
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
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    if [[ -n "$value" && -d "$VOICES_DIR/$value" ]]; then
      printf '%s\n' "$value"
      return
    fi
  fi

  default_theme || true
}

resolve_theme() {
  if [[ -n "${1:-}" ]]; then
    printf '%s\n' "$1"
    return
  fi

  read_stored_theme
}

theme_dirs() {
  local theme="$1"

  if [[ -d "$VOICES_DIR/$theme" ]]; then
    printf '%s\n' "$VOICES_DIR/$theme"
    return 0
  fi

  return 1
}

theme_exists() {
  local theme="$1"
  theme_dirs "$theme" >/dev/null 2>&1
}

theme_cache_key() {
  local theme="$1"

  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$theme" | shasum -a 1 | awk '{print $1}'
    return
  fi

  if command -v md5sum >/dev/null 2>&1; then
    printf '%s' "$theme" | md5sum | awk '{print $1}'
    return
  fi

  if command -v md5 >/dev/null 2>&1; then
    md5 -q -s "$theme"
    return
  fi

  printf '%s' "$theme" | cksum | awk '{print $1}'
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

is_valid_volume() {
  local value="$1"
  awk -v value="$value" '
    BEGIN {
      if (value ~ /^([0-9]+([.][0-9]+)?|[.][0-9]+)$/ && value >= 0 && value <= 1) {
        exit 0
      }
      exit 1
    }
  '
}

resolve_sound_volume() {
  local raw_value="${CODEX_SOUND_VOLUME:-$DEFAULT_SOUND_VOLUME}"

  if ! is_valid_volume "$raw_value"; then
    echo "Invalid CODEX_SOUND_VOLUME: $raw_value (expected 0.0 to 1.0)." >&2
    raw_value="$DEFAULT_SOUND_VOLUME"
  fi

  awk -v value="$raw_value" 'BEGIN { printf "%.3f\n", value }'
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
  local theme_key="$1"
  local source_file="$2"
  local file_hash
  file_hash="$(hash_file "$source_file")"
  printf '%s\n' "$CACHE_DIR/converted/$theme_key/$file_hash.wav"
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
  ffplay -nodisp -autoexit -loglevel error -volume "$FFPLAY_VOLUME" "$file" >/dev/null 2>"$err_file"
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
  local theme_key="$3"
  local converted
  case "$player" in
    afplay_pcm)
      converted="$(converted_file_for_source "$theme_key" "$file")"
      ensure_converted_pcm "$file" "$converted" || return 1
      afplay -v "$SOUND_VOLUME" "$converted" >/dev/null 2>&1
      ;;
    ffplay)
      ffplay_with_validation "$file"
      ;;
    afplay)
      afplay -v "$SOUND_VOLUME" "$file" >/dev/null 2>&1
      ;;
    paplay)
      paplay --volume="$PAPLAY_VOLUME" "$file" >/dev/null 2>&1
      ;;
    aplay)
      aplay "$file" >/dev/null 2>&1
      ;;
    play)
      play -q -v "$SOUND_VOLUME" "$file" >/dev/null 2>&1
      ;;
    *)
      return 1
      ;;
  esac
}

cache_file_for_theme() {
  local theme="$1"
  local theme_key
  theme_key="$(theme_cache_key "$theme")"
  printf '%s\n' "$CACHE_DIR/candidates-$theme_key.txt"
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
  echo "Run: $0 --list" >&2
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

SOUND_VOLUME="$(resolve_sound_volume)"
FFPLAY_VOLUME="$(awk -v value="$SOUND_VOLUME" 'BEGIN { printf "%.0f\n", value * 100 }')"
PAPLAY_VOLUME="$(awk -v value="$SOUND_VOLUME" 'BEGIN { printf "%.0f\n", value * 65536 }')"

echo "Theme: $THEME" >&2
echo "Volume: $SOUND_VOLUME" >&2

THEME_CACHE_KEY="$(theme_cache_key "$THEME")"
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
    if [[ -n "$player" ]] && play_file "$player" "$CHOSEN_FILE" "$THEME_CACHE_KEY"; then
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
