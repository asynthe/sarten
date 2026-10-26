#!/usr/bin/env bash
# sarten homelab monitor — health check + log sampler for all Proxmox guests.
#
# Usage:
#   ./monitor.sh                 summary table: container status + HTTP checks
#   ./monitor.sh --logs          also dump recent ERROR/FATAL lines per container
#   ./monitor.sh --logs -n 500   scan the last 500 log lines instead of the default 200
#   ./monitor.sh media           only check the named guest (repeatable)
#
# Reads host/service inventory from hosts.conf (same dir). Add new guests or
# services there, not in this script. Secrets never belong in either file —
# this script only reads container status and public endpoints, no credentials.
#
# Requires: ssh access to the 'sarten' Proxmox host (see ~/.ssh/config) with
# passwordless sudo for /usr/sbin/pct (already set up for asynthe on sarten).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hosts.conf
source "$SCRIPT_DIR/hosts.conf"

SHOW_LOGS=false
LOG_LINES=200
FILTER_NAMES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --logs) SHOW_LOGS=true; shift ;;
    -n) LOG_LINES="$2"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) FILTER_NAMES+=("$1"); shift ;;
  esac
done

C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'

ok()   { echo "${C_GREEN}OK${C_RESET}"; }
warn() { echo "${C_YELLOW}WARN${C_RESET}"; }
bad()  { echo "${C_RED}DOWN${C_RESET}"; }

wanted() {
  local name="$1"
  [[ ${#FILTER_NAMES[@]} -eq 0 ]] && return 0
  for f in "${FILTER_NAMES[@]}"; do [[ "$f" == "$name" ]] && return 0; done
  return 1
}

pct_exec() { # $1=ct_id, rest = command (each remaining arg is quoted safely for the remote shell)
  local ct="$1"; shift
  local cmd
  printf -v cmd '%q ' "$@"
  ssh "$PROXMOX_HOST" "sudo -n /usr/sbin/pct exec $ct -- $cmd" 2>/dev/null
}

echo "${C_BOLD}== sarten homelab status — $(date '+%Y-%m-%d %H:%M:%S %Z') ==${C_RESET}"
echo "Proxmox host: $PROXMOX_HOST ($PROXMOX_WEBUI)"
if ssh -o ConnectTimeout=5 -o BatchMode=yes "$PROXMOX_HOST" true 2>/dev/null; then
  echo "SSH to $PROXMOX_HOST: $(ok)"
else
  echo "SSH to $PROXMOX_HOST: $(bad)  -- cannot continue, aborting."
  exit 1
fi
echo

for guest in "${GUESTS[@]}"; do
  IFS='|' read -r ct_id name ip services <<< "$guest"
  wanted "$name" || continue

  echo "${C_BOLD}--- $name (ct $ct_id, $ip) ---${C_RESET}"

  # container status (skip gracefully if this guest has no docker, e.g. native installs)
  containers="$(pct_exec "$ct_id" docker ps -a --format '{{.Names}}|{{.Status}}')"
  if [[ -z "$containers" ]]; then
    echo "  docker: no containers found (native install or not provisioned yet)"
  else
    while IFS='|' read -r cname cstatus; do
      [[ -z "$cname" ]] && continue
      if [[ "$cstatus" == Up* ]]; then
        state=$(ok)
      else
        state=$(bad)
      fi
      printf "  %-28s %-45s %s\n" "$cname" "$cstatus" "$state"
    done <<< "$containers"
  fi

  # HTTP health checks for advertised services
  if [[ -n "$services" ]]; then
    IFS=',' read -ra svc_list <<< "$services"
    for svc in "${svc_list[@]}"; do
      sname="${svc%%:*}"; sport="${svc##*:}"
      scheme="http"
      [[ " $WAZUH_HTTPS_CTS " == *" $ct_id "* ]] && scheme="https"
      code=$(curl -s -o /dev/null -w "%{http_code}" -m 5 -k "$scheme://$ip:$sport/" 2>/dev/null)
      if [[ "$code" =~ ^(200|301|302|401)$ ]]; then
        state=$(ok)
      elif [[ "$code" == "000" ]]; then
        state=$(bad)
      else
        state=$(warn)
      fi
      printf "  %-28s %-45s %s (HTTP %s)\n" "$sname" "$scheme://$ip:$sport/" "$state" "$code"
    done
  fi

  # error scan in recent logs
  if [[ "$SHOW_LOGS" == true && -n "$containers" ]]; then
    while IFS='|' read -r cname _; do
      [[ -z "$cname" ]] && continue
      errs=$(pct_exec "$ct_id" docker logs --tail "$LOG_LINES" "$cname" 2>&1 \
        | grep -iE "error|fatal|panic|exception|refused|unreachable" \
        | grep -viE "0 error|no error" | tail -5)
      if [[ -n "$errs" ]]; then
        echo "  ${C_YELLOW}recent errors in $cname:${C_RESET}"
        echo "$errs" | sed 's/^/    /'
      fi
    done <<< "$containers"
  fi

  echo
done
