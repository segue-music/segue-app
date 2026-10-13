#!/bin/sh
# Builds the Android version (phones and Android TV) with tool/flutter.sh on the Android image, as
# build/segue-android.apk: one APK for every ABI, to install by hand (adb install), signed with the app's key where
# android/key.properties names it (README.md, "Releases"), else with a debug key. Build the image first:
# docker build -t segue-flutter-android -f tool/android.Dockerfile tool
set -e
cd "$(dirname "$0")/.."
# The version code counts the commits (tool/build-number.sh), so each build goes up: Android refuses
# an update with a lower one, and launchers keep the icon they have of an app until its version code
# changes.
SEGUE_FLUTTER_IMAGE=${SEGUE_FLUTTER_IMAGE:-segue-flutter-android} tool/flutter.sh build apk --release \
  --build-number="$(tool/build-number.sh)"
cp build/app/outputs/flutter-apk/app-release.apk build/segue-android.apk
echo "$(pwd)/build/segue-android.apk"
