# qcoumes-deployment

Docker Compose-based deployment management system for managing multiple services with separate environments.

## Repository Structure

```
.
├── bin/
├── composes/ 
├── templates/
└── live/
```

### Directory Details

- **bin/**: Contains shell scripts to manage Docker Compose services (start, stop, restart, etc.)
- **composes/**: Docker Compose YAML files defining each service for a given application.
- **templates/**: Base configuration for supported applications.
- **live/**: Where live applications data and configuration reside.

## Available Commands

All commands in `bin/` follow the same pattern:

```bash
./bin/<command>.sh <name> [<env>]
```
- `<name>`: The service name (matches a file in `composes/<name>.yml`)
- `[<env>]`: Optional environment name (defaults to `<name>` if not provided). References a directory in `live/<env>/`.

`[<env>]` allows for a same application to be run in multiple environments, for instance a production and staging
environment.

All commands are the equivalent of running `docker compose <command> -f composes/<name>.yml`. `up.sh` will additionnaly
ensure that all path define in the docker compose configuration file (`env_file`, `volumes`, ...) exist in `live/<env>/`
before starting the service.

Each command will also source `live/<env>/.docker.env` if it exists, allowing you to define environment variables to be
used in the compose file (such as `TRAEFIK_RULE` - see below).

### Command Reference

| Command       | Description                                         | Docker Compose Equivalent |
|---------------|-----------------------------------------------------|---------------------------|
| `up.sh`       | Validates paths and starts service in detached mode | `docker compose up -d`    |
| `down.sh`     | Stops and removes containers, networks              | `docker compose down`     |
| `start.sh`    | Starts existing stopped containers                  | `docker compose start`    |
| `stop.sh`     | Stops running containers without removing them      | `docker compose stop`     |
| `restart.sh`  | Restarts running containers                         | `docker compose restart`  |
| `recreate.sh` | Tears down and rebuilds the service                 | `down.sh` + `up.sh`       |

## Starting an application

### HTTPS and Traefik

This repository assumes that all your applications will be served over HTTPS. This is done by using Traefik as a
reverse proxy and automatically generating HTTPS certificates using Let's Encrypt.

To run Traefik, use the `traefik` template:

```bash
cp -R templates/traefik/ live/traefik/
```

Then run `./bin/up.sh traefik`. Certificate can take a few minutes to be generated the first time (up to 15 minutes).

If you want access to the Treafik dashboard, edit `live/traefik/.docker.env` and set `TRAEFIK_RULE` and `TRAEFIK_USER`:
* A valid `TRAEFIK_RULE` could be ``'Host`traefik.<host>.com`)'`` or ``'Host(`<host>.com`) && PrefixPath(`/traefik`)'``.
* To generate a `TRAEFIK_USER`, use `htpasswd -nbB <username> '<password>'`.

You will need to recreate the service after changing `live/traefik/.docker.env`: `./bin/recreate.sh traefik`.

### Basic Usage

To set up an application (let's use `filebrowser` as an example), first copy its relevant template in the `live` directory:

```shell
cp -R templates/filebrowser/ live/filebrowser/
```

Then modify any relevant variables in `live/filebrowser/.docker.env` (such as `TRAEFIK_RULE`) and in
`live/filebrowser/.env` (for application-specific variables such as passwords and database access). Be careful as
the fist one need to `export` its variable, but not the second one.

Then run `./bin/up.sh filebrowser`

This will:
1. Use `composes/filebrowser.yml` as the compose file
2. Use `live/filebrowser/` as the environment directory
3. Source `live/filebrowser/.docker.env` if it exists
4. Validate all paths referenced in the compose file
5. Run `docker compose -f composes/filebrowser.yml up -d`

### Using Different Environments for a Same Application

To use a different environment for the same application, for instance, a staging environment, copy the template in
another directory as `live/filebrowser-staging/`, fills its environment variables, and run:

```bash
./bin/up.sh filebrowser filebrowser-staging
```

This uses `composes/filebrowser.yml` but references `live/filebrowser-staging/` for environment data.

### Other Operations

```bash
# Stop the applications services
./bin/stop.sh filebrowser

# Start the application services again
./bin/start.sh filebrowser

# Restart the application services
./bin/restart.sh filebrowser

# Completely tear down and up the application services
./bin/recreate.sh filebrowser

# Tear down without rebuilding the application services
./bin/down.sh filebrowser
```

## Creating a New Service

You can use existing templates as examples (see below).

### Step 1: Create the Compose File

Create a new Docker Compose file in `composes/`:

```bash
# Example: composes/myapp.yml
```

**Key conventions:**
- Use `${COMPOSE_ENV}` variable for container names and paths to support multiple environments. This variable is defined
  by the `bin/*` scripts based on the second argument (or first if no second argument is provided).
- Reference live environment paths as: `../live/${COMPOSE_ENV}/...`
- Use `env_file` prefixed with `../live/${COMPOSE_ENV}/` (e.g. `../live/${COMPOSE_ENV}/.env`) for the environment
  variables of your services. Different services can have different `env_file`.
- Connect to the `web` network if using Traefik for routing
- Add appropriate Traefik labels for HTTPS and routing

Example structure:

```yaml
services:
  
  myapp:
    image: myimage:latest
    container_name: ${COMPOSE_ENV}-myapp
    env_file: "../live/${COMPOSE_ENV}/.env"
    volumes:
      - ../live/${COMPOSE_ENV}/data:/data
      - ../live/${COMPOSE_ENV}/config:/config
    restart: unless-stopped
    expose:
      - "80"
    networks:
      - web
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=web"
      - "traefik.http.routers.${COMPOSE_ENV}.rule=${TRAEFIK_RULE}"
      - "traefik.http.routers.${COMPOSE_ENV}.entrypoints=websecure"
      - "traefik.http.routers.${COMPOSE_ENV}.tls=true"
      - "traefik.http.routers.${COMPOSE_ENV}.tls.certresolver=letsencrypt"
      - "traefik.http.services.${COMPOSE_ENV}-filebrowser.loadbalancer.server.port=80"

networks:
  web:
    external: true
    name: web
```

### Step 2: Create Environment Directory

Create the live environment directory structure:

```bash
mkdir -p live/myapp
```

### Step 3: Create Configuration Files

#### `.docker.env` (optional)

Create `live/myapp/.docker.env` for variables used in the Docker Compose file:

```bash
# Traefik routing rule
export TRAEFIK_RULE=Host(`myapp.example.com`)
```

**Do not forget to export the variables in this file !**

#### `.env` (for application)

Create `live/myapp/.env` for service-specific environment variables:

```bash
# service configuration
DATABASE_URL=postgresql://...
API_KEY=your-api-key
```

### Step 4: Create Required Directories and Files

Based on your compose file's volumes, create necessary directories:

```bash
# Example for the structure above
mkdir -p live/myapp/data
mkdir -p live/myapp/config
```

### Step 5: Start the Application

```bash
./bin/up.sh myapp
```

The `up.sh` script will validate that all required paths exist before starting the service.

### Step 6: Make a Template

You can copy the `live/myapp/` directory to `templates/myapp/` to make it easier to create new services with similar
configurations. **Do not forget to remove any sensitive data !**.

## Examples

### Example: Existing Services

The repository includes several services you can reference:

- **traefik**: Reverse proxy with automatic HTTPS
- **filebrowser**: File management web interface.
- **emushpedia-archives**: A simple application allowing to dump [emushpedia](https://emushpedia.miraheze.org/)
  regularly and making the dumps available using [`nginx:download`](https://nginx.org/en/download.html).

## Notes
- The `live/` directory is gitignored to protect sensitive configuration and data
- All scripts expect to be run from the repository root
- Docker and Docker Compose must be installed
- For Traefik integration, ensure the `web` network exists: `docker network create web`
