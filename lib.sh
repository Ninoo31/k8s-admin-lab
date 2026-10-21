#!/usr/bin/env bash
# Fonctions communes à tous les modules du lab
set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=cluster.env
source "$LAB_DIR/cluster.env"
MACHINES="$LAB_DIR/machines.txt"

log()  { printf '\n\033[1;34m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
ok()   { printf '\033[1;32m  ✔\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  ⚠ %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m  ✘ %s\033[0m\n' "$*" >&2; exit 1; }

require_root() {
  if [[ $EUID -ne 0 ]]; then die "Lance ce script en root (sudo -i)"; fi
}

require_machines() {
  if [[ ! -f $MACHINES ]]; then
    die "machines.txt absent : cp machines.txt.example machines.txt puis remplis-le (module 0)"
  fi
}

# Lignes utiles de machines.txt (sans commentaires ni lignes vides)
machines()    { grep -vE '^[[:space:]]*(#|$)' "$MACHINES"; }
server_ip()   { machines | awk '$3=="server"{print $1; exit}'; }
server_name() { machines | awk '$3=="server"{print $2; exit}'; }
workers()     { machines | awk '$3=="worker"{print $2}'; }
all_ips()     { machines | awk '{print $1}'; }
ip_of()       { machines | awk -v h="$1" '$2==h{print $1}'; }
podcidr_of()  { machines | awk -v h="$1" '$2==h{print $4}'; }

# Exécuter une commande sur une machine en root via SSH
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -o BatchMode=yes)
on() { local host=$1; shift; ssh "${SSH_OPTS[@]}" "root@$host" "$@"; }
# Copier un fichier vers une machine : cp_to <host> <fichier_local> <chemin_distant>
cp_to() { scp -q "${SSH_OPTS[@]}" "$2" "root@$1:$3"; }
