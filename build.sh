#!/bin/bash

git clone https://github.com/flutter/flutter.git --depth 1
export PATH="$PATH:`pwd`/flutter/bin"

flutter config --enable-web
flutter pub get
flutter build web --release