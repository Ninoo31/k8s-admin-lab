#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# Module 0 — Préparer les machines (checkpoint rejouable)
# À lancer en root sur le control plane. Idempotent.
# ─────────────────────────────────────────────────────────────
source "$(dirname "$0")/lib.sh"
require_root
require_machines

mapfile -t NODES < <(machines)

log "1/4 Clé SSH du control plane"
if [[ ! -f ~/.ssh/id_ed25519 ]]; then
  ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519 -q
fi
ok "~/.ssh/id_ed25519 présente"

log "2/4 Accès SSH root sans mot de passe"
for line in "${NODES[@]}"; do
  read -r ip host _ <<<"$line"
  if on "$ip" true </dev/null 2>/dev/null; then
    ok "$host ($ip) joignable"
  else
    die "Pas d'accès à root@$ip → ssh-copy-id root@$ip (ou colle ~/.ssh/id_ed25519.pub dans /root/.ssh/authorized_keys de $host)"
  fi
done

log "3/4 /etc/hosts identique partout (bloc géré entre marqueurs)"
HOSTS_BLOCK="$(machines | awk '{print $1"\t"$2}')"
for line in "${NODES[@]}"; do
  read -r ip host _ <<<"$line"
  printf '# >>> k8s-lab\n%s\n# <<< k8s-lab\n' "$HOSTS_BLOCK" |
    on "$ip" 'sed -i "/# >>> k8s-lab/,/# <<< k8s-lab/d" /etc/hosts && cat >> /etc/hosts'
  ok "$host"
done

log "4/4 Prérequis noyau : swap off, modules, sysctl"
for line in "${NODES[@]}"; do
  read -r ip _ <<<"$line"
  on "$ip" bash -s <<'REMOTE'
set -e
# swap : le kubelet refuse de démarrer par défaut si le swap est actif
swapoff -a
sed -ri '/\sswap\s/ s/^#*/#/' /etc/fstab
# overlay : système de fichiers des couches d'images
# br_netfilter : rendre le trafic des bridges visible par iptables (Services)
cat > /etc/modules-load.d/k8s.conf <<M
overlay
br_netfilter
M
modprobe overlay
modprobe br_netfilter
# ip_forward : le nœud doit router les paquets des Pods
cat > /etc/sysctl.d/99-k8s.conf <<S
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
S
sysctl --system >/dev/null
. /etc/os-release
printf '  ✔ %-14s %-22s arch=%-6s swap=%s ip_forward=%s br_netfilter=%s\n' \
  "$(hostname -s)" "$PRETTY_NAME" "$(dpkg --print-architecture)" \
  "$(swapon --show --noheadings | wc -l)" "$(sysctl -n net.ipv4.ip_forward)" \
  "$(lsmod | grep -q br_netfilter && echo oui || echo NON)"
REMOTE
done

log "Module 0 terminé ✔"
