#!/usr/bin/env bash
# Vérifie un serveur Nakama qui tourne : compte appareil, profil, placement d'une tour.
set -euo pipefail
H=${NAKAMA_URL:-http://127.0.0.1:7350}
TOKEN=$(curl -sf -u defaultkey: -X POST "$H/v2/account/authenticate/device?create=true" \
  -H 'Content-Type: application/json' -d '{"id":"appareil-test-aodk-0001"}' | sed -E 's/.*"token":"([^"]+)".*/\1/')
rpc() { curl -sf -X POST "$H/v2/rpc/$1" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d "$2"; echo; }
rpc sante '"{}"'
rpc profil_lire '"{}"'
rpc bastion_placer '"{\"id\":\"mur\",\"x\":1,\"y\":1}"'
