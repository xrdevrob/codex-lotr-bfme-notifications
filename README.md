# codex-lotr-bfme-notifications

LOTR/BFME-themed sound notifications for Codex turn completion.

## Quick Start

```bash
cd /path/to/codex-lotr-bfme-notifications
./scripts/setup.sh
codex "your prompt"
```

If you hit `permission denied`:

```bash
chmod +x scripts/*.sh
./scripts/setup.sh
```

## Common Commands

```bash
# Re-run interactive theme picker
./scripts/setup.sh

# Set a theme directly
./scripts/set-theme.sh "ELVEN UNITS/Lorien Archers"

# Show or list themes
./scripts/set-theme.sh --show
./scripts/set-theme.sh --list-groups
./scripts/set-theme.sh --list

# Play one sample now
./scripts/play-theme-sound.sh

# Diagnostics
./scripts/doctor.sh --quick
```

## Uninstall

Remove this repo's Codex notify hook:

```bash
./scripts/uninstall.sh
```

If Codex config still references an old repo path:

```bash
./scripts/uninstall.sh --hook "/old/path/codex-lotr-bfme-notifications/scripts/codex-notify.sh"
```

Also remove local theme/cache files:

```bash
./scripts/uninstall.sh --purge-local
```

If you added a wrapper alias:

```bash
unalias codexn 2>/dev/null
```

## How It Works

- `scripts/setup.sh` sets your theme and adds `scripts/codex-notify.sh` to `~/.codex/config.toml` `notify`.
- On `agent-turn-complete`, Codex runs the hook and one random clip plays from the current theme.
- No daemon or background service is required.

## Scripts

- `scripts/setup.sh`: first-time setup and theme picker
- `scripts/set-theme.sh`: set/show/list themes
- `scripts/play-theme-sound.sh`: play one random clip
- `scripts/codex-notify.sh`: Codex notify hook target
- `scripts/codex-with-sound.sh`: optional wrapper mode (play once when Codex exits)
- `scripts/doctor.sh`: installation/config checks
- `scripts/uninstall.sh`: remove this repo hook from Codex config

## Notes

- Theme is stored in `.codex-theme`.
- Cache/logs are in `.codex-cache/`.
- macOS uses `afplay`; Linux supports `paplay`, `aplay`, or `play`.
- For verbose playback troubleshooting: `CODEX_SOUND_DEBUG=1 ./scripts/play-theme-sound.sh`.
