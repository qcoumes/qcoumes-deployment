#!/usr/bin/env bash
set -euo pipefail

./bin/down.sh valheim || true

r2modman-headless \
  --install-dir=live/valheim/r2mod-staging \
  --work-dir=live/valheim/r2mod-work \
  --profile-zip=/tmp/valheim-server.r2z

sudo rsync -a --delete \
  live/valheim/r2mod-staging/BepInEx/plugins/ \
  live/valheim/config/bepinex/plugins/

./bin/up.sh valheim || true
