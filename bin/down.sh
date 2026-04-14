#!/bin/bash

# Colors
Color_Off=$'\e[0m' # Text Reset
Red=$'\e[0;31m'    # Red
Green=$'\e[0;32m'  # Green
Yellow=$'\e[0;33m' # Yellow
Purple=$'\e[0;35m' # Purple
Cyan=$'\e[0;36m'   # Cyan

#########################################################


# Check if name argument is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <name> [<env>]"
  exit 1
fi

NAME="$1"
export COMPOSE_FILE="composes/${NAME}.yml"
export COMPOSE_ENV="${2:-$NAME}"
EXIT_CODE=0

printf "Using docker-compose:\t${Purple}${COMPOSE_FILE}${Color_Off}\n"
printf "Using project env:\t${Cyan}${COMPOSE_ENV}${Color_Off}\n"

# Check if the compose file exists
if [ ! -f "$COMPOSE_FILE" ]; then
  echo "${Red}❌ Error: Compose file './composes/$COMPOSE_FILE' does not exist.${Color_Off}"
  exit 1
fi

# Check if the environment exists
if [ ! -e "live/${COMPOSE_ENV}" ]; then
  echo "${Red}❌ Error: Environment './live/${COMPOSE_ENV}' does not exist.${Color_Off}"
  exit 1
fi

# If a .docker.env exists in the environment, source it
if [ -f "live/${COMPOSE_ENV}/.docker.env" ]; then
    source "live/${COMPOSE_ENV}/.docker.env"
else
    echo "${Yellow}⚠️  No 'live/${COMPOSE_ENV}/.docker.env' found.${Color_Off}"
fi

# Run the Docker Compose stop command
# Run the Docker Compose
echo
echo "Running '${Purple}docker compose -f ${COMPOSE_FILE} down${Color_Off}'"
docker compose -p "$COMPOSE_ENV" -f "$COMPOSE_FILE" down
