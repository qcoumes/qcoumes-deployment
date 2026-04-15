eMushpedia
==========

*Uses [`composes/emushpedia.yml`](../composes/emushpedia.yaml).*

This template allow to setup three mediawiki instances (FR, EN and ES).


## Services

It is composed of 7 services:
* `emushpedia-mysql` - MySQL instance storing the database of each instance.
* `emushpedia-mediawiki-fr` - MediaWiki instance for the french language.
* `emushpedia-nginx-fr` - Sits between Traefik and `emushpedia-mediawiki-fr`. This allow more flexibilty than exposing MediaWik directly and allow things such as pretty URL (`/wiki/` instead of `/index.php`).
* `emushpedia-mediawiki-en` - Same as `emushpedia-mediawiki-fr` for the english language.
* `emushpedia-nginx-en` - Same as `emushpedia-nginx-fr`, but for `emushpedia-mediawiki-en`.
* `emushpedia-mediawiki-es` - MediaWiki instance for the spanish language.
* `emushpedia-nginx-es` - Same as `emushpedia-nginx-fr`, but for `emushpedia-mediawiki-es`.
* `emushpedia-mail` - A postfix service used to send emails (e.g. forgotten password).


## Database

Each MediaWiki instance use the `emushpedia-mysql` service to store data. The init file [`01-create-databases.sql`](./mysql-init/01-create-databases.sql) will create 3 databases (`emushpedia_fr`, `emushpedia_en` and `emushpedia_es`) and grant all access to user `mediawiki`).

The three instances share some tables (stored in the FR instance database). This allow sharing the users and permissions, aggregating stats, make the maintenance of somewhat static table (e.g. `interwiki`) easier. The shared tables are :
* `user`
* `user_properties`
* `user_autocreate_serial`
* `actor`
* `ipblocks`
* `user_groups`
* `user_former_groups`
* `interwiki`
* `site_stats`


## Setup (with `qcoumes-deployment`)

***This guide assume you have:***
* ***Three SQL dumps, one for each MediaWiki instance.***
* ***Three archives containing all the images for each instance.***
* ***A valid domain name with 3 subdomains (e.g. `fr.emushpedia.com`, `en.emushpedia.com` and `es.emushpedia.com`).***

The first step is to copy the template in the `live` directory:
* `cp -r templates/emushpedia/ live/emushpedia`

You will then need to setup the databases, network, mediawiki, then (optionally) the emails.


### Databases

To setup your databases from the dumps, first comment the `LocalSettings.php` volume in **each** `emushpedia-mediawiki-<lang>` service by adding a `#` at the start of the line, for example :
```yaml
    volumes:
      - ../live/${COMPOSE_ENV}/data/es/images:/var/www/html/images
      # - ../live/${COMPOSE_ENV}/data/es/LocalSettings.php:/var/www/html/LocalSettings.php
      - ../live/${COMPOSE_ENV}/data/es/favicon.ico:/var/www/html/favicon.ico
      - ../live/${COMPOSE_ENV}/data/extensions:/var/www/html/extensions/non-core/
```

Then edit the [`.env`](./.env) and fill `MYSQL_ROOT_PASSWORD` and `MYSQL_PASSWORD` with different secured password.

You can now run `./bin/up.sh emushpedia` to initialise the database.

Once the `emushpedia-mysql` service is up and healthy, you can import the 3 dumps using the `MYSQL_ROOT_PASSWORD` defined earlier:
* `cat emushpedia_fr.sql | docker exec -i emushpedia-mysql mysql -u root -p emushpedia_fr`
* `cat emushpedia_en.sql | docker exec -i emushpedia-mysql mysql -u root -p emushpedia_en`
* `cat emushpedia_es.sql | docker exec -i emushpedia-mysql mysql -u root -p emushpedia_es`

You must now edit the 3 `LocalSettings.php` (located in `live/emushpedia/data/<lang>/`) files and set the variable `$wgDBpassword` to the value of `MYSQL_PASSWORD` as defined in the `.env` earlier.

Your databases should is now ready, but we won't be able to test it before finishing the setup of MediaWiki. I recommend to down the containers for now  `./bin/down.sh emushpedia`: 

### Network

To allow Traefik to redirect request to the nginx services, and make some element of MediaWiki work correctly, we must add the domain and subdomain to different place.

First edit the [`.docker.env`](./.docker.env) file and add an host for each language, this will be used by the docker-compose to inform Traefik on which host to use to redirect to which instance, e.g.
```sh
export TRAEFIK_RULE_FR='Host(`fr.emushpedia.com`)'
export TRAEFIK_RULE_EN='Host(`en.emushpedia.com`)'
export TRAEFIK_RULE_ES='Host(`es.emushpedia.com`)'
```

Then edit the 3 `LocalSettings.php` (located in `live/emushpedia/data/<lang>/`) files and set the following variable :
* `$wgServer` (use the correct subdomain, e.g. `$wgServer = "https://fr.emushpedia.com";`)
* `$wgPasswordSender` (use the domain, e.g. `$wgPasswordSender = "noreply@emushpedia.com";`)
* `$wgSMTP - IDHost` (use the domain, e.g. `'IDHost' => 'emushpedia.com',`
* `$wgSMTP - localhost` (use the domain, e.g. `'localhost' => 'emushpedia.com',`
* `$wgCookieDomain` (use the domain, e.g. `$wgCookieDomain = '.emushpedia.com';`)

Once this is done, only MediaWiki remains to be configured.


### MediaWiki

If it is not already done, down the services for now: `./bin/down.sh emushpedia`.

Edit the 3 `LocalSettings.php` (located in `live/emushpedia/data/<lang>/`) files and set the variable `$wgSecretKey` to the **same** value for the three language.
> You can generate a secret key with the following command: `openssl rand -hex 32`

eMushpedia need some extensions to work properly. Run the following command to install needed extensions:
```bash
git clone https://gerrit.wikimedia.org/r/mediawiki/extensions/CreatePageUw live/emushpedia/data/extensions/CreatePageUw
git clone https://gerrit.wikimedia.org/r/mediawiki/extensions/DarkMode live/emushpedia/data/extensions/DarkMode
git clone https://gerrit.wikimedia.org/r/mediawiki/extensions/UniversalLanguageSelector live/emushpedia/data/extensions/UniversalLanguageSelector
git clone https://gerrit.wikimedia.org/r/mediawiki/extensions/UserMerge live/emushpedia/data/extensions/UserMerge
git clone https://gerrit.wikimedia.org/r/mediawiki/extensions/Variables live/emushpedia/data/extensions/Variables
```

Now you need to uncomment the `LocalSettings.php` volume in **each** `emushpedia-mediawiki-<lang>` service by removing the `#` added earlier at the start of the line, for example :
```yaml
    volumes:
      - ../live/${COMPOSE_ENV}/data/es/images:/var/www/html/images
      - ../live/${COMPOSE_ENV}/data/es/LocalSettings.php:/var/www/html/LocalSettings.php
      - ../live/${COMPOSE_ENV}/data/es/favicon.ico:/var/www/html/favicon.ico
      - ../live/${COMPOSE_ENV}/data/extensions:/var/www/html/extensions/non-core/
```

And up the service again: `./bin/up.sh emushpedia`
