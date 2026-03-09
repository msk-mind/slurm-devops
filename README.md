# slurm-devops

DevOps scripts and cron jobs for the MSK MIND Slurm HPC cluster.

## Contents

| Path | Purpose |
|---|---|
| `scripts/node-health/fix-stuck-nodes.sh` | Auto-resumes nodes stuck in transient failure states |
| `scripts/node-health/install.sh` | Installs the node health script and cron job |
| `cron/slurm-node-health.cron` | Cron job definition (every 5 min, runs as `slurm` user) |

## Node Health

Detects and resumes Slurm compute nodes in `down`, `drain`, or `not_responding` states that got there due to transient Slurm-generated reasons (e.g. "not responding", "kill task failed"). Nodes with admin-set reasons are left alone.

### Install

```bash
sudo bash scripts/node-health/install.sh
```

Installs to `/usr/local/sbin/slurm-node-health` and `/etc/cron.d/slurm-node-health`.

### Test (dry run)

```bash
SLURM_HEALTH_DRY_RUN=1 SLURM_HEALTH_LOG_DIR=/tmp /usr/local/sbin/slurm-node-health
```

### Configuration

| Variable | Default | Purpose |
|---|---|---|
| `SLURM_HEALTH_LOG_DIR` | `/var/log/slurm` | Log directory |
| `SLURM_HEALTH_LOCK` | `/tmp/slurm-node-health.lock` | Lock file path |
| `SLURM_HEALTH_DRY_RUN` | `0` | Set to `1` to skip `scontrol` calls |

Logs to `/var/log/slurm/node-health.log`. Rotates at 50 MB.

## See Also

[Slurm DevOps — MSK MIND Confluence](https://mskconfluence.mskcc.org/spaces/MM/pages/160712277/Slurm+DevOps)
