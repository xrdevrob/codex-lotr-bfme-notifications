#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLAY_SCRIPT="$ROOT_DIR/scripts/play-theme-sound.sh"
SOUND_LOG_FILE="${CODEX_SOUND_LOG_FILE:-$ROOT_DIR/.codex-cache/playback.log}"
HOOK_LOG_FILE="${CODEX_HOOK_LOG_FILE:-$ROOT_DIR/.codex-cache/notify-hook.log}"

payload="${1:-}"
if [[ -z "$payload" && ! -t 0 ]]; then
  payload="$(cat || true)"
fi

# Some callers may pass a path to a JSON payload file.
if [[ -n "$payload" && -f "$payload" ]]; then
  payload="$(cat "$payload" 2>/dev/null || true)"
fi

if [[ -z "$payload" ]]; then
  exit 0
fi

event_type=""
if command -v jq >/dev/null 2>&1; then
  event_type="$(printf '%s' "$payload" | jq -r '.type // .event_type // .event?.type // empty' 2>/dev/null || true)"
elif command -v python3 >/dev/null 2>&1; then
  event_type="$(
    python3 - "$payload" <<'PY'
import json
import sys
try:
    obj = json.loads(sys.argv[1])
    event_type = obj.get("type") or obj.get("event_type")
    if not event_type and isinstance(obj.get("event"), dict):
        event_type = obj["event"].get("type")
    print(event_type or "")
except Exception:
    pass
PY
  )"
fi

if [[ "$event_type" != "agent-turn-complete" ]]; then
  if [[ "${CODEX_SOUND_DEBUG:-0}" == "1" ]]; then
    mkdir -p "$ROOT_DIR/.codex-cache"
    printf '[%s] skipped event_type=%s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "${event_type:-<empty>}" >>"$HOOK_LOG_FILE"
  fi
  exit 0
fi

if [[ ! -x "$PLAY_SCRIPT" ]]; then
  if [[ "${CODEX_SOUND_DEBUG:-0}" == "1" ]]; then
    mkdir -p "$ROOT_DIR/.codex-cache"
    printf '[%s] play script not executable: %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$PLAY_SCRIPT" >>"$HOOK_LOG_FILE"
  fi
  exit 0
fi

# Keep Codex responsive: run playback in a short-lived background subprocess.
if [[ "${CODEX_SOUND_DEBUG:-0}" == "1" ]]; then
  mkdir -p "$ROOT_DIR/.codex-cache"
  printf '[%s] playing event_type=%s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$event_type" >>"$HOOK_LOG_FILE"
  (
    "$PLAY_SCRIPT"
  ) >>"$SOUND_LOG_FILE" 2>&1 < /dev/null &
else
  (
    "$PLAY_SCRIPT"
  ) >/dev/null 2>&1 < /dev/null &
fi

exit 0
