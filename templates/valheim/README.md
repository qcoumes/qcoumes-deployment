Valheim
=======

*Uses [`composes/valheim.yml`](../../composes/valheim.yml).*

This template runs a dedicated [Valheim](https://www.valheimgame.com/) server with
[`community-valheim-tools/valheim-server`](https://github.com/community-valheim-tools/valheim-server-docker), with
optional mods through BepInEx.

It does not go through Traefik: the game uses UDP ports that must be forwarded straight to the host.


## Services

* `valheim` - The game server. It downloads and updates the server on start, and backs up the world regularly (in
  `config/backups/`).

Ports:
* `2456-2458/udp` - The game. Forward them to the host on your router / firewall.
* `9001/tcp` - Supervisor web interface, only active with `SUPERVISOR_HTTP=true` (do not expose it without a password).


## Template structure

```
templates/valheim/
├── .env                        # Server name, world, password, BepInEx
├── config/                     # Worlds, backups, admin/ban lists, BepInEx config and plugins
├── data/                       # Server installation (downloaded on start)
├── r2mod-staging/              # Mods installed by update_mods.sh (r2modman)
├── r2mod-work/                 # r2modman working directory
└── update_mods.sh
```


## Setup (with `qcoumes-deployment`)

1. Copy the template:

    ```bash
    cp -r templates/valheim/ live/valheim
    ```

2. Fill `live/valheim/.env`:
    * `SERVER_NAME` - Name shown in the server list.
    * `WORLD_NAME` - World to load or create (`config/worlds_local/<WORLD_NAME>.db`).
    * `SERVER_PASS` - Password to join, at least 5 characters, and must not appear in `SERVER_NAME`.
    * `BEPINEX` - `true` to load mods.

   Any other variable of the image can be added there (e.g. `SUPERVISOR_HTTP`, `BACKUPS_MAX_AGE`), see its
   [documentation](https://github.com/community-valheim-tools/valheim-server-docker#environment-variables).

3. Start it: `./bin/up.sh valheim`. The first start downloads the server, it can take a few minutes:
   `docker logs -f valheim`.

To use an existing world, stop the server and copy its `.db` and `.fwl` files in `live/valheim/config/worlds_local/`.


## Mods

Mods are managed with [r2modman](https://r2modman.com/): build the mod profile in r2modman on your computer, export it
as a file (`.r2z`), and copy it on the server as `/tmp/valheim-server.r2z`. Then, from
the repository root:

```bash
live/valheim/update_mods.sh
```

It stops the server, installs the profile with `r2modman-headless` (must be installed on the host) into
`r2mod-staging/`, copies the plugins into `config/bepinex/plugins/` (with `sudo`, the server files belong to the
container user), and starts the server again. Players need the same mods: share the same profile file with them.

The paths in `update_mods.sh` assume the environment is `live/valheim`.
