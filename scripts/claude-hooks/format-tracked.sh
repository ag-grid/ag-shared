#!/usr/bin/env bash
# external/ag-shared/scripts/claude-hooks/format-tracked.sh
#
# Claude Code Stop hook. Formats the files edited this session (recorded by
# track-edit.sh) in length-capped `nx format` batches, then clears the list.
#
# On success            → clear the list, exit 0.
# On a genuine failure  → keep the failed files, exit non-zero so Claude Code
#                         surfaces its standard (non-blocking) "<hook> hook error"
#                         notice; the model can react, and we retry next turn.
# Benign "no files matched" (e.g. root config files nx can't map to a project)
# is treated as success rather than nagging every turn.
#
# Reads hook JSON on stdin: { "session_id": "...", "cwd": "...", ... }  (no tool_input on Stop)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

export NX_DAEMON=false
ch_sweep_stale

INPUT=$(cat 2>/dev/null || true)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)

LIST=$(ch_tracking_file "$SESSION_ID")
[ -f "$LIST" ] || exit 0

# Dedupe; keep only still-existing, formattable files.
mapfile -t FILES < <(sort -u "$LIST" | while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$f" ] && ch_is_formattable "$f" && printf '%s\n' "$f"
done)

if [ "${#FILES[@]}" -eq 0 ]; then
    rm -f "$LIST"
    exit 0
fi

ROOT="${CLAUDE_PROJECT_DIR:-$CWD}"
[ -n "$ROOT" ] && [ -d "$ROOT" ] || ROOT=$(git -C "${CWD:-.}" rev-parse --show-toplevel 2>/dev/null || echo "$CWD")
cd "$ROOT" 2>/dev/null || { ch_log "could not resolve repo root; keeping list"; exit 1; }

# A long --files value has been seen to get nx killed at launch (exit 137, no output).
MAX_BATCH_CHARS=500
FAILED=()

format_batch() {
    local csv out status
    csv=$(IFS=,; printf '%s' "$*")
    out=$(yarn nx format --files "$csv" 2>&1)
    status=$?
    [ "$status" -eq 0 ] && return 0

    # nx couldn't associate the file(s) with a project — benign, not a format error.
    printf '%s' "$out" | grep -q "No files matching the pattern were found" && return 0

    if [ "$status" -eq 137 ]; then
        ch_log "nx format was killed (SIGKILL), not a formatting error; not formatted: $csv"
    else
        # Genuine failure (e.g. a parse error in the model's own edit) — surface it.
        printf '%s\n' "$out" >&2
        ch_log "format failed for: $csv"
    fi
    FAILED+=("$@")
}

BATCH=()
BATCH_CHARS=0
for file in "${FILES[@]}"; do
    if [ "${#BATCH[@]}" -gt 0 ] && [ $((BATCH_CHARS + ${#file} + 1)) -gt "$MAX_BATCH_CHARS" ]; then
        format_batch "${BATCH[@]}"
        BATCH=()
        BATCH_CHARS=0
    fi
    BATCH+=("$file")
    BATCH_CHARS=$((BATCH_CHARS + ${#file} + 1))
done
format_batch "${BATCH[@]}"

if [ "${#FAILED[@]}" -eq 0 ]; then
    rm -f "$LIST"
    exit 0
fi

# Retry only what failed next turn.
printf '%s\n' "${FAILED[@]}" > "$LIST"
exit 1
