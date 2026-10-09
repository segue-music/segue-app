import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How this device's player levels the songs' loudness, so that they play about as loud as one another (ReplayGain):
/// by the gains the media server gives, or else the file's tags.
enum ReplayGainMode {
  /// The songs as they are.
  off,

  /// By album ([album]) where a song plays among its album's, in their order: unshuffled, with the song before or after
  /// it of the same album. By song ([track]) otherwise.
  automatic,

  /// Every song as loud as the others.
  track,

  /// Every album as loud as the others, its songs as loud as they are against one another.
  album,
}

/// How much louder than ReplayGain's reference (89 dB, about -18 LUFS) the songs play levelled, in dB: about -10 LUFS.
/// At the reference itself most songs of today play 6 to 10 dB quieter than as they are. A song still plays no louder
/// than its peak lets it.
const replayGainPreamp = 8.0;

/// How the player levels the songs: the way the user picked, kept across launches (and sign-outs), or, until they pick
/// one, off: the songs as they are. A pick holds at once, for the song that plays too.
class ReplayGainChoice extends ValueNotifier<ReplayGainMode> {
  ReplayGainChoice([super.value = ReplayGainMode.off]);

  static final _prefs = SharedPreferencesAsync();
  static const _key = 'replayGain';

  /// The way picked last; off when none was.
  static Future<ReplayGainChoice> load() async =>
      ReplayGainChoice(ReplayGainMode.values.asNameMap()[await _prefs.getString(_key)] ?? ReplayGainMode.off);

  /// Levels the songs [mode]'s way from now on, and on the next launches.
  Future<void> pick(ReplayGainMode mode) async {
    value = mode;
    await _prefs.setString(_key, mode.name);
  }
}
