#!/bin/sh
# Builds congruitas.app (menu bar only, no Dock icon) next to this script, via the Xcode project.
set -e
cd "$(dirname "$0")"
xcodebuild -project congruitas.xcodeproj -scheme congruitas -configuration Release \
  -destination 'platform=macOS' -derivedDataPath .build/xcode -quiet build
rm -rf congruitas.app
cp -R .build/xcode/Build/Products/Release/congruitas.app .
echo "Built $(pwd)/congruitas.app"
