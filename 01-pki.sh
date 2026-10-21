#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# Module 1 — PKI : les cartes d'identité du cluster (checkpoint)
# À lancer en root sur le control plane. Idempotent :
# un certificat déjà présent n'est pas régénéré (la CA reste stable).
# ─────────────────────────────────────────────────────────────
source "$(dirname "$0")/lib.sh"
require_root
require_machines

SERVER_IP="$(server_ip)"
SERVER="$(server_name)"
mkdir -p "$PKI_DIR"
cd "$PKI_DIR"

# ── 1. L'autorité de certification (CA) ─────────────────────
log "1/4 Autorité de certification"
if [[ ! -f ca.crt ]]; then
  cat > ca.cnf <<'EOF'
[req]
distinguished_name = dn
prompt             = no
x509_extensions    = v3_ca

[dn]
CN = KUBERNETES-CA

[v3_ca]
basicConstraints     = critical, CA:TRUE
keyUsage             = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
EOF
  openssl genrsa -out ca.key 4096 2>/dev/null
  openssl req -x509 -new -key ca.key -sha256 -days 3650 -config ca.cnf -out ca.crt
  ok "ca.crt créée (10 ans)"
else
  ok "ca.crt déjà présente"
fi

# ── 2. Fabrique de certificats ──────────────────────────────
# gen_cert <fichier> <CN> <O ou ""> <extendedKeyUsage> [SANs]
#   CN  → devient le NOM D'UTILISATEUR vu par l'API server
#   O   → devient le GROUPE (utilisé par RBAC)
#   SAN → noms/IP sous lesquels un SERVEUR a le droit de répondre
gen_cert() {
  local name=$1 cn=$2 org=$3 eku=$4 sans=${5:-}
  if [[ -f $name.crt ]]; then ok "$name.crt déjà présent"; return; fi

  local subj="/CN=$cn"
  if [[ -n $org ]]; then subj+="/O=$org"; fi

  openssl genrsa -out "$name.key" 2048 2>/dev/null
  openssl req -new -key "$name.key" -subj "$subj" -out "$name.csr"

  {
    echo "basicConstraints = critical, CA:FALSE"
    echo "keyUsage = critical, digitalSignature, keyEncipherment"
    echo "extendedKeyUsage = $eku"
    if [[ -n $sans ]]; then echo "subjectAltName = $sans"; fi
  } > "$name.ext"

  openssl x509 -req -in "$name.csr" -CA ca.crt -CAkey ca.key -CAcreateserial \
    -days 365 -sha256 -extfile "$name.ext" -out "$name.crt" 2>/dev/null
  ok "$name.crt  →  CN=$cn${org:+  O=$org}"
}

log "2/4 Certificats des composants"
# Humain : groupe system:masters = super-admin (contourne RBAC)
gen_cert admin admin system:masters clientAuth

# Kubelets : un cert PAR nœud, CN = system:node:<nom> (Node Authorizer)
for w in $(workers); do
  gen_cert "$w" "system:node:$w" system:nodes "serverAuth,clientAuth" \
    "DNS:$w,IP:$(ip_of "$w")"
done

gen_cert kube-proxy              system:kube-proxy              system:node-proxier            clientAuth
gen_cert kube-controller-manager system:kube-controller-manager system:kube-controller-manager clientAuth
gen_cert kube-scheduler          system:kube-scheduler          system:kube-scheduler          clientAuth

# API server : serveur pour tout le monde + client des kubelets (logs/exec)
API_SANS="IP:127.0.0.1,IP:$API_SERVICE_IP,IP:$SERVER_IP,DNS:$SERVER"
API_SANS+=",DNS:kubernetes,DNS:kubernetes.default,DNS:kubernetes.default.svc"
API_SANS+=",DNS:kubernetes.default.svc.cluster,DNS:kubernetes.default.svc.cluster.local"
gen_cert kube-api-server kubernetes "" "serverAuth,clientAuth" "$API_SANS"

# Paire de clés qui SIGNE les jetons des ServiceAccounts
gen_cert service-accounts service-accounts "" clientAuth

chmod 600 ./*.key

# ── 3. Contrôle de la chaîne de confiance ───────────────────
log "3/4 Vérification : chaque cert est-il signé par notre CA ?"
for c in *.crt; do
  [[ $c == ca.crt ]] && continue
  if openssl verify -CAfile ca.crt "$c" >/dev/null 2>&1; then ok "$c"; else die "$c NON signé par ca.crt"; fi
done

# ── 4. Distribution vers les workers ────────────────────────
log "4/4 Distribution vers les workers"
for w in $(workers); do
  ip="$(ip_of "$w")"
  on "$ip" 'mkdir -p /var/lib/kubelet /var/lib/kube-proxy' </dev/null
  cp_to "$ip" ca.crt   /var/lib/kubelet/ca.crt
  cp_to "$ip" "$w.crt" /var/lib/kubelet/kubelet.crt
  cp_to "$ip" "$w.key" /var/lib/kubelet/kubelet.key
  ok "$w ← ca.crt, kubelet.crt, kubelet.key"
done
# Les certs du control plane restent dans $PKI_DIR : le module 4 les installera.

log "Module 1 terminé ✔  (PKI dans $PKI_DIR)"
