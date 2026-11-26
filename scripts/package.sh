#!/bin/bash
# Fabrique un NookFlow.zip à partager (app universelle Apple Silicon + Intel, signature ad hoc).
# Usage : ./scripts/package.sh [version]     ex. ./scripts/package.sh 1.0
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-1.0}"
BUILD_DIR="$HOME/Library/Caches/NookFlowBuild-release"
OUT="dist"
rm -rf "$BUILD_DIR" "$OUT"
mkdir -p "$OUT"

xcodegen generate
xcodebuild \
  -project NookFlow.xcodeproj -scheme NookFlow -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$BUILD_DIR" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=YES \
  MARKETING_VERSION="$VERSION" \
  build | tail -n 5

APP="$BUILD_DIR/Build/Products/Release/NookFlow.app"
[ -d "$APP" ] || { echo "Compilation échouée." >&2; exit 1; }

# ditto conserve correctement les signatures et les liens (zip classique : à éviter).
ditto -c -k --keepParent "$APP" "$OUT/NookFlow-$VERSION.zip"
echo "Archive prête : $OUT/NookFlow-$VERSION.zip"
