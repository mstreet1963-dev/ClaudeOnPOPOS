#!/usr/bin/env bash
# Recover a Claude Code environment from a Windows install onto Pop!_OS / Linux.
#
# Expected source layout (on the mounted Windows drive):
#   <SRC>/Users/msdst/.claude/{projects,sessions,todos,plans,plugins,hooks,
#                              session-env,statsig,settings.json,
#                              mcp-needs-auth-cache.json,.credentials.json,...}
#
# Usage:
#   ./recover-claude-env.sh --src "/run/media/$USER/255 GB Volume" [--dest "$HOME/.claude"]
#                           [--user msdst] [--dry-run] [--force]

set -euo pipefail

SRC=""
DEST="${HOME}/.claude"
WIN_USER="msdst"
DRY_RUN=0
FORCE=0

log()   { printf '\033[1;34m[info]\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
err()   { printf '\033[1;31m[err ]\033[0m %s\n' "$*" >&2; }
run()   { if (( DRY_RUN )); then printf '\033[2m[dry ] %s\033[0m\n' "$*"; else eval "$@"; fi; }

usage() {
    sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while (( $# )); do
    case "$1" in
        --src)     SRC="$2"; shift 2 ;;
        --dest)    DEST="$2"; shift 2 ;;
        --user)    WIN_USER="$2"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        --force)   FORCE=1; shift ;;
        -h|--help) usage 0 ;;
        *) err "unknown arg: $1"; usage 1 ;;
    esac
done

# ---------- locate source ----------
if [[ -z "$SRC" ]]; then
    for candidate in \
        "/run/media/$USER/255 GB Volume" \
        "/run/media/$USER"/* \
        "/media/$USER"/* \
        "/mnt"/*; do
        [[ -d "$candidate/Users/$WIN_USER/.claude" ]] && { SRC="$candidate"; break; }
    done
fi
[[ -z "$SRC" ]] && { err "could not auto-detect source drive; pass --src"; exit 2; }

SRC_CLAUDE="$SRC/Users/$WIN_USER/.claude"
[[ -d "$SRC_CLAUDE" ]] || { err "not a .claude directory: $SRC_CLAUDE"; exit 2; }

log "source : $SRC_CLAUDE"
log "dest   : $DEST"
(( DRY_RUN )) && log "mode   : DRY RUN (no changes)"

# ---------- back up existing dest ----------
if [[ -e "$DEST" ]]; then
    if (( FORCE )); then
        stamp="$(date +%Y%m%d-%H%M%S)"
        backup="${DEST}.bak.${stamp}"
        log "existing $DEST -> $backup"
        run "mv \"$DEST\" \"$backup\""
    else
        warn "$DEST already exists; rerun with --force to back it up, or --dest <other>"
        exit 3
    fi
fi
run "mkdir -p \"$DEST\""

# ---------- what to copy ----------
# Portable across OSes (per-user data, not machine-specific):
PORTABLE=(
    projects        # session history per cwd; paths encode Windows cwd but data is preserved
    sessions
    todos
    plans
    plugins
    session-env
    statsig
    backups
    skills
)
# Portable but review recommended:
PORTABLE_REVIEW=(
    hooks           # may contain .bat/.ps1 or Windows paths
    settings.json
    mcp-needs-auth-cache.json
)
# Skipped (Windows-specific or non-portable):
SKIP=(
    shell-snapshots # Windows cmd/powershell snapshots, useless on Linux
    ide             # Windows IDE integration state
    debug
    telemetry
    .credentials.json  # DPAPI-sealed on Windows; re-auth on Linux
)

# ---------- copy portable items ----------
copy_item() {
    local name="$1"
    local src="$SRC_CLAUDE/$name"
    local dst="$DEST/$name"
    if [[ ! -e "$src" ]]; then
        warn "missing on source: $name (skipping)"
        return
    fi
    log "copy   $name"
    if [[ -d "$src" ]]; then
        run "cp -a \"$src/.\" \"$dst/\" 2>/dev/null || cp -a \"$src\" \"$dst\""
    else
        run "cp -a \"$src\" \"$dst\""
    fi
}

for item in "${PORTABLE[@]}" "${PORTABLE_REVIEW[@]}"; do
    copy_item "$item"
done

for item in "${SKIP[@]}"; do
    [[ -e "$SRC_CLAUDE/$item" ]] && warn "skipping (non-portable): $item"
done

# ---------- rewrite Windows paths in settings.json ----------
SETTINGS="$DEST/settings.json"
if [[ -f "$SETTINGS" ]] && ! (( DRY_RUN )); then
    log "rewriting Windows paths in settings.json"
    python3 - "$SETTINGS" "$WIN_USER" "$USER" <<'PY' || warn "settings rewrite failed; original preserved"
import json, re, shutil, sys
path, win_user, lin_user = sys.argv[1], sys.argv[2], sys.argv[3]
shutil.copy2(path, path + ".pre-recover")
raw = open(path, "r", encoding="utf-8").read()
# C:\Users\msdst\...  or  C:/Users/msdst/...  ->  /home/<linuser>/...
patterns = [
    (re.compile(rf"[A-Za-z]:\\\\Users\\\\{re.escape(win_user)}\\\\", re.I), f"/home/{lin_user}/"),
    (re.compile(rf"[A-Za-z]:/Users/{re.escape(win_user)}/", re.I),        f"/home/{lin_user}/"),
    (re.compile(r"\\\\"),                                                   "/"),
]
for pat, repl in patterns:
    raw = pat.sub(repl, raw)
try:
    json.loads(raw)  # validate
    open(path, "w", encoding="utf-8").write(raw)
    print("[info] settings.json rewritten (backup: settings.json.pre-recover)")
except json.JSONDecodeError as e:
    print(f"[warn] rewrite produced invalid JSON ({e}); original restored")
    shutil.copy2(path + ".pre-recover", path)
PY
fi

# ---------- permissions & ownership ----------
if ! (( DRY_RUN )); then
    log "fixing permissions"
    chmod 700 "$DEST" 2>/dev/null || true
    [[ -f "$DEST/settings.json" ]] && chmod 600 "$DEST/settings.json" || true
    find "$DEST" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
fi

# ---------- summary ----------
log "done."
cat <<EOF

Next steps:
  1. Re-authenticate:  claude login       # Windows creds won't decrypt on Linux
  2. Review hooks:     ls "$DEST/hooks"   # remove any *.bat / *.ps1
  3. Sanity-check:     cat "$DEST/settings.json"
  4. Launch:           claude

If anything looks off, a backup of your previous ~/.claude is at ${DEST}.bak.*.
EOF
