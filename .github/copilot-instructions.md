# Copilot Instructions

## Repository Purpose

Bash scripts and cron jobs for Slurm HPC cluster node health management. The primary script auto-resumes compute nodes that are stuck in transient failure states (down, drain, not_responding) without human intervention.

## Architecture

```
cron/slurm-node-health.cron   ← installed to /etc/cron.d/, runs every 5 min as slurm user
scripts/node-health/fix-stuck-nodes.sh  ← the actual health-check logic
```

**Flow:** cron triggers the script → script acquires a lock file → queries `sinfo` for down/drain/not_responding nodes → for each node, checks if the reason is Slurm-auto-generated vs. admin-set → resumes only auto-generated reasons via `scontrol`.

## Key Conventions

### Safe-Resume Pattern
The script only auto-resumes nodes whose `reason` field matches known Slurm-generated strings (e.g., `"not responding"`, `"kill task failed"`, `"communication error"`). Admin-set reasons (anything else) are skipped with a `SKIP` log entry. When adding new auto-resolvable reasons, add them to the `is_slurm_auto_reason()` function's pattern list.

### Environment-Overridable Configuration
All tunables are set via env vars with sane defaults:

| Variable | Default | Purpose |
|---|---|---|
| `SLURM_HEALTH_LOG_DIR` | `/var/log/slurm` | Directory for `node-health.log` |
| `SLURM_HEALTH_LOCK` | `/tmp/slurm-node-health.lock` | Lock file path |
| `SLURM_HEALTH_DRY_RUN` | `0` | Set to `1` to log actions without executing `scontrol` |

### Testing the Script
Run in dry-run mode against the real cluster (no changes made):
```bash
SLURM_HEALTH_DRY_RUN=1 SLURM_HEALTH_LOG_DIR=/tmp bash scripts/node-health/fix-stuck-nodes.sh
```

### Log Format
`YYYY-MM-DDTHH:MM:SS [fix-stuck-nodes.sh] [LEVEL] message`  
Levels: `INFO`, `ACTION`, `SKIP`, `DEBUG`, `ERROR`, `WARN`

Log rotates automatically at 50 MB (renamed to `.YYYYMMDDTHHMMSS.old`).

### Installation
```bash
sudo bash scripts/node-health/install.sh
```
Installs the script to `/usr/local/sbin/slurm-node-health` and the cron file to `/etc/cron.d/slurm-node-health`.
