import 'package:flutter_test/flutter_test.dart';
import 'package:segue/subsonic/navidrome_ids.dart';

void main() {
  // The ids and what they become are Navidrome's own tests' (db/migrations/id_canonical_test.go), and its function's
  // answers for the others.
  test('an id becomes the one Navidrome 0.64 gave its item, from each of the shapes ids had before', () {
    expect(canonicalId('5cLJPkLA5DK2BADhoeotPk'), '5cLJPkLA5DK2BADhoeotPk', reason: 'already in 128 bits');
    expect(canonicalId('zzzzzzzzzzzzzzzzzzzzzz'), '3LyqmwQBm5IRqlVjNYASwb', reason: 'too big: its MD5');
    expect(
      canonicalId('Zk3pQ9wX2mN7vB4cL8tR1y'),
      '0IWWbypKFIm1e3Qx4FIlLc',
      reason: 'too big, its MD5 less than 22 digits',
    );
    expect(canonicalId('7N42dgm5tFLK9N8MT7fHC7'), '7N42dgm5tFLK9N8MT7fHC7', reason: '2^128 - 1, the largest that fits');
    expect(canonicalId('7N42dgm5tFLK9N8MT7fHC8'), '4lNKf50OxNrXbwJuGRpSfD', reason: '2^128');
    expect(canonicalId('e3b7fc2ae9447bbec37a13bf916e3cf6'), '6VHl3uR4kss6sUPKA8Cwnk', reason: 'hex, the same value');
    expect(canonicalId('E3B7FC2AE9447BBEC37A13BF916E3CF6'), '6VHl3uR4kss6sUPKA8Cwnk', reason: 'hex in upper case');
    expect(canonicalId('000000000000000000000000000000ff'), '0000000000000000000047', reason: 'zeros first');
    expect(canonicalId('f47ac10b-58cc-4372-a567-0e02b2c3d479'), '7rke2SAWaicSeSYzkhww6R', reason: 'a UUID');
  });

  test('an id of another shape stays as it is', () {
    for (final id in [
      '',
      'aB3xY9kQz1', // a share's
      '0123456789abcdef',
      '!!!!!!!!!!!!!!!!!!!!!!',
      '-zzzzzzzzzzzzzzzzzzzzz',
      '+N42dgm5tFLK9N8MT7fHC8',
      'zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz',
      '000000000000000000000000000000000000',
      'f47ac10b-58cc-4372-a567-0e02b2c3d4-9',
    ]) {
      expect(canonicalId(id), id);
    }
  });

  test('an id made canonical stays as it is made again', () {
    for (final id in [
      'zzzzzzzzzzzzzzzzzzzzzz',
      'e3b7fc2ae9447bbec37a13bf916e3cf6',
      'f47ac10b-58cc-4372-a567-0e02b2c3d479',
    ]) {
      expect(canonicalId(canonicalId(id)), canonicalId(id));
    }
  });

  test('a cover becomes the one of the item\'s new id, with what its picture is', () {
    expect(canonicalCoverId('mf-zzzzzzzzzzzzzzzzzzzzzz_65a1b2c3'), 'mf-3LyqmwQBm5IRqlVjNYASwb_65a1b2c3');
    expect(canonicalCoverId('al-e3b7fc2ae9447bbec37a13bf916e3cf6'), 'al-6VHl3uR4kss6sUPKA8Cwnk');
    expect(
      canonicalCoverId('pl-f47ac10b-58cc-4372-a567-0e02b2c3d479_0'),
      'pl-7rke2SAWaicSeSYzkhww6R_0',
      reason: 'a UUID, whose dashes come after the kind\'s',
    );
    expect(
      canonicalCoverId('dc-e3b7fc2ae9447bbec37a13bf916e3cf6:2_9f86d081884c7d65'),
      'dc-6VHl3uR4kss6sUPKA8Cwnk:2_9f86d081884c7d65',
    );
    expect(canonicalCoverId('zzzzzzzzzzzzzzzzzzzzzz'), '3LyqmwQBm5IRqlVjNYASwb', reason: 'a song\'s own id');
    expect(canonicalCoverId('ar-5cLJPkLA5DK2BADhoeotPk_0'), 'ar-5cLJPkLA5DK2BADhoeotPk_0');
    expect(
      canonicalCoverId('fanart:f47ac10b-58cc-4372-a567-0e02b2c3d479'),
      'fanart:f47ac10b-58cc-4372-a567-0e02b2c3d479',
      reason: 'a picture from elsewhere',
    );
  });

  test('Navidrome gives its items canonical ids from 0.64', () {
    expect(hasCanonicalIds(type: 'navidrome', version: '0.64.0 (1a2b3c4)'), isTrue);
    expect(hasCanonicalIds(type: 'navidrome', version: '0.65.1-SNAPSHOT (1a2b3c4)'), isTrue);
    expect(hasCanonicalIds(type: 'navidrome', version: '1.0.0 (1a2b3c4)'), isTrue);
    expect(hasCanonicalIds(type: 'navidrome', version: '0.63.2 (1a2b3c4)'), isFalse);
    expect(
      hasCanonicalIds(type: 'navidrome', version: 'dev'),
      isFalse,
      reason: 'from when, it can\'t say',
    );
    expect(hasCanonicalIds(type: 'navidrome', version: 'master (1a2b3c4)'), isFalse);
    expect(hasCanonicalIds(type: 'gonic', version: '0.64.0'), isFalse);
    expect(hasCanonicalIds(type: null, version: null), isFalse, reason: 'a server without OpenSubsonic');
  });
}
