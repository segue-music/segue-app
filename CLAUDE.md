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
tool/flutter.sh gen-l10n                      # the app's words, after editing lib/l10n's ARB files
DART=1 tool/flutter.sh format lib test        # page width 120 (analysis_options.yaml)
tool/flutter.sh test
tool/flutter.sh test test/player_test.dart    # one file
tool/flutter.sh test --plain-name 'a refused hello is a final HubClosed'
tool/flutter.sh run -d linux                  # the app in this desktop (display, GPU, sound, session bus, language)
tool/package-linux.sh                         # release build → build/segue-linux-x64.tar.gz
DART=1 tool/flutter.sh run tool/icons.dart    # every icon (Android, TV banner, Linux, iOS, macOS, Windows) from tool/icon.png
```

The Android build (phones and Android TV) uses a second image, with the JDK and Android SDK/NDK:

```sh
docker build -t segue-flutter-android -f tool/android.Dockerfile tool
tool/package-android.sh                       # → build/segue-android.apk (debug-signed, every ABI)
tool/flutter.sh run -d android                # the first device of the host's adb server (phone, TV, emulator),
                                              # or the SDK's emulator, which it starts (SEGUE_AVD, or the first AVD)
```

Once this image is built, `tool/flutter.sh run` takes it, to reach the host's Android devices as well
as its desktop.

The iOS build needs a Mac, so it runs on Codemagic (`codemagic.yaml`), which signs it and uploads
it to TestFlight. It starts from Codemagic's page or with a tag: `git tag ios-<n> && git push origin
ios-<n>`. Nothing iOS-specific can run here: `Info.plist` and the Xcode project are only checked by
that build.

Both builds number themselves with `tool/build-number.sh`: the commit count, plus the commits the
segue repository had without the app when it moved out, so that build numbers keep rising for
TestFlight and Android.

With Flutter installed locally, the same commands work as `flutter ...` (`flutter run -d linux`).
The container keeps its own `.dart_tool` (in `~/.cache/segue-flutter/dart_tool`), whose paths are
the container's, so it doesn't break the analyzer of an editor that uses the local Flutter.

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

The tests read the app in Portuguese: a test's own `MaterialApp` takes
`localizationsDelegates: AppLocalizations.localizationsDelegates` and
`supportedLocales: const [Locale('pt')]`, and one of the whole `SegueApp` sets the system's language
(`tester.platformDispatcher.localesTestValue`). `languages_test.dart` goes through the pages in the
other languages, where a text too long for its room fails.

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
  over itself on a jump to it, which mpv ignores. It reports when a track starts over on repeat. It
  stops on a track that fails to load (`failed`), paused where it was, where mpv would move on to the
  next and, with a media server that fails them all, through the whole queue in a moment; mpv's log
  tells which track failed, since its events can announce the next one first. Opened paused (the
  last playback, as the app opens), it loads the track all the same, so that play starts at once, but
  keeps a failure then quiet (`failed` stays false) until play or a jump: play tries the track again,
  and only a failure that follows is told. It tries a track again with mpv's `playlist-play-index`:
  right after the failure mpv may still be on it, in its youtube-dl hook, and ignores a write of
  `playlist-pos` to it. Until a track it opened paused, or at a position, has
  loaded, it holds a seek, play and pause for when it has, since mpv can't seek before. The play order
  (`order`) maps the shuffled playlist back to the songs. mpv's playlist names the tracks
  (`segue://track/<open>/<track>`) rather than holding their streams: as mpv loads one, its on_load hook asks the
  track for its stream (`TrackSource`), so that a new quality holds from the next song, and a stream that can't seek
  (one a Subsonic server transcodes as it goes) seeks by loading its track again from that point (`timeOffset`), the
  engine adding where the stream starts to mpv's positions. That a track has loaded it learns by asking mpv for its
  duration after each "Playing:" in the log: mpv's own notice says nothing for a track as long as the one before.
  Until then the position stays where the track is to start, and a seek waits for it.
- `ConnectController` (`lib/connect/`) follows the Connect model: the app controls one device at a
  time (`activeId`, null meaning this device). UI actions go through it (`playSongs`, `toggle`,
  `seek`, ...): it either runs them on the local player or sends them as hub commands. The UI should
  call `connect`, not `player`, for playback. It also follows whichever device starts playing, and
  restores the last playback on first connect. It links the player and the hub:
  `player.onReport → client.sendState` and `client.onCommand → player.obey`.
- On a wide screen, `HomePage` keeps its bars (the top one, the side rail, the player's) and opens
  pages between them, in a nested navigator, the page area (`lib/ui/page_area.dart`), whose
  `PageHistory` the top bar's arrows and the keyboard's left and right go back and forward through.
  From outside it (the player bar), pages open with `PageArea.navigatorOf(context)`, not
  `Navigator.of`; the full-screen cover and the sheets open in the app's navigator, over the window.
  A navigator's pages keep the arrows in them, so the page area's lets them on from a page's edges
  to the bars (`routeDirectionalTraversalEdgeBehavior`). The bars' scope holds every page, the
  hidden ones too, so `TopPageTraversal` leaves those under the top one out of the traversal (not
  out of the focus, which would forget where it was in them), and the sections not shown are out
  of the focus (`Visibility`).
- On a phone the page area is there too, the same navigator (by its key, so pages stay open as the
  window changes width), between the top of the screen and the bars at the bottom (the player's and
  the sections'), which stay. It isn't under a top bar (`PageArea.underTopBar`), so its pages keep
  their own, with the back arrow (`PageArea.holdsUnderTopBar`). The full-screen player and the
  queue open in the app's navigator there, over everything (`PageArea.playerNavigatorOf`); the
  player takes the area along (`PlayerRoute.area`), so its links close it and open their page in
  the area. A page in the area has no player bar of its own (`PageArea.holds`): even an empty one
  would take away the room the home's bars leave at the bottom (`extendBody`, `MediaQuery`).
- `MediaServer` (`lib/server/server.dart`) is what pages, the player and the media controls ask of
  the media server, in either API: `SubsonicApi` (`lib/subsonic/`) or `JellyfinApi`
  (`lib/jellyfin/`). The user types only the address: `signIn` (`lib/server/sign_in.dart`) asks it
  which API it speaks (`detectApi`: a Subsonic ping, else Jellyfin's `System/Info/Public`), and
  `openServer` reopens a saved sign-in by its credentials. The API also gives the hub's hello its
  `api` and `auth`, so a Jellyfin sign-in is a Jellyfin device, with ids in Jellyfin's API. A song
  streams as its file, or within a bitrate (`QualityChoice`, `lib/quality_choice.dart`, which
  `PlayerController` reads as each song loads, the automatic one by `MobileData`, `lib/mobile_data.dart`, from
  connectivity_plus): Subsonic's `maxBitRate`, with `timeOffset` to start later where the server has OpenSubsonic's
  transcodeOffset, or Jellyfin's `universal`, as HLS.
- `lib/lyrics/lrclib.dart`: LRCLIB, where the full-screen player's lyrics (`LyricsView`) come from
  when the media server has none, by the song's title, artist, album and length. `Services.start`
  gives it one; tests leave `Services.lrclib` null, so that none goes out to the internet.
- `lib/releases/musicbrainz.dart`: MusicBrainz, where the album page's release date, record labels and
  type (album, EP, single, compilation) come from when the media server doesn't say them: by the
  album's MusicBrainz id (its release), or, for the date and the type only, by its name, artist and
  year (its release group). It sends a request a second at
  most, as MusicBrainz asks, and remembers what it found for the session. `Services.start` gives it
  one; tests leave `Services.musicBrainz` null, so that none goes out to the internet.
- `lib/segue/`: protocol types, the client (reconnects with backoff; stops on final close codes
  4001/4002/4003) and hub discovery (`/connect/v1/info` next to the server).
- `MediaControls` (`lib/player/media_controls.dart`) mirrors `connect.nowPlaying` to the system's
  media controls: Linux (MPRIS) and iOS (Now Playing, also CarPlay's) for now.
- `PlayCounter` (`lib/player/play_counter.dart`) counts the songs this device's player plays toward
  the user's most played (`MediaServer.scrobble`; a no-op on Jellyfin, where the hub's
  `Sessions/Playing` counts them). Only `Services.start` makes one: widget tests that build
  `Services` themselves have none, since its timer would outlive them. Its tests run in fake time
  (`fake_async`), which is why it and `FakeEngine` read the time from `clock`.
- `AudioInterruptions` (`lib/player/audio_interruptions.dart`), on iOS only, sets the audio session
  up for music and pauses the local player for calls (resuming after, when iOS says to) and when the
  car or headphones go away. libmpv knows of neither.
- The app's words are in `lib/l10n/`'s ARB files, one per language (Portuguese, English, Spanish),
  from which gen-l10n makes `AppLocalizations` (`l10n.yaml`). `LanguageChoice`
  (`lib/language_choice.dart`) is the language shown: the system's, of those the app has the first
  it prefers and English when it has none, until a menu (`LanguageButton`, in the top bar and in the
  sign-in's corner) picks one, which the preferences keep, as `ThemeChoice` does the theme. Where no
  `BuildContext` reaches, the words come in: `describeError` takes them, and `MediaControls` gets
  them from a widget under `MaterialApp` (`app.dart`), again as the language changes.
- `Session` keeps the token (Subsonic's, with its salt, or Jellyfin's access token) in secure
  storage and everything else in `shared_preferences`, with the API under `api` (none: a session
  saved before Jellyfin, so Subsonic). The password itself is never stored.
- Android TV: the remote drives the app through focus. `segueTheme` (`lib/ui/theme.dart`) gives
  focused buttons a ring and everything else a strong tint, and `FocusRing` draws a ring on tiles
  whose image hides the tint. `FocusRing` must keep the same widget tree with or without focus,
  since rebuilding the child would drop its focus as soon as it arrived. On a TV
  (`lib/television.dart`, asking `MainActivity.kt`), focus highlights are always on: Flutter starts
  Android in touch mode and ignores key events from virtual keyboards, which is what
  `adb shell input keyevent` sends. `TextFieldArrowShortcuts` lets up and down leave text fields
  (on a TV, left and right too). A text field opens the keyboard as the focus comes to it, and on a
  TV the keyboard covers half the screen and takes the D-pad, so there the home's search bar stays
  read-only until the center button (its `onTap`) opens it.
- `MainActivity` extends audio_service's `AudioServiceActivity`, so the screen and the plugin share
  one Flutter engine. With a plain `FlutterActivity`, audio_service started an engine of its own,
  and with it a second, hidden copy of the app that connected to the hub as the same device. It
  also answers `lib/device.dart` (TV or not, the device's name in the system settings).

## Conventions

- The app's UI text is in `lib/l10n/`'s ARB files, never a literal in the code: a widget takes it
  from `AppLocalizations.of(context)` (a local `strings`). A new text is a message in all three,
  `app_pt.arb` (the template, with its description and its placeholders), `app_en.arb` and
  `app_es.arb`; `l10n_test.dart` fails on one missing. A sentence whose words change with a number
  or a kind is one message, with a `plural` or a `select` (`albumCount`, `playRelease`), not pieces
  put together. The Dart code (`lib/l10n/app_localizations*.dart`, not in git) comes from the ARB
  files on `pub get` and on every build, but not on `test` or `analyze`: after editing one,
  `tool/flutter.sh gen-l10n`. Code, comments and `README.md` are in English. Error codes from the
  hub and players become messages in `describeError` (`lib/ui/errors.dart`), so a new error string
  needs an entry there.
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
- Icons come from Hugeicons (`ThemedIcon(HugeIcons.strokeRounded...)`, `lib/ui/themed_icon.dart`),
  which draws them as SVG paths, and never through its own `HugeIcon`: that one is 24 pixels
  whatever the `IconTheme` says, so an icon button's `iconSize` or a navigation bar's theme would
  miss it. No Material icon is left, and `test/icons_test.dart` keeps it so; the back arrow Flutter
  adds to a page comes from the theme (`actionIconTheme`).
- The Linux build renders with Skia, not Impeller (`linux/runner/my_application.cc`): Flutter
  3.47's Impeller, on OpenGL, clips without antialiasing, so the round edges of covers and artists'
  pictures came out jagged, and it left the icons' thin strokes jagged too. On each Flutter update
  (`tool/dev.Dockerfile`, `codemagic.yaml`), check that Linux still has Skia, and try Impeller
  again: without that line, look at a cover's edges and at the icons in a Linux desktop session.
- On a computer the pointer is a hand over what can be clicked, which Flutter leaves to the web: the
  theme (`segueTheme`) gives it to buttons, list tiles and menus' items, and an `InkWell`, which no
  theme reaches, takes `mouseCursor: WidgetStateMouseCursor.clickable`. `test/cursor_test.dart` goes
  over them.
- No name ends in `_`: when the obvious one is taken, as by an import prefix (`http`), pick a fuller
  one (`httpClient`). A leading `_` is Dart's privacy, not style, and stays.
- Docs, comments and tests stay generic: no names from a particular setup (machine or device names,
  hostnames, server paths, the tooling of the server it is developed on). Use names like `laptop`,
  `phone`, `tv` and `music.example`.
