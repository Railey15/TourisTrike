#!/bin/bash

git clone https://github.com/flutter/flutter.git --depth 1
export PATH="$PATH:`pwd`/flutter/bin"

flutter config --enable-web
flutter pub get

if [ -z "$GOOGLE_MAPS_BROWSER_API_KEY" ]; then
  echo "GOOGLE_MAPS_BROWSER_API_KEY is required for the web Maps JavaScript SDK" >&2
  exit 1
fi

flutter build web --release

printf "window.tourisTrikeConfig = { googleMapsBrowserApiKey: '%s' };\n" \
  "$GOOGLE_MAPS_BROWSER_API_KEY" > build/web/google_maps_config.js
