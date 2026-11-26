#!/bin/bash
# Compile NookFlow en Release et l'installe dans /Applications.
# Usage : depuis le dossier du projet,  ./scripts/install.sh
set -euo pipefail
cd "$(dirname "$0")/.."

# On compile hors de ~/Desktop et ~/Documents : iCloud Drive y ajoute des métadonnées
# cachées qui font échouer la signature (« resource fork, Finder information… »).
BUILD_DIR="$HOME/Library/Caches/NookFlowBuild"
rm -rf "$BUILD_DIR"

echo "→ Génération du projet Xcode"
xcodegen generate

echo "→ Compilation (Release)"
xcodebuild \
  -project NookFlow.xcodeproj \
  -scheme NookFlow \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES \
  build | tail -n 8

APP="$BUILD_DIR/Build/Products/Release/NookFlow.app"
if [ ! -d "$APP" ]; then
  echo "Erreur : $APP introuvable, la compilation a échoué." >&2
  exit 1
fi

echo "→ Arrêt de NookFlow s'il tourne"
pkill -x NookFlow 2>/dev/null || true
sleep 1

echo "→ Installation dans /Applications"
rm -rf /Applications/NookFlow.app
cp -R "$APP" /Applications/NookFlow.app

echo "→ Lancement"
open /Applications/NookFlow.app
echo "Terminé. Active « Lancer à l'ouverture de session » dans les préférences si tu le souhaites."
