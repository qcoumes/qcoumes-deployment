#!/bin/bash

# Colors
Color_Off=$'\e[0m' # Text Reset
Red=$'\e[0;31m'    # Red
Green=$'\e[0;32m'  # Green
Yellow=$'\e[0;33m' # Yellow
Purple=$'\e[0;35m' # Purple
Cyan=$'\e[0;36m'   # Cyan
Cyan=$'\e[0;36m'   # Cyan

# Function to check if path exists under ./live directory
check_live_path() {
  local path="$1"
  if [[ "$path" == live/* ]]; then
    local relative_path="${path#live/}"
    echo -n "Checking ${Purple}./live/${relative_path}${Color_Off}: "
    if [ ! -e "./live/$relative_path" ]; then
      echo "${Red}Missing ❌${Color_Off}"
      EXIT_CODE=1
    fi
  fi
  echo "${Green}Found ✅${Color_Off}"
}


#########################################################


# Check if name argument is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <name>"
  exit 1
fi

NAME="$1"
COMPOSE_FILE="composes/${NAME}.yml"
EXIT_CODE=0

# Check if the compose file exists
if [ ! -f "$COMPOSE_FILE" ]; then
  echo "${Red}Error: Compose file '$COMPOSE_FILE' does not exist.${Color_Off}"
  exit 1
fi

echo "Using docker-compose: ${Purple}${COMPOSE_FILE}${Color_Off}"

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
   echo "${Red} Some expected path are missing${Color_Off}"
   exit $EXIT_CODE
fi

# Run the Docker Compose
echo
echo "Running '${Purple}docker compose -f ${COMPOSE_FILE} up -d${Color_Off}'"
docker compose -f "$COMPOSE_FILE" up -d
