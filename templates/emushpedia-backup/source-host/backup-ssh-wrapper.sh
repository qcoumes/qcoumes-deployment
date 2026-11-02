#!/usr/bin/env bash
# Forced command for the titan backup key (see ~/.ssh/authorized_keys).
# Allows only: "dump <fr|en|es>" and a read-only rsync of live/emushpedia.
set -euo pipefail
LIVE=/srv/qcoumes-deployment/live/emushpedia
CMD="${SSH_ORIGINAL_COMMAND:-}"
CMD="${CMD#"${CMD%%[![:space:]]*}"}"  # strip leading spaces (rsync adds one)

case "$CMD" in
  "dump fr"|"dump en"|"dump es")
    db="emushpedia_${CMD#dump }"
    exec docker exec emushpedia-mysql sh -c "MYSQL_PWD=\"\$MYSQL_ROOT_PASSWORD\" exec mysqldump -uroot \
      --single-transaction --quick --routines --triggers --events --hex-blob --set-gtid-purged=OFF \
      --databases $db"
    ;;
  "rsync --server --sender "*)
    # sudo: data/mail/keys (DKIM) is root-only
    exec sudo -n env SSH_ORIGINAL_COMMAND="$CMD" /usr/bin/rrsync -ro "$LIVE"
    ;;
  *)
    echo "backup-ssh-wrapper: command not allowed: $CMD" >&2
    exit 1
    ;;
esac
