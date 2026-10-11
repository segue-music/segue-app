import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/player/audio_interruptions.dart';
import 'package:segue/player/player.dart';
import 'package:segue/server/models.dart';
import 'package:segue/subsonic/api.dart';

import 'fakes.dart';

final api = SubsonicApi(
  Uri.parse('https://music.test'),
  const SubsonicCredentials(username: 'a', token: 't', salt: 's'),
);

const songs = [Song(id: 's1', title: 'One', duration: Duration(minutes: 3))];

void main() {
  late StreamController<AudioInterruptionEvent> interruptions;
  late StreamController<void> becomingNoisy;
  late PlayerController player;
  late AudioInterruptions subject;
  // What was asked of the audio session: true to take the audio, false to give it back.
  late List<bool> activations;
  // Whether Android gives the audio.
  late bool granted;

  // What iOS sends (audio_session's mapping): a beginning of unknown type, then an end that is a
  // pause when the system says to resume, and unknown when it doesn't.
  final began = AudioInterruptionEvent(true, AudioInterruptionType.unknown);
  final endedResume = AudioInterruptionEvent(false, AudioInterruptionType.pause);
  final endedForGood = AudioInterruptionEvent(false, AudioInterruptionType.unknown);
  // What Android sends: the same beginning for the audio taken for good, by another app, with no end; a pause for it
  // taken for a while (a call), and then the end that resumes.
  final lostForAWhile = AudioInterruptionEvent(true, AudioInterruptionType.pause);

  setUp(() async {
    interruptions = StreamController(sync: true);
    becomingNoisy = StreamController(sync: true);
    player = PlayerController(FakeEngine(), api);
    activations = [];
    granted = true;
    subject = AudioInterruptions(
      interruptions.stream,
      becomingNoisy.stream,
      activate: (active) async {
        activations.add(active);

        return granted;
      },
    )..attach(player);
    await player.playQueue(songs);
  });

  test('a call pauses the music, and it plays again after the call', () async {
    interruptions.add(began);
    await pumpEventQueue();
    expect(player.playing, isFalse);

    interruptions.add(endedResume);
    await pumpEventQueue();
    expect(player.playing, isTrue);
  });

  test("an interruption that ends without the system saying to resume leaves it paused", () async {
    interruptions.add(began);
    interruptions.add(endedForGood);
    await pumpEventQueue();
    expect(player.playing, isFalse);
  });

  test('music paused before the interruption stays paused after it', () async {
    await player.pause();
    interruptions.add(began);
    interruptions.add(endedResume);
    await pumpEventQueue();
    expect(player.playing, isFalse);
  });

  test('another app ducking the music leaves it playing', () async {
    interruptions.add(AudioInterruptionEvent(true, AudioInterruptionType.duck));
    await pumpEventQueue();
    expect(player.playing, isTrue);
  });

  test('leaving the car or unplugging the headphones pauses the music', () async {
    becomingNoisy.add(null);
    await pumpEventQueue();
    expect(player.playing, isFalse);
  });

  test('signed out, nothing is attached and the events do nothing', () async {
    subject.attach(null);
    interruptions.add(began);
    becomingNoisy.add(null);
    await pumpEventQueue();
    expect(player.playing, isTrue);
  });

  test('playing takes the audio from the other apps, once as it starts', () async {
    expect(activations, [true]);

    await player.seek(const Duration(seconds: 30));
    await player.pause();
    await player.play();
    await pumpEventQueue();
    expect(activations, [true, true]);
  });

  test('the audio refused, the music pauses and the request is given back', () async {
    await player.pause();
    granted = false;
    await player.play();
    await pumpEventQueue();
    expect(player.playing, isFalse);
    expect(activations, [true, true, false]);
  });

  test('the audio taken for a while, the music plays again when it comes back', () async {
    interruptions.add(lostForAWhile);
    await pumpEventQueue();
    expect(player.playing, isFalse);

    interruptions.add(endedResume);
    await pumpEventQueue();
    expect(player.playing, isTrue);
  });

  test('signed out, the audio is given back', () async {
    subject.attach(null);
    await pumpEventQueue();
    expect(activations, [true, false]);
  });
}
