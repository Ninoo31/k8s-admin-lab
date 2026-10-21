# k8s-admin-lab

Sandbox Kubernetes « à casser » sur le playground KodeKloud Ubuntu multi-node (3 machines).
Phase 1 : Kubernetes The Hard Way. Phase 2 : kubeadm prod-like. Objectif : CKA.

## Règle d'or

- Le module **en cours** se tape **à la main** (jamais de copier-coller).
- Les modules **déjà faits** se rejouent avec les scripts : le playground est éphémère.

## Démarrer une session dans un playground neuf

```bash
sudo -i
git clone https://gitlab.com/<toi>/k8s-admin-lab.git && cd k8s-admin-lab
cp machines.txt.example machines.txt && vi machines.txt   # tes IP/hostnames du jour
chmod +x *.sh
./checkpoint.sh 1        # rejoue les modules 0 et 1, puis attaque le module 2
```

> Les IP changent à chaque playground : `machines.txt` est à refaire à chaque session
> (ne le commit pas : il est dans `.gitignore`).

## Contenu

| Fichier | Rôle |
|---|---|
| `cluster.env` | Version K8s, plages réseau (Services, Pods), dossier PKI |
| `machines.txt.example` | Modèle d'inventaire des 3 machines |
| `lib.sh` | Fonctions communes (log, ssh, lecture inventaire) |
| `00-preflight.sh` | Module 0 : SSH, /etc/hosts, swap, modules noyau, sysctl |
| `01-pki.sh` | Module 1 : CA + certificats de chaque composant, distribution |
| `checkpoint.sh N` | Rejoue les modules 0 → N |
