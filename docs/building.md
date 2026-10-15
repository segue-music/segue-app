# Building Segue

How to build the app, pack it, release it and work on it. How to use it is in the [README](../README.md).

## Flutter from Docker

`tool/flutter.sh` runs Flutter from a Docker image, as your user, so nothing else needs installing:

```sh
docker build -t segue-flutter-dev -f tool/dev.Dockerfile tool
tool/flutter.sh pub get
tool/flutter.sh analyze
tool/flutter.sh test
tool/flutter.sh run -d linux
tool/package-linux.sh
```

`tool/flutter.sh run` opens the app in your desktop (Wayland or X11): the container gets the display, the GPU, the
sound and the session bus. Its settings, downloads and log are its own, in `~/.cache/segue-flutter` (the log in
`.local/share/io.github.mateusguilherme.segue/logs/` there), but its token goes to the same keyring as an installed
copy's (the app id is the same), so signing out in one signs the other out too.

For Android, a second image adds the JDK and the Android SDK and NDK to the first:

```sh
docker build -t segue-flutter-android -f tool/android.Dockerfile tool
tool/package-android.sh
tool/flutter.sh run -d android
```

Once this image is built, `tool/flutter.sh run` takes it, and reaches the Android devices of your computer's adb
server (`adb devices`) as well as your desktop: a phone on USB, an emulator, or a TV after `adb connect`. `-d android`
stands for the first of them; with several, `-d` takes the one `adb devices` names. With none, `-d android` starts an
emulator: the Android SDK's (`ANDROID_HOME`, or `~/Android/Sdk`, where Android Studio puts it) on the first of its
virtual devices, or the one `SEGUE_AVD` names. `-d emulator-5554` starts it too where it isn't open, on that port, which
names it in `adb devices`. It stays open after `flutter run` ends, for the next one.

## Flutter installed

Install Flutter 3.47 ([instructions](https://docs.flutter.dev/get-started/install/linux)) and what the Linux build
needs: clang, cmake, make, ninja, pkg-config, GTK 3, liblzma and libstdc++ headers, plus the headers of libmpv (audio)
and libsecret (secure storage). On Fedora that should be the following (check the names with `dnf search` if one is
missing):

```sh
sudo dnf install clang cmake make ninja-build pkgconf-pkg-config gtk3-devel xz-devel \
  libstdc++-devel mpv-libs-devel libsecret-devel jsoncpp-devel
flutter pub get
flutter run -d linux
```

On Windows, which has no Docker image for it, this is the only way: Flutter 3.47
([instructions](https://docs.flutter.dev/get-started/install/windows)), Visual Studio with its "Desktop development
with C++" workload (`flutter doctor` says whether it finds it), and Developer Mode on (Settings > System > For
developers), since the plugins are symlinks. The build fetches libmpv by itself. Then:

```powershell
flutter pub get
flutter run -d windows
tool\package-windows.ps1
```

## Packages

The packages that the releases have, which the README says how to run ("Running on Linux", "Running on Windows",
"Running on Android and Android TV"):

- `tool/package-linux.sh` builds the Linux version (see "Flutter from Docker") and packs it as
  `build/segue-linux-x64.tar.gz`.
- `tool\package-windows.ps1`, in PowerShell, builds the Windows version (see "Flutter installed") and packs it as
  `build\segue-windows-x64.zip`.
- `tool/package-android.sh` builds `build/segue-android.apk` (see "Flutter from Docker"): one APK for every processor,
  signed with the app's key where the app's folder has it (see "Releases"), else with a debug key.

## Android Auto without a car

The Desktop Head Unit shows the car's screen on a computer, with Android Auto letting in the app installed by hand as
the README says ("Running on Android and Android TV"): in the Android SDK's manager, "Android Auto Desktop Head Unit
Emulator" (in `extras/google/auto/`), and on the phone, connected by USB, Android Auto's "Start head unit server" (in
its menu, with the developer settings on). Then:

```sh
adb forward tcp:5277 tcp:5277
<Android SDK>/extras/google/auto/desktop-head-unit
```

## iOS

The iOS version needs a Mac to build, so it is built on Codemagic (`codemagic.yaml`), which signs it and uploads it
to App Store Connect; the iPhone installs it from TestFlight. That takes a paid Apple Developer Program membership.
Codemagic's free plan has enough build minutes for a few builds a week.

Once, on the web, with nothing to install:

1. In the Apple Developer site, under Certificates, Identifiers & Profiles, register the app's identifier: an
   explicit App ID `io.github.mateusguilherme.segue`, with no extra capabilities.
2. In App Store Connect, create the app with that bundle ID. Its name there has to be unique in the App Store; the
   home screen shows "Segue" whatever it is. In its TestFlight tab, make an internal testing group with yourself in it
   and automatic distribution on, so that each build reaches it.
3. In App Store Connect, under Users and Access > Integrations, make an App Store Connect API key with the App Manager
   role. Its `.p8` file downloads only once; note its Key ID and the Issuer ID.
4. In Codemagic, sign in with GitHub and add this repository. In the team's integrations, add the key under Developer
   Portal, named `segue` (the name `codemagic.yaml` asks for).
5. In Codemagic's code signing identities, generate an Apple Distribution certificate with that key. Then, in the
   Apple Developer site, make an App Store Connect provisioning profile for the App ID with that certificate, and
   fetch it in Codemagic.
6. In the app's environment variables in Codemagic, add `FANART_TV_KEY`, the fanart.tv key (see "Keys"), marked
   secret, in a group named `keys` (the name `codemagic.yaml` asks for: a build fails without that group, though the
   variable may be empty).

Then each build starts from Codemagic's page (workflow "iOS to TestFlight") or by pushing a tag starting with `ios-`:

```sh
git tag ios-1 && git push origin ios-1
```

It takes about 15 minutes, plus Apple's processing. The build then shows in the TestFlight app on the iPhone, from the
internal group's invitation, for 90 days.

Codemagic may report the upload as failed when App Store Connect answers it with server errors (500), even though the
log says `UPLOAD SUCCEEDED`. The build often arrived anyway, so look in App Store Connect's TestFlight tab before
building again. Building the same commit again doesn't help either way: the build number counts the commits, and App
Store Connect refuses a number it already has.

## Releases

`.github/workflows/release.yml` builds the Linux, Android and Windows packages on GitHub's machines, with the scripts of
"Packages", and for a tag `v<version>` puts them in a release of this repository, with their SHA-256 (`SHA256SUMS`). The
tag says pubspec.yaml's version, which the app shows in its settings: for a new one, change `version` there (the build
number after the `+` is the commit count's, whatever it says) and `appVersion` in `lib/server/server.dart`, the one the
app gives the media server, the hub and the services it asks, which the release checks against it, commit, and

```sh
git tag v<version> && git push origin v<version>
```

Run from the Actions tab ("Release", "Run workflow"), it only builds the packages, kept a day as the run's artifacts.
It takes the keys from the repository's secrets (Settings > Secrets and variables > Actions):

- `FANART_TV_KEY`: the fanart.tv key (see "Keys").
- `ANDROID_KEYSTORE`: the app's key, below, in base64 (`base64 -w0 android/release.jks`).
- `ANDROID_KEYSTORE_PASSWORD`: its password.

Android installs an update only when it is signed with the same key as the installed app, so the APKs handed out are
signed with the app's own, `android/release.jks`, not with a debug key, which is one computer's.
`android/key.properties` names it, and git ignores both:

```properties
storeFile=release.jks
storePassword=...
keyAlias=segue
keyPassword=...
```

Where they are, every build is signed with it, the debug one too, so that `flutter run` installs over a released APK
(with another key, it uninstalls the app first). Keep a copy of both away from this computer: with the key lost, no
update installs over the app, and whoever has it has to uninstall it first. It was made once, with a JDK's keytool
(the Android image has one), the password the same twice:

```sh
keytool -genkeypair -keystore android/release.jks -storetype PKCS12 -alias segue -keyalg RSA -keysize 4096 \
  -validity 10000 -dname CN=Segue
```

An APK signed with it has this certificate's SHA-256 (`apksigner verify --print-certs`, in the Android SDK's
build-tools): `b47c9a81410d037b1e3640579fad9acecc552f7d4d5bd7aab94fa1ebcaf8bb31`.

## Keys

The app asks fanart.tv with a key of its own, which isn't in git: a build gets it as it's made, and one without it
shows an artist's biography with the media server's picture alone, and a person where the server has none.
`tool/flutter.sh` gives `run` and `build` (and so `tool/package-linux.sh` and `tool/package-android.sh`) the
`keys.json` at the top of the app's folder, where there is one, which git ignores:

```json
{
  "FANART_TV_KEY": "..."
}
```

With Flutter installed, the same file goes in by hand (`flutter run -d linux --dart-define-from-file=keys.json`), except
in `tool\package-windows.ps1`, which gives it to the build itself. Codemagic takes the key from its environment
variables ("iOS"), and the release workflow from the repository's secrets ("Releases"). A key comes from fanart.tv's
page for one (fanart.tv/get-an-api-key), as a project's.

## Tests

The tests against the hub (`test/hub_test.dart`) run its binary, built from the segue repository (`go build -o
segue-hub ./cmd/segue-hub` in its `hub/`): the one in a clone of segue next to this one (`../segue`), or the one
`SEGUE_HUB_BIN` names. Without it, they are skipped.

## Icons

After changing the artwork (`tool/icon.png`), `DART=1 tool/flutter.sh run tool/icons.dart` makes every icon again:
Android's (adaptive, the TV banner, the notification's), Linux's, iOS's, macOS's, Windows's and the app's own. The
positions of the rounded square and of the ring in the artwork are measured at the top of `tool/icons.dart`, so a new
artwork needs them measured again.

## Screenshots

The README's pictures (`docs/screenshots/`) are of the app on a made-up library, its covers drawn in code:
`tool/flutter.sh test tool/screenshots.dart` makes them again, rendering the app as the widget tests do, with Roboto
from Flutter's own copy, in each device's frame, drawn there too (Android's status and gesture bars on the phone and the
tablet). Each is a PNG, whole, which the page links to, and a WebP at half its width, which the page shows, a tenth as
heavy and as sharp as the page needs on a screen of 2 pixels per point (cwebp, in the dev image). The mixes on the
computer's home, which the app picks at random, are picked there with a seed, so that each run makes the same pictures.

## Code

| Folder | What |
|---|---|
| `lib/server/` | `MediaServer`, what the app asks of the media server in either API; finding out which API a server speaks, and signing in; `PlaylistEditor`, the changes to the user's playlists |
| `lib/subsonic/` | The Subsonic API |
| `lib/jellyfin/` | The Jellyfin API |
| `lib/downloads/` | `Downloads`, what is downloaded to the device, and `ServerWithDownloads`, the media server as the app sees it, the downloads included |
| `lib/segue/` | The Segue protocol in Dart (its `SPEC.md` is in the segue repository), the hub client and hub discovery |
| `lib/player/` | `PlayerController` over an `AudioEngine` (`MediaKitEngine`, libmpv, and `CrossfadeEngine`, on two of them); `MediaControls`, the system's media controls and Android Auto; `AudioInterruptions`, calls and other apps |
| `lib/connect/` | `ConnectController`: which device the app controls, and moving the music between devices |
| `lib/lyrics/` | LRCLIB, and LRC |
| `lib/pictures/` | fanart.tv |
| `lib/releases/` | MusicBrainz, and `AlbumCredits`, the server's credits and MusicBrainz's together |
| `lib/ui/` | The pages and their pieces, by subject (`app/`, `home/`, `album/`, `artist/`, `genre/`, `playlist/`, `song/`, `player/`, `settings/`), and `widgets/`, what several of them use |
| `lib/l10n/` | The app's words in each language, as ARB files |
| `test/` | Unit and widget tests, and tests against the real Go hub (`hub_test.dart`) |
| `tool/` | The Docker images and scripts to build and test without installing Flutter; `icons.dart`, every icon from `icon.png`; `screenshots.dart`, the README's pictures |
| `docs/screenshots/` | The README's pictures, which `tool/screenshots.dart` makes: whole, as PNG, and as the page shows them, as WebP |

`CLAUDE.md` goes into how these fit together.
