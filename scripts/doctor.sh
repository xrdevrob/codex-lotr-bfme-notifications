#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SET_THEME="$ROOT_DIR/scripts/set-theme.sh"
PLAY_SOUND="$ROOT_DIR/scripts/play-theme-sound.sh"
NOTIFY_SCRIPT="$ROOT_DIR/scripts/codex-notify.sh"
THEME_FILE="$ROOT_DIR/.codex-theme"
CACHE_DIR="$ROOT_DIR/.codex-cache"
CODEX_CONFIG_FILE="${CODEX_CONFIG_FILE:-$HOME/.codex/config.toml}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/doctor.sh
  scripts/doctor.sh --quick

Checks local setup for Codex LOTR notifications.
USAGE
}

QUICK_MODE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --quick)
      QUICK_MODE=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

ok() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'OK   %s\n' "$1"
}

warn() {
  WARN_COUNT=$((WARN_COUNT + 1))
  printf 'WARN %s\n' "$1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'FAIL %s\n' "$1"
}

has_command() {
  command -v "$1" >/dev/null 2>&1
}

detect_player() {
  if has_command afplay; then
    printf 'afplay\n'
    return 0
  fi
  if has_command paplay; then
    printf 'paplay\n'
    return 0
  fi
  if has_command aplay; then
    printf 'aplay\n'
    return 0
  fi
  if has_command play; then
    printf 'play\n'
    return 0
  fi
  if has_command ffplay; then
    printf 'ffplay\n'
    return 0
  fi
  return 1
}

mkdir -p "$CACHE_DIR"

echo "Codex LOTR Notification Doctor"
echo "Repo: $ROOT_DIR"
echo

if has_command codex; then
  ok "codex found at $(command -v codex)"
else
  fail "codex binary not found in PATH"
fi

if [[ -x "$SET_THEME" && -x "$PLAY_SOUND" && -x "$NOTIFY_SCRIPT" ]]; then
  ok "scripts are executable"
else
  fail "one or more required scripts are not executable"
fi

theme="elves"
if [[ -x "$SET_THEME" ]]; then
  theme="$($SET_THEME --show 2>/dev/null || echo "elves")"
elif [[ -f "$THEME_FILE" ]]; then
  IFS= read -r theme <"$THEME_FILE" || true
fi

if "$PLAY_SOUND" --prime-cache "$theme" >/dev/null 2>&1; then
  ok "theme is valid ($theme)"
else
  fail "theme is invalid ($theme). Run: $SET_THEME --list"
fi

if player="$(detect_player)"; then
  ok "audio player found ($player)"
else
  fail "no supported audio player found (afplay/paplay/aplay/play/ffplay)"
fi

if [[ -f "$CODEX_CONFIG_FILE" ]]; then
  if grep -Fq "$NOTIFY_SCRIPT" "$CODEX_CONFIG_FILE"; then
    ok "notify hook configured in $CODEX_CONFIG_FILE"
  elif grep -Eq '^notify[[:space:]]*=' "$CODEX_CONFIG_FILE"; then
    warn "notify is configured but does not include this repo hook"
  else
    fail "notify hook is missing in $CODEX_CONFIG_FILE"
  fi
else
  fail "Codex config not found at $CODEX_CONFIG_FILE"
fi

hook_log="$CACHE_DIR/doctor-notify-hook.log"
sound_log="$CACHE_DIR/doctor-playback.log"
rm -f "$hook_log" "$sound_log"
payload='{"type":"agent-turn-complete","source":"doctor"}'

if CODEX_SOUND_DEBUG=1 CODEX_HOOK_LOG_FILE="$hook_log" CODEX_SOUND_LOG_FILE="$sound_log" "$NOTIFY_SCRIPT" "$payload"; then
  if grep -Fq 'playing event_type=agent-turn-complete' "$hook_log"; then
    ok "notify hook accepts agent-turn-complete payload"
  else
    fail "notify hook ran but did not log turn-complete handling"
  fi
else
  fail "notify hook execution failed for synthetic payload"
fi

if [[ "$QUICK_MODE" == "0" ]]; then
  if "$PLAY_SOUND" >/dev/null 2>&1; then
    ok "playback script completed successfully"
  else
    warn "playback test failed (retry with: CODEX_SOUND_DEBUG=1 $PLAY_SOUND)"
  fi
fi

echo
printf 'Summary: %d OK, %d WARN, %d FAIL\n' "$PASS_COUNT" "$WARN_COUNT" "$FAIL_COUNT"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi

exit 0
