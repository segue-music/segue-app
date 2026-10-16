# TODO

## The iPhone's own name

Other devices see an iPhone as "iPhone" (an iPad as "iPad"), not by its name in Settings: since
iOS 16, `UIDevice.current.name` gives that name only to an app with Apple's
`com.apple.developer.device-information.user-assigned-device-name` entitlement. The app already asks
for it (`ios/Runner/AppDelegate.swift`); only the entitlement is missing.

1. Requested on 2026-10-16, at https://developer.apple.com/contact/request/user-assigned-device-name/,
   with links to screenshots of the device picker and to a demo video; the answer comes by e-mail.
   Connect fits Apple's criteria: the name shows in the device picker, it identifies the user's own
   devices in a feature across several of them, and it goes only to the user's own media server and
   hub. Its weak point is that Connect needs the hub, where Apple asks for a feature most users have.
2. Once Apple grants it: in the Apple Developer site, turn on "User Assigned Device Name" under the
   App ID's Additional Capabilities, make the App Store provisioning profile again and fetch it
   again in Codemagic.
3. Add `ios/Runner/Runner.entitlements` with the key (`<true/>`) and point the Runner target's
   `CODE_SIGN_ENTITLEMENTS` at it, in its three configurations (Debug, Release, Profile). Not
   before step 2: a profile without the entitlement fails the build's signing.
4. In `README.md`, drop "What iOS does differently"'s item on the name, and add the entitlement to
   "Running on iOS" (step 1 there says "with no extra capabilities").

## From the survey of music apps' features

A survey of the popular music apps (Spotify, Apple Music, YouTube Music, Amazon Music, Deezer, Tidal, Qobuz) and of the
self-hosted clients (Plexamp, Symfonium, Finamp, Feishin, Amperfy, Tempus), on 2026-10-09, with what users ask for and
complain about. What it found the app lacking, as of 2026-10-11, the most worth it first. Its main findings:

- About 79% of what people play starts from their own library (their playlists, albums, search), 14 to 21% from
  autoplay, radios and mixes, and little from editors (Deezer and CNRS, RecSys 2021, 51 million plays of 8,639
  subscribers; Music Ally 2024, 25.3 billion Spotify streams).
- The features with the most evidence of use and of love are the yearly recap (Wrapped 2025: 300 million people),
  synced lyrics (79% of streaming listeners used them, MIDiA 2018), autoplay, and Spotify Connect, the one most often
  named by those who left Spotify and came back.
- The complaints are about control: price, repetitive recommendations, what the algorithm pushes in (Smart Shuffle, the
  talking DJ, podcasts). The loved small features are those that decide what plays next. AI shown off does badly:
  Plexamp took its ChatGPT playlists (Sonic Sage) out in September 2026.
- In 2026 Navidrome's users asked for "a Spotify Connect" (Discussion #5154) and "a Jam" (#5517), which no popular
  client gives. Navidrome's maintainer plans shared listening for a future Navidrome API, and Music Assistant's Sendspin
  is an open multi-room protocol: the gap the app fills won't stay empty.

### A device that leaves the hub

Spotify Connect's commonest complaint is a device missing from the list, and Deezer dropped its Connect in May 2025:
Connect keeps listeners only as long as it is reliable, which weighs more than any new feature. On iOS, a paused app in
the background is suspended, and the hub sees it leave until it opens again (README, "Running on iOS"; SPEC.md,
section 9). Waking it with a push notification is an open question (SPEC.md, section 13). A push goes through the
app's own keys with Apple (APNs) and Google (FCM), which a hub each user runs doesn't have: it would need a relay of
the project's, or another way.

### Listening together

Spotify's Jam has about 50 million people, its top device is the car, and Brazil is among its five largest markets.
Navidrome's users ask for it (#1551, "Shared listening – Radio with friends", 23 votes; #5517, "like Spotify Jams"),
Feishin too (#1159), and Jellyfin has SyncPlay. SPEC.md leaves it out for now (its goals leave out the Jam and "queues
edited by several people"; section 13, "Group playback"): it needs a way out of one device playing at a time (section 4), and the queue as a
state that several people change. The commands that change the queue (play next, add, move, remove) are there now:
the group's queue would build on them. SPEC.md, the hub and the app together.

### A recap of the month and of the year

The recap is the most loved feature with an effect on the business: Wrapped's first day in 2025 was Spotify's largest
day of new subscribers. Apple's Replay is monthly since 2024, Deezer has My Deezer Month (2025), Amazon its Insights.
What people love is the data about themselves: Wrapped 2024, which swapped the data's stories for an AI podcast, was
disliked. A page of stats the whole year round isn't even Spotify's (stats.fm fills it). Neither API gives the plays by
date (OpenSubsonic and Jellyfin give only the last one), but the hub sees every device's: it could keep the history
and give each device the recap of them all, which no client alone can.

### "Don't play this again"

Navidrome's Ideas #3899 (skipping disliked songs, 19 votes), Spotify's taste profile exclusions (October 2025) and its
Hide and Snooze. Autoplay and the mixes would leave those songs out. On Subsonic a rating (`setRating`), on Jellyfin
its own (`likes`), or a list the app keeps.

### CarPlay as an app

Browsing the library on the car's screen, as Android Auto does now (`BrowseTree`): Finamp's most voted issue (#24, 57
votes), and Qobuz rebuilt its own in 2026. It needs Apple's CarPlay audio entitlement
(`com.apple.developer.carplay-audio`), asked for as the device name's is, and native code (README, "Not yet").

### New releases of the library's artists

Spotify's Release Radar, Tidal's My New Arrivals, Navidrome #5106. The home has the library's latest albums; MusicBrainz
(which the app already asks, by the artist's MusicBrainz id) also says those the library lacks, on the artist's page
or in a row of the home. They can't play, so they would link to MusicBrainz.

### More mixes

The home's mixes are by genre and by decade. Others the survey found loved: songs the user hasn't played in a long
time ("rediscovering their own collection" is why many leave Spotify for their own server), Spotify's daylist (70% come
back every week), Plexamp's Time Travel radio, and Deezer's Flow Tuner (February 2026: the user turns genres on and
off and edits what comes next), which shows what listeners want of a radio: control over it.

### Cast and DLNA

Finamp #50 (27 votes), Amperfy #277, Tempus #46. Navidrome closed native Chromecast and UPnP/DLNA as not planned (#250,
#305), which leaves them to the clients; Feishin got DLNA in 2026. Postponed on 2026-10-10, before picking where it
goes: a bridge in the hub's repository (SPEC.md, section 11) that lists each renderer as a device, or the app casting
with the phone serving the streams.

### Word-synced lyrics, and translated

Lyrics are now word by word (Apple's Sing, Qobuz's player of July 2026) and translated (Spotify, Apple in iOS 26).
OpenSubsonic's lyrics have words' timings since Navidrome 0.63; a translation needs a service of its own.

### A person's page

Tidal's credits list everything a producer or musician did, by role, and Spotify's SongDNA (credits, samples, covers)
had 265 million interactions between March and May 2026. The album's credits link only to the library's artists: a page of all the
songs someone played on, wrote or produced in the library, and their mix, where the server lists songs by contributor
(OpenSubsonic's contributors, Jellyfin's people).

### Sonic similarity

Navidrome #4332 (similarity and automatic playlists, 47 votes), Plexamp's Sonic Adventure (a path of songs between
two). Only where the server has it: Navidrome's plugins (AudioMuse-AI) and OpenSubsonic's `sonicSimilarity` (0.62).

### Smaller ones

- The file's format, bit depth and sample rate in the player, as Qobuz's player of 2026 shows them (OpenSubsonic's
  song has them, Jellyfin's media streams too): audiophiles pick a service by them.
- On a touch screen, a swipe on a song's line to play it next (Spotify's Swipe to Queue was greeted as Spotify
  "finally" listening), and picking several songs of the queue at once (back in Spotify in May 2026).
- A seek bar of the song's waveform, as SoundCloud's, Supersonic's and Feishin's.
- An album's booklet and its other images (Navidrome #2551, 18 votes, and #5591; Qobuz's booklets), once the server
  gives them.
- Music outside the library: artists like an artist's that it lacks, ListenBrainz's daily playlists (which Navidrome
  0.60's plugin imports as playlists). The one thing those who leave Spotify miss most, which a library can't replace:
  linking to it, not copying it.

### Left out on purpose

A talking DJ, playlists from a prompt, videos, podcasts, messages, Canvas: little use where they were measured (14% of
those who got Spotify's prompted playlists), complaints of a cluttered app, and Plexamp took its own out.

## From Spotube

Spotube (`team-spotube/spotube`, 5.1.2), a player in Flutter, takes its catalog from metadata plugins (an unofficial
Spotify one, through the web player's internal API; MusicBrainz and ListenBrainz) and its audio from audio-source
plugins (YouTube's, searched for each track). Looked at on 2026-10-11 for what the app could take from it. Its Connect
has nothing the protocol lacks but working without a hub, over the local network, which is left out (SPEC.md's hub signs
devices in with the media server).

### Playlists from other services

Spotube finds each track's audio by its ISRC, else by its title and artists, ranks what it found (the title has the
track's name, the channel is the artist), keeps the match, and lets the user swap a wrong one for another of the
results. The same, aimed at the library rather than YouTube, brings in a playlist from elsewhere: each track searched
for by title and artist, and confirmed by its ISRC or MusicBrainz id where the server gives them (OpenSubsonic's song
has both), else by its length; the match kept, and correctable; the playlist made through `PlaylistEditor`, with what
the library lacks listed. From a file exported (Exportify's CSV, JSPF, M3U) or from ListenBrainz. What Spotify's public
API still lets a new app read wasn't checked.

### ListenBrainz's recommendations as mixes

Spotube's MusicBrainz and ListenBrainz plugin makes radios of the user's top artists (LB Radio), playlists by mood, and
shows the playlists ListenBrainz makes for each user (Weekly Jams, Weekly Exploration). Navidrome already sends the
plays to ListenBrainz. Matched to the library as above, by the user's ListenBrainz name, they would be more `Mix`es
(`lib/mixes.dart`), of the songs the library has. Navidrome 0.60's plugin imports the daily ones as playlists ("Smaller
ones", above), on that server only.

### A queue edit that checks its track

Spotube takes a track out of the queue by its id. SPEC.md's `moveInQueue` and `removeFromQueue` go by its place, which
the queue page keeps right for its own edits (`_QueueChange`, and the commands arrive in order), but two controllers
editing one queue at once can hit the wrong track. An optional `id` in both, which the player checks against the track
at `index`, failing where it differs, would close that; an id alone, as Spotube's, can't tell apart a song that is twice
in the queue. SPEC.md, the hub and the app together. Not urgent.

### Left out on purpose

A mode without a media server, streaming as Spotube does (Spotify's catalog, YouTube's audio). The App Store's
guideline 5.2.3 forbids playing or downloading media of third parties (YouTube by name) without their leave, so the
whole app would be refused, not the mode: Spotube is on iOS only as an IPA to sideload. The hub signs devices in with
the media server, and the queue's ids are the server's (SPEC.md, sections 2 and 8), so Connect would need another
sign-in and other ids. And both sides are reverse-engineered, to be chased as they change: the Spotify plugin's token
needs a TOTP secret that Spotify versions, and YouTube changes the JavaScript challenges a stream's address needs.

## Asking Lidarr or SoulSync for what the library lacks

Following an artist or wanting an album now takes leaving for the service's own pages. The app could offer both where
the user already is, sending them on: on an artist's page, a button that follows the artist (the watchlist), and in the discography the
albums the library lacks (MusicBrainz's release groups, by the artist's MusicBrainz id, as in "New releases of the
library's artists" above), each with a button that wants it (the wishlist); and a page of the requests, with the artists
followed, the albums wanted and what is downloading. Searching for the files, their sources and their quality stay the
service's. Looked at on 2026-10-11.

- Behind an interface with one implementation for each service, as `MediaServer` has `SubsonicApi` and `JellyfinApi`,
  in MusicBrainz's terms, which the app already speaks (Navidrome's and Jellyfin's ids, `lib/releases/musicbrainz.dart`).
- Lidarr first: its API (`/api/v1`, the key in `X-Api-Key`) goes by MusicBrainz ids (the artist's, the release
  group's); its monitored artists are the watchlist, its wanted (missing) albums the wishlist, its queue the downloads.
  Soulseek, where that is why SoulSync is used, comes to Lidarr through a plugin (Tubifarry, by slskd) or Soularr (not
  checked).
- SoulSync's API (`/api/v1`, 87 endpoints, a `Bearer` key; `Support/API.md` in `Nezreka/SoulSync`) doesn't fit yet:
  its wishlist takes one track at a time, with Spotify's data (`spotify_track_data`), its watchlist takes Spotify's or
  iTunes's artist ids, and nothing gives an artist's albums or an album's tracks from outside the library. The app would
  find each by its name in Spotify's terms, which breaks easily, and the API changes from one version to the next. To
  ask its author for, or to contribute: an album wanted at once, and MusicBrainz ids.
- From the app, with the service's address and key in the settings, not through the hub: it isn't Connect's. Either
  service's key can do anything to it, so this fits a server of one user, or only the user who sets the key; a server
  several people use would need something between them that holds the key.
