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
DART=1 tool/flutter.sh run tool/icons.dart    # every icon (Android, TV banner, notification, Linux, iOS, macOS, Windows) from tool/icon.png
tool/flutter.sh test tool/screenshots.dart    # the README's pictures (docs/screenshots), of a made-up library
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

The Linux, Android and Windows packages are also built on GitHub's machines (`.github/workflows/release.yml`), and,
for a tag `v<version>` (pubspec's version), put in a release: `git tag v<version> && git push origin v<version>`.
There `tool/flutter.sh` runs the Flutter installed (`SEGUE_FLUTTER_IMAGE=none`), the images not fitting, and the keys
come from the repository's secrets. The APK is signed with the app's key (`android/key.properties` naming
`android/release.jks`, which git ignores; README.md, "Releases"), every build where it is, so that `flutter run`
installs over a released APK instead of uninstalling it.

The builds (iOS, Android, Linux's and Windows's packages) number themselves with `tool/build-number.sh`: the commit
count, plus the commits the segue repository had without the app when it moved out, so that build
numbers keep rising for TestFlight and Android. The settings show it beside the version
(`package_info_plus`); `flutter run` doesn't take one, so there it is pubspec's, 1.

With Flutter installed locally, the same commands work as `flutter ...` (`flutter run -d linux`).
The container keeps its own `.dart_tool` (in `~/.cache/segue-flutter/dart_tool`), whose paths are
the container's, so it doesn't break the analyzer of an editor that uses the local Flutter.

The Windows build has no image: it takes Flutter installed on Windows, with Visual Studio's C++ desktop workload and
Developer Mode on (the plugins are symlinks), then `flutter run -d windows`, `keys.json` by hand
(`--dart-define-from-file=keys.json`). `tool\package-windows.ps1` (PowerShell) builds the release, with `keys.json`,
and packs it as `build\segue-windows-x64.zip`, Visual C++'s runtime beside the app, so that it runs on a Windows
without Visual C++'s redistributable. There, in debug only, the app may crash as it starts (0xC0000005, after
"media_kit: NativeReferenceHolder: Located"): media_kit keeps a file in the temporary folder for each process id and
never deletes it, and Windows gives an id again, whose file then points at another process's memory. Deleting
`%TEMP%\com.alexmercerind.media_kit.NativeReferenceHolder.*` clears it.

The keys of the services the app asks (fanart.tv's, `FANART_TV_KEY`) aren't in git: `tool/flutter.sh`
gives `run` and `build` the `keys.json` at the top of this folder (`--dart-define-from-file`), which
git ignores, and Codemagic its environment variables' group `keys`. A build without them runs without
those services (README.md, "Keys").

The tests are two suites, run apart: the code's, `tool/flutter.sh test` (everything in `test/`), and the README's
pictures', `tool/flutter.sh test tool/screenshots.dart`, which makes them again in `docs/screenshots/` (`git status
docs/` then says whether they changed). Each change runs what it needs, the whole suite being slow: while it is made,
only the test files of what it touches, and before a push the suite of what the commits touch, the code's for the app's
code, its tests, its platforms' code or its dependencies, the pictures' for their generator, the pictures themselves or
the UI they show (`lib/ui/`, the theme, the app's words), both for both, and neither for the README's text, the
Dockerfiles or other docs alone. A change of the UI that changes the pictures has them looked at, that they show it as
they should, and they go with it.

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
  shortcuts all see it. A window closed on a computer disposes them before Flutter ends the app (`_exit`, through
  `AppLifecycleListener.onExitRequested`), the player before the hub's connection, whose close can wait on the network:
  ended with mpv still playing, the process aborted, often, mpv calling media_kit's wakeup callback after the Dart that
  it called had gone ("Callback invoked after it has been deleted").
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
  (`order`) maps the shuffled playlist back to the songs. mpv's playlist names each track by its stream's address as
  it was opened, with the track's own id (`<open>.<track>`) last in its query (`segueTrack`), or, for a file, by the
  id alone (`segue://track/<open>.<track>`): as mpv loads one, its on_load hook asks the track for its stream
  (`TrackSource`), so that a new quality holds from the next song, and a stream that can't seek (one a Subsonic server
  transcodes as it goes) seeks by loading its track again from that point (`timeOffset`), the engine adding where the
  stream starts to mpv's positions. mpv opens the next track ahead as the one before plays (`prefetch-playlist`), so
  that it plays right after it, with no gap (gapless), however late the media server answers: it opens the track's
  name, before the hook, which is why the name is the stream. As a track loads, the engine has mpv open the next one
  ahead only where its name is still its stream (not a file, nor a stream of the quality before), and names one of
  another quality anew in its place (`_rename`). A stream that fails to open is the loading track's only where it is
  its name or the stream the hook gave it: another is the next one, opened ahead, which mpv tries again as it loads it.
  mpv can't drop a stream it opened ahead, so the next track changed after that (play next, a move) opens as it
  starts, as before. That a track has loaded it learns by asking mpv for its
  duration after each "Playing:" in the log: mpv's own notice says nothing for a track as long as the one before.
  Until then the position stays where the track is to start, and a seek waits for it. It adds tracks (`add`, play next
  or at the end) by appending them to mpv's playlist and moving them after the current one (`_rearrange`): media_kit
  tells of a move with the index from before, and mpv of the current track's new place only after, so while it moves
  them it knows the current track by its name, and after a move that takes a track over the current one it waits for
  mpv's word, which would otherwise come with a later playlist and name another track. mpv's unshuffle puts back only
  the tracks it shuffled, and the others anywhere, so turning shuffle off moves them where they go the same way. It
  moves a track (`move`) the same way, and takes one out (`remove`, never the current one) first from the tracks it
  has, so that what mpv says of the playlist with it isn't taken for the queue now, waiting, where it was before the
  current one, for mpv's word of the current track's new place. `PlayerController` makes the changes to the queue
  (adding, moving, removing) one after another, and holds the engine's changes until each is done: until then its
  songs aren't where the engine has them, and a report would send the current track's new place with the queue as it
  was. The
  on_load hook also plays the track with its gain (`TrackGain`, ReplayGain): the file's tags, through mpv's
  `replaygain` (and `replaygain-preamp`), or a gain in dB, which goes in `replaygain-fallback` with `replaygain` off:
  mpv then applies it to every track, as a volume of its own (`compute_replaygain` in its `player/audio.c`). `PlayerController` picks each song's
  (`ReplayGainChoice`, `lib/replay_gain_choice.dart`): the media server's gain, or, where it gives none, the file's
  tags, either 8 dB louder (`replayGainPreamp`) and capped by its peak.
  The equalizer (`setEqualizer`, from `EqualizerChoice`, `lib/equalizer_choice.dart`) is mpv's `af`: FFmpeg's
  `equalizer`, one for each of its ten bands, in a single lavfi graph. Of FFmpeg's filters, media_kit's libmpv for
  Android has only `equalizer` (no `aresample`, no `volume`; iOS's has no `volume`), so mpv's own `format` filter
  takes the audio to 48 kHz first (a band at half a track's sample rate, 16 kHz in one of 32 kHz, silences it in
  FFmpeg), and one more `equalizer`, at the head of the graph, lowers it by as much as the bands raise the loudest
  frequency: of a Q so small (0.0001) that its band takes in every frequency, it is a gain. One graph, since on
  Android (mpv 0.35, FFmpeg 6.0) a second lavfi filter after mpv's resampler fails every frame. Turning it on or
  off restarts the audio output, a moment of silence; moving a band makes the graph anew, but not the output.
  Autoplay (`AutoplayChoice`, `lib/autoplay_choice.dart`, on until turned off, `Services.autoplay`): as the queue's
  last song starts playing, repeat off, `PlayerController` asks the media server for songs like it
  (`MediaServer.similarSongs`: Subsonic's getSimilarSongs2 by the song's id, which Navidrome takes, else by its
  artist's; Jellyfin's `Items/{id}/InstantMix`), once for that song in that queue, and adds at the end up to
  `autoplaySize` of them the queue doesn't have, unless, as they come, the song is no longer last. Added before the
  queue ends, they play on from it. Turned off, it takes those that haven't played out of the queue (`_autoplayed`,
  the songs themselves, not their ids: the same song added otherwise stays), with one report, and turned on again on
  the same song asks again. It is each device's own setting, not the protocol's: the hub sees a longer queue, or a
  shorter one.
  The crossfade (`CrossfadeChoice`, `lib/crossfade_choice.dart`, off until a length is picked, `Services.crossfade`),
  each device's own too: while it is on, `PlayerController` plays on a `CrossfadeEngine`
  (`lib/player/crossfade_engine.dart`) rather than on the engine it was given, and as it goes on or off it opens the
  queue on the other engine where it was, in the same play order (`open`'s `order`), the one before stopped (or, the
  crossfade's, disposed); `songEnded` is the engine's in use. mpv plays one track at a time, so the `CrossfadeEngine`
  has two decks (`Deck`, each a `MediaKitEngine` of one track) and keeps the queue, its play order and repeat itself:
  a track plays on its deck to its end. 10 s before its turn the next one opens, paused, on the other deck, at level 0
  (`Deck.setLevel`: a part of the volume, which goes in mpv's by its cube root, mpv making its volume a gain by its
  cube; `volume` stays, and nothing is told of it). Within the crossfade's length of the end (`Deck.duration`, mpv's
  where it knows the length, a file or a stream that can seek, or else the media server's, `TrackSource.duration`),
  the next one starts and is the current track from then (`ended` fires), each deck's level following its own
  position at equal power, over half of either track at most. A jump, a seek or an open stops the track fading out;
  repeat one is the deck's own; a track whose length is unknown plays to its end, the next one starting then. No
  gapless there. Only the current deck's changes are the engine's.
- `SleepTimer` (`lib/player/sleep_timer.dart`, `Services.sleepTimer`, `SleepTimerButton`) pauses this device's
  player after a while, the music fading out over the last 30 s through `PlayerController.setVolume` (`keep: false`,
  so that the next launch doesn't open at a fade's volume; a volume the user picks meanwhile stays) and getting its
  volume back once paused, or as the song ends (`PlayerController.songEnded`,
  the engine's `ended`: the next track starting by itself, or its crossfade, the track starting over where it repeats
  by itself, or the last one ending, repeat off; media_kit tells `completed` at the end of every track, so only the last one's counts),
  the next one then paused at its start. A stopped player turns it off. It is each device's own, like autoplay: the
  protocol has no timer, so its button shows only while this device plays. Only `Services.start` makes one.
- The volume (`VolumeControl`, `lib/ui/player/volume_control.dart`, at the end of the wide player bar) shows only on a
  computer: a phone's and a TV's own buttons set the system's volume, and mpv's is a second one under it. A button, to
  save the bar's room, over which the slider, upright, opens in the overlay (`OverlayPortal`, growing up out of the
  button as it fades in) while the pointer is on either, a drag holds it or the button has the keyboard's focus,
  closing 300 ms after none does, time to go from one to the other. The button has no tooltip, which would cover the
  slider, only its words for a screen reader (`MergeSemantics`). It is the
  protocol's `setVolume`, so of whichever device the app controls (`ConnectController.setVolume`, `NowPlaying.volume`):
  this device's follows the slider as it moves, another device's takes a command as the slider stops, 300 ms after its
  last step (the drag let go, the wheel or the keyboard's arrows still), the slider holding the value until the device
  reports it. Muting sets
  0, and `ConnectController.unmute` gives back the volume the device had before it went to none, kept for each device
  (`from`: where a drag went down to none, the volume as it started, not its last step). `VolumeChoice`
  (`lib/volume_choice.dart`) keeps this device's volume for the next launch: `PlayerController` starts at it and keeps
  what `setVolume` sets, here or from another device.
- `ConnectController` (`lib/connect/`) follows the Connect model: the app controls one device at a
  time (`activeId`, null meaning this device). UI actions go through it (`playSongs`, `toggle`,
  `seek`, ...): it either runs them on the local player or sends them as hub commands. The UI should
  call `connect`, not `player`, for playback. It also follows whichever device starts playing, and
  restores the last playback on first connect, paused, or playing for a play pressed before it came back
  (`playRestoredBy`: `MediaControls` holds a headphone's play that opened the app on Android). It links the player and the hub:
  `player.onReport → client.sendState` and `client.onCommand → player.obey`.
- `lib/ui/` goes by subject, so that what changes together is together: `album/`, `artist/`, `genre/` and
  `playlist/` each hold their section's list (`*_view`) and their pages, `song/` a song's line, menu and links,
  `player/` the player bar, the full-screen player and what opens from them, `settings/` the settings and their
  pages, `home/` the home's rows and the search, and `app/` the frame around the pages (sign-in, `HomePage` and its
  bars, the page area, theme, shortcuts). `widgets/` holds what several subjects use (`Cover`, `Spinner`,
  `ThemedIcon`, `describeError`, ...): a piece only one subject uses stays in its folder.
- On a wide screen, `HomePage` keeps its bars (the top one, the side rail, the player's) and opens
  pages between them, in a nested navigator, the page area (`lib/ui/app/page_area.dart`), whose
  `PageHistory` the top bar's arrows and the keyboard's left and right go back and forward through. A TV has no
  arrows there: its remote's back closes the page on top (`NavigatorPopHandler`). Nor has a TV the player bar
  (`NowPlayingBar` is empty there): a strip of small buttons the remote went through at the bottom of every page.
  There the side rail's first button, while something plays ("Tocando agora", its icon the `Equalizer`), opens the
  full-screen player over everything, as on a phone (`PageArea.holdsPlayer`), as a video player.
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
  connectivity_plus, and offered only on a device with mobile data, `hasMobileData`): Subsonic's `maxBitRate`, with
  `timeOffset` to start later where the server has OpenSubsonic's transcodeOffset, or Jellyfin's `universal`, as HLS.
- `Downloads` (`lib/downloads/downloads.dart`, `Services.downloads`) keeps the albums and playlists the user
  downloads, in a folder of the app's for each user on each server (`Services.downloadsDirectory`): the songs as their
  files are, or in the quality picked (`DownloadChoice`, `lib/download_choice.dart`, through `MediaServer.downloadUrl`,
  which on Jellyfin transcodes into one MP3 file rather than the HLS `streamUrl` gives), their covers at 800 pixels,
  their lyrics (`lyrics/`, the server's or LRCLIB's, a file that says so where there are none), their artists, with
  their pictures (the server's, or fanart.tv's, kept as the cover `fanart:<MusicBrainz id>`), and an index
  (`index.json`, written beside and moved over, so that it is never half written) of what they are, as JSON. Files are
  named by their ids in base 64; a song in several downloads is there once, and goes with the last. It fetches what
  they lack one thing at a time, songs, covers, lyrics, then artists, while the server is in reach and the downloads
  aren't held (`DownloadHold`: on mobile data, unless the user lets them go over it), skipping what failed until the
  server is back, or `retry`. LRCLIB and fanart.tv failing for the network fail as anything else would
  (`Services._lyricsOf`, `_fanartPicture`), rather than set the media server out of reach. `ServerWithDownloads`
  (`lib/downloads/server_with_downloads.dart`) is the `MediaServer` the app is given (`Services.api`): a downloaded
  song's `streamUrl` is its file (`file://`, which mpv plays and seeks in), and a downloaded cover's `coverArtUrl` its
  own (`Cover` shows a `file://` one as a file), in reach or not; out of reach, the reads come from the downloads, and
  what changes the server fails at once. The plays this device makes out of reach (`scrobble`) are kept
  (`PendingPlays`, `plays.json` in the same folder) and counted as the server is back, by `scrobbleMissed`: Subsonic's
  scrobble at their time, and on Jellyfin, whose `scrobble` counts nothing since the hub reports the plays, the song
  marked played then (`UserPlayedItems`). `Reachability` (`lib/server/reachability.dart`) says whether the server is in
  reach: `Services.start` pings it (`MediaServer.ping`) as it discovers the hub, both waiting a few seconds at most,
  since a request to a server out of reach can wait for minutes, and a request that fails for the network
  (`isNetworkFailure`) sets it out of reach, from when it pings every 30 s. `HomePage` builds its sections anew as it
  changes. Where discovery finds none as the app opens (the server out of reach, or the network blinking with the
  server in reach), the hub is the one last found next to the server (`Session.foundHub`), which `SegueClient` reaches
  once it can. Tests leave `Services.downloads` null, and `Services.start` too where it can't
  have a folder.
- `PlaylistEditor` (`lib/server/playlist_editor.dart`, `Services.playlistEditor`) makes the changes to the user's
  playlists (create, rename, delete, add, remove, move), one after another in the order they come, since removing and
  moving go by the songs' places, and tells its listeners once none is left: the playlists section and a playlist's page
  load them again then. A playlist's page shows its own changes at once and sends them through it. Subsonic moves no
  song, so `moveInPlaylist` sends the playlist's songs back in their new order (`createPlaylist` with its id), in a
  form's body where the server has OpenSubsonic's formPost; Jellyfin removes and moves by the entry's id
  (`PlaylistItemId`, from `Playlists/{id}/Items`), so the API asks for the entries first.
- Mixes (`lib/mixes.dart`): a `Mix` is songs of the library at random (`MediaServer.randomSongs`: Subsonic's
  getRandomSongs, Jellyfin's `Items` sorted `Random`, out of reach the downloaded albums'), of a genre (`GenreMix`) or
  a decade (`DecadeMix`), 100 of them, after which autoplay goes on from the last. `SuggestedMixes` are the home's
  (`MixRow`, `lib/ui/home/mix_row.dart`, above the albums' rows): two genres, then a decade, and so on, 6 of the 12 genres
  the user plays most (before anything has played, of those with the most albums) and 3 of the 6 decades
  (`MediaServer.mostPlayedDecades`), picked at random each time the home loads, the higher one ranks the likelier
  (`_pickedByRank`; the tests give it a seeded `Random`); each with its first songs, asked for once, as its tile
  shows, which plays them first (`playMix`) and shows the picture of the first of their artists who has one, the
  server's or else fanart.tv's (`SuggestedMixes.picture`: each artist asked for as the one before has none), or, where
  none has one, the mix's own (`_MixArt`: its kind's icon on the theme's containers' colors). On Subsonic the genres and decades played most
  share one request for the 500 most played albums, and on Jellyfin one for the most played songs, while it's under
  way. A genre's page has a button that plays its mix (`MixButton`). The mix goes to the hub as any queue does: the
  protocol knows nothing of it.
- `Favorites` (`lib/server/favorites.dart`, `Services.favorites`) holds the user's favorite songs, albums and artists:
  as the media server last gave them (`MediaServer.favorites`: Subsonic's getStarred2, the latest starred first;
  Jellyfin's items marked `IsFavorite`, by name, since it doesn't say when), with the changes made here since, which
  show at once and go to the server one after another (`setFavorite`: star and unstar; `UserFavoriteItems/{id}`), a
  refused one undone; once none is left, they load again. `Services.start` loads them, and again as the server comes
  back in reach; the pages that list them (`FavoriteSongsPage`, first among the playlists, the albums' and the
  artists' "Favoritos" chips) load them as they open. `FavoriteButton` (`lib/ui/song/favorite_button.dart`) is the
  heart, filled (`filledHeart`, Hugeicons' outline with a fill, as its free icons have no filled heart) while the item
  is a favorite: on an album's page, an artist's, the phone's full-screen player (by the title) and the wide player
  bar; a song's menu has it as an item. A favorite song's line in a list has it too, filled, before its duration
  (`SongTrailing`), which a press takes out of them; a song that isn't has none there.
- `lib/lyrics/lrclib.dart`: LRCLIB, where the full-screen player's lyrics (`LyricsView`) come from
  when the media server has none, by the song's title, artist, album and length. `Services.start`
  gives it one; tests leave `Services.lrclib` null, so that none goes out to the internet.
- `lib/releases/musicbrainz.dart`: MusicBrainz, where the album page's release date, record labels and
  type (album, EP, single, compilation) come from when the media server doesn't say them: by the
  album's MusicBrainz id (its release), or, for the date and the type only, by its name, artist and
  year (its release group). Also the years a band (a group, an orchestra, a choir) has been
  together, beside its name in its biography, by the artist's MusicBrainz id (OpenSubsonic's, or
  Jellyfin's `ProviderIds`), and only by it: a name can be another artist's. A person's years in
  MusicBrainz are their life's, not their music's, so a person has none. It sends a request a second at
  most, as MusicBrainz asks, and remembers what it found for the session. `Services.start` gives it
  one; tests leave `Services.musicBrainz` null, so that none goes out to the internet.
- `lib/pictures/fanart_tv.dart`: fanart.tv, where more pictures of an artist than the media server's one come from,
  for their biography's gallery (`PictureGallery`, `lib/ui/artist/picture_gallery.dart`): its square ones (artist thumbs),
  the most liked first, by the artist's MusicBrainz id, and only by it. Where the server has no picture of an artist
  (`coverArt` null: Jellyfin without a primary image, Navidrome since 0.64, which before gave its placeholder), the
  most liked is theirs, wherever it shows (`ArtistPicture` and `FanartPicture`, `lib/ui/widgets/cover.dart`; `Cover` takes a
  picture's URL where it has no cover id). It asks with the app's own key (a project's), `fanartTvKey`, given as the
  app is built, and remembers what it found for the session, at once (`foundPictures`) for a picture built again, as a
  list scrolls back to it. `Services.start` gives it one where the build has the key; tests leave
  `Services.fanartTv` null, so that none goes out to the internet.
- `lib/releases/album_credits.dart`: an album's credits (`CreditsPage`, from the button after its
  byline), by section (performing, writing, producing) and by person: in each section the media
  server's (`Song.credits`: OpenSubsonic's contributors, Jellyfin's people), or, where it has none
  there, MusicBrainz's (`MusicBrainz.credits`, by the album's MusicBrainz id, a request of its own:
  its recordings' relations and their works'), whose tracks are the songs whose MusicBrainz id they
  have, or else those in their places. Where it was recorded, mixed and mastered, and who made its
  cover and booklet, only MusicBrainz says.
- `lib/segue/`: protocol types, the client (reconnects with backoff; stops on final close codes
  4001/4002/4003) and hub discovery (`/connect/v1/info` next to the server).
- `MediaControls` (`lib/player/media_controls.dart`) mirrors `connect.nowPlaying` to the system's
  media controls: Linux (MPRIS), iOS (Now Playing, also CarPlay's) and Android (its media session, whose
  foreground service keeps the app running in the background while the music plays) for now. Android draws the
  notification's icon (`drawable/ic_notification`, from `tool/icons.dart`) from its alpha alone, and the release build
  keeps it only because `res/raw/keep.xml` says so: Dart names it, where the resource shrinker doesn't look. Swiped
  out of Android's recent apps (`onTaskRemoved`), the app closes (`_close`, in `app.dart`): this device's music
  pauses, the media controls let go of it and the services go, but the process stays, idle, until Android ends it or
  the app opens in it again (`_reopen`, as its screen shows or for a headphone's play). Ended at once, it came back
  without a screen: as a media session ends, Android's media controls bind to the app's `MediaBrowserService` to look
  for music to resume, and audio_service's service starts the Flutter engine, and with it the whole app. That
  `MediaBrowserService` is also Android Auto's: `MediaControls` answers what the car browses from a `BrowseTree`
  (`lib/player/browse_tree.dart`: tabs, home, playlists, albums, artists; search; what is said, from Android's
  `MediaStore` extras), plays what it picks on this device (`ConnectController.playHere`, the hub then stopping the
  device that played, SPEC.md section 4), shows a stretch of the queue, and gives the song that played last as the
  music to resume (the `recent` root), without opening the app again for it. What the car asks before the app has a
  session waits for one, the app closed (`_close`) opening again for it. audio_service drops, unanswered, what the car
  asks before Dart has a handler (the app starting for the car), so the root is told changed once there is a session.
  The car reads covers only as `content://`: `CoverProvider.kt` serves the files `MediaControls` downloads to the cache
  (`segue-covers`, written whole under another name, then renamed), waiting a while for one still coming; the media
  server's address of a cover carries the login. The manifest declares the car app (`res/xml/automotive_app_desc.xml`).
- `PlayCounter` (`lib/player/play_counter.dart`) counts the songs this device's player plays toward
  the user's most played (`MediaServer.scrobble`; a no-op on Jellyfin, where the hub's
  `Sessions/Playing` counts them). Only `Services.start` makes one: widget tests that build
  `Services` themselves have none, since its timer would outlive them. Its tests run in fake time
  (`fake_async`), which is why it and `FakeEngine` read the time from `clock`.
- `AudioInterruptions` (`lib/player/audio_interruptions.dart`), on iOS and Android, sets the audio
  session up for music and pauses the local player for calls (resuming after, when the system says
  to), for another app's music and when the car or headphones go away. libmpv knows of none of it.
  On Android it also asks for the audio focus as the local player starts playing (audio_session's
  `setActive`), which tells the app that had it to stop: without it, another app's music played on
  alongside. Refused (during a call), the music pauses.
- The app's words are in `lib/l10n/`'s ARB files, one per language (Portuguese, English, Spanish),
  from which gen-l10n makes `AppLocalizations` (`l10n.yaml`). `LanguageChoice`
  (`lib/language_choice.dart`) is the language shown: the system's, of those the app has the first
  it prefers and English when it has none, until the settings (`SettingsPage`, from the top bar), or
  before signing in a menu in the sign-in's corner (`LanguageButton`), pick one, which the preferences
  keep, as `ThemeChoice` does the theme. Where no
  `BuildContext` reaches, the words come in: `describeError` takes them, and `MediaControls` gets
  them from a widget under `MaterialApp` (`app.dart`), again as the language changes.
- `Session` keeps the token (Subsonic's, with its salt, or Jellyfin's access token) in secure
  storage and everything else in `shared_preferences`, with the API under `api` (none: a session
  saved before Jellyfin, so Subsonic). The password itself is never stored.
- Pairing (`lib/pairing/pairing.dart`): a TV signs in from a phone signed in, the remote typing nothing. The TV's
  `LoginPage` (in directional mode) starts a `PairingServer`, an HTTP server on a port of its own, and shows its
  `PairingInvite` as a QR code (qr_flutter): the TV's address on the local network, its name, a random id (the path
  it takes the sign-in at) and a random key. The phone's `SignInTvPage` (settings, Android and iOS, mobile_scanner)
  reads it and, once the user confirms (`ConfirmSignInTv`, which names the TV and its address, both under the TV's
  code too), `offerSignIn` posts a `PairingOffer` sealed with that key (AES-GCM, cryptography, the id and the way it
  goes as associated data): the server, the hub, and on Subsonic the credentials. The TV (`takeOffer`) pings the server
  with them and saves the session, or on Jellyfin starts a Quick Connect (`JellyfinApi.initiateQuickConnect`), answers
  its code, which the phone authorizes, and polls until it can sign in with a token of its own. The hub has no part in
  it: the TV knows neither the server nor the hub before. Against a code made to look like a TV's, the phone takes
  only one whose address is a private IPv4 one (`PairingInvite.isLocal`), so that none has the sign-in go to the
  internet, and the TV shows one only on such a network; against someone on the network answering in the TV's place
  (their own Quick Connect code, for the phone to authorize), the answers are sealed with the key too; against a
  code seen on a photo of the screen, a code is good for one sign-in, whatever comes of it, the TV showing another
  (`PairingServer.invite`), so the phone asks about each code once (`_asked`, rather than the camera's own
  `noDuplicates`, which would take the new one, read while the one before is sent, for one seen). The widget
  tests reach the TV's server with a real `HttpClient` (`HttpOverrides`, the binding's answering 400) and pump while
  they wait, its handler running in the test's clock.
- Android TV: the remote drives the app through focus. That it does is Flutter's navigation mode, directional
  (`DirectionalNavigation`, `lib/ui/widgets/directional_navigation.dart`, which `TelevisionScreen` turns on), which
  the pages ask with `DirectionalNavigation.of`, not the platform. A widget laid out otherwise for the remote throughout
  is two, sharing the rest (`TileRow`: `_PointerTileRow`, `_TelevisionTileRow`), rather than one asking it at every
  turn. `segueTheme` (`lib/ui/app/theme.dart`) gives
  focused buttons a ring and everything else a strong tint, and `FocusRing` draws a ring on tiles
  whose image hides the tint, and grows a card (`grows`: an album's, an artist's, a mix's) by 6% there, a row of
  them (`TileRow`) having the room above and below for it, and the page scrolling as far as shows it grown, ring and
  all (`_showGrown`), past where the focus scrolls the card itself. The top bar and the player's keep the arrows in
  them (`BarTraversalPolicy`, `lib/ui/widgets/bar_traversal.dart`), leaving only on the page's side: Flutter's
  directional search looks at the whole screen, where cards scrolled under the top bar, or, on a computer, built
  under the player's, lie level with their buttons. `TelevisionScreen` (`lib/ui/app/television_screen.dart`,
  around the app on a TV) has the text 15% bigger than the system's and gives the screen's edges room (6 all round,
  an eighth of Android TV's 48 at the sides, for TVs that cut them off, since the bars keep their own inside it) as
  the system's padding, which the bars keep out of by themselves, and the home's rail by its `SafeArea`, their
  backgrounds going on to the edges. The page area goes on to the right edge,
  the left's padding taken out of it (the rail's), so that a row of tiles runs on to the side as it scrolls, as Google
  TV's do: `TileRow` keeps its title and its last tile out of the right's padding, and the full-screen
  player keeps out of it all. A row has no arrows there, which the remote, going along its tiles, wouldn't reach,
  nor the top bar its back and forward ones: its tiles grow, rather, as much as shows 40% of one at the screen's side
  (`_TelevisionTileRow._peek`), whatever its width, so that the row says it goes on, their pictures growing and their lines
  staying as they are (a row's tiles, as the album grid's, are as tall as their cover and lines,
  `AlbumRow.tileSize`). The card with the focus stays in the first one's place, the row moving under it
  (`_keepAtStart`), as Google TV's do, so that the cards after it and that piece stay in view; `FocusRing` then
  only shows it grown above and below. There the row starts 8 further in, its title too (`_TelevisionTileRow._grownSide`), for
  that card to grow into with its ring clear of the rail. `FocusRing` must keep the same widget tree with or without focus, since rebuilding the child
  would drop its focus as soon as it arrived. On a TV
  (`adaptToTelevision`, `lib/device.dart`, asking `MainActivity.kt`), focus highlights are always on: Flutter starts
  Android in touch mode and ignores key events from virtual keyboards, which is what
  `adb shell input keyevent` sends. `TextFieldArrowShortcuts` lets up and down leave text fields
  (on a TV, left and right too). A text field opens the keyboard as the focus comes to it, and on a
  TV the keyboard covers half the screen and takes the D-pad, so there the home's search bar stays
  read-only until the center button (its `onTap`) opens it. On a TV the full-screen player is as a video player
  (`lib/ui/player/television_player.dart`): no top bar, on the theme's background, and its controls under it
  (`TelevisionControls`) showing as it opens and as the arrows
  or OK are pressed, which then only bring them back, play taking the focus, and going after 5 s with no key, but
  while a menu or a sheet opened from them shows; the slider stays, and where it plays, when another device does, beside
  them, on a pill while they show and its words alone, faint, while they are hidden. What plays lines up with them, as
  far from the screen's sides (`TelevisionControls.side`): with the lyrics, the cover at the start, as the time played
  (`SeekSlider.timesAtEnds`), and the lyrics, with no room of their own at their sides, ending where the song's length
  does. The remote's back hides them first, and only then closes the player. The screen stays on while it plays. On a TV the lyrics are karaoke (`LyricsView.karaoke`, by
  the navigation mode): the full-screen player opens with them, in three fifths of the screen, keeping the screen on,
  and the line that plays is bigger, in the middle (its style animated, `TweenAnimationBuilder`, on the `Text` itself,
  and the scroll going, along with it, straight to where the line ends up once grown and the one before shrunk:
  `_growth` lays their text out in the style they go to). Each line shows broken where it breaks as the line that
  plays (`_brokenAsPlaying`, its text laid out in that style): as it grew, a word went to the next line at some size
  on the way, or the line became two. As they come and go, the player makes them once for all
  the steps, which then neither build them nor, on a layer of their own (`RepaintBoundary`), paint them again; on a
  TV they stay, hidden, between showings (`Visibility`, `maintainState`): built anew as they came, their lines held
  up the first step. A song without lyrics shows the cover alone, the lyrics still on for the next: the player asks
  `lyricsOf` (`lib/ui/player/lyrics_view.dart`), which `LyricsView` asks too, and which remembers the last few songs'
  lyrics for each media server, so that they are asked for once, and a player opened again on a song without them knows
  at once (`hasLyrics`). A TV's remote seldom has a menu key, so a song's or a
  playlist's menu also opens with the center button held (`MenuShortcuts`, `lib/ui/widgets/menu_shortcuts.dart`):
  there a press of it plays the song (opens the playlist) as it is let go, not as it goes down. A TV has no drag, so
  the queue's and a playlist's songs move by the remote (`MovableSongs`, `lib/ui/song/movable_song.dart`, the list
  that drags them elsewhere; each a `MovableSong`, from the song's menu): there the list is a plain `SliverList` that
  finds each line by its key (`findChildIndexCallback`), as `SliverReorderableList` keys each line by its index too,
  and makes it anew as it moves, dropping the focus; and a playlist loaded again keeps its entries (`_entriesOf`),
  for the same reason.
- `MainActivity` extends audio_service's `AudioServiceActivity`, so the screen and the plugin share
  one Flutter engine. With a plain `FlutterActivity`, audio_service started an engine of its own,
  and with it a second, hidden copy of the app that connected to the hub as the same device. It
  also answers `lib/device.dart` (TV or not, the device's name in the system settings, whether it has mobile data,
  for the automatic quality), as `AppDelegate.swift` does on iOS (the name, mobile data).

## Conventions

- The app's UI text is in `lib/l10n/`'s ARB files, never a literal in the code: a widget takes it
  from `AppLocalizations.of(context)` (a local `strings`). A new text is a message in all three,
  `app_pt.arb` (the template, with its description and its placeholders), `app_en.arb` and
  `app_es.arb`; `l10n_test.dart` fails on one missing. A sentence whose words change with a number
  or a kind is one message, with a `plural` or a `select` (`albumCount`, `playRelease`), not pieces
  put together. The Dart code (`lib/l10n/app_localizations*.dart`, not in git) comes from the ARB
  files on `pub get` and on every build, but not on `test` or `analyze`: after editing one,
  `tool/flutter.sh gen-l10n`. Code, comments and `README.md` are in English. Error codes from the
  hub and players become messages in `describeError` (`lib/ui/widgets/errors.dart`), so a new error string
  needs an entry there.
- Commit messages are in Portuguese: a short title and a body explaining the behaviour and why.
- `README.md` lists what the app does and what it doesn't do yet. Update it when a feature lands,
  and segue's `README.md` ("Next steps") when the feature was listed there.
- Dart layout: every `if`, `for` and `while` body is in braces, even a single `return` (the lints
  `curly_braces_in_flow_control_structures` and `always_put_control_body_on_new_line` enforce it).
  A statement with braces (`if`, `for`, `while`, `do`, `switch`, `try`, a local function) has a
  blank line before and after it, separating it from the statements around it, but not at the
  start or end of its block. The `return` that ends a function (a method, a closure) has one above
  it too, where other statements come before it. A comment above the statement belongs to it, so
  the blank line goes above the comment. `dart format` keeps blank lines but never adds them, so
  this is by hand.
- Dart design follows Effective Dart's guidelines (https://dart.dev/effective-dart/design). The ones
  a lint can check are on in `analysis_options.yaml`; the rest (terms used consistently, no
  abbreviations, noun phrases for values, verbs for side effects, no `get` prefix, ...) are by hand.
  `avoid_positional_boolean_parameters` stays off: the guideline exempts setters, and a method like
  `setShuffle(true)` is one that can't be a setter, being async.
- A comment says what the code can't: why it is so, what it works around, what a number means.
  One that only says again what the code says (`/// Goes to the playlists.` over
  `openSection(tester, 'Playlists')`) goes. Where every member of a list of fields or of an enum's
  values has its doc, the obvious one stays, rather than leave a gap.
- Icons come from Hugeicons (`ThemedIcon(HugeIcons.strokeRounded...)`, `lib/ui/widgets/themed_icon.dart`),
  which draws them as SVG paths, and never through its own `HugeIcon`: that one is 24 pixels
  whatever the `IconTheme` says, so an icon button's `iconSize` or a navigation bar's theme would
  miss it. No Material icon is left, and `test/icons_test.dart` keeps it so; the back arrow Flutter
  adds to a page comes from the theme (`actionIconTheme`).
- The Linux build renders with Skia, not Impeller (`linux/runner/my_application.cc`): Flutter
  3.47's Impeller, on OpenGL, clips without antialiasing, so the round edges of covers and artists'
  pictures came out jagged, and it left the icons' thin strokes jagged too. On each Flutter update
  (`tool/dev.Dockerfile`, `codemagic.yaml`, `.github/workflows/release.yml`), check that Linux still has Skia, and
  try Impeller again: without that line, look at a cover's edges and at the icons in a Linux desktop session.
- On a computer the pointer is a hand over what can be clicked, which Flutter leaves to the web: the
  theme (`segueTheme`) gives it to buttons, list tiles and menus' items, and an `InkWell`, which no
  theme reaches, takes `mouseCursor: WidgetStateMouseCursor.clickable`. `test/cursor_test.dart` goes
  over them.
- No name ends in `_`: when the obvious one is taken, as by an import prefix (`http`), pick a fuller
  one (`httpClient`). A leading `_` is Dart's privacy, not style, and stays.
- Docs, comments and tests stay generic: no names from a particular setup (machine or device names,
  hostnames, server paths, the tooling of the server it is developed on). Use names like `laptop`,
  `phone`, `tv` and `music.example`.
