#!/bin/sh
# Runs flutter (or dart, with DART=1) from the dev image on this app, as the current user.
# Build the image first: docker build -t segue-flutter-dev -f tool/dev.Dockerfile tool
# SEGUE_FLUTTER_IMAGE picks another image: segue-flutter-android, for the Android build.
set -e
app=$(cd "$(dirname "$0")/.." && pwd)
cache=${SEGUE_FLUTTER_CACHE:-$HOME/.cache/segue-flutter}
# The container keeps its own .dart_tool, in the cache: pub writes absolute paths there (/opt/flutter,
# /home/dev/.pub-cache), which would break the analyzer of an editor running on a Flutter installed
# here.
mkdir -p "$cache/dart_tool" "$app/.dart_tool"
tool=flutter
[ -n "$DART" ] && tool=dart
set -- "${SEGUE_FLUTTER_IMAGE:-segue-flutter-dev}" "$tool" "$@"
# The tests against the hub run its binary: SEGUE_HUB_BIN, or the one built in a clone of the segue
# repository next to this one.
hub=${SEGUE_HUB_BIN:-$app/../segue/hub/segue-hub}

if [ -f "$hub" ]; then
  hub=$(realpath "$hub")
  set -- -v "$hub:$hub:ro" -e SEGUE_HUB_BIN="$hub" "$@"
fi

exec docker run --rm -i --user "$(id -u):$(id -g)" --network host \
  -v "$app:$app" -v "$cache/dart_tool:$app/.dart_tool" -v "$cache:/home/dev" -w "$app" \
  -e HOME=/home/dev -e PUB_CACHE=/home/dev/.pub-cache "$@"
