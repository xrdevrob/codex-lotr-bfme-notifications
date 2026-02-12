# codex-lotr-bfme-notifications

LOTR/BFME themed completion sounds for Codex runs.

## What this adds

- Theme selection from actual folder hierarchy (`voices/<CATEGORY>/<UNIT_OR_HERO>`)
- Random voice-line playback from `sounds-library/voices`
- Native Codex notification-hook integration (`agent-turn-complete`) for per-turn sounds

## Scripts

- `scripts/setup.sh` interactive wizard for first-time setup
- `scripts/set-theme.sh` sets or shows the current theme
- `scripts/play-theme-sound.sh` plays one random bite from the current theme
- `scripts/codex-notify.sh` Codex notify-hook target (reads event payload, plays on turn-complete)
- `scripts/codex-with-sound.sh` runs `codex "$@"` and then plays a completion sound
- `scripts/doctor.sh` validates your local install and hook wiring

## Simple setup (recommended)

```bash
chmod +x scripts/*.sh
./scripts/setup.sh
```

`setup.sh` does the following:

- Uses an interactive arrow-key picker (Up/Down + Enter)
- Lets you choose a category (for example `ELVEN UNITS`) and then a final folder (for example `Lorien Archers`)
- Lets you go back from the final folder list to the category list
- Primes the local sound cache
- Installs the Codex `notify` hook in `~/.codex/config.toml` (idempotent)

Then just run Codex normally:

```bash
codex "fix failing test in parser"
```

No wrapper is required for normal use.

## Theme model

- Preferred theme format is folder-based, for example:
  - `ELVEN UNITS/Lorien Archers`
  - `DWARVEN HEROES/Gimli`
- Legacy aliases are still supported for compatibility:
  - `elves`, `men`, `dwarves`, `aragorn`, `legolas`

## Notes

- Current theme is stored in `.codex-theme` at repo root.
- Cached candidate lists are stored in `.codex-cache/` for faster startup.
- On macOS playback uses `afplay`; Linux fallback supports `paplay`, `aplay`, or `play`.
- On macOS, if available, audio is auto-converted with `ffmpeg` and played via `afplay` for reliability.
- The player prefers more "voice-like" clips (`voisel`, `voiseb`, `voisal`, `select`) and falls back to any clip in the theme if needed.
- Rebuild cache manually with `./scripts/play-theme-sound.sh --refresh-cache`.
- Troubleshoot with `CODEX_SOUND_DEBUG=1 ./scripts/play-theme-sound.sh`.

## How it connects to Codex

- It is **not** a server and there is no always-on daemon.
- Native hook mode (recommended):
  1. Codex emits `agent-turn-complete`
  2. Codex runs `scripts/codex-notify.sh` with event JSON
  3. hook script triggers themed playback
- Optional wrapper mode:
  - `scripts/codex-with-sound.sh` plays once when the whole Codex process exits.
  - Useful if you want end-of-run sound only.

## Troubleshooting

- Check hook config:
  - `grep '^notify' ~/.codex/config.toml`
- Run diagnostics:
  - `./scripts/doctor.sh --quick`
- Re-run setup to repair config:
  - `./scripts/setup.sh`
- In your current shell, clear old alias overrides (if any):
  - `unalias codex 2>/dev/null`
- To capture playback errors to a log:
  - `CODEX_SOUND_DEBUG=1 codex "test"`
  - log file: `.codex-cache/playback.log`
