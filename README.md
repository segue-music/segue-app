<p align="center"><img src="linux/runner/resources/app_icon.png" alt="" width="128"></p>

# Segue app

A music player for Navidrome, any other OpenSubsonic server, or Jellyfin, built
around Segue Connect: you pick a device, and whatever you play goes there. One Flutter codebase for Linux,
Windows, macOS, Android and iOS. The interface is in Portuguese, English and Spanish.

Segue's protocol and its hub, which runs next to the media server, are in
[segue-music/segue](https://github.com/segue-music/segue). Without a hub, the app plays on
the device it runs on.

> [!NOTE]
> **Vibe-coded.** The app was written by Claude (through Claude Code), with a person deciding what
> to build and trying it on real devices. Every commit says so.

**Status: skeleton.** It does:
- signing in with the media server's own account, with only its address: the app finds out whether
  it speaks Subsonic (Navidrome, other OpenSubsonic servers) or Jellyfin (a Jellyfin server, or
  Navidrome's Jellyfin API at `/jellyfin`, experimental since Navidrome 0.64 and turned on with
  `ND_JELLYFIN_ENABLED=true`). The password isn't kept: the system's secure storage gets a Subsonic
  token, or Jellyfin's access token, which signing out ends on a Jellyfin server (Navidrome's keeps
  it until the password changes). Signing out is at the end of the settings (a page the top bar's
  button opens, with the theme, the language, the quality and the open source licenses), under the
  user and the server it signs out of;
- the open source licenses: the app's own, Flutter's and the Dart packages', and, where the app
  brings them (Android, iOS, macOS, Windows), those of libmpv, FFmpeg and Mbed TLS, the native
  libraries it plays with, which Flutter's list leaves out; a package a line, each opening its
  licenses' text;
- a home, where the app opens, with a row of the latest released albums (by release date, or by
  year where the server has no more), one of the albums the user plays most and one of the latest
  added to the library, 30 each, with arrows in each row's corner to go a screenful forward and
  back, and a title that opens the albums tab in the row's order (on a Jellyfin server, which counts
  plays only by song, an album's plays are its songs', added up), which load again as the home is
  dragged down from its top (with a finger, a touchpad, or on a computer the mouse); albums (by name, the latest
  released, the most played or the latest added, picked in chips above them, the next ones coming
  as the grid nears its end), artists (by name or the most played first, picked above them, a thumb
  sliding to the one picked: on a Subsonic server, which counts no plays by artist, from the 500
  most played albums; each with their albums and then, apart, their singles and EPs, where the
  server says which are, under five songs of theirs, numbered, which play from the one picked: the
  ones the user plays most, once any has played (on a Subsonic server, which lists no songs by
  plays, those of the artist's albums, from the albums that have played), or the popular ones, which
  a Subsonic server learns from Last.fm (getTopSongs), picked over them where there are both (a
  thumb sliding to the one picked), and these alone before any of the user's has played) and
  genres (by name, each with its number of albums, under the ten the user listens to
  most, and its albums by name, under a row of those the user plays most: on a Subsonic server,
  which counts no plays by genre, both come from the 500 most played albums):
  albums, artists and genres in a side rail, as icons that name their sections on hover, beside them,
  and the home under the app's icon, in the top bar's left corner (on a phone, the icon goes there
  too, and all four are in a bar at the bottom, with the search after them: its bar shows in it alone,
  blank under it until a search finds something);
  the album page, whose cover opens full screen; search (artists, albums and songs); and playback
  through media_kit (libmpv), with a seek bar, shuffle and repeat (the queue, or the track until
  another one is picked), in the player bar and in a full-screen player that the song in the bar
  opens, which shows the song's lyrics beside it, or under it on a phone (OpenSubsonic's songLyrics,
  as Navidrome's from the file's tags or
  a .lrc next to it, or Jellyfin's; when the server has none, LRCLIB's, from lrclib.net, by the
  song's title, artist, album and length, synced ones wherever it has them, also in another entry
  of the song, as a single's): synced ones mark the line that plays and keep it in view,
  with a note for a part with no singing, and a line tapped goes there; under the player, the cover
  smaller to make room for them, a tap on them (or the button at their corner) opens them full screen,
  with the seek bar and the buttons, where a button at the top left hides them, back to the player
  as it opened, as on a phone a drag down does, with the finger; a wide bar's lyrics button opens the player with them. The bar stays put from page to page, and on a wide screen under the
  full-screen player too, whose top then leaves the lyrics, the queue and the devices to it, and the
  player the seek bar and the buttons, showing the song alone; on a phone it has them all, the
  lyrics, the devices and the queue in a bar at the bottom, and the album's name at the top, and a
  drag down takes it down with the finger and closes it (let go past a third of the way, or flung),
  from anywhere but the lyrics, which scroll (taller than the screen, it scrolls to its top first). A swipe on
  its cover goes to the next song (to the left) or the previous one (to the right). In both,
  the song's title
  opens its album (as does the album's name, in the full-screen player) and each of its artists
  their page, whichever device it plays on (several apart by a dot, "Run-DMC · Aerosmith", whatever
  the media server puts between them, and in too little room, as many as fit); on a phone the whole song
  in the bar opens the player (its artists there apart by commas where the media server has
  semicolons). A song the media server fails to give (as when it can't read its disk)
  stops the player on it, paused where it was, and says so, rather than the player skipping through
  the queue; play tries it again. As the app opens on the last playback, paused, it already loads the
  song, so that play starts at once; should the server fail it then, the app says so only if play,
  trying it again, fails too. Wherever albums are listed (the home's rows, the albums tab and
  search), an album's artist opens their page, a button in the middle of its cover plays it from
  its first song (on a computer, while the pointer is over the album; on a tablet, always; on a
  phone, where it covered much of the cover, and on a TV, which goes from album to album, never), and the rest of it opens the album; on the album's
  page the artist links too, and there the keyboard and the remote get to them (in the lists, each
  album is one stop), and each song's artists, under its title, open their page too, each their
  own (for the keyboard and the remote, each song is one stop);
- on a wide screen (a computer, a tablet, a TV), the top bar, the side rail and the player bar stay,
  and pages (an album, an artist, a genre, the queue, the full-screen player) open between them, with
  the search bar in the middle of the top bar. Arrows beside the app's icon go back and forward through
  those pages, as a browser's do, and so do the keyboard's left and right (on a phone, left goes back
  from a page with a back arrow). A section, or a search, closes them. An artist's page has their
  picture, round, and behind it the same picture, blurred, across the top of the page. On an album's
  or an artist's page, once the cover or the picture has gone up, the name stays at the top of the
  page, in a bar that comes in as it goes, after the album's play button. Esc takes the focus off
  what has it; in the search bar, it first clears what was typed. The key / goes to the search bar
  (on a phone, to the search), but in a text field, where it types;
- on a phone, the player bar and the sections' bar stay at the bottom, and pages (an album, an
  artist, a genre) open over the rest, each with its own back arrow; a section closes them. An
  album's and an artist's have their name at the top, in bold, as is the arrow; on an artist's, over
  their picture, the arrow, the name and the system's icons are dark over a light picture and light
  over a dark one, until the page's color fills the bar as it scrolls. The full-screen player and
  the queue cover everything, and the player's links close it to open their page under the bars;
- the queue of whichever device the app controls, from the full-screen player or, on a wide
  screen, the player bar: the current track on top, the next ones under it and what played before
  above it. A tap on a track plays it there;
- the album's songs and the queue have a header naming their columns: the number ("#") or the
  cover, the title, and the duration as a clock; over the queue it stays as the tracks scroll;
- on the album page, what kind of release it is (an album, an EP, a single or a compilation: on a
  computer above its name, on a phone before its year), which its play button, and the one on its
  cover wherever albums are listed, say too ("Tocar o EP"); under its name, its artist with their
  picture, its year, how many songs it has and how long they last; after its songs, its release
  date, as precisely as the server knows it, and its record labels (OpenSubsonic's; on a Jellyfin
  server, which reads no labels from music files, the album's studios, where someone set them),
  which the keyboard and the remote, coming to the last song, scroll on to. The kind is
  OpenSubsonic's (in Navidrome, the files' MusicBrainz release type, or their compilation tag).
  Where the server says no date (or only the year), no labels or no kind (Jellyfin never says it),
  MusicBrainz (musicbrainz.org) fills them in: by the album's MusicBrainz id, where the server knows
  it, its edition's date and labels and its kind; without it, only the date the album first came
  out and its kind, by its name, artist and year, when these match one album only;
- on the album page and in search, the current song (on whichever device the app controls) stands
  out in the theme's color, with an equalizer in place of its number, or over its cover, while it
  plays, its bars moving (still where the system asks for less motion);
- Connect: the hub is found next to the server (or typed in), and the device picker lists the
  user's other devices that are online, with what they play. Picking one makes the app control it
  (play, pause, skip, seek, shuffle, repeat, play an album there). Picking this device again moves the music here, at the
  same point. If the device it controls closes, its music stays here, paused. When another device
  starts playing, music left paused here goes, so that no device is listed paused with music that
  now plays elsewhere. An app opened when nothing plays anywhere picks up where the music was.
- plays count toward the user's most played: on a Subsonic server, the device that plays a song
  scrobbles it once it has played half of it or four minutes (not one of 30 seconds or less), its
  playing time added up across pauses and seeks, so that a song moved to another device halfway
  doesn't count on both; on a Jellyfin server the hub counts them, as a song starts (with no hub,
  nothing counts them there yet);
- the quality the songs stream in: automatic (the files as they are on Wi-Fi or a cable, 160 kbps on mobile data,
  as the system says the device is online), the files as they are, or transcoded by the media server down to 320,
  160 or 96 kbps, picked in the settings, which the app keeps and
  which holds, as a change of connection does, from the next song on. A song a Subsonic server transcodes as it
  goes can't seek, so a seek asks for it again from that point (OpenSubsonic's transcodeOffset, which Navidrome
  has), as does opening on the last playback; a Jellyfin server sends it as HLS, which can seek;

- the system's media controls (through `audio_service`) show and command what the now-playing bar
  shows, the device it follows included: on Linux (MPRIS) the media keys, the desktop's player
  widget and KDE Connect; on iOS (Now Playing) the lock screen, Control Center, headphone buttons
  and CarPlay's Now Playing screen;
- on iOS, playing in the background and with the silent switch on; a call pauses the music, which
  plays again after it, and leaving the car or unplugging the headphones pauses it;
- the interface in Portuguese, English or Spanish: the system's language, where the app has it
  (English where it has none of the system's), until the settings (or, before signing in, the
  language menu in the sign-in's corner) pick one, which the app keeps. Dates, numbers of albums and songs, and Material's own words (tooltips, the text
  fields' menu) follow it, and on iOS the local network permission's prompt follows the system's;
- its icon (made by `tool/icons.dart` from `tool/icon.png`): Android's launcher icon, adaptive from
  Android 8 on, the Android TV banner, on Linux the window's icon and an entry in the application
  menu, the iOS and macOS icons, the Windows icon, and the app's own, in its top bar. The theme,
  light or dark (as the system's, until the settings pick one, or the system's again, which the app
  keeps, the old theme fading into the new one), takes the icon's colors: its pink,
  the deep and the light pink of the ring around the note, and in the dark the black around it, as
  the background. On Linux the window's title bar, with the close button, takes the background too.
  On a computer the window opens maximized.

Not yet: playlists, editing the queue (play next, add to it, reorder it), the media controls on the other platforms (Android's
media session), on a Jellyfin server the cover of a song that came from another device
when its file has none of its own (Jellyfin doesn't fall back to the album's) and an artist's popular songs (Jellyfin
knows only its users' plays), an offline cache, settings, sending the music
to speakers and TVs that don't run the app (Google Cast, UPnP/DLNA), and CarPlay as an app of its own (browsing the library
on the car's screen, which needs Apple's CarPlay entitlement and native code). The Android build
has been tried on a tablet and on an Android TV; the iOS build has not been tried on a device yet.

## Code

| Folder | What |
|---|---|
| `lib/server/` | `MediaServer`, what the app asks of the media server in either API, and its albums, artists and songs; finding out which API a server speaks, and signing in to it |
| `lib/subsonic/` | The Subsonic API: token sign-in, albums, artists, songs, search, stream and cover URLs |
| `lib/jellyfin/` | The Jellyfin API: sign-in by name for this device, the same library calls, and signing out |
| `lib/segue/` | The Segue protocol in Dart (its `SPEC.md` is in the segue repository), the hub client (reconnects by itself) and hub discovery |
| `lib/player/` | `PlayerController` (queue, commands, state reports) over an `AudioEngine`; `MediaKitEngine` is the real one. `MediaControls`: the system's media controls. `AudioInterruptions`: calls and the like pausing the music, on iOS |
| `lib/connect/` | `ConnectController`: which device the app controls, and moving the music between devices |
| `lib/lyrics/` | LRCLIB (lrclib.net), where lyrics come from when the media server has none, and LRC |
| `lib/releases/` | MusicBrainz (musicbrainz.org), where an album's release date and record labels come from when the media server doesn't say them |
| `lib/ui/` | The pages: sign-in, home, albums, artists, album, artist, search, player bar and full-screen player, queue, device picker |
| `lib/l10n/` | The app's words in each language, as ARB files (Portuguese's, the template, says what each is); the Dart code comes from them on `pub get` and on every build |
| `test/` | Unit and widget tests, and tests against the real Go hub (`hub_test.dart`) |
| `tool/` | A Docker image and script to build and test without installing Flutter; `icons.dart` makes every icon from the artwork, `icon.png` |

## Running on Linux

### A build from elsewhere, without Flutter

`tool/package-linux.sh` builds the Linux version (with Flutter from Docker, see below) and packs
it as `build/segue-linux-x64.tar.gz`, 10 MB. The computer that runs it needs glibc 2.38 or newer,
GTK 3, libsecret and libmpv, all runtime packages. On Fedora (checked on Fedora 44):

```sh
sudo dnf install gtk3 libsecret mpv-libs
tar xzf segue-linux-x64.tar.gz
segue/segue
```

`segue/install-desktop-entry.sh` puts Segue in the application menu, with its icon: it writes
`~/.local/share/applications/io.github.mateusguilherme.segue.desktop`, pointing at the folder (run
it again after moving the folder). On Wayland the window takes its icon from that file, so without
it the window has a generic one.

### With Flutter installed

Install Flutter 3.47 ([instructions](https://docs.flutter.dev/get-started/install/linux)) and
what the Linux build needs: clang, cmake, make, ninja, pkg-config, GTK 3, liblzma and libstdc++
headers, plus the headers of libmpv (audio) and libsecret (secure storage). On Fedora that should
be the following (check the names with `dnf search` if one is missing):

```sh
sudo dnf install clang cmake make ninja-build pkgconf-pkg-config gtk3-devel xz-devel \
  libstdc++-devel mpv-libs-devel libsecret-devel jsoncpp-devel
flutter pub get
flutter run -d linux
```

Sign in with the media server's address (`https://` is added if left out), user and password.

### Connect

Connect needs the hub, from [segue-music/segue](https://github.com/segue-music/segue).
Published at `/connect` on the media server's address, it is found by itself, with nothing to type
at sign-in. To try it without that, run it on your computer, pointing at the media server (with Go,
in a clone of that repository):

```sh
cd segue/hub
go build -o segue-hub ./cmd/segue-hub
env SEGUE_UPSTREAM=https://navidrome.example ./segue-hub
```

and at sign-in, under "Advanced" ("Avançado"), put `http://127.0.0.1:8480` as the hub's address. The hub's
binary is static, so one built on another computer runs as it is.

To see two devices on one computer, start a second copy of the app as another device:

```sh
env SEGUE_DEVICE_ID=second SEGUE_DEVICE_NAME="Second copy" segue/segue
```

## Running on Android and Android TV

`tool/package-android.sh` builds `build/segue-android.apk` (with Flutter and the Android SDK from
Docker, see below): one APK for every processor, signed with a debug key, to install by hand. On
Android TV the app is in the home screen, and the remote drives it: the D-pad moves around, from
the page out to the bars around it (the top one, the side rail, the player's) and back (its center
button presses, and a white ring shows where it is), the keyboard opens on the search bar with the
center button rather than as the focus passes by, and the play/pause, next and previous buttons
drive playback.

To install it from a computer with adb (`android-tools` on Fedora), turn on the TV's developer
options (Settings > Device Preferences > About: press "Build" seven times) and, in them, network
debugging. Then:

```sh
adb connect <TV address>
adb install -r segue-android.apk
```

Newer Google TVs offer wireless debugging instead: `adb pair` with the address and code the TV
shows, then `adb connect`. The TV has to reach the media server (and the hub) at the address used
to sign in.

Phones and tablets work the same way, through wireless debugging (Settings > About: press "Build
number" seven times, then Developer options > Wireless debugging). Its main screen shows the address
and port for `adb connect`; "Pair device with pairing code" shows another port, and the code, for
`adb pair`, which is needed once per computer:

```sh
adb pair <address>:<pairing port> <code>
adb connect <address>:<port>
adb install -r segue-android.apk
```

The port changes each time wireless debugging is turned on, and the address can change too when
the device rejoins the network. Over a slow Wi-Fi link the APK can take a while: copying it to the
device and opening it there (allowing that app to install apps) does the same.

## Running on iOS

The iOS version needs a Mac to build, so it is built on Codemagic's (`codemagic.yaml`), which
signs it and uploads it to App Store Connect; the iPhone installs it from TestFlight. That takes a
paid Apple Developer Program membership. Codemagic's free plan has enough build minutes for a few
builds a week.

Once, on the web, with nothing to install:

1. In the Apple Developer site, under Certificates, Identifiers & Profiles, register the app's
   identifier: an explicit App ID `io.github.mateusguilherme.segue`, with no extra capabilities.
2. In App Store Connect, create the app with that bundle ID. Its name there has to be unique in the
   App Store; the home screen shows "Segue" whatever it is. In its TestFlight tab, make an internal
   testing group with yourself in it and automatic distribution on, so that each build reaches it.
3. In App Store Connect, under Users and Access > Integrations, make an App Store Connect API key
   with the App Manager role. Its `.p8` file downloads only once; note its Key ID and the Issuer ID.
4. In Codemagic, sign in with GitHub and add this repository. In the team's integrations, add the
   key under Developer Portal, named `segue` (the name `codemagic.yaml` asks for).
5. In Codemagic's code signing identities, generate an Apple Distribution certificate with that
   key. Then, in the Apple Developer site, make an App Store Connect provisioning profile for the
   App ID with that certificate, and fetch it in Codemagic.

Then each build starts from Codemagic's page (workflow "iOS to TestFlight") or by pushing a tag
starting with `ios-`:

```sh
git tag ios-1 && git push origin ios-1
```

It takes about 15 minutes, plus Apple's processing (the first build took about an hour). The build then
shows in the TestFlight app on the iPhone, from the internal group's invitation, for 90 days. The
first time the app reaches a server in the local network, iOS asks for permission.

Codemagic may report the upload as failed when App Store Connect answers it with server errors (500),
even though the log says `UPLOAD SUCCEEDED`. The build often arrived anyway, so look in App Store
Connect's TestFlight tab before building again. Building the same commit again doesn't help either
way: the build number counts the commits, and App Store Connect refuses a number it already has.

What iOS does differently:
- In the background, iOS keeps the app running only while it plays. Paused, or just controlling
  another device, it is suspended after a while, and the hub sees it leave until it is opened again.
- In a car, the music shows in CarPlay's Now Playing screen, with its controls, but the app has no
  screen of its own there.
- Other devices see this one as "iPhone" (or "iPad"), not by its name in Settings (General > About
  > Name): since iOS 16 an app reads that name only with an entitlement Apple grants on request
  (`com.apple.developer.device-information.user-assigned-device-name`), which the app doesn't have
  yet.

## Building and testing without Flutter installed

`tool/flutter.sh` runs Flutter from a Docker image, as your user. The tests against the hub
(`test/hub_test.dart`) run its binary, built from the segue repository (`go build -o segue-hub
./cmd/segue-hub` in its `hub/`): the one in a clone of segue next to this one (`../segue`), or the
one `SEGUE_HUB_BIN` names. Without it, they are skipped.

```sh
docker build -t segue-flutter-dev -f tool/dev.Dockerfile tool
tool/flutter.sh pub get
tool/flutter.sh analyze
tool/flutter.sh test
tool/flutter.sh run -d linux
tool/flutter.sh build linux
tool/package-linux.sh
```

`tool/flutter.sh run` opens the app in your desktop (Wayland or X11): the container gets the
display, the GPU, the sound and the session bus. Its settings are its own, in
`~/.cache/segue-flutter`, but its token goes to the same keyring as an installed copy's (the app id
is the same), so signing out in one signs the other out too.

After changing the artwork (`tool/icon.png`), `DART=1 tool/flutter.sh run tool/icons.dart` makes
the icons again. The rounded square's position in the artwork is measured at the top of
`tool/icons.dart`, so a new artwork needs it measured again.

For Android, a second image adds the JDK and the Android SDK and NDK to the first:

```sh
docker build -t segue-flutter-android -f tool/android.Dockerfile tool
tool/package-android.sh
tool/flutter.sh run -d android
```

Once this image is built, `tool/flutter.sh run` takes it, and reaches the Android devices of your
computer's adb server (`adb devices`) as well as your desktop: a phone on USB, an emulator, or a TV
after `adb connect`. `-d android` stands for the first of them; with several, `-d` takes the one
`adb devices` names. With none, `-d android` starts an emulator: the Android SDK's (`ANDROID_HOME`,
or `~/Android/Sdk`, where Android Studio puts it) on the first of its virtual devices, or the one
`SEGUE_AVD` names. It stays open after `flutter run` ends, for the next one.

## License

MIT, see [LICENSE](LICENSE).
