File Browser
============

*Uses [`composes/filebrowser.yml`](../../composes/filebrowser.yml).*

This template sets up [FileBrowser Quantum](https://github.com/gtsteffaniak/filebrowser) (`gtstef/filebrowser`), a web
interface to browse, upload, share and download the files of a directory.

*This guide assume `traefik` is running, see the main [README.md](../../README.md).*


## Services

* `filebrowser` - FileBrowser Quantum, serving `folder/`. Runs as `1000:1000`, so the files it writes belong to that
  user on the host.
* `filebrowser-nginx` - Sits between Traefik and `filebrowser`. Removes the upload size limit
  (`client_max_body_size 0`) and raises the timeouts for large uploads.


## Template structure

```
templates/filebrowser/
├── .docker.env                 # TRAEFIK_RULE
├── .env                        # Config path, admin password
├── cache/                      # Thumbnails / upload cache (/tmp/filebrowser)
├── conf/
│   └── config.yaml             # FileBrowser configuration (the database is created next to it)
├── folder/                     # The files served
└── nginx/conf.d/
```


## Setup (with `qcoumes-deployment`)

1. Copy the template:

    ```bash
    cp -r templates/filebrowser/ live/filebrowser
    ```

2. Set `TRAEFIK_RULE` in `live/filebrowser/.docker.env`, e.g. ``export TRAEFIK_RULE='Host(`files.domain.com`)'``.

3. Set `FILEBROWSER_ADMIN_PASSWORD` in `live/filebrowser/.env`: it is the password of the `admin` user, created on the
   first start.

4. Make sure the mounted directories belong to the container user, then start the service:

    ```bash
    sudo chown -R 1000:1000 live/filebrowser/{cache,conf,folder}
    ./bin/up.sh filebrowser
    ```

The served directory and other settings (sources, default permissions, ...) are set in
[`conf/config.yaml`](./conf/config.yaml), see the
[FileBrowser Quantum configuration](https://github.com/gtsteffaniak/filebrowser/wiki/Full-Config-Example).
