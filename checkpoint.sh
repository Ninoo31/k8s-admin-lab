#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# Rejoue tous les modules jusqu'au numéro N inclus.
# Usage, dans un playground neuf, avant d'attaquer le module 3 :
#   ./checkpoint.sh 2
# ─────────────────────────────────────────────────────────────
source "$(dirname "$0")/lib.sh"
target="${1:?usage : ./checkpoint.sh <dernier module déjà maîtrisé>}"

for script in "$LAB_DIR"/[0-9][0-9]-*.sh; do
  num=$((10#$(basename "$script" | cut -c1-2)))
  if (( num > target )); then break; fi
  log "════ Checkpoint : $(basename "$script") ════"
  bash "$script"
done

log "Cluster remis à l'état « fin du module $target ». À toi de jouer."
