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
  echo "Usage: $0 <name>"
  exit 1
fi

NAME="$1"
COMPOSE_FILE="composes/${NAME}.yml"

# Check if the compose file exists
if [ ! -f "$COMPOSE_FILE" ]; then
  echo "${Red}Error: Compose file '$COMPOSE_FILE' does not exist.${Color_Off}"
  exit 1
fi

echo "Using docker-compose: ${Purple}${COMPOSE_FILE}${Color_Off}"

# Run the Docker Compose stop command
# Run the Docker Compose
echo
echo "Running '${Purple}docker compose -f ${COMPOSE_FILE} stop${Color_Off}'"
docker compose -f "$COMPOSE_FILE" stop
