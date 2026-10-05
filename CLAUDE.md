# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

The Segue app: a Flutter music player for Navidrome, other OpenSubsonic servers and Jellyfin, and
the first real client of Segue, a draft "Connect" protocol.
The protocol (`SPEC.md`) and its reference hub, in Go, are in another repository,
`github.com/segue-music/segue`, usually cloned next to this one as `../segue`.

`lib/segue/` is the protocol's Dart side. Where it and `SPEC.md` disagree, one of them has a bug,
so a protocol change touches `SPEC.md` and the hub (in segue) and `lib/segue/` (here) together, in
a commit in each repository. Code comments cite the spec by section ("SPEC.md, section 4").

The app lived in segue's `app/` until 2026-10-05; its history came along.

## Commands

Flutter 3.47 runs from a Docker image through `tool/flutter.sh` (as the current user, this folder
mounted), so nothing needs installing. Build the image once:

```sh
docker build -t segue-flutter-dev -f tool/dev.Dockerfile tool
tool/flutter.sh pub get
tool/flutter.sh analyze
DART=1 tool/flutter.sh format lib test        # page width 120 (analysis_options.yaml)
tool/flutter.sh test
tool/flutter.sh test test/player_test.dart    # one file
tool/flutter.sh test --plain-name 'a refused hello is a final HubClosed'
tool/package-linux.sh                         # release build → build/segue-linux-x64.tar.gz
DART=1 tool/flutter.sh run tool/icons.dart    # every icon (Android, TV banner, Linux, iOS, macOS) from tool/icon.png
```

The Android build (phones and Android TV) uses a second image, with the JDK and Android SDK/NDK:

```sh
docker build -t segue-flutter-android -f tool/android.Dockerfile tool
tool/package-android.sh                       # → build/segue-android.apk (debug-signed, every ABI)
```

The iOS build needs a Mac, so it runs on Codemagic (`codemagic.yaml`), which signs it and uploads
it to TestFlight. It starts from Codemagic's page or with a tag: `git tag ios-<n> && git push origin
ios-<n>`. Nothing iOS-specific can run here: `Info.plist` and the Xcode project are only checked by
that build.

Both builds number themselves with `tool/build-number.sh`: the commit count, plus the commits the
segue repository had without the app when it moved out, so that build numbers keep rising for
TestFlight and Android.

With Flutter installed locally, the same commands work as `flutter ...` (`flutter run -d linux`).

Test prerequisites:
- `test/hub_test.dart` runs the app's client and `ConnectController` against the real Go hub
  binary: `SEGUE_HUB_BIN`, or `../segue/hub/segue-hub` (a clone of segue next to this one). Build
  it there first (`go build -o segue-hub ./cmd/segue-hub` in `hub/`, or that repository's Docker
  command). Without it these tests are skipped, so check they ran. `tool/flutter.sh` mounts the
  binary into the container. The tests start the hub with `SEGUE_AUTH=none` and find its port by
  parsing its log line `msg="hub listening" url=http://...`; changing that line in the hub breaks
  them.
- `test/media_kit_engine_test.dart` uses the real libmpv with audio output disabled. The dev image
  has libmpv; elsewhere these tests are skipped.

Running two app instances on one machine as different devices:
`env SEGUE_DEVICE_ID=second SEGUE_DEVICE_NAME="Second copy" segue/segue`.

## Architecture

- `services.dart`: `Services.start` wires one signed-in session: `MediaServer` →
  `PlayerController` → `ConnectController`, plus a `SegueClient` if a hub was discovered (otherwise
  the app only plays locally). `ServicesScope` hands this down the tree. It sits in
  `MaterialApp.builder` (`app.dart`), above the navigator, so pages, sheets and the keyboard
  shortcuts all see it.
- `PlayerController` (`lib/player/`) is this device's player over an `AudioEngine` interface.
  `MediaKitEngine` (libmpv) is the real engine; `test/fakes.dart` has `FakeEngine` for tests.
  `MediaKitEngine` works around media_kit in a few places, each pinned by
  `media_kit_engine_test.dart` against the real libmpv. It tracks the current index itself, since
  media_kit's `state.playlist.index` briefly drops to 0 on every open. It keeps the position it
  commanded (seek, jump, open) until media_kit's catches up, so the report right after isn't stale.
  It reapplies shuffle after each open, since media_kit turns it off. It starts the current track
  over itself on a jump to it, which mpv ignores. And it reports when a track starts over on repeat. The play order (`order`) maps the shuffled playlist back to the songs.
- `ConnectController` (`lib/connect/`) follows the Connect model: the app controls one device at a
  time (`activeId`, null meaning this device). UI actions go through it (`playSongs`, `toggle`,
  `seek`, ...): it either runs them on the local player or sends them as hub commands. The UI should
  call `connect`, not `player`, for playback. It also follows whichever device starts playing, and
  restores the last playback on first connect. It links the player and the hub:
  `player.onReport → client.sendState` and `client.onCommand → player.obey`.
- `MediaServer` (`lib/server/server.dart`) is what pages, the player and the media controls ask of
  the media server, in either API: `SubsonicApi` (`lib/subsonic/`) or `JellyfinApi`
  (`lib/jellyfin/`). The user types only the address: `signIn` (`lib/server/sign_in.dart`) asks it
  which API it speaks (`detectApi`: a Subsonic ping, else Jellyfin's `System/Info/Public`), and
  `openServer` reopens a saved sign-in by its credentials. The API also gives the hub's hello its
  `api` and `auth`, so a Jellyfin sign-in is a Jellyfin device, with ids in Jellyfin's API.
- `lib/segue/`: protocol types, the client (reconnects with backoff; stops on final close codes
  4001/4002/4003) and hub discovery (`/connect/v1/info` next to the server).
- `MediaControls` (`lib/player/media_controls.dart`) mirrors `connect.nowPlaying` to the system's
  media controls: Linux (MPRIS) and iOS (Now Playing, also CarPlay's) for now.
- `AudioInterruptions` (`lib/player/audio_interruptions.dart`), on iOS only, sets the audio session
  up for music and pauses the local player for calls (resuming after, when iOS says to) and when the
  car or headphones go away. libmpv knows of neither.
- `Session` keeps the token (Subsonic's, with its salt, or Jellyfin's access token) in secure
  storage and everything else in `shared_preferences`, with the API under `api` (none: a session
  saved before Jellyfin, so Subsonic). The password itself is never stored.
- Android TV: the remote drives the app through focus. `segueTheme` (`lib/ui/theme.dart`) gives
  focused buttons a ring and everything else a strong tint, and `FocusRing` draws a ring on tiles
  whose image hides the tint. `FocusRing` must keep the same widget tree with or without focus,
  since rebuilding the child would drop its focus as soon as it arrived. On a TV
  (`lib/television.dart`, asking `MainActivity.kt`), focus highlights are always on: Flutter starts
  Android in touch mode and ignores key events from virtual keyboards, which is what
  `adb shell input keyevent` sends. `TextFieldArrowShortcuts` lets up and down leave text fields.
- `MainActivity` extends audio_service's `AudioServiceActivity`, so the screen and the plugin share
  one Flutter engine. With a plain `FlutterActivity`, audio_service started an engine of its own,
  and with it a second, hidden copy of the app that connected to the hub as the same device. It
  also answers `lib/device.dart` (TV or not, the device's name in the system settings).

## Conventions

- The app's UI text is in Portuguese. Code, comments and `README.md` are in English. Error codes
  from the hub and players become Portuguese messages in `describeError` (`lib/ui/errors.dart`), so
  a new error string needs an entry there.
- Commit messages are in Portuguese: a short title and a body explaining the behaviour and why.
- `README.md` lists what the app does and what it doesn't do yet. Update it when a feature lands,
  and segue's `README.md` ("Next steps") when the feature was listed there.
- Dart layout: every `if`, `for` and `while` body is in braces, even a single `return` (the lints
  `curly_braces_in_flow_control_structures` and `always_put_control_body_on_new_line` enforce it).
  A statement with braces (`if`, `for`, `while`, `do`, `switch`, `try`, a local function) has a
  blank line before and after it, separating it from the statements around it, but not at the
  start or end of its block. A comment above the statement belongs to it, so the blank line goes
  above the comment. `dart format` keeps blank lines but never adds them, so this is by hand.
- Dart design follows Effective Dart's guidelines (https://dart.dev/effective-dart/design). The ones
  a lint can check are on in `analysis_options.yaml`; the rest (terms used consistently, no
  abbreviations, noun phrases for values, verbs for side effects, no `get` prefix, ...) are by hand.
  `avoid_positional_boolean_parameters` stays off: the guideline exempts setters, and a method like
  `setShuffle(true)` is one that can't be a setter, being async.
- No name ends in `_`: when the obvious one is taken, as by an import prefix (`http`), pick a fuller
  one (`httpClient`). A leading `_` is Dart's privacy, not style, and stays.
- Docs, comments and tests stay generic: no names from a particular setup (machine or device names,
  hostnames, server paths, the tooling of the server it is developed on). Use names like `laptop`,
  `phone`, `tv` and `music.example`.
