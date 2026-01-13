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

./bin/down.sh "$1" "${2:-$1}"
./bin/up.sh "$1" "${2:-$1}"
