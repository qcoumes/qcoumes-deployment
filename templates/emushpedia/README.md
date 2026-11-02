eMushpedia
==========

*Uses [`composes/emushpedia.yml`](../../composes/emushpedia.yml).*

This template allow to setup three MediaWiki instances (FR, EN and ES) sharing their users, with full-text search
(CirrusSearch + OpenSearch), OAuth2 and emails.

*This guide assume `traefik` is running, see the main [README.md](../../README.md).*


## Services

It is composed of 10 services:
* `emushpedia-mysql` - MySQL instance storing the database of each instance.
* `emushpedia-opensearch` - OpenSearch instance used by CirrusSearch for the search of the three instances. Built from
  [`opensearch/Dockerfile`](./opensearch/Dockerfile) (adds the Wikimedia `opensearch-extra` plugin). It is only
  reachable on the internal `search` network, which is why its security plugin can be disabled.
* `emushpedia-mediawiki-fr` - MediaWiki instance for the french language.
* `emushpedia-nginx-fr` - Sits between Traefik and `emushpedia-mediawiki-fr`. This allow more flexibility than exposing
  MediaWiki directly and allow things such as pretty URL (`/wiki/` instead of `/index.php`), a `robots.txt` and
  protections against crawlers (anonymous visitors cannot reach endless URL spaces such as diffs and histories).
* `emushpedia-mediawiki-en` / `emushpedia-nginx-en` - Same as the FR services, for the english language.
* `emushpedia-mediawiki-es` / `emushpedia-nginx-es` - Same as the FR services, for the spanish language.
* `emushpedia-nginx-root` - Serves the root domain (e.g. `emushpedia.com`) and redirects to the language subdomain, using
  the `emushpedia_lang` cookie if set, else the browser's `Accept-Language` (default: `en`).
* `emushpedia-mail` - A postfix service (with DKIM) used to send emails (e.g. forgotten password).


## Database

Each MediaWiki instance use the `emushpedia-mysql` service to store data. The init file
[`01-create-databases.sql`](./mysql-init/01-create-databases.sql) will create 3 databases (`emushpedia_fr`,
`emushpedia_en` and `emushpedia_es`) and grant all access to user `mediawiki`.

The three instances share some tables (stored in the FR instance database). This allow sharing the users and
permissions, aggregating stats, make the maintenance of somewhat static table (e.g. `interwiki`) easier. The shared
tables are :
* `user`
* `user_properties`
* `user_autocreate_serial`
* `actor`
* `ipblocks`
* `user_groups`
* `user_former_groups`
* `interwiki`
* `site_stats`

OAuth is also centralized on the FR instance (`$wgMWOAuthCentralWiki = 'emushpedia_fr'`).


## Template structure

```
templates/emushpedia/
├── .docker.env                     # Traefik rules (root domain + one per language)
├── .env                            # MySQL passwords
├── bin/
│   ├── install-extensions.sh       # Clone the non-bundled extensions for a MediaWiki release
│   ├── update-extensions.sh        # Switch the extensions to another release branch
│   └── check-extensions.sh         # Show installed extensions versions and compatibility
├── data/
│   ├── fr/ en/ es/
│   │   ├── LocalSettings.php
│   │   ├── favicon.ico
│   │   ├── images/                 # Uploaded files
│   │   └── nginx/conf.d/nginx.conf
│   ├── root/nginx/conf.d/          # Root domain redirection
│   ├── extensions/                 # Filled by bin/install-extensions.sh
│   ├── oauth2/                     # OAuth2 keys (to generate)
│   ├── mail/keys/                  # DKIM keys (to generate)
│   ├── mysql/
│   └── opensearch/
├── mysql-init/01-create-databases.sql
└── opensearch/Dockerfile
```


## Setup (with `qcoumes-deployment`)

***This guide assume you have:***
* ***Three SQL dumps, one for each MediaWiki instance.***
* ***Three archives containing all the images for each instance.***
* ***A valid domain name with 3 subdomains (e.g. `fr.emushpedia.com`, `en.emushpedia.com` and `es.emushpedia.com`).***

The first step is to copy the template in the `live` directory:
* `cp -r templates/emushpedia/ live/emushpedia`

You will then need to setup the extensions, databases, network, MediaWiki, the search index then (optionally) the
emails.


### Extensions

The compose file mounts some extensions directly (`CirrusSearch`, `Elastica`, `OAuth`), so they must be installed
before the first `./bin/up.sh`. Install all the non-bundled extensions for the release branch matching the MediaWiki
image of the compose file (e.g. `mediawiki:1.46.2` → `REL1_46`):

```bash
live/emushpedia/bin/install-extensions.sh REL1_46
```

The list of extensions is at the top of [`bin/install-extensions.sh`](./bin/install-extensions.sh).


### OAuth2 keys

The files in `data/oauth2/` are empty placeholders. Generate the keys, and make them readable by the MediaWiki
containers (`www-data`, gid 33):

```bash
cd live/emushpedia/data/oauth2
openssl genrsa -out oauth2-private.key 2048
openssl rsa -in oauth2-private.key -pubout -out oauth2-public.key
openssl rand -hex 32 > oauth-secret.key
sudo chgrp 33 oauth2-private.key oauth2-public.key oauth-secret.key
chmod 660 oauth2-private.key oauth2-public.key oauth-secret.key
```


### Databases

To setup your databases from the dumps, first comment the `LocalSettings.php` volume in **each**
`emushpedia-mediawiki-<lang>` service by adding a `#` at the start of the line, for example :
```yaml
    volumes:
      - ../live/${COMPOSE_ENV}/data/es/images:/var/www/html/images
      # - ../live/${COMPOSE_ENV}/data/es/LocalSettings.php:/var/www/html/LocalSettings.php
      - ../live/${COMPOSE_ENV}/data/es/favicon.ico:/var/www/html/favicon.ico
```

Then edit the [`.env`](./.env) and fill `MYSQL_ROOT_PASSWORD` and `MYSQL_PASSWORD` with different secured password.

You can now run `./bin/up.sh emushpedia` to initialise the database.

Once the `emushpedia-mysql` service is up and healthy, you can import the 3 dumps using the `MYSQL_ROOT_PASSWORD`
defined earlier:
* `cat emushpedia_fr.sql | docker exec -i emushpedia-mysql mysql -u root -p emushpedia_fr`
* `cat emushpedia_en.sql | docker exec -i emushpedia-mysql mysql -u root -p emushpedia_en`
* `cat emushpedia_es.sql | docker exec -i emushpedia-mysql mysql -u root -p emushpedia_es`

You must now edit the 3 `LocalSettings.php` (located in `live/emushpedia/data/<lang>/`) files and set the variable
`$wgDBpassword` to the value of `MYSQL_PASSWORD` as defined in the `.env` earlier.

Your databases are now ready, but we won't be able to test it before finishing the setup of MediaWiki. I recommend to
down the containers for now: `./bin/down.sh emushpedia`.


### Network

To allow Traefik to redirect request to the nginx services, and make some element of MediaWiki work correctly, we must
add the domain and subdomain to different place.

First edit the [`.docker.env`](./.docker.env) file and add the root domain and a host for each language, this will be
used by the docker-compose to inform Traefik on which host to use to redirect to which instance, e.g.
```sh
export TRAEFIK_RULE_ROOT='Host(`emushpedia.com`)'
export TRAEFIK_RULE_FR='Host(`fr.emushpedia.com`)'
export TRAEFIK_RULE_EN='Host(`en.emushpedia.com`)'
export TRAEFIK_RULE_ES='Host(`es.emushpedia.com`)'
```

If you use another domain than `emushpedia.com`, also update
[`data/root/nginx/conf.d/nginx.conf`](./data/root/nginx/conf.d/nginx.conf) (`server_name` and redirections) and the
`emushpedia-mail` service environment in the compose file (`ALLOWED_SENDER_DOMAINS`, `POSTFIX_myhostname`,
`POSTFIX_mydomain`).

Then edit the 3 `LocalSettings.php` (located in `live/emushpedia/data/<lang>/`) files and set the following variable :
* `$wgServer` (use the correct subdomain, e.g. `$wgServer = "https://fr.emushpedia.com";`)
* `$wgPasswordSender` (use the domain, e.g. `$wgPasswordSender = "noreply@emushpedia.com";`)
* `$wgSMTP - IDHost` (use the domain, e.g. `'IDHost' => 'emushpedia.com',`)
* `$wgSMTP - localhost` (use the domain, e.g. `'localhost' => 'emushpedia.com',`)
* `$wgCookieDomain` (use the domain, e.g. `$wgCookieDomain = '.emushpedia.com';`)

Once this is done, only MediaWiki remains to be configured.


### MediaWiki

If it is not already done, down the services for now: `./bin/down.sh emushpedia`.

Edit the 3 `LocalSettings.php` (located in `live/emushpedia/data/<lang>/`) files and set the variables `$wgSecretKey`
and `$wgUpgradeKey` to the **same** values for the three languages.
> You can generate a secret key with the following command: `openssl rand -hex 32`, and an upgrade key with
> `openssl rand -hex 8`.

Now you need to uncomment the `LocalSettings.php` volume in **each** `emushpedia-mediawiki-<lang>` service by removing
the `#` added earlier at the start of the line, and up the service again: `./bin/up.sh emushpedia`.

Finally, create the tables of the extensions (e.g. OAuth) and apply the schema updates, for each language:
```bash
for lang in fr en es; do docker exec emushpedia-mediawiki-$lang php maintenance/run.php update --quick; done
```


### Search index

The search uses CirrusSearch and `emushpedia-opensearch` (one index per language, `$wgCirrusSearchIndexBaseName`). Once
the services are up and `emushpedia-opensearch` is healthy, create and fill the indexes:
```bash
for lang in fr en es; do
  docker exec emushpedia-mediawiki-$lang php maintenance/run.php CirrusSearch:UpdateSearchIndexConfig
  docker exec emushpedia-mediawiki-$lang php maintenance/run.php CirrusSearch:ForceSearchIndex --skipLinks --indexOnSkip
  docker exec emushpedia-mediawiki-$lang php maintenance/run.php CirrusSearch:ForceSearchIndex --skipParse
done
```

`data/opensearch/` is not worth backing up: the indexes can always be rebuilt this way.


### Emails (optional)

`emushpedia-mail` signs the emails with DKIM, using the selector `mail` and the key pair
`data/mail/keys/<domain>.private` / `<domain>.txt`. To generate them (with the `opendkim-tools` package):
```bash
cd live/emushpedia/data/mail/keys
opendkim-genkey -b 2048 -d emushpedia.com -s mail
mv mail.private emushpedia.com.private && mv mail.txt emushpedia.com.txt
```
Then publish the content of `<domain>.txt` as the `mail._domainkey.<domain>` TXT record, and add a SPF record allowing
the server's IP.


## Maintenance

### Upgrading MediaWiki

Change the `mediawiki:<version>` image of the 3 MediaWiki services in the compose file, then switch the extensions to
the matching release branch and check them:
```bash
live/emushpedia/bin/update-extensions.sh REL1_47 --dry-run
live/emushpedia/bin/update-extensions.sh REL1_47
live/emushpedia/bin/check-extensions.sh --fetch
./bin/recreate.sh emushpedia
for lang in fr en es; do docker exec emushpedia-mediawiki-$lang php maintenance/run.php update --quick; done
```

### Backups

See the [`emushpedia-backup`](../emushpedia-backup/README.md) template: nightly pull backup of the databases and files
into a restic repository, from another host. Its `source-host/backup-ssh-wrapper.sh` is installed in
`live/emushpedia/bin/`.
