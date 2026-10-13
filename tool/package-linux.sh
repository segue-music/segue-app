#!/bin/sh
# Builds the Linux version with tool/flutter.sh and packs it as build/segue-linux-x64.tar.gz, to run
# on another computer without Flutter. That computer needs glibc 2.38 or newer, GTK 3, libsecret
# and libmpv (libmpv.so.2 is enough: mpv-libs on Fedora, libmpv2 on Debian).
set -e
cd "$(dirname "$0")/.."
# The build number counts the commits (tool/build-number.sh), as on Android and iOS, and the settings show it beside the
# version.
tool/flutter.sh build linux --release --build-number="$(tool/build-number.sh)"
# A debug build (flutter run) leaves its Dart code, kernel_blob.bin, in build/flutter_assets, which the release build
# shares and copies whole into the bundle: over 100 MB the release doesn't read, its code being compiled
# (lib/libapp.so).
rm -f build/linux/x64/release/bundle/data/flutter_assets/kernel_blob.bin
tar -C build/linux/x64/release -czf build/segue-linux-x64.tar.gz --transform 's,^bundle,segue,' bundle
echo "$(pwd)/build/segue-linux-x64.tar.gz"
