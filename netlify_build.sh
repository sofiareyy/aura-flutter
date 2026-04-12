#!/bin/bash
set -e

FLUTTER_VERSION=${FLUTTER_VERSION:-3.27.4}
FLUTTER_DIR="$HOME/flutter"

echo "→ Instalando Flutter $FLUTTER_VERSION..."
if [ ! -d "$FLUTTER_DIR" ]; then
  git clone https://github.com/flutter/flutter.git \
    -b "$FLUTTER_VERSION" --depth 1 "$FLUTTER_DIR"
fi

export PATH="$PATH:$FLUTTER_DIR/bin"
flutter config --no-analytics
flutter precache --web

echo "→ Obteniendo dependencias..."
flutter pub get

echo "→ Building Flutter web..."
flutter build web --release --web-renderer html

echo "→ Copiando _redirects..."
cp web/_redirects build/web/_redirects

echo "✓ Build terminado"
