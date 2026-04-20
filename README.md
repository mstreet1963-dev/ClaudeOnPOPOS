# Recover Claude Code env from a Windows drive

A helper script for migrating a `.claude` user directory from a mounted Windows
disk onto Pop!_OS / Linux.

## What it does

Copies the portable pieces of your Claude Code environment (session history,
todos, plans, plugins, settings, MCP auth cache, etc.) and skips the
Windows-specific pieces that don't port cleanly (shell snapshots, IDE state,
DPAPI-sealed credentials).

## Usage

Plug in the Windows drive, then:

```bash
# Dry-run first to see what it would do:
./recover-claude-env.sh --src "/run/media/$USER/255 GB Volume" --dry-run

# Real run (backs up any existing ~/.claude as ~/.claude.bak.<timestamp>):
./recover-claude-env.sh --src "/run/media/$USER/255 GB Volume" --force
```

Flags:

| flag        | default         | purpose                                          |
|-------------|-----------------|--------------------------------------------------|
| `--src`     | auto-detected   | mount point of the Windows drive                 |
| `--dest`    | `~/.claude`     | where to restore to                              |
| `--user`    | `msdst`         | Windows username under `Users/`                  |
| `--dry-run` | off             | print actions without writing                    |
| `--force`   | off             | back up existing `--dest` and overwrite          |

## What's copied vs skipped

**Copied** (portable): `projects`, `sessions`, `todos`, `plans`, `plugins`,
`session-env`, `statsig`, `backups`, `skills`, `hooks`, `settings.json`,
`mcp-needs-auth-cache.json`.

**Skipped** (non-portable): `shell-snapshots` (Windows cmd/powershell),
`ide`, `debug`, `telemetry`, `.credentials.json` (Windows DPAPI-sealed —
run `claude login` after recovery).

## After running

1. `claude login` to refresh credentials.
2. Review `~/.claude/hooks/` and delete any `.bat` / `.ps1` files.
3. Inspect `~/.claude/settings.json` — the script rewrites
   `C:\Users\msdst\...` paths to `/home/$USER/...`, but custom hook commands
   may still reference Windows binaries.
