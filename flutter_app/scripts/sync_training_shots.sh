#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# CAPTURES DU GUIDE ET DU MANUEL DE FORMATION « Suivi Évangélisation »
#
#   ./scripts/sync_training_shots.sh
#
# Régénère les captures de l'application (test/formation/, serveur de
# démonstration — aucun vrai numéro), puis les copie dans le module Odoo
# (static/help/app/), réduites à 540 px de large : la taille d'origine
# (1170 px) alourdirait le PDF sans rien gagner à l'impression.
#
# Les vidéos, elles, prennent les originaux de test/formation/ (la loupe a
# besoin de la pleine résolution). Le guide et le manuel citent les fichiers
# par leur nom ; un test côté Odoo vérifie que chaque image citée existe.
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail
cd "$(dirname "$0")/.."

DEST="../static/help/app"
mkdir -p "$DEST"

flutter test --tags formation --run-skipped --update-goldens

for png in test/formation/*.png; do
  name=$(basename "$png")
  sips --resampleWidth 540 "$png" --out "$DEST/$name" >/dev/null
done
echo "✓ $(ls test/formation/*.png | wc -l | tr -d ' ') captures copiées dans $DEST (540 px)"
