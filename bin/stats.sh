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
  echo "Usage: $0 [<env>] [--no-stream]"
  echo
  echo "With <env>: resource usage of each container of the environment (like 'docker stats'),"
  echo "plus the aggregated usage of all its containers."
  echo "Without <env>: aggregated usage of each running environment, plus the overall total."
  echo
  echo "Refreshes until Ctrl-C, unless --no-stream."
}

# Print the stats table.
#   render <env>  one row per container of the compose project <env>, then their total
#   render        one row per compose project (env) with running containers, then the overall total
#
# Containers are matched to their env with the com.docker.compose.project label (the env name for
# anything started with bin/up.sh); containers started outside compose are grouped under "-".
#
# CPU % follows 'docker stats': 100% = one CPU, so the total can exceed 100%.
# The last line also gives the share of the whole host (all CPUs, total memory).
render() {
  local env="$1" ids filter=()
  [ -n "$env" ] && filter=(--filter "label=com.docker.compose.project=${env}")

  ids=$(docker ps -q "${filter[@]}")
  if [ -z "$ids" ]; then
    if [ -n "$env" ]; then
      echo "${Yellow}⚠️  No running container for env '${env}'.${Color_Off}"
    else
      echo "${Yellow}⚠️  No running container.${Color_Off}"
    fi
    return
  fi

  # First input: container name -> env. Second input: the stats of each container.
  # shellcheck disable=SC2086
  awk -F'\t' -v mode="${env:+containers}" -v ncpu="$NCPU" -v memtotal="$MEMTOTAL" \
      -v bold="$Bold" -v cyan="$Cyan" -v off="$Color_Off" '
    BEGIN {
      if (mode == "") mode = "envs"
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
    function pct(c) { sub(/%/, "", c); return c + 0 }
    function plural(n, word) { return n " " word (n == 1 ? "" : "s") }
    function crow(name, cpu, mem, memp, net, blk, pids) {
      printf "%-" w "s  %8s  %-22s  %7s  %-21s  %-21s  %5s\n", name, cpu, mem, memp, net, blk, pids
    }
    function erow(name, cnt, cpu, mem, memp, net, blk, pids) {
      printf "%-" w "s  %10s  %8s  %10s  %7s  %-21s  %-21s  %5s\n", name, cnt, cpu, mem, memp, net, blk, pids
    }

    NR == FNR { project[$1] = ($2 == "" ? "-" : $2); next }

    {
      split($3, m, "/"); split($5, x, "/"); split($6, y, "/")
      mem = bytes(m[1]); rx = bytes(x[1]); tx = bytes(x[2]); rd = bytes(y[1]); wr = bytes(y[2]); cpu = pct($2)
      t_cpu += cpu; t_mem += mem; t_rx += rx; t_tx += tx; t_rd += rd; t_wr += wr; t_pids += $7; t_n++

      if (mode == "containers") {
        n++
        name[n] = $1; c_cpu[n] = $2; c_mem[n] = $3; c_memp[n] = $4; c_net[n] = $5; c_blk[n] = $6; c_pids[n] = $7
        if (length($1) > w) w = length($1)
      } else {
        e = ($1 in project) ? project[$1] : "-"
        if (!(e in e_n)) { n++; env[n] = e }
        e_n[e]++; e_cpu[e] += cpu; e_mem[e] += mem; e_rx[e] += rx; e_tx[e] += tx; e_rd[e] += rd; e_wr[e] += wr
        e_pids[e] += $7
        if (length(e) > w) w = length(e)
      }
    }

    END {
      if (mode == "containers") {
        total = "TOTAL (" plural(t_n, "container") ")"
        if (length(total) > w) w = length(total)
        printf "%s", bold; crow("NAME", "CPU %", "MEM USAGE / LIMIT", "MEM %", "NET I/O", "BLOCK I/O", "PIDS"); printf "%s", off
        for (i = 1; i <= n; i++) crow(name[i], c_cpu[i], c_mem[i], c_memp[i], c_net[i], c_blk[i], c_pids[i])
        printf "%s%s", bold, cyan
        crow(total, sprintf("%.2f%%", t_cpu), hbin(t_mem) " / " hbin(memtotal), sprintf("%.2f%%", 100 * t_mem / memtotal),
             hdec(t_rx) " / " hdec(t_tx), hdec(t_rd) " / " hdec(t_wr), t_pids)
        printf "%s", off
      } else {
        # sort the envs by name (insertion sort, mawk has no asort)
        for (i = 2; i <= n; i++) { v = env[i]; for (j = i - 1; j >= 1 && env[j] > v; j--) env[j + 1] = env[j]; env[j + 1] = v }
        total = "TOTAL (" plural(n, "env") ")"
        if (length(total) > w) w = length(total)
        printf "%s", bold; erow("ENV", "CONTAINERS", "CPU %", "MEM USAGE", "MEM %", "NET I/O", "BLOCK I/O", "PIDS"); printf "%s", off
        for (i = 1; i <= n; i++) {
          e = env[i]
          erow(e, e_n[e], sprintf("%.2f%%", e_cpu[e]), hbin(e_mem[e]), sprintf("%.2f%%", 100 * e_mem[e] / memtotal),
               hdec(e_rx[e]) " / " hdec(e_tx[e]), hdec(e_rd[e]) " / " hdec(e_wr[e]), e_pids[e])
        }
        printf "%s%s", bold, cyan
        erow(total, t_n, sprintf("%.2f%%", t_cpu), hbin(t_mem), sprintf("%.2f%%", 100 * t_mem / memtotal),
             hdec(t_rx) " / " hdec(t_tx), hdec(t_rd) " / " hdec(t_wr), t_pids)
        printf "%s", off
      }
      printf "\nHost: %.2f%% of %d CPUs, %.2f%% of %s memory\n", t_cpu / ncpu, ncpu, 100 * t_mem / memtotal, hbin(memtotal)
    }' \
    <(docker ps "${filter[@]}" --format '{{.Names}}\t{{.Label "com.docker.compose.project"}}') \
    <(docker stats --no-stream \
        --format '{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}\t{{.PIDs}}' $ids | sort)
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

# Check if the environment exists
if [ -n "$ENV" ] && [ ! -e "live/${ENV}" ]; then
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
  printf "Env: ${Cyan}%s${Color_Off}    (%s, Ctrl-C to quit)\n\n%s\n" "${ENV:-all}" "$(date '+%T')" "$out"
done
