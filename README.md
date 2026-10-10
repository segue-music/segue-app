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
  button opens, in groups: the appearance, with the theme and the language, the playback, with the quality, the volume's
  normalization and the equalizer, and about the app, its version and the open source licenses; each choice a line that
  says the option picked and opens a sheet of them all), under the user and the server it signs out of;
- the open source licenses: the app's own, Flutter's and the Dart packages', and, where the app
  brings them (Android, iOS, macOS, Windows), those of libmpv, FFmpeg and Mbed TLS, the native
  libraries it plays with, which Flutter's list leaves out; a package a line, each opening its
  licenses' text;
- a home, where the app opens, with a row of the latest released albums (by release date, or by
  year where the server has no more), one of the albums the user plays most and one of the latest
  added to the library, 30 each, with arrows in each row's corner to go a screenful forward and
  back (on a computer and a TV; on a touch screen a finger drags the row), and a title that opens
  the albums tab in the row's order (on a Jellyfin server, which counts plays only by song, an
  album's plays are its songs', added up), which load again as the home is
  dragged down from its top (with a finger, a touchpad, or on a computer the mouse), each row then from its first
  album; albums (by name, the latest
  released, the most played or the latest added, picked in chips above them, the next ones coming
  as the grid nears its end), artists (by name or the most played first, picked above them, a thumb
  sliding to the one picked: on a Subsonic server, which counts no plays by artist, from the 500
  most played albums; each with their picture, the media server's or, where it has none (on Navidrome, since
  0.64, which before gave its placeholder), the one fanart.tv's users like most, by the artist's MusicBrainz id,
  there too in search, on their page and by their name on an album's; each with their albums or, picked above
  them as the artists' order is, their singles and EPs, where the
  server says which are, and at the end a row of the library's artists like them, each opening their page,
  where the server knows them (Navidrome from Last.fm, Jellyfin by their metadata), their genres, the three
  most of their albums are in, each a link to its page (under how many albums they have; on a phone, over the
  bottom of their picture),
  a button after how many they have that opens their biography, where the
  server has one (Navidrome's comes from Last.fm), on black under their pictures, as a cover full
  screen is, in a gallery: the server's, as wide as the text under it, then up to three more from
  fanart.tv, by the artist's MusicBrainz id, as they come, the next showing a little beside the one in
  the middle, which a swipe, a tap on the one beside, the arrows left and right (a TV remote's too) and, with a
  mouse, arrows over them go through, and for a band, beside its name, in parentheses, the years it has been together, which
  MusicBrainz knows by the artist's MusicBrainz id, where the server has it ("desde 1991", "1966 – 1978"),
  under it, by a pin, where the artist comes from: the place a band formed in, or a person was born in, as
  MusicBrainz names it, and its country, in the app's language ("Boston, Estados Unidos"): at once the one
  MusicBrainz gives the artist, then, where it turns out to be another (one born abroad's), the place's, which
  MusicBrainz says by what the place is part of, a request a level up, and the app keeps for the next launches,
  a link, but on a TV, to it on a map, by its name (on Android in the maps app picked, on an iPhone or a Mac in
  Apple Maps, on another computer OpenStreetMap's, in the browser),
  and, under the biography, a group's members, one a line, with the years they have been in it ("1970 – 1979,
  desde 1984"), those it has now apart from those who have left (all together where it has broken up), the ones
  in the library too, by their MusicBrainz ids, links to their pages,
  under five songs of theirs, numbered, which play from the one picked: the
  ones the user plays most, once any has played (on a Subsonic server, which lists no songs by
  plays, those of the artist's albums, from the albums that have played), or the popular ones, which
  a Subsonic server learns from Last.fm (getTopSongs), picked over them where there are both (a
  thumb sliding to the one picked), and these alone before any of the user's has played),
  genres (by name, each with its number of albums, under the ten the user listens to
  most, and its albums by name, under a row of those the user plays most: on a Subsonic server,
  which counts no plays by genre, both come from the 500 most played albums) and playlists (the
  user's and those shared with them, by name, each with its picture and how many songs it has; its
  page, laid out as an album's, has its picture, how many songs it has and how long they last, a button
  that plays it, and its songs, in its order, each with its cover and its artists, which play the
  playlist from the one picked):
  albums, artists, genres and playlists in a side rail, as icons that name their sections on hover, beside
  them, and the home under the app's icon, in the top bar's left corner (on a phone, the icon goes there
  too, on the home, beside the app's name, Segue Music, and the bar at the bottom has three: the home, the search,
  whose bar shows in it alone, in
  the top bar, over the genres until a search finds something, the keyboard opening only at a tap on it or on the
  search's button again, and a touch elsewhere only closing it, without opening what it touched, and the
  library, whose albums, artists and playlists are tabs in the top bar, opening again on the one picked last; a
  swipe goes from the home to the search and on through the library's tabs, and back);
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
  as it opened, and on a phone a drag down takes them down with the finger, back under the player (full screen, on
  a phone or a tablet, they keep the screen on); a wide bar's lyrics button opens the player with them. The bar stays put from page to page, and on a wide screen under the
  full-screen player too, whose top then leaves the lyrics, the queue and the devices to it, and the
  player the seek bar and the buttons, showing the song alone; on a phone it has them all, the
  lyrics, the devices and the queue in a bar at the bottom, and the album's name at the top, and a
  drag down takes it down with the finger and closes it (let go past a third of the way, or flung), or, with the
  lyrics under it, takes them out, from anywhere but the lyrics, which scroll (taller than the screen, it scrolls to
  its top first); a drag up brings them in with the finger, and with them in, opens them full screen. A swipe on
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
  own (for the keyboard and the remote, each song is one stop), but on a phone, where a finger on the
  song would often land on them, that open from the player only (on an album's or a playlist's page);
- on a wide screen (a computer, a tablet, a TV), the top bar, the side rail and the player bar stay,
  and pages (an album, an artist, a genre, the queue, the full-screen player) open between them, with
  the search bar in the middle of the top bar. Arrows beside the app's icon go back and forward through
  those pages, as a browser's do, and so do the keyboard's left and right (on a phone, left goes back
  from a page with a back arrow). A section, or a search, closes them. On a touch screen, a page with a
  back arrow also goes back with a finger swiped to the right from anywhere on it, the page following the
  finger, rather than only from the screen's edge. An artist's page has their
  picture, round, and behind it the same picture, blurred, across the top of the page. On an album's
  or an artist's page, once the cover or the picture has gone up, the name stays at the top of the
  page, in a bar that comes in as it goes, after the album's play button. Esc takes the focus off
  what has it; in the search bar, it first clears what was typed. The key / goes to the search bar
  (on a phone, to the search), but in a text field, where it types;
- on a phone, the player bar and the sections' bar stay at the bottom, and pages (an album, an
  artist, a genre) open over the rest, each with its own back arrow; a section closes them. An
  album's has its name at the top; an artist's has theirs big, in bold, over the bottom of their
  picture, where it fades into the page, over their genres, and at the top once it has gone up
  there, as the page's color fills the bar; over their picture, the arrow and the system's icons are
  dark over a light picture and light over a dark one, until then. The
  full-screen player and the queue cover everything, and the player's links close it to open their
  page under the bars;
- the queue of whichever device the app controls, from the full-screen player or, on a wide
  screen, the player bar: the current track on top, the next ones under it and what played before
  above it. A tap on a track plays it there. On a device that takes it, a track moves by dragging it,
  from the one on top down (on a touch screen, once held a moment), and goes out of the queue from its
  menu, but for the current one, which plays on either way, wherever it goes. Shuffled, a move changes
  the play order alone, which turning shuffle off forgets. The queue shows the change at once, and on
  another device until its queue comes; one the device refuses goes back, and a message says why;
- songs played next, right after the one that plays, or added at the end of the queue, on whichever
  device the app controls: a song from its menu, an album, all its songs, from the button beside its
  play button, and a playlist from its menu, on its page and in the list of them (a long press, or the
  menu key), another user's too. Shuffled, they still play next, and turning shuffle off puts them where they would
  have gone unshuffled. To an empty queue they are the queue, paused at the first. A message at the
  bottom says so;
- the album's songs and the queue have a header naming their columns: the number ("#") or the
  cover, the title, and the duration as a clock; over the queue it stays as the tracks scroll;
- making and changing playlists: a new one, from a button over the list of them, named in a dialog; a
  song added to one, from its menu (a button after its duration, wherever songs are listed: an album's
  page, an artist's, a playlist's, search; for the keyboard and the remote, which stop at the song
  alone, the menu key or Shift+F10 on it), or an album, all its songs, from the button beside its play
  button, to one of those the user can change, picked in a dialog, or to a new one named there; on the
  page of one the user can change, a song taken out from its menu, a song moved by dragging it (on a
  touch screen, once held a moment), and the playlist renamed or deleted (once asked) from its own
  menu, which in the list of them a long press on it opens too (with a finger or the mouse), or the menu key. Another user's playlist, or one the server makes from rules (Navidrome's smart playlists), as
  OpenSubsonic says, has none of these: its menu only plays it next or adds it to the queue. Each change goes to the server as it's made, one after another,
  and what shows the playlists then loads them again as the server has them; one the server refuses
  says so. On a Subsonic server a song moves as the playlist's songs go back in their new order, which
  a server with OpenSubsonic's formPost (Navidrome) takes in a form's body, rather than in the URL;
- downloads, to listen without the media server: an album or a playlist, from the button beside its
  play button, which shows how far it has got and, once all its songs are on the device, that it is
  downloaded; pressed then, it takes it off the device, once asked. The songs come as their files are,
  or in the quality picked for downloads in the settings (320, 160 or 96 kbps, transcoded by the server
  into one file: on Jellyfin MP3, rather than the HLS it streams), with their covers, their lyrics (the
  server's, or else LRCLIB's), their artists with their pictures (the server's, or else fanart.tv's)
  and what the app shows of them, one at a time while the server is in reach; on a device with mobile
  data, over Wi-Fi or a cable alone, unless the settings let them go over mobile data too (the button
  says it waits). What failed comes again as the server is back, or from the button. A song in several downloads is on the device once. A downloaded song plays from its file and a
  downloaded cover shows from its own, the server in reach or not; a downloaded playlist follows the
  server's as its page shows it. In the library, a chip after the albums' orders ("Baixados") shows the
  downloaded albums alone, the latest first, and one over the playlists ("Baixadas") the downloaded
  playlists; the settings list the downloads, with the room they take, each opening its page and going
  off the device from its own button. With the server out of reach (the app asks it,
  with a short wait, as it opens, and again every 30 s once a request has failed), the top bar says so,
  and the app shows what was downloaded: the home a row of the downloaded albums alone, the library
  their albums, artists and genres and the downloaded playlists, the search them too, and their pages,
  which play from the files, with their lyrics and their artists' pictures; as it is back, it shows the
  whole library again. The hub is then the one last found next to the server, which the app reaches
  once it can. The plays made meanwhile are kept on the device, and counted as the server is back, at
  the time they were made (on Jellyfin, where the hub counts the plays it sees, by marking the song
  played then);
- on the album page, what kind of release it is (an album, an EP, a single or a compilation: on a
  computer above its name, on a phone before its year), which its play button, and the one on its
  cover wherever albums are listed, say too ("Tocar o EP"); under its name, its artist with their
  picture, its year, how many songs it has and how long they last (on a phone, whose line has no
  room for it, that after its songs, under its release date); after its songs, its release
  date, as precisely as the server knows it, and its record labels (OpenSubsonic's; on a Jellyfin
  server, which reads no labels from music files, the album's studios, where someone set them),
  which the keyboard and the remote, coming to the last song, scroll on to. The kind is
  OpenSubsonic's (in Navidrome, the files' MusicBrainz release type, or their compilation tag).
  Where the server says no date (or only the year), no labels or no kind (Jellyfin never says it),
  MusicBrainz (musicbrainz.org) fills them in: by the album's MusicBrainz id, where the server knows
  it, its edition's date and labels and its kind; without it, only the date the album first came
  out and its kind, by its name, artist and year, when these match one album only; after how many
  songs it has and how long they last, a button that opens its credits, on black under its cover, as
  an artist's biography is: who performed it (with what they played or sang, in the app's language
  where it has a name for it), wrote it and produced it, one a line, what they did beside them, with
  the songs they did it on where it isn't all of them ("voz principal, gaita (faixa 2)"), the
  library's artists among them links to their pages. In each of these sections, the server's credits
  (OpenSubsonic's contributors, which Navidrome reads from the files' tags; Jellyfin's people), or,
  where it has none there, MusicBrainz's, by the album's MusicBrainz id: those of its recordings and
  of the works they perform, its tracks matched to the album's songs by their MusicBrainz ids or their
  places. MusicBrainz also says, after who produced it, where it was recorded, and when ("janeiro –
  fevereiro de 1975"), then where it was mixed and mastered ("mixagem, março de 1975"), and, last,
  who made its cover and booklet (art direction, design, illustration, photography, liner notes),
  which the media servers never say;
- at the end of the album page, the artist's other albums in a row, under "Mais de" and their name ("Mais de
  Aerosmith"), which opens their page: their albums, newest first, then their singles and EPs, as their page lists
  them, each with its year and its type where it isn't an album;
- on the album page, a playlist's and in search, the current song (on whichever device the app controls) stands
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
- the quality the songs stream in: the files as they are, as it is until the settings pick another; automatic, on a
  device with mobile data (a phone, a tablet with a SIM: the files as they are on Wi-Fi or a cable, 160 kbps on mobile
  data, as the system says the device is online); or transcoded by the media server down to 320, 160 or 96 kbps. The
  app keeps the one picked, which holds, as a change of connection does, from the next song on. A song a Subsonic server transcodes as it
  goes can't seek, so a seek asks for it again from that point (OpenSubsonic's transcodeOffset, which Navidrome
  has), as does opening on the last playback; a Jellyfin server sends it as HLS, which can seek;
- each song right after the one before, with no gap between them (gapless), as a live album or one whose songs run
  into each other plays: the next song is asked of the media server while the one before plays, however late the
  server answers, in the quality then picked. A song put next while the one before plays, or moved there, is asked as
  it starts, as every song was before;
- the volume's normalization (ReplayGain), so that the songs this device plays play about as loud as one another:
  off, as it is until the settings pick another; automatic (by album where a song plays among its album's, in their
  order, unshuffled; by song otherwise); by song; or by album. The app keeps the one picked, which holds at once, for
  the song that plays too.
  The gains are the media server's, whatever the quality: OpenSubsonic's replayGain, which Navidrome reads from the
  files' tags, or Jellyfin's normalization gain, which it measures itself where a file has no tags (the album's comes
  with each song from Jellyfin 12.0 on, and before that only on the album's page, elsewhere the song's own standing in
  for it). Where the server gives none (a song another device sent, a server without them), the file's own tags, which
  a file as it is has, but not one Jellyfin transcodes. The songs play 8 dB over ReplayGain's reference (89 dB, about
  -18 LUFS), at about -10 LUFS: at the reference most songs of today play 6 to 10 dB quieter than as they are. A gain
  never makes a song clip: no louder than its peak lets it, or, where the server doesn't say its peak, as Jellyfin
  doesn't, no louder than it is;
- an equalizer of ten bands, from 31 Hz to 16 kHz, for the songs this device plays, on its page from the settings:
  off, as it is until it is turned on, a curve made for a kind of music (rock, pop, jazz, classical, electronic,
  hip-hop, voices, more bass, more treble, Android's presets spread over ten bands), or the user's own, by moving the
  bands up and down 12 dB (a double tap takes one back to 0 dB), which the app keeps, and which holds at once, for the song that plays too. The bands never
  make a song clip: with them on, the whole goes down by as much as they raise the frequency they raise most. On a TV,
  the D-pad's up and down move a band once the center button has taken it;

- the system's media controls (through `audio_service`) show and command what the now-playing bar
  shows, the device it follows included: on Linux (MPRIS) the media keys, the desktop's player
  widget and KDE Connect; on iOS (Now Playing) the lock screen, Control Center, headphone buttons
  and CarPlay's Now Playing screen; on Android (its media session) the notification, the lock
  screen and the headphones' buttons, Bluetooth's too, whose play, once the system has closed the
  app, opens it and plays the music where it was;
- on Android, playing in the background and with the screen off, as the media session's
  notification keeps the app running while the music plays; swiped out of the recent apps, the app
  closes, as closing its window does on a computer: the music this device plays stops, paused where it
  was, and opens there again, and another device's plays on;
- on iOS, playing in the background and with the silent switch on; a call pauses the music, which
  plays again after it, and leaving the car or unplugging the headphones pauses it;
- the interface in Portuguese, English or Spanish: the system's language, where the app has it
  (English where it has none of the system's), until the settings (or, before signing in, the
  language menu in the sign-in's corner) pick one, which the app keeps. Dates, numbers of albums and songs, and Material's own words (tooltips, the text
  fields' menu) follow it, and on iOS the local network permission's prompt follows the system's;
- its icon (made by `tool/icons.dart` from `tool/icon.png`): Android's launcher icon, adaptive from
  Android 8 on, the Android TV banner, the ring and the note in white in Android's media notification, on Linux the window's icon and an entry in the application
  menu, the iOS and macOS icons, the Windows icon, and the app's own, in its top bar. The theme,
  light or dark (as the system's, until the settings pick one, or the system's again, which the app
  keeps, the old theme fading into the new one), takes the icon's colors: its pink,
  the deep and the light pink of the ring around the note, and in the dark the black around it, as
  the background. On Linux the window's title bar, with the close button, takes the background too.
  On a computer the window opens maximized.

Not yet: moving a playlist's or the queue's songs with the remote (a TV has no drag), adding the song that plays to a
playlist from the player, the media controls on macOS and Windows, on a Jellyfin server the cover of a song that came from another device
when its file has none of its own (Jellyfin doesn't fall back to the album's) and an artist's popular songs (Jellyfin
knows only its users' plays), sending the music
to speakers and TVs that don't run the app (Google Cast, UPnP/DLNA), and CarPlay as an app of its own (browsing the library
on the car's screen, which needs Apple's CarPlay entitlement and native code). The Android build
has been tried on a tablet and on an Android TV, and the iOS build on an iPhone, with CarPlay's Now Playing screen.

## Code

| Folder | What |
|---|---|
| `lib/server/` | `MediaServer`, what the app asks of the media server in either API, and its albums, artists and songs; finding out which API a server speaks, and signing in to it; `PlaylistEditor`, the changes to the user's playlists |
| `lib/subsonic/` | The Subsonic API: token sign-in, albums, artists, songs, playlists, search, stream and cover URLs |
| `lib/jellyfin/` | The Jellyfin API: sign-in by name for this device, the same library calls, and signing out |
| `lib/downloads/` | `Downloads`, the albums and playlists downloaded to the device, and `ServerWithDownloads`, the media server as the app sees it: downloaded songs and covers from their files, and with the server out of reach, what was downloaded |
| `lib/segue/` | The Segue protocol in Dart (its `SPEC.md` is in the segue repository), the hub client (reconnects by itself) and hub discovery |
| `lib/player/` | `PlayerController` (queue, commands, state reports, each song's ReplayGain, the equalizer) over an `AudioEngine`; `MediaKitEngine` is the real one. `MediaControls`: the system's media controls. `AudioInterruptions`: calls and the like pausing the music, on iOS |
| `lib/connect/` | `ConnectController`: which device the app controls, and moving the music between devices |
| `lib/lyrics/` | LRCLIB (lrclib.net), where lyrics come from when the media server has none, and LRC |
| `lib/pictures/` | fanart.tv, where more pictures of an artist than the media server's one come from, for their biography, and their picture where the server has none |
| `lib/releases/` | MusicBrainz (musicbrainz.org), where an album's release date and record labels come from when the media server doesn't say them, its credits where the server has none, where it was recorded, mixed and mastered, who made its cover, a band's years and members, and where an artist comes from; `AlbumCredits`, the server's credits and MusicBrainz's together, by person |
| `lib/ui/` | The pages: sign-in, home, albums, artists, genres, playlists, album, artist, playlist, search, player bar and full-screen player, queue, device picker |
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
6. In the app's environment variables in Codemagic, add `FANART_TV_KEY`, the fanart.tv key (see
   "Keys"), marked secret, in a group named `keys` (the name `codemagic.yaml` asks for: a build
   fails without that group, though the variable may be empty).

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

## Keys

The app asks fanart.tv with a key of its own, which isn't in git: a build gets it as it's made, and
one without it shows an artist's biography with the media server's picture alone, and a person where
the server has none. `tool/flutter.sh`
gives `run` and `build` (and so `tool/package-linux.sh` and `tool/package-android.sh`) the
`keys.json` at the top of this folder, where there is one, which git ignores:

```json
{
  "FANART_TV_KEY": "..."
}
```

With Flutter installed, the same file goes in by hand: `flutter run -d linux
--dart-define-from-file=keys.json`. Codemagic takes the key from its environment variables
("Running on iOS"). A key comes from fanart.tv's page for one (fanart.tv/get-an-api-key), as a
project's.

## License

MIT, see [LICENSE](LICENSE).
