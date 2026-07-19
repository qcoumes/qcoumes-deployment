#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
EMUSHPEDIA_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
EXTENSIONS_DIR="${EXTENSIONS_DIR:-$EMUSHPEDIA_DIR/data/extensions}"
DRY_RUN=false

usage() {
  cat <<'USAGE'
Usage:
  update-extension-branches.sh REL<VERSION> [--dry-run] [--extensions-dir PATH]

Switch every independent Git repository in the extensions directory to the
requested MediaWiki release branch, fetch it from origin, and fast-forward it.

Examples:
  update-extension-branches.sh REL1_46
  update-extension-branches.sh REL1_47 --dry-run

Options:
  --dry-run                Show what would be done without changing anything.
  --extensions-dir PATH    Override live/emushpedia/data/extensions.
  -h, --help               Show this help.

Environment:
  EXTENSIONS_DIR           Same as --extensions-dir.

Safety:
  - Repositories with local changes are skipped.
  - Directories without their own .git metadata are skipped.
  - Repositories without the requested remote branch are skipped.
  - Updates use --ff-only and never rewrite local history.
USAGE
}

if (($# == 0)); then
  usage >&2
  exit 2
fi

TARGET_BRANCH="$1"
shift

if [[ ! "$TARGET_BRANCH" =~ ^REL[0-9]+_[0-9]+$ ]]; then
  echo "Error: invalid branch '$TARGET_BRANCH'." >&2
  echo "Expected a value such as REL1_46." >&2
  exit 2
fi

while (($#)); do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --extensions-dir)
      if (($# < 2)); then
        echo "Error: --extensions-dir requires a path." >&2
        exit 2
      fi
      EXTENSIONS_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! -d "$EXTENSIONS_DIR" ]]; then
  echo "Error: extensions directory not found: $EXTENSIONS_DIR" >&2
  exit 1
fi

run() {
  if $DRY_RUN; then
    printf '  +'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

updated=0
already_current=0
skipped_dirty=0
skipped_missing_branch=0
skipped_not_repo=0
failed=0
found=0

while IFS= read -r -d '' directory; do
  found=1
  extension="$(basename "$directory")"

  echo
  echo "===== $extension ====="

  # Require repository metadata inside the extension itself. This avoids
  # treating directories such as Arrays or OAuth as the parent deployment repo.
  if [[ ! -e "$directory/.git" ]]; then
    echo "SKIP: not an independent Git repository."
    ((skipped_not_repo += 1))
    continue
  fi

  if ! git -C "$directory" diff --quiet ||
     ! git -C "$directory" diff --cached --quiet ||
     [[ -n "$(git -C "$directory" ls-files --others --exclude-standard)" ]]
  then
    echo "SKIP: repository has modified or untracked files."
    git -C "$directory" status --short
    ((skipped_dirty += 1))
    continue
  fi

  remote_url="$(git -C "$directory" remote get-url origin 2>/dev/null || true)"
  if [[ -z "$remote_url" ]]; then
    echo "ERROR: no origin remote."
    ((failed += 1))
    continue
  fi

  echo "Remote: $remote_url"

  if ! $DRY_RUN; then
    if ! git -C "$directory" fetch --quiet --prune origin; then
      echo "ERROR: unable to fetch origin."
      ((failed += 1))
      continue
    fi
  else
    run git -C "$directory" fetch --prune origin
  fi

  if ! git -C "$directory" ls-remote \
      --exit-code --heads origin "$TARGET_BRANCH" >/dev/null 2>&1
  then
    echo "SKIP: origin/$TARGET_BRANCH does not exist."
    ((skipped_missing_branch += 1))
    continue
  fi

  current_branch="$(git -C "$directory" branch --show-current || true)"

  if [[ "$current_branch" == "$TARGET_BRANCH" ]]; then
    echo "Already on $TARGET_BRANCH."
    if $DRY_RUN; then
      run git -C "$directory" pull --ff-only origin "$TARGET_BRANCH"
      ((already_current += 1))
      continue
    fi

    if git -C "$directory" pull --ff-only origin "$TARGET_BRANCH"; then
      echo "Updated $TARGET_BRANCH."
      ((already_current += 1))
    else
      echo "ERROR: fast-forward update failed."
      ((failed += 1))
    fi
    continue
  fi

  if git -C "$directory" show-ref \
      --verify --quiet "refs/heads/$TARGET_BRANCH"
  then
    run git -C "$directory" switch "$TARGET_BRANCH"
  else
    run git -C "$directory" switch \
      --track -c "$TARGET_BRANCH" "origin/$TARGET_BRANCH"
  fi

  if $DRY_RUN; then
    run git -C "$directory" pull --ff-only origin "$TARGET_BRANCH"
    ((updated += 1))
    continue
  fi

  if git -C "$directory" pull --ff-only origin "$TARGET_BRANCH"; then
    echo "Switched to and updated $TARGET_BRANCH."
    ((updated += 1))
  else
    echo "ERROR: switched branches, but fast-forward update failed."
    ((failed += 1))
  fi
done < <(
  find "$EXTENSIONS_DIR" \
    -mindepth 1 \
    -maxdepth 1 \
    -type d \
    -print0 |
  sort -z
)

echo
echo "===== Summary ====="
echo "Target branch:          $TARGET_BRANCH"
echo "Switched:               $updated"
echo "Already on target:      $already_current"
echo "Skipped, dirty:         $skipped_dirty"
echo "Skipped, branch absent: $skipped_missing_branch"
echo "Skipped, not own repo:  $skipped_not_repo"
echo "Failures:               $failed"

if ((found == 0)); then
  echo "Error: no extension directories found." >&2
  exit 1
fi

if ((failed > 0)); then
  exit 1
fi

