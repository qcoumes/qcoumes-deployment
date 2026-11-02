#!/usr/bin/env bash
# Pull backup of the eMushpedia wikis into the restic repository at /data/restic.
#
# 1. each wiki database is dumped on the source host and streamed into restic,
# 2. the source env directory (minus data/mysql and data/opensearch) is rsynced
#    to /data/files, then backed up,
# 3. old snapshots are pruned, and the repository is checked once a week.
#
# On the source host, the SSH key must be restricted by
# source-host/backup-ssh-wrapper.sh (see README.md), which only accepts
# "dump <wiki>" and a read-only rsync.
set -euo pipefail

: "${SOURCE_HOST:?missing}" "${SOURCE_USER:?missing}" "${SOURCE_PORT:=22}"
: "${WIKIS:=fr en es}"
: "${SNAPSHOT_HOST:=emushpedia}"
: "${KEEP_DAILY:=7}" "${KEEP_WEEKLY:=4}" "${KEEP_MONTHLY:=12}"
: "${CHECK_WEEKDAY:=7}" "${CHECK_SUBSET:=10%}"

STAGE=/data/files
SSH=(ssh -i /config/id_ed25519 -o IdentitiesOnly=yes -o BatchMode=yes
     -o UserKnownHostsFile=/config/known_hosts -o StrictHostKeyChecking=yes
     -o ServerAliveInterval=30 -p "$SOURCE_PORT" "$SOURCE_USER@$SOURCE_HOST")

log() { echo "[$(date '+%F %T')] $*"; }

# A manual `docker exec ... backup` must not overlap the scheduled one.
exec 9>/data/cache/.backup.lock
flock -n 9 || { log "another backup is already running"; exit 1; }

if ! restic cat config >/dev/null 2>&1; then
  if [ -z "$(ls -A /data/restic | grep -v '^\.gitkeep$')" ]; then
    log "empty repository directory, running restic init"
    restic init
  else
    log "cannot open the restic repository (wrong password?)" >&2
    exit 1
  fi
fi

# 1. Databases, streamed straight into restic (no snapshot is saved if the dump fails)
for wiki in $WIKIS; do
  log "dump emushpedia_$wiki"
  restic backup --quiet --host "$SNAPSHOT_HOST" --tag db \
    --stdin-from-command --stdin-filename "emushpedia_$wiki.sql" -- \
    "${SSH[@]}" "dump $wiki"
done

# 2. Files: images, LocalSettings, extensions, oauth2, DKIM keys, env files, scripts.
#    data/mysql is covered by the dumps, data/opensearch is rebuilt by CirrusSearch.
log "rsync files"
rsync -a --delete --exclude /data/mysql --exclude /data/opensearch \
  -e "${SSH[*]}" :./ "$STAGE/"
log "backup files"
restic backup --quiet --host "$SNAPSHOT_HOST" --tag files "$STAGE"

# 3. Retention
log "forget/prune"
restic forget --quiet --host "$SNAPSHOT_HOST" \
  --keep-daily "$KEEP_DAILY" --keep-weekly "$KEEP_WEEKLY" --keep-monthly "$KEEP_MONTHLY" --prune

# 4. Integrity check, once a week (date +%u: 1 = Monday ... 7 = Sunday)
if [ "$(date +%u)" = "$CHECK_WEEKDAY" ]; then
  log "check (read $CHECK_SUBSET of the data)"
  restic check --read-data-subset="$CHECK_SUBSET"
fi

log "done"
