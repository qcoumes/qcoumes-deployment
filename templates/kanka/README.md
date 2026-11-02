Kanka
=====

*Uses [`composes/kanka.yml`](../../composes/kanka.yml).*

This template sets up [Kanka Community Edition](https://github.com/kanka-ce/kanka-ce), a worldbuilding and tabletop RPG
campaign manager, with its REST API.

*This guide assume `traefik` is running, see the main [README.md](../../README.md).*


## Services

* `kanka` (`<env>-app`) - Kanka CE (Laravel). Serves both the web application and the API, on two different hosts.
* `mariadb` (`<env>-mariadb`) - The database.
* `redis` (`<env>-redis`) - Cache.
* `meilisearch` (`<env>-meilisearch`) - Search engine.

Containers are named `<env>-app`, `<env>-mariadb`, ... (`kanka-app` for the `kanka` env), so several environments can
run on the same host, each with its own hosts in `TRAEFIK_RULE`.


## Template structure

```
templates/kanka/
├── .docker.env                     # TRAEFIK_RULE (app and API hosts)
├── .env                            # Kanka, MariaDB and Meilisearch settings, also mounted as Kanka's .env
├── init/
│   └── 10-kanka-permissions.sh     # Run at container start: fixes bootstrap/cache permissions
├── kanka/                          # Laravel storage (uploads in kanka/app/public, logs, sessions, cache)
├── mariadb/
├── meilisearch/
└── redis/
```


## Setup (with `qcoumes-deployment`)

1. Copy the template:

    ```bash
    cp -r templates/kanka/ live/kanka
    ```

2. Kanka needs **two host names**, each with its own DNS record: one for the application (e.g. `kanka.domain.com`) and
   one for the API (e.g. `api.kanka.domain.com`). Set both in `live/kanka/.docker.env`:

    ```bash
    export TRAEFIK_RULE='Host(`kanka.domain.com`) || Host(`api.kanka.domain.com`)'
    ```

3. Fill `live/kanka/.env`:
    * `APP_URL`, `FRONT_DOMAIN`, `APP_DOMAIN`: `https://<application host>`.
    * `API_DOMAIN`: the API host name **alone**, without `https://` (e.g. `api.kanka.domain.com`). Kanka binds the API
      routes to this host and drops their `/api` prefix: with a URL, or the application host, the API answers 404.
    * `APP_KEY`: 32 random characters (`openssl rand -hex 16`).
    * `DB_PASSWORD` / `MYSQL_PASSWORD` (same value), `DB_ROOT_PASSWORD` / `MYSQL_ROOT_PASSWORD` (same value),
      `MEILISEARCH_KEY` / `MEILI_MASTER_KEY` (same value, `openssl rand -hex 32`).
    * `APP_INVITATION_PASSWORD`: needed to register while `APP_INVITATION_REQUIRED=true`.
    * `FONTAWESOME_KIT`: id of a free [Font Awesome kit](https://fontawesome.com/kits), without it the icons do not
      load.

4. Start the services: `./bin/up.sh kanka`. Always use the `bin/` scripts: they set the compose project name, plain
   `docker compose -f composes/kanka.yml` conflicts with the existing container names.

5. Create your account on the application host (with the invitation password), then close the registrations if needed
   (`APP_REGISTRATION_ENABLED`, `APP_INVITATION_REQUIRED`) and `./bin/recreate.sh kanka`.


## API

The API is served at `https://<API_DOMAIN>/1.0/...` (no `/api` prefix). Requests are limited to `API_THROTTLE_LIMIT` per
minute (Kanka default: 30, the template sets 600).

To use it, create a personal access token from your profile (Settings → API). If token creation fails because of a
missing personal access client, create it once:

```bash
docker exec -it <env>-app php artisan passport:client --personal --provider=users
```


## Notes

* `MEILI_UPGRADE_DB=true` lets Meilisearch migrate its data in place when the `latest` image changes version.
* `APP_CUSTOM_ENTITIES=true` enables custom modules (user-defined entity types).
* After any change in `.env`, recreate the services: `./bin/recreate.sh kanka`.
