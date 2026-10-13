import 'dart:convert';

import 'package:crypto/crypto.dart';

// Navidrome 0.64 gave its items new ids. Each is now 22 digits of base 62 holding 128 bits, where some were bigger
// (most of those drawn at random: a playlist's, a song's added since 0.55), or 32 hex digits (a song's or an album's in
// a library older than 0.55), or a playlist's UUID. An id kept from before (a download's, a play held, the last
// playback the hub kept) no longer finds its item: these give the one it has now, as Navidrome's migration did
// (`canonicalID`, in its `db/migrations/20260720015443_uniform_canonical_ids.go`), from the id alone.

/// The id Navidrome 0.64 gives the item it gave [id] before. An id already in that form (as its artists' and albums'
/// were, hashes of their names), or of another shape (a share's), stays as it is.
String canonicalId(String id) {
  switch (id.length) {
    case 22:
      final digits = _base62Digits(id);

      if (digits == null || !_overflows(digits)) {
        return id;
      }

      // A value too big for 128 bits: its MD5 instead, as Navidrome makes ids from names.
      return _encode(md5.convert(utf8.encode(id)).bytes);
    case 32:
      final bytes = _hexBytes(id);

      return bytes == null ? id : _encode(bytes);
    case 36:
      if (id[8] != '-' || id[13] != '-' || id[18] != '-' || id[23] != '-') {
        return id;
      }

      final bytes = _hexBytes(
        id.substring(0, 8) + id.substring(9, 13) + id.substring(14, 18) + id.substring(19, 23) + id.substring(24),
      );

      return bytes == null ? id : _encode(bytes);
  }

  return id;
}

/// The id Navidrome 0.64 gives the cover it gave [id] before. Navidrome's names the item it is of, the kind first
/// (`al-<album>`, `mf-<song>`, `dc-<album>:<disc>`), with what the picture is after an `_`; one may also be the item's
/// own id, as the app gives a song's. Another (`fanart:` and an artist's MusicBrainz id, the downloads') stays as it
/// is.
String canonicalCoverId(String id) {
  final dash = id.indexOf('-');

  if (dash < 0 || !_artworkKinds.contains(id.substring(0, dash))) {
    return canonicalId(id);
  }

  final kind = id.substring(0, dash);
  final rest = id.substring(dash + 1);
  final underscore = rest.indexOf('_');
  final item = underscore < 0 ? rest : rest.substring(0, underscore);
  final picture = underscore < 0 ? '' : rest.substring(underscore);
  // A disc's names its album, then the disc's number.
  final colon = kind == 'dc' ? item.indexOf(':') : -1;

  return colon < 0
      ? '$kind-${canonicalId(item)}$picture'
      : '$kind-${canonicalId(item.substring(0, colon))}${item.substring(colon)}$picture';
}

/// Whether a Subsonic server whose answers say [type] and [version] (OpenSubsonic's `type` and `serverVersion`, as
/// `0.64.2 (1a2b3c4)`) gives its items the ids of [canonicalId]: Navidrome from 0.64. One whose version isn't numbers
/// (`dev`, a build of a branch) is taken for one from before: there an id made canonical would find nothing, a fresh one
/// too, where after it only those kept from before would.
bool hasCanonicalIds({required String? type, required String? version}) {
  if (type != 'navidrome' || version == null) {
    return false;
  }

  final match = RegExp(r'^(\d+)\.(\d+)').firstMatch(version);

  if (match == null) {
    return false;
  }

  final (major, minor) = (int.parse(match[1]!), int.parse(match[2]!));

  return major > 0 || minor >= 64;
}

/// The kinds of Navidrome's covers, as their ids start (its `model/artwork_id.go`): a song's, an artist's, an album's, a
/// playlist's, a disc's, a radio's.
const _artworkKinds = {'mf', 'ar', 'al', 'pl', 'dc', 'ra'};

/// Base 62's digits as Go writes them, which Navidrome's ids are in: the lower case letters before the upper case ones.
const _base62 = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';

/// The largest value 128 bits hold, 2^128 - 1, in 22 such digits.
const _largest = '7N42dgm5tFLK9N8MT7fHC7';

/// The value of each of [id]'s characters as a digit of base 62; null where one isn't.
List<int>? _base62Digits(String id) {
  final digits = [for (final character in id.split('')) _base62.indexOf(character)];

  return digits.contains(-1) ? null : digits;
}

/// Whether 22 [digits] of base 62 hold more than 128 bits: being as many, in the same order as their values, they
/// compare as [_largest]'s do, the first that differs saying which is bigger.
bool _overflows(List<int> digits) {
  for (final (i, digit) in digits.indexed) {
    final largest = _base62.indexOf(_largest[i]);

    if (digit != largest) {
      return digit > largest;
    }
  }

  return false;
}

/// The bytes 32 hex digits are, in either case; null where they aren't.
List<int>? _hexBytes(String hex) => RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(hex)
    ? [for (var i = 0; i < 32; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)]
    : null;

/// 16 [bytes] as an id: their value in 22 digits of base 62, zeros first where it takes fewer.
String _encode(List<int> bytes) {
  var value = bytes.fold(BigInt.zero, (value, byte) => (value << 8) | BigInt.from(byte));
  final base = BigInt.from(62);
  final digits = <String>[];

  while (value > BigInt.zero) {
    digits.add(_base62[(value % base).toInt()]);
    value ~/= base;
  }

  return digits.reversed.join().padLeft(22, '0');
}
