#!/bin/bash

# Colors
Color_Off=$'\e[0m' # Text Reset
Red=$'\e[0;31m'    # Red
Green=$'\e[0;32m'  # Green
Yellow=$'\e[0;33m' # Yellow
Purple=$'\e[0;35m' # Purple
Cyan=$'\e[0;36m'   # Cyan
Bold=$'\e[1m'      # Bold

usage() {
  echo "Usage: $0 <env> [--no-stream]"
  echo
  echo "Per container resource usage of an environment (like 'docker stats'), plus the"
  echo "aggregated usage of all its containers. Refreshes until Ctrl-C, unless --no-stream."
}

# Print the stats table of every running container of the compose project $1.
#
# CPU % follows 'docker stats': 100% = one CPU, so the total can exceed 100%.
# The total line also gives the share of the whole host (all CPUs, total memory).
render() {
  local env="$1" ids
  ids=$(docker ps -q --filter "label=com.docker.compose.project=${env}")
  if [ -z "$ids" ]; then
    echo "${Yellow}⚠️  No running container for env '${env}'.${Color_Off}"
    return
  fi

  # shellcheck disable=SC2086
  docker stats --no-stream \
      --format '{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}\t{{.PIDs}}' $ids \
    | sort \
    | awk -F'\t' -v ncpu="$NCPU" -v memtotal="$MEMTOTAL" -v bold="$Bold" -v cyan="$Cyan" -v off="$Color_Off" '
      BEGIN {
        split("B KiB MiB GiB TiB", binu, " ")
        split("B kB MB GB TB", decu, " ")
        mult["B"] = 1
        mult["kB"] = 1e3;  mult["KB"] = 1e3; mult["MB"] = 1e6;  mult["GB"] = 1e9;  mult["TB"] = 1e12
        mult["KiB"] = 1024; mult["MiB"] = 1024^2; mult["GiB"] = 1024^3; mult["TiB"] = 1024^4
      }
      function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
      # "123.4MiB" -> bytes
      function bytes(s,    n) {
        s = trim(s)
        if (!match(s, /^[0-9.]+/)) return 0
        n = substr(s, 1, RLENGTH) + 0
        return n * mult[substr(s, RLENGTH + 1)]
      }
      # bytes -> "123.4MiB" (memory, like docker: binary units, 4 digits)
      function hbin(b,    i) { for (i = 1; b >= 1024 && i < 5; i++) b /= 1024; return sprintf("%.4g%s", b, binu[i]) }
      # bytes -> "123MB" (I/O, like docker: decimal units, 3 digits)
      function hdec(b,    i) { for (i = 1; b >= 1000 && i < 5; i++) b /= 1000; return sprintf("%.3g%s", b, decu[i]) }
      function row(name, cpu, mem, memp, net, blk, pids) {
        printf "%-" w "s  %8s  %-22s  %7s  %-21s  %-21s  %5s\n", name, cpu, mem, memp, net, blk, pids
      }
      {
        n++
        name[n] = $1; cpu[n] = $2; mem[n] = $3; memp[n] = $4; net[n] = $5; blk[n] = $6; pids[n] = $7
        if (length($1) > w) w = length($1)

        split($3, m, "/"); t_mem += bytes(m[1])
        split($5, x, "/"); t_rx += bytes(x[1]); t_tx += bytes(x[2])
        split($6, y, "/"); t_rd += bytes(y[1]); t_wr += bytes(y[2])
        c = $2; sub(/%/, "", c); t_cpu += c
        t_pids += $7
      }
      END {
        total = "TOTAL (" n (n == 1 ? " container)" : " containers)")
        if (length(total) > w) w = length(total)
        printf "%s", bold; row("NAME", "CPU %", "MEM USAGE / LIMIT", "MEM %", "NET I/O", "BLOCK I/O", "PIDS"); printf "%s", off
        for (i = 1; i <= n; i++) row(name[i], cpu[i], mem[i], memp[i], net[i], blk[i], pids[i])
        printf "%s%s", bold, cyan
        row(total, sprintf("%.2f%%", t_cpu), hbin(t_mem) " / " hbin(memtotal), sprintf("%.2f%%", 100 * t_mem / memtotal),
            hdec(t_rx) " / " hdec(t_tx), hdec(t_rd) " / " hdec(t_wr), t_pids)
        printf "%s", off
        printf "\nHost: %.2f%% of %d CPUs, %.2f%% of %s memory\n", t_cpu / ncpu, ncpu, 100 * t_mem / memtotal, hbin(memtotal)
      }'
}

#########################################################


ENV=""
STREAM=1
for arg in "$@"; do
  case "$arg" in
    --no-stream) STREAM=0 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "${Red}❌ Error: Unknown option '$arg'.${Color_Off}"; usage; exit 1 ;;
    *) [ -z "$ENV" ] && ENV="$arg" || { usage; exit 1; } ;;
  esac
done

# Check if env argument is provided
if [ -z "$ENV" ]; then
  usage
  exit 1
fi

# Check if the environment exists
if [ ! -e "live/${ENV}" ]; then
  echo "${Red}❌ Error: Environment './live/${ENV}' does not exist.${Color_Off}"
  exit 1
fi

read -r NCPU MEMTOTAL < <(docker info --format '{{.NCPU}} {{.MemTotal}}')

if [ "$STREAM" = 0 ]; then
  render "$ENV"
  exit 0
fi

# Live mode: render off-screen, then redraw in one go to avoid flickering.
trap 'tput cnorm; echo; exit 0' INT TERM
tput civis
while true; do
  out=$(render "$ENV")
  tput clear
  printf "Env: ${Cyan}%s${Color_Off}    (%s, Ctrl-C to quit)\n\n%s\n" "$ENV" "$(date '+%T')" "$out"
done
