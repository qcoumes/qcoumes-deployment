#!/usr/bin/env bash
# Runs `backup` on BACKUP_SCHEDULE with supercronic (cron that runs as non-root
# and logs job output to stdout, i.e. `docker logs`).
set -euo pipefail

: "${BACKUP_SCHEDULE:=0 4 * * *}"

echo "$BACKUP_SCHEDULE /usr/local/bin/backup" > /tmp/crontab
echo "[entrypoint] schedule: '$BACKUP_SCHEDULE' (TZ=${TZ:-UTC})"

if [ "${RUN_ON_START:-false}" = "true" ]; then
  echo "[entrypoint] RUN_ON_START=true, running a backup now"
  /usr/local/bin/backup || echo "[entrypoint] initial backup FAILED" >&2
fi

# Full path: as PID 1, supercronic re-executes itself through argv[0] to reap zombies.
exec /usr/bin/supercronic -passthrough-logs /tmp/crontab
