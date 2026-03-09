#!/usr/bin/env bash
# fix-stuck-nodes.sh — auto-resume Slurm nodes stuck in transient failure states
# Safe: only acts on nodes with Slurm-generated reasons; skips admin-set reasons.

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration (env-overridable)
# ---------------------------------------------------------------------------
LOG_FILE="${SLURM_HEALTH_LOG_DIR:-/var/log/slurm}/node-health.log"
LOCK_FILE="${SLURM_HEALTH_LOCK:-/tmp/slurm-node-health.lock}"
DRY_RUN="${SLURM_HEALTH_DRY_RUN:-0}"
MAX_LOG_BYTES=$((50 * 1024 * 1024))   # rotate at 50 MB

SCRIPT_NAME="$(basename "$0")"

# ---------------------------------------------------------------------------
# Lock — exit 0 immediately if another instance is already running
# ---------------------------------------------------------------------------
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    # Can't write to log yet (setup not called), so use stderr only
    echo "$(date -Is) [$SCRIPT_NAME] [WARN] Already running — exiting" >&2
    exit 0
fi

# ---------------------------------------------------------------------------
# setup — ensure log directory exists
# ---------------------------------------------------------------------------
setup() {
    mkdir -p "$(dirname "$LOG_FILE")"
}

# ---------------------------------------------------------------------------
# rotate_log_if_needed — mv log to timestamped .old if > MAX_LOG_BYTES
# ---------------------------------------------------------------------------
rotate_log_if_needed() {
    if [[ -f "$LOG_FILE" ]]; then
        local size
        size=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
        if (( size > MAX_LOG_BYTES )); then
            local ts
            ts=$(date +%Y%m%dT%H%M%S)
            mv "$LOG_FILE" "${LOG_FILE%.log}.${ts}.old"
        fi
    fi
}

# ---------------------------------------------------------------------------
# log LEVEL msg
# ---------------------------------------------------------------------------
log() {
    local level="$1"
    local msg="$2"
    local ts
    ts=$(date '+%Y-%m-%dT%H:%M:%S')
    local line="${ts} [$SCRIPT_NAME] [${level}] ${msg}"
    echo "$line" | tee -a "$LOG_FILE"
}

# ---------------------------------------------------------------------------
# is_slurm_auto_reason REASON
# Returns 0 (safe to auto-resume) for empty/none or known Slurm-auto reasons.
# Returns 1 (admin-set, leave alone) for anything else.
# ---------------------------------------------------------------------------
is_slurm_auto_reason() {
    local reason="${1:-}"

    # Strip trailing annotation like [user@timestamp] that Slurm appends
    reason="${reason% \[*}"

    # Empty or literal "none" → safe
    local lower="${reason,,}"
    [[ -z "$lower" || "$lower" == "none" ]] && return 0

    # Known Slurm-auto-generated reason prefixes / exact strings
    local pattern
    for pattern in \
        "^not responding" \
        "^not_responding" \
        "^slurmd contact timeout" \
        "^slurmdcontacttimeout" \
        "^kill task failed" \
        "^node unexpectedly rebooted" \
        "^low socket.core.thread count" \
        "^low realmemory" \
        "^prolog not responding" \
        "^epilog not responding" \
        "^communication error" \
        "^slurm error" \
    ; do
        [[ "$lower" =~ $pattern ]] && return 0
    done

    return 1
}

# ---------------------------------------------------------------------------
# do_resume NODE STATE REASON
# ---------------------------------------------------------------------------
do_resume() {
    local node="$1" state="$2" reason="$3"
    log "ACTION" "Resuming node=${node} state=${state} reason=${reason}"

    if [[ "$DRY_RUN" == "1" ]]; then
        log "INFO" "[DRY-RUN] Would run: scontrol update NodeName=${node} State=resume"
        return
    fi

    local output
    local rc=0
    output=$(scontrol update NodeName="${node}" State=resume 2>&1) || rc=$?
    if (( rc == 0 )); then
        log "INFO" "scontrol resume succeeded for node=${node}"
    else
        log "ERROR" "scontrol resume failed for node=${node} rc=${rc} output=${output}"
    fi
}

# ---------------------------------------------------------------------------
# classify_and_act NODE STATE REASON
# ---------------------------------------------------------------------------
classify_and_act() {
    local node="$1" state="$2" reason="$3"

    log "INFO" "Checking node=${node} state=${state} reason=${reason}"

    case "$state" in
        down|down+drain|down+drain+not_responding|not_responding|down+not_responding|drain|drained)
            if is_slurm_auto_reason "$reason"; then
                do_resume "$node" "$state" "$reason"
            else
                log "SKIP" "node=${node} state=${state} reason=${reason} — admin reason"
            fi
            ;;
        draining|draining+not_responding)
            log "SKIP" "node=${node} state=${state} — node has active jobs"
            ;;
        *)
            log "DEBUG" "node=${node} state=${state} — unhandled state, skipping"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# process_nodes — query sinfo and act on each node
# ---------------------------------------------------------------------------
process_nodes() {
    local found=0
    while IFS='|' read -r node state reason; do
        [[ -z "$node" ]] && continue
        found=1
        classify_and_act "$node" "$state" "$reason"
    done < <(sinfo -h -N -o "%N|%T|%E" --states=down,drain,not_responding 2>/dev/null || true)

    if (( found == 0 )); then
        log "INFO" "No nodes in down/drain/not_responding states"
    fi
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
    setup
    rotate_log_if_needed
    log "INFO" "Starting node health check (DRY_RUN=${DRY_RUN})"
    process_nodes
    log "INFO" "Node health check complete"
}

main
