#!/bin/bash
set -euo pipefail
trap 'echo "Build failed at line $LINENO; deployment stopped." >&2' ERR

cd "$(dirname "${BASH_SOURCE[0]}")"

node tool/configure_web_maps.cjs --check-env

# Match the stable SDK used and verified locally (Dart 3.12.2).
# Cloning the default branch at depth 1 can omit release tags and report
# 0.0.0-unknown. A fresh directory also avoids a stale Vercel SDK cache.
FLUTTER_VERSION="3.44.8"
FLUTTER_SDK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/touristrike-flutter.XXXXXX")"
git clone --depth 1 --single-branch --branch "$FLUTTER_VERSION" \
  https://github.com/flutter/flutter.git "$FLUTTER_SDK_DIR"
git -C "$FLUTTER_SDK_DIR" checkout -b stable
export PATH="$FLUTTER_SDK_DIR/bin:$PATH"

flutter --version
flutter --version --machine > "$FLUTTER_SDK_DIR/verified-version.json"
node - "$FLUTTER_SDK_DIR/verified-version.json" "$FLUTTER_VERSION" <<'NODE'
const version = JSON.parse(require('node:fs').readFileSync(process.argv[2], 'utf8'));
if (version.frameworkVersion !== process.argv[3] || version.channel !== 'stable') {
  console.error('Flutter SDK does not match the pinned stable release.');
  process.exit(1);
}
NODE

flutter config --enable-web
flutter pub get
flutter build web --release --no-pub

if [[ ! -d build/web || ! -s build/web/index.html || ! -s build/web/flutter_bootstrap.js ]]; then
  echo "Flutter did not produce a complete build/web output; Maps injection skipped." >&2
  exit 1
fi

# This project injects the key and its verification fingerprint into index.html;
# no separate google_maps_config.js file is used by web/index.html.
node tool/configure_web_maps.cjs
echo "Build complete: build/web (Maps browser configuration verified)."
