#!/bin/bash

git clone https://github.com/flutter/flutter.git --depth 1
export PATH="$PATH:`pwd`/flutter/bin"

flutter config --enable-web
flutter pub get
flutter build web --release

if [ -z "$GOOGLE_MAPS_BROWSER_API_KEY" ]; then
  echo "GOOGLE_MAPS_BROWSER_API_KEY is required for the web Maps JavaScript SDK" >&2
  exit 1
fi

sed -i "s/__GOOGLE_MAPS_BROWSER_API_KEY__/$GOOGLE_MAPS_BROWSER_API_KEY/g" build/web/index.html
