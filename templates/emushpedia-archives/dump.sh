#!/usr/bin/env bash

set -euo pipefail

: "${EMUSHPEDIA_FILENAME:?missing}"
: "${EMUSHPEDIA_DUMP_PATH:?missing}"
: "${EMUSHPEDIA_LOG_PATH:?missing}"
: "${EMUSHPEDIA_VENV_PATH:?missing}"

TMP_DUMP="/tmp/${EMUSHPEDIA_FILENAME}"

# Activate venv
source "${EMUSHPEDIA_VENV_PATH}/bin/activate"

# Run dump
wikiteam3dumpgenerator \
  https://emushpedia.miraheze.org \
  --xml \
  --images \
  --bypass-cdn-image-compression \
  --delay=0.5 \
  --path "$TMP_DUMP"

# Archive
(
  cd /tmp
  zip -rq "$EMUSHPEDIA_DUMP_PATH" "$EMUSHPEDIA_FILENAME"
)
