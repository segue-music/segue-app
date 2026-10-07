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

# flutter run -d android runs on the first device of this machine's adb server (adb devices),
# whatever its serial.
if [ "$tool $command" = "flutter run" ]; then
  for arg do
    shift

    if [ "$previous" = -d ] && [ "$arg" = android ]; then
      arg=$(adb devices | awk 'NR > 1 && $2 == "device" { print $1; exit }')

      if [ -z "$arg" ]; then
        echo "tool/flutter.sh: no Android device in adb devices" >&2
        exit 1
      fi
    fi

    set -- "$@" "$arg"
    previous=$arg
  done
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

  if [ -S "$runtime/bus" ]; then
    set -- -v "$runtime/bus:$runtime/bus" -e DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime/bus" "$@"
  fi

  [ -S "$runtime/at-spi/bus" ] && set -- -v "$runtime/at-spi/bus:$runtime/at-spi/bus" "$@"
fi

exec docker run --rm -i --user "$(id -u):$(id -g)" --network host \
  -v "$app:$app" -v "$cache/dart_tool:$app/.dart_tool" -v "$cache:/home/dev" -w "$app" \
  -e HOME=/home/dev -e PUB_CACHE=/home/dev/.pub-cache "$@"
