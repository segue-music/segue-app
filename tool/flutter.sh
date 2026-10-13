#!/bin/sh
# Runs flutter (or dart, with DART=1) from the dev image on this app, as the current user.
# Build the image first: docker build -t segue-flutter-dev -f tool/dev.Dockerfile tool
# SEGUE_FLUTTER_IMAGE picks another image: segue-flutter-android, for the Android build (flutter run
# takes it by itself).
set -e
app=$(cd "$(dirname "$0")/.." && pwd)
cache=${SEGUE_FLUTTER_CACHE:-$HOME/.cache/segue-flutter}
# The container keeps its own .dart_tool, in the cache: pub writes absolute paths there (/opt/flutter,
# /home/dev/.pub-cache), which would break the analyzer of an editor running on a Flutter installed
# here.
mkdir -p "$cache/dart_tool" "$app/.dart_tool"
tool=flutter
[ -n "$DART" ] && tool=dart
command=$1
image=${SEGUE_FLUTTER_IMAGE:-segue-flutter-dev}

# flutter run takes the Android image when it's built, so that it reaches Android devices as well as
# this desktop.
if [ -z "$SEGUE_FLUTTER_IMAGE" ] && [ "$tool $command" = "flutter run" ] \
  && docker image inspect segue-flutter-android > /dev/null 2>&1; then
  image=segue-flutter-android
fi

# The first device of this machine's adb server (adb devices) that is ready, whatever its serial.
android_device() {
  adb devices | awk 'NR > 1 && $2 == "device" { print $1; exit }'
}

# Whether the device [serial], or else the first of this machine's adb server, has booted: adb lists
# an emulator before Android has booted, which flutter run can't install on yet.
booted() {
  serial=${1:-$(android_device)}
  [ -n "$serial" ] && [ "$(adb -s "$serial" shell getprop sys.boot_completed 2> /dev/null | tr -d '\r')" = 1 ]
}

# Starts an emulator, the Android SDK's (ANDROID_HOME, or where Android Studio puts it) on SEGUE_AVD
# or the first of its virtual devices, and waits until it has booted: on the console port [port],
# where one is given, which names it in adb (emulator-<port>), or else the first one free. It is
# left running out of this terminal's reach (setsid), so that q or Ctrl+C in flutter run doesn't
# close it and the next run finds it.
start_emulator() {
  port=$1
  emulator=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}/emulator/emulator

  if [ ! -x "$emulator" ] && ! emulator=$(command -v emulator); then
    echo "tool/flutter.sh: no Android device in adb devices, and no emulator to start" >&2
    exit 1
  fi

  avd=${SEGUE_AVD:-$("$emulator" -list-avds | head -n 1)}

  if [ -z "$avd" ]; then
    echo "tool/flutter.sh: no Android device in adb devices, and no virtual device for the emulator" >&2
    exit 1
  fi

  echo "tool/flutter.sh: starting the emulator ($avd)" >&2
  log=$cache/emulator.log
  setsid "$emulator" -avd "$avd" ${port:+-port "$port"} > "$log" 2>&1 < /dev/null &
  emulator_process=$!

  until booted "${port:+emulator-$port}"; do
    if ! kill -0 "$emulator_process" 2> /dev/null; then
      echo "tool/flutter.sh: the emulator stopped (its output is in $log)" >&2
      exit 1
    fi

    sleep 1
  done
}

# flutter run -d android runs on the first device of this machine's adb server, starting an
# emulator when there is none; -d emulator-<port> on that emulator, starting it on that port where
# adb doesn't list it, and waiting for it where it is still booting.
if [ "$tool $command" = "flutter run" ]; then
  for arg do
    shift

    if [ "$previous" = -d ] && [ "$arg" = android ]; then
      arg=$(android_device)

      if [ -z "$arg" ]; then
        start_emulator
        arg=$(android_device)
      fi
    elif [ "$previous" = -d ] && [ "${arg#emulator-}" != "$arg" ]; then
      if ! adb devices | awk -v serial="$arg" 'NR > 1 && $1 == serial { found = 1 } END { exit !found }'; then
        start_emulator "${arg#emulator-}"
      fi

      until booted "$arg"; do
        sleep 1
      done
    fi

    set -- "$@" "$arg"
    previous=$arg
  done
fi

# What flutter run and build make gets the keys of the services the app asks, which aren't in git:
# keys.json, at the top of the app (beside tool/), where there is one (README.md, "Keys").
if [ "$tool" = flutter ] && { [ "$command" = run ] || [ "$command" = build ]; } && [ -f "$app/keys.json" ]; then
  set -- "$@" --dart-define-from-file=keys.json
fi

# SEGUE_FLUTTER_IMAGE=none runs the Flutter installed here, with no container: the release workflow's
# (.github/workflows/release.yml), on GitHub's machines, which have no room for the images.
if [ "$image" = none ]; then
  cd "$app"
  exec "$tool" "$@"
fi

set -- "$image" "$tool" "$@"
# The tests against the hub run its binary: SEGUE_HUB_BIN, or the one built in a clone of the segue
# repository next to this one.
hub=${SEGUE_HUB_BIN:-$app/../segue/hub/segue-hub}

if [ -f "$hub" ]; then
  hub=$(realpath "$hub")
  set -- -v "$hub:$hub:ro" -e SEGUE_HUB_BIN="$hub" "$@"
fi

# flutter run opens the app in this desktop: the container gets the terminal (for run's keys, r and
# q), the display (Wayland or X11), the GPU, the sound server (PipeWire's socket, which libmpv tries
# first, and PulseAudio's, which PipeWire also serves), the session bus (the keyring that keeps
# the token, the media controls) and the accessibility one. Only flutter run: the other commands run
# code from packages, which needs none of it. Android devices come from this machine's adb server
# (adb devices starts it), over the host network.
if [ "$tool $command" = "flutter run" ]; then
  [ -t 0 ] && set -- -t "$@"
  runtime=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
  set -- --tmpfs "$runtime:mode=0700,uid=$(id -u),gid=$(id -g)" -e XDG_RUNTIME_DIR="$runtime" "$@"

  if [ -n "$WAYLAND_DISPLAY" ]; then
    set -- -v "$runtime/$WAYLAND_DISPLAY:$runtime/$WAYLAND_DISPLAY" -e WAYLAND_DISPLAY="$WAYLAND_DISPLAY" "$@"
  fi

  if [ -n "$DISPLAY" ]; then
    set -- -v /tmp/.X11-unix:/tmp/.X11-unix:ro -e DISPLAY="$DISPLAY" "$@"
    [ -n "$XAUTHORITY" ] && set -- -v "$XAUTHORITY:$XAUTHORITY:ro" -e XAUTHORITY="$XAUTHORITY" "$@"
  fi

  # SYS_PTRACE lets Mesa call kcmp, which Docker's seccomp allows only with it, to tell whether two
  # of its GPU file descriptors share one open file ("amdgpu: os_same_file_description couldn't
  # determine..."). The app runs as the user, not root, so the capability itself doesn't reach it.
  for render in /dev/dri/renderD*; do
    [ -e "$render" ] && set -- --device /dev/dri --group-add "$(stat -c %g "$render")" --cap-add SYS_PTRACE "$@"
    break
  done

  [ -S "$runtime/pipewire-0" ] && set -- -v "$runtime/pipewire-0:$runtime/pipewire-0" "$@"

  # PULSE_SERVER names the socket: otherwise libpulse looks for it in $runtime/pulse only once it has
  # made sure it owns that folder, which Docker made, as root, to mount the socket in, so it never
  # tried the socket and mpv fell back to ALSA, which has no sound card here.
  if [ -S "$runtime/pulse/native" ]; then
    set -- -v "$runtime/pulse/native:$runtime/pulse/native" -e PULSE_SERVER="unix:$runtime/pulse/native" "$@"
  fi

  # The links the app opens (where an artist comes from, on a map) go through this desktop's portal,
  # on that bus, which opens them in its browser: the container has none to open them with. GTK reads
  # GTK_USE_PORTAL, GLib GIO_USE_PORTALS.
  if [ -S "$runtime/bus" ]; then
    set -- -v "$runtime/bus:$runtime/bus" -e DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime/bus" \
      -e GTK_USE_PORTAL=1 -e GIO_USE_PORTALS=1 "$@"
  fi

  # The media controls hand the desktop the cover as a file, in /tmp/segue-covers
  # (lib/player/media_controls.dart): the desktop reads it from this machine's /tmp, not the
  # container's, so that folder is this machine's.
  mkdir -p /tmp/segue-covers
  set -- -v /tmp/segue-covers:/tmp/segue-covers "$@"

  [ -S "$runtime/at-spi/bus" ] && set -- -v "$runtime/at-spi/bus:$runtime/at-spi/bus" "$@"

  # The app shows this desktop's language, which Flutter reads from the first of LANGUAGE, LC_ALL,
  # LC_MESSAGES and LANG that is set (GLib's g_get_language_names): without any, it showed English.
  # The container gets it as LANGUAGE alone, which needs no locale installed: it has only C, and
  # with LANG set to another, GTK warned and fell back to C as the app started.
  language=${LANGUAGE:-${LC_ALL:-${LC_MESSAGES:-$LANG}}}
  [ -n "$language" ] && set -- -e LANGUAGE="$language" "$@"
fi

exec docker run --rm -i --user "$(id -u):$(id -g)" --network host \
  -v "$app:$app" -v "$cache/dart_tool:$app/.dart_tool" -v "$cache:/home/dev" -w "$app" \
  -e HOME=/home/dev -e PUB_CACHE=/home/dev/.pub-cache "$@"
