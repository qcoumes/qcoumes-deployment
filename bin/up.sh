#!/bin/bash

# Colors
Color_Off=$'\e[0m' # Text Reset
Red=$'\e[0;31m'    # Red
Green=$'\e[0;32m'  # Green
Yellow=$'\e[0;33m' # Yellow
Purple=$'\e[0;35m' # Purple
Cyan=$'\e[0;36m'   # Cyan

# Function to check if path exists under ./live directory
check_live_path() {
  local path="$1"
  if [[ "$path" == live/* ]]; then
    local relative_path="${path#live/}"
    local expanded_path=$(printf '%s' "$relative_path" | envsubst)
    echo -n "Checking ${Purple}./live/${expanded_path}${Color_Off}: "
    if [ ! -e "./live/$expanded_path" ]; then
      echo "${Red}Missing ❌${Color_Off}"
      EXIT_CODE=1
    else
      echo "${Green}Found ✅${Color_Off}"
    fi
  fi
}


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

# Extract and check paths in volumes and env_file sections
echo
echo "Checking all required path exists"
while read -r line; do
  # Extract paths containing "live/" in volumes and env_file sections
  if [[ "$line" =~ live/ ]]; then
    # Only take the part to the left of `:` in volume entries and clean up extra characters
    path=$(echo "$line" | sed -E 's/.*(live\/[^:"[:space:]]*).*/\1/' | cut -d':' -f1)
    check_live_path "$path"
  fi
done < <(grep -E "^\s*(volumes|env_file):\s*|^\s*-.*live/" "$COMPOSE_FILE")
if [ $EXIT_CODE = 1 ] ; then
   echo "${Red}❌ Some expected path are missing${Color_Off}"
   exit $EXIT_CODE
fi

# Run the Docker Compose
echo
echo "Running '${Purple}docker compose -f ${COMPOSE_FILE} up -d${Color_Off}'"
docker compose -f "$COMPOSE_FILE" up -d 
echo
