eMushpedia backup
=================

*Uses [`composes/emushpedia-backup.yml`](../../composes/emushpedia-backup.yml).*

This template sets up a nightly **pull** backup of an [`emushpedia`](../emushpedia/README.md) environment running on
another host, into a [restic](https://restic.net) repository (deduplicated, compressed, encrypted).

The backup host connects to the wiki host; the wiki host has no access to the backups.


## Services

* `emushpedia-backup` - Alpine image with restic, rsync, OpenSSH and [supercronic](https://github.com/aptible/supercronic),
  running `backup` on `BACKUP_SCHEDULE`. Job output goes to `docker logs`.

Each run:

1. dumps each wiki database (`mysqldump --single-transaction`) and streams it into restic: one snapshot per wiki,
   tagged `db`, path `/emushpedia_<wiki>.sql`. If the dump fails, no snapshot is saved,
2. rsyncs the source `live/emushpedia/` directory to `data/files/` (images, `LocalSettings.php`, extensions, oauth2,
   DKIM keys, env files, ...), then backs it up (tag `files`). `data/mysql` is covered by the dumps, `data/opensearch`
   is rebuilt by CirrusSearch, so both are excluded,
3. applies the retention (`KEEP_DAILY`, `KEEP_WEEKLY`, `KEEP_MONTHLY`) and prunes,
4. on `CHECK_WEEKDAY`, reads back `CHECK_SUBSET` of the data (`restic check --read-data-subset`).


## Template structure

```
templates/emushpedia-backup/
├── .docker.env                     # BACKUP_UID / BACKUP_GID of the container user
├── .env                            # schedule, source host, retention
├── docker/                         # Docker build context
│   ├── Dockerfile
│   ├── backup.sh                   # installed as /usr/local/bin/backup
│   └── entrypoint.sh
├── secrets/                        # mounted read-only on /config
│   ├── id_ed25519                  # (to create) SSH key used to reach the source host
│   ├── known_hosts                 # (to create) source host key
│   └── restic.pwd                  # (to create) restic repository password
├── data/
│   ├── restic/                     # the restic repository
│   ├── files/                      # rsync staging area
│   └── cache/                      # restic cache
└── source-host/
    └── backup-ssh-wrapper.sh       # to install on the source host
```


## Setup (with `qcoumes-deployment`)

1. Copy the template and fill `.env` (`SOURCE_HOST`, `SOURCE_PORT`, `SOURCE_USER`) and `.docker.env`:

    ```bash
    cp -r templates/emushpedia-backup live/emushpedia-backup
    ```

2. Create the secrets. **Save `restic.pwd` somewhere else (e.g. a password manager)**: without it, the backups cannot
   be read.

    ```bash
    cd live/emushpedia-backup/secrets
    ssh-keygen -t ed25519 -N "" -C "emushpedia-backup@$(hostname)" -f id_ed25519
    (umask 077; openssl rand -base64 48 | tr -d '\n' > restic.pwd)
    ssh-keyscan -p <port> <host> > known_hosts   # check the fingerprint against the source host!
    chmod 600 id_ed25519 restic.pwd
    ```

3. On the source host, copy `source-host/backup-ssh-wrapper.sh` to `live/emushpedia/bin/` (edit `LIVE` and the
   MySQL container name if needed), then authorize the key **with the forced command** in `~/.ssh/authorized_keys`:

    ```
    restrict,command="/srv/qcoumes-deployment/live/emushpedia/bin/backup-ssh-wrapper.sh" ssh-ed25519 AAAA... emushpedia-backup@titan
    ```

    The wrapper only accepts `dump <fr|en|es>` and a read-only rsync (`rrsync -ro`) of `live/emushpedia`. The source
    user needs access to Docker and passwordless `sudo` (the DKIM keys are only readable by root).

4. Start the service. The repository is created on the first run if `data/restic/` is empty:

    ```bash
    ./bin/up.sh emushpedia-backup
    docker exec emushpedia-backup backup      # first backup, now
    ```

After changing anything in `docker/`, rebuild with
`docker compose -p emushpedia-backup -f composes/emushpedia-backup.yml up -d --build`.


## Usage

`restic` is configured in the container, so it can be used directly:

```bash
docker logs emushpedia-backup                          # output of the scheduled runs
docker exec emushpedia-backup backup                   # run a backup now
docker exec emushpedia-backup restic snapshots
docker exec emushpedia-backup restic stats --mode raw-data
```


## Restore

```bash
# A database, into the emushpedia MySQL container
docker exec emushpedia-backup restic dump latest --path /emushpedia_fr.sql /emushpedia_fr.sql \
  | docker exec -i emushpedia-mysql sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot'

# The files (not into data/files/: it is the rsync target, emptied by --delete)
docker exec emushpedia-backup restic restore latest --tag files --target /tmp/restore
docker cp emushpedia-backup:/tmp/restore/data/files ./emushpedia-files
docker exec emushpedia-backup rm -rf /tmp/restore
```

A dump contains `CREATE DATABASE IF NOT EXISTS` and drops/recreates each table. The search index is not backed up:
rebuild it with CirrusSearch's `ForceSearchIndex.php` after a restore.
