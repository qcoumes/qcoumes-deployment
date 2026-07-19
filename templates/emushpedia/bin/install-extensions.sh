#!/usr/bin/env bash

set -euo pipefail

EXTENSIONS=(
  Analytics
  Arrays
  CirrusSearch
  CreatePageUw
  DarkMode
  Elastica
  OAuth
  UniversalLanguageSelector
  UserMerge
  Variables
)

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
EXTENSIONS_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)/data/extensions"
GERRIT_BASE_URL="https://gerrit.wikimedia.org/r/mediawiki/extensions"

usage() {
  cat <<EOF
Usage:
  $(basename "$0") REL<VERSION>

Example:
  $(basename "$0") REL1_46

Extensions directory:
  $EXTENSIONS_DIR
EOF
}

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 2
fi

TARGET_BRANCH="$1"

if [[ ! "$TARGET_BRANCH" =~ ^REL[0-9]+_[0-9]+$ ]]; then
  echo "Error: invalid branch '$TARGET_BRANCH'." >&2
  echo "Expected format: REL1_46" >&2
  exit 2
fi

mkdir -p "$EXTENSIONS_DIR"

cloned=0
updated=0
unchanged=0
skipped=0
failed=0

for extension in "${EXTENSIONS[@]}"; do
  repo_url="$GERRIT_BASE_URL/$extension"
  destination="$EXTENSIONS_DIR/$extension"

  echo
  echo "===== $extension ====="

  if [[ ! -e "$destination" ]]; then
    echo "Cloning $TARGET_BRANCH..."

    if git clone       --branch "$TARGET_BRANCH"       --single-branch       "$repo_url"       "$destination"
    then
      ((cloned += 1))
    else
      echo "ERROR: failed to clone $extension on $TARGET_BRANCH." >&2
      ((failed += 1))
    fi

    continue
  fi

  if [[ ! -d "$destination/.git" ]]; then
    echo "SKIP: directory exists but is not an independent Git repository:"
    echo "  $destination"
    ((skipped += 1))
    continue
  fi

  if ! git -C "$destination" diff --quiet ||
     ! git -C "$destination" diff --cached --quiet ||
     [[ -n "$(git -C "$destination" ls-files --others --exclude-standard)" ]]
  then
    echo "SKIP: repository contains local changes:"
    git -C "$destination" status --short
    ((skipped += 1))
    continue
  fi

  current_origin="$(git -C "$destination" remote get-url origin 2>/dev/null || true)"

  if [[ -z "$current_origin" ]]; then
    git -C "$destination" remote add origin "$repo_url"
  elif [[ "$current_origin" != "$repo_url" && "$current_origin" != "$repo_url.git" ]]; then
    echo "SKIP: origin does not match the expected repository."
    echo "  Current : $current_origin"
    echo "  Expected: $repo_url"
    ((skipped += 1))
    continue
  fi

  echo "Fetching origin..."
  if ! git -C "$destination" fetch --prune origin; then
    echo "ERROR: git fetch failed for $extension." >&2
    ((failed += 1))
    continue
  fi

  if ! git -C "$destination" ls-remote       --exit-code       --heads origin "$TARGET_BRANCH" >/dev/null 2>&1
  then
    echo "SKIP: origin/$TARGET_BRANCH does not exist."
    ((skipped += 1))
    continue
  fi

  current_branch="$(git -C "$destination" branch --show-current || true)"
  before_commit="$(git -C "$destination" rev-parse HEAD)"

  if git -C "$destination" show-ref       --verify       --quiet "refs/heads/$TARGET_BRANCH"
  then
    if [[ "$current_branch" != "$TARGET_BRANCH" ]]; then
      git -C "$destination" switch "$TARGET_BRANCH"
    fi
  else
    git -C "$destination" switch       --track       -c "$TARGET_BRANCH"       "origin/$TARGET_BRANCH"
  fi

  if ! git -C "$destination" merge --ff-only "origin/$TARGET_BRANCH"; then
    echo "ERROR: cannot fast-forward $extension." >&2
    ((failed += 1))
    continue
  fi

  after_commit="$(git -C "$destination" rev-parse HEAD)"

  if [[ "$before_commit" == "$after_commit" && "$current_branch" == "$TARGET_BRANCH" ]]; then
    echo "Already up to date on $TARGET_BRANCH."
    ((unchanged += 1))
  else
    echo "Updated to $TARGET_BRANCH at ${after_commit:0:12}."
    ((updated += 1))
  fi
done

echo
echo "===== Summary ====="
echo "Target branch:           $TARGET_BRANCH"
echo "Cloned:                  $cloned"
echo "Updated:                 $updated"
echo "Already up to date:      $unchanged"
echo "Skipped:                 $skipped"
echo "Failures:                $failed"

if ((failed > 0)); then
  exit 1
fi
