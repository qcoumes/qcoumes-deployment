Traefik
=======

*Uses [`composes/traefik.yml`](../../composes/traefik.yml).*

This template runs [Traefik](https://doc.traefik.io/traefik/), the reverse proxy in front of every other application:
it routes HTTPS requests to the containers by host name, and gets their certificates from Let's Encrypt.

It must be started first: it creates the `web` network the other applications join.


## How it works

* **Entrypoints**: `web` (`:80`, redirects everything to HTTPS) and `websecure` (`:443`). Both ports must be forwarded
  to the host.
* **Docker provider**: only the containers with the `traefik.enable=true` label are exposed, through the `web` network.
  Each application declares its rule (e.g. ``Host(`app.domain.com`)``) in its labels, usually from a `TRAEFIK_RULE`
  variable of its `.docker.env`.
* **Certificates**: the `letsencrypt` resolver uses the HTTP challenge, so each host name must have a DNS record
  pointing to this server **before** the application starts. Certificates are stored in `letsencrypt/acme.json`.
* **File provider**: the files in `configuration/` are watched and reloaded live. [`tls.yaml`](./configuration/tls.yaml)
  sets TLS 1.2 minimum, modern ciphers, and `sniStrict: true`.


## Template structure

```
templates/traefik/
├── .docker.env                 # TRAEFIK_RULE and TRAEFIK_USER, for the dashboard
├── configuration/
│   └── tls.yaml
└── letsencrypt/                # acme.json (certificates), created by Traefik
```


## Setup (with `qcoumes-deployment`)

1. Copy the template:

    ```bash
    cp -r templates/traefik/ live/traefik
    ```

2. Set the Let's Encrypt account email (`--certificatesresolvers.letsencrypt.acme.email`) in
   [`composes/traefik.yml`](../../composes/traefik.yml).

3. For the dashboard, set in `live/traefik/.docker.env`:
    * `TRAEFIK_RULE`, e.g. ``'Host(`traefik.domain.com`)'``,
    * `TRAEFIK_USER`, generated with `htpasswd -nbB <username> '<password>'`, between single quotes (the hash contains
      `$`).

4. Start it: `./bin/up.sh traefik`. The first certificates can take a few minutes.

After changing `.docker.env`, recreate the service: `./bin/recreate.sh traefik`.


## Troubleshooting

* **A host has no certificate**: check its DNS record (Let's Encrypt fails with `NXDOMAIN` otherwise), then restart its
  container (`docker restart <container>`): Traefik does not retry a failed challenge by itself.
* **`unrecognized name` TLS error**: with `sniStrict: true`, Traefik refuses hosts it has no certificate for, so a new
  application cannot be tested through `:443` before its certificate exists. Test its backend from a throwaway
  container on the `web` network instead, e.g.
  `docker run --rm --network web curlimages/curl -s http://<container>:<port>/`.
