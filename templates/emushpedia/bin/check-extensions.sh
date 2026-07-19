#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
EMUSHPEDIA_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
EXTENSIONS_DIR="${EXTENSIONS_DIR:-$EMUSHPEDIA_DIR/data/extensions}"
MEDIAWIKI_CONTAINER="${MEDIAWIKI_CONTAINER:-emushpedia-mediawiki-fr}"
FETCH_REMOTE=false

usage() {
  cat <<'USAGE'
Usage: check-extension-versions.sh [--fetch] [--extensions-dir PATH]

Show the installed version and compatibility information for every extension
stored in live/emushpedia/data/extensions.

Options:
  --fetch                 Fetch Git remotes before checking update status.
  --extensions-dir PATH   Override the extensions directory.
  -h, --help              Show this help.

Environment variables:
  EXTENSIONS_DIR          Same as --extensions-dir.
  MEDIAWIKI_CONTAINER     Container used as a PHP fallback when jq is absent.
                          Default: emushpedia-mediawiki-fr
USAGE
}

while (($#)); do
  case "$1" in
    --fetch)
      FETCH_REMOTE=true
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
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! -d "$EXTENSIONS_DIR" ]]; then
  echo "Error: extensions directory not found: $EXTENSIONS_DIR" >&2
  exit 1
fi

read_json_field() {
  local file="$1"
  local jq_filter="$2"
  local php_key="$3"

  if [[ ! -f "$file" ]]; then
    printf '%s' "-"
    return
  fi

  if command -v jq >/dev/null 2>&1; then
    jq -r "$jq_filter // \"-\"" "$file" 2>/dev/null || printf '%s' "invalid JSON"
    return
  fi

  if command -v docker >/dev/null 2>&1 && docker inspect "$MEDIAWIKI_CONTAINER" >/dev/null 2>&1; then
    local relative_path
    relative_path="${file#"$EXTENSIONS_DIR"/}"
    docker exec "$MEDIAWIKI_CONTAINER" php -r '
      $data = json_decode(file_get_contents($argv[1]), true);
      if (!is_array($data)) {
          echo "invalid JSON";
          exit;
      }
      $path = explode(".", $argv[2]);
      $value = $data;
      foreach ($path as $key) {
          if (!is_array($value) || !array_key_exists($key, $value)) {
              echo "-";
              exit;
          }
          $value = $value[$key];
      }
      echo is_scalar($value) ? $value : json_encode($value);
    ' "/var/www/html/extensions/non-core/$relative_path" "$php_key" 2>/dev/null || printf '%s' "-"
    return
  fi

  printf '%s' "jq required"
}

shorten() {
  local value="$1"
  local max="$2"
  if ((${#value} > max)); then
    printf '%s…' "${value:0:max-1}"
  else
    printf '%s' "$value"
  fi
}

printf '%-30s %-16s %-16s %-12s %-10s %-12s %s\n' \
  "EXTENSION" "VERSION" "MW REQUIREMENT" "BRANCH" "COMMIT" "REMOTE" "STATUS"
printf '%-30s %-16s %-16s %-12s %-10s %-12s %s\n' \
  "------------------------------" "----------------" "----------------" "------------" "----------" "------------" "----------------"

found=0
while IFS= read -r -d '' directory; do
  found=1
  extension="$(basename "$directory")"
  json_file="$directory/extension.json"

  version="$(read_json_field "$json_file" '.version' 'version')"
  requirement="$(read_json_field "$json_file" '.requires.MediaWiki' 'requires.MediaWiki')"

  branch="-"
  commit="-"
  remote_branch="-"
  status="not a Git repository"

  # Only treat the extension as an independent repository when its own .git
  # metadata exists. This avoids reporting the parent deployment repository.
  if [[ -e "$directory/.git" ]]; then
    branch="$(git -C "$directory" branch --show-current 2>/dev/null || true)"
    [[ -n "$branch" ]] || branch="detached"
    commit="$(git -C "$directory" rev-parse --short=8 HEAD 2>/dev/null || printf '%s' '-')"

    if $FETCH_REMOTE; then
      git -C "$directory" fetch --quiet --prune 2>/dev/null || true
    fi

    upstream="$(git -C "$directory" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
    if [[ -n "$upstream" ]]; then
      remote_branch="$upstream"
      counts="$(git -C "$directory" rev-list --left-right --count HEAD..."$upstream" 2>/dev/null || true)"
      if [[ -n "$counts" ]]; then
        read -r ahead behind <<<"$counts"
        if ((ahead == 0 && behind == 0)); then
          status="up to date"
        elif ((ahead == 0)); then
          status="behind $behind"
        elif ((behind == 0)); then
          status="ahead $ahead"
        else
          status="ahead $ahead, behind $behind"
        fi
      else
        status="unable to compare"
      fi
    else
      status="no upstream"
    fi

    if ! git -C "$directory" diff --quiet 2>/dev/null || \
       ! git -C "$directory" diff --cached --quiet 2>/dev/null; then
      status="$status; modified"
    fi
  fi

  printf '%-30s %-16s %-16s %-12s %-10s %-12s %s\n' \
    "$(shorten "$extension" 30)" \
    "$(shorten "$version" 16)" \
    "$(shorten "$requirement" 16)" \
    "$(shorten "$branch" 12)" \
    "$commit" \
    "$(shorten "$remote_branch" 12)" \
    "$status"
done < <(find "$EXTENSIONS_DIR" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

if ((found == 0)); then
  echo "No extension directories found in $EXTENSIONS_DIR" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo >&2
  echo "Note: jq is not installed; extension.json fields were read through $MEDIAWIKI_CONTAINER." >&2
fi
