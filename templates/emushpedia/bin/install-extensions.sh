#!/usr/bin/env bash

set -euo pipefail

# Format:
#   "custom_name|repository_url|fallback_branch"
#
# custom_name:
#   Leave empty to derive it from the repository URL.
#
# fallback_branch:
#   Leave empty to skip the extension when the requested REL branch does not
#   exist. When provided, it is used only if the requested REL branch is absent.
#
# Examples:
#   "|https://gerrit.wikimedia.org/r/mediawiki/extensions/Analytics|"
#   "ThemeToggle|https://github.com/wiki-gg-oss/mediawiki-extensions-ThemeToggle|main"

EXTENSIONS=(
  "|https://gerrit.wikimedia.org/r/mediawiki/extensions/Analytics|"
  "|https://gerrit.wikimedia.org/r/mediawiki/extensions/Arrays|"
  "|https://gerrit.wikimedia.org/r/mediawiki/extensions/CirrusSearch|"
  "|https://gerrit.wikimedia.org/r/mediawiki/extensions/CreatePageUw|"
  "|https://gerrit.wikimedia.org/r/mediawiki/extensions/DarkMode|"
  "|https://gerrit.wikimedia.org/r/mediawiki/extensions/Elastica|"
  "|https://gerrit.wikimedia.org/r/mediawiki/extensions/OAuth|"
  "|https://gerrit.wikimedia.org/r/mediawiki/extensions/UniversalLanguageSelector|"
  "|https://gerrit.wikimedia.org/r/mediawiki/extensions/UserMerge|"
  "|https://gerrit.wikimedia.org/r/mediawiki/extensions/Variables|"
)

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
EXTENSIONS_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)/data/extensions"

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

remote_branch_exists() {
  local repository="$1"
  local branch="$2"

  git ls-remote \
    --exit-code \
    --heads \
    "$repository" \
    "refs/heads/$branch" >/dev/null 2>&1
}

resolve_branch() {
  local repository="$1"
  local requested_branch="$2"
  local fallback_branch="$3"

  if remote_branch_exists "$repository" "$requested_branch"; then
    printf '%s\n' "$requested_branch"
    return 0
  fi

  if [[ -z "$fallback_branch" ]]; then
    return 1
  fi

  if remote_branch_exists "$repository" "$fallback_branch"; then
    printf '%s\n' "$fallback_branch"
    return 0
  fi

  return 2
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
fallbacks=0

for extension_entry in "${EXTENSIONS[@]}"; do
  custom_name=""
  repo_url=""
  fallback_branch=""

  IFS='|' read -r custom_name repo_url fallback_branch extra \
    <<< "$extension_entry"

  if [[ -n "${extra:-}" ]]; then
    echo
    echo "ERROR: invalid extension entry:" >&2
    echo "  $extension_entry" >&2
    echo "Expected format:" >&2
    echo "  custom_name|repository_url|fallback_branch" >&2
    ((failed += 1))
    continue
  fi

  if [[ -z "$repo_url" ]]; then
    echo
    echo "ERROR: repository URL is empty:" >&2
    echo "  $extension_entry" >&2
    ((failed += 1))
    continue
  fi

  if [[ -n "$custom_name" ]]; then
    extension="$custom_name"
  else
    extension="${repo_url%/}"
    extension="${extension##*/}"
    extension="${extension%.git}"
  fi

  if [[ -z "$extension" || "$extension" == "." || "$extension" == ".." ]]; then
    echo
    echo "ERROR: invalid extension name for repository:" >&2
    echo "  $repo_url" >&2
    ((failed += 1))
    continue
  fi

  if [[ "$extension" == */* ]]; then
    echo
    echo "ERROR: extension name must not contain '/':" >&2
    echo "  $extension" >&2
    ((failed += 1))
    continue
  fi

  destination="$EXTENSIONS_DIR/$extension"

  echo
  echo "===== $extension ====="
  echo "Repository:       $repo_url"
  echo "Destination:      $destination"
  echo "Requested branch: $TARGET_BRANCH"

  if [[ -n "$fallback_branch" ]]; then
    echo "Fallback branch:  $fallback_branch"
  fi

  # For an existing repository, use origin after validating it.
  # For a new repository, query the configured URL directly.
  branch_repository="$repo_url"

  if [[ -e "$destination" ]]; then
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

    current_origin="$(
      git -C "$destination" remote get-url origin 2>/dev/null || true
    )"

    expected_origin="${repo_url%/}"
    expected_origin="${expected_origin%.git}"

    normalized_current_origin="${current_origin%/}"
    normalized_current_origin="${normalized_current_origin%.git}"

    if [[ -z "$current_origin" ]]; then
      echo "Adding missing origin remote..."

      if ! git -C "$destination" remote add origin "$repo_url"; then
        echo "ERROR: failed to add origin for $extension." >&2
        ((failed += 1))
        continue
      fi
    elif [[ "$normalized_current_origin" != "$expected_origin" ]]; then
      echo "SKIP: origin does not match the expected repository."
      echo "  Current : $current_origin"
      echo "  Expected: $repo_url"
      ((skipped += 1))
      continue
    fi

    branch_repository="origin"

    echo "Fetching origin..."

    if ! git -C "$destination" fetch --prune origin; then
      echo "ERROR: git fetch failed for $extension." >&2
      ((failed += 1))
      continue
    fi
  fi

  resolved_branch=""

  if [[ "$branch_repository" == "origin" ]]; then
    if git -C "$destination" show-ref \
      --verify \
      --quiet "refs/remotes/origin/$TARGET_BRANCH"
    then
      resolved_branch="$TARGET_BRANCH"
    elif [[ -z "$fallback_branch" ]]; then
      echo "SKIP: origin/$TARGET_BRANCH does not exist and no fallback is configured."
      ((skipped += 1))
      continue
    elif git -C "$destination" show-ref \
      --verify \
      --quiet "refs/remotes/origin/$fallback_branch"
    then
      resolved_branch="$fallback_branch"
    else
      echo "ERROR: neither requested nor fallback branch exists." >&2
      echo "  Requested: origin/$TARGET_BRANCH" >&2
      echo "  Fallback:  origin/$fallback_branch" >&2
      ((failed += 1))
      continue
    fi
  else
    resolve_status=0
    resolved_branch="$(
      resolve_branch \
        "$repo_url" \
        "$TARGET_BRANCH" \
        "$fallback_branch"
    )" || resolve_status=$?

    case "$resolve_status" in
      0)
        ;;
      1)
        echo "SKIP: $TARGET_BRANCH does not exist and no fallback is configured."
        ((skipped += 1))
        continue
        ;;
      2)
        echo "ERROR: neither requested nor fallback branch exists." >&2
        echo "  Requested: $TARGET_BRANCH" >&2
        echo "  Fallback:  $fallback_branch" >&2
        ((failed += 1))
        continue
        ;;
      *)
        echo "ERROR: failed to inspect remote branches for $extension." >&2
        ((failed += 1))
        continue
        ;;
    esac
  fi

  if [[ "$resolved_branch" != "$TARGET_BRANCH" ]]; then
    echo "Requested branch does not exist; using fallback: $resolved_branch"
    ((fallbacks += 1))
  else
    echo "Using branch: $resolved_branch"
  fi

  if [[ ! -e "$destination" ]]; then
    echo "Cloning $resolved_branch..."

    if git clone \
      --branch "$resolved_branch" \
      --single-branch \
      "$repo_url" \
      "$destination"
    then
      ((cloned += 1))
    else
      echo "ERROR: failed to clone $extension on $resolved_branch." >&2
      ((failed += 1))
    fi

    continue
  fi

  current_branch="$(
    git -C "$destination" branch --show-current || true
  )"

  before_commit="$(
    git -C "$destination" rev-parse HEAD
  )"

  if git -C "$destination" show-ref \
    --verify \
    --quiet "refs/heads/$resolved_branch"
  then
    if [[ "$current_branch" != "$resolved_branch" ]]; then
      if ! git -C "$destination" switch "$resolved_branch"; then
        echo "ERROR: failed to switch $extension to $resolved_branch." >&2
        ((failed += 1))
        continue
      fi
    fi
  else
    if ! git -C "$destination" switch \
      --track \
      -c "$resolved_branch" \
      "origin/$resolved_branch"
    then
      echo "ERROR: failed to create local branch $resolved_branch." >&2
      ((failed += 1))
      continue
    fi
  fi

  if ! git -C "$destination" merge \
    --ff-only \
    "origin/$resolved_branch"
  then
    echo "ERROR: cannot fast-forward $extension." >&2
    ((failed += 1))
    continue
  fi

  after_commit="$(
    git -C "$destination" rev-parse HEAD
  )"

  if [[ "$before_commit" == "$after_commit" &&
        "$current_branch" == "$resolved_branch" ]]
  then
    echo "Already up to date on $resolved_branch."
    ((unchanged += 1))
  else
    echo "Updated to $resolved_branch at ${after_commit:0:12}."
    ((updated += 1))
  fi
done

echo
echo "===== Summary ====="
echo "Requested branch:        $TARGET_BRANCH"
echo "Cloned:                  $cloned"
echo "Updated:                 $updated"
echo "Already up to date:      $unchanged"
echo "Fallback branches used:  $fallbacks"
echo "Skipped:                 $skipped"
echo "Failures:                $failed"

if ((failed > 0)); then
  exit 1
fi
