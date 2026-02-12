#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_PATH="$ROOT_DIR/scripts/codex-with-sound.sh"
PLAY_SCRIPT="${CODEX_PLAY_SCRIPT:-$ROOT_DIR/scripts/play-theme-sound.sh}"
SOUND_LOG_FILE="${CODEX_SOUND_LOG_FILE:-$ROOT_DIR/.codex-cache/playback.log}"

resolve_codex_bin() {
  if [[ -n "${CODEX_BIN:-}" ]]; then
    printf '%s\n' "$CODEX_BIN"
    return 0
  fi

  if [[ -x "/opt/homebrew/bin/codex" ]]; then
    printf '%s\n' "/opt/homebrew/bin/codex"
    return 0
  fi

  local found
  found="$(command -v codex || true)"
  if [[ -n "$found" && "$found" != "$SCRIPT_PATH" ]]; then
    printf '%s\n' "$found"
    return 0
  fi

  return 1
}

CODEX_BIN_PATH="$(resolve_codex_bin || true)"
if [[ -z "$CODEX_BIN_PATH" ]]; then
  echo "codex binary not found in PATH." >&2
  exit 127
fi

set +e
"$CODEX_BIN_PATH" "$@"
CODEX_EXIT=$?
set -e

if [[ -x "$PLAY_SCRIPT" ]]; then
  mkdir -p "$(dirname "$SOUND_LOG_FILE")"
  if [[ "${CODEX_SOUND_ASYNC:-0}" == "1" ]]; then
    if [[ "${CODEX_SOUND_DEBUG:-0}" == "1" ]]; then
      (
        "$PLAY_SCRIPT"
      ) >>"$SOUND_LOG_FILE" 2>&1 < /dev/null &
    else
      (
        "$PLAY_SCRIPT"
      ) >/dev/null 2>&1 < /dev/null &
    fi
  else
    "$PLAY_SCRIPT" || true
  fi
fi

exit "$CODEX_EXIT"
