#!/bin/bash
# Vérifie l'intégrité du projet : génération depuis project.yml, aucun fichier Swift oublié,
# et (avec --test) exécution de NookFlowTests.
# Usage : ./scripts/check.sh          vérification rapide
#         ./scripts/check.sh --test   vérification + tests
set -euo pipefail
cd "$(dirname "$0")/.."

echo "→ Génération du projet depuis project.yml"
xcodegen generate

echo "→ Contrôle : chaque fichier Swift est dans le projet"
missing=0
while IFS= read -r file; do
  if ! grep -q "$(basename "$file")" NookFlow.xcodeproj/project.pbxproj; then
    echo "  absent du projet : $file" >&2
    missing=1
  fi
done < <(find NookFlow NookFlowTests -name '*.swift')
[ "$missing" -eq 0 ] || { echo "Erreur : fichiers Swift non référencés." >&2; exit 1; }
echo "  ok"

if [ "${1:-}" = "--test" ]; then
  echo "→ Tests (NookFlowTests)"
  xcodebuild test \
    -project NookFlow.xcodeproj \
    -scheme NookFlow \
    -destination 'platform=macOS' \
    -derivedDataPath "${TMPDIR:-/tmp}/NookFlowCheck" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_ALLOWED=YES \
    | tail -n 25
fi
echo "Terminé."
