import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/connect/connect.dart';
import 'package:segue/l10n/app_localizations.dart';
import 'package:segue/player/player.dart';
import 'package:segue/server/models.dart';
import 'package:segue/services.dart';
import 'package:segue/session.dart';
import 'package:segue/subsonic/api.dart';
import 'package:segue/ui/shortcuts.dart';

import 'fakes.dart';

void main() {
  late PlayerController player;

  Future<void> pumpApp(WidgetTester tester, Widget page, {bool mediaKeys = false}) async {
    const credentials = SubsonicCredentials(username: 'a', token: 't', salt: 's');
    final api = SubsonicApi(Uri.parse('https://music.test'), credentials);
    player = PlayerController(FakeEngine(), api);
    final services = Services(
      Session(server: Uri.parse('https://music.test'), credentials: credentials, deviceId: 'me', deviceName: 'me'),
      api,
      player,
      ConnectController(player: player),
    );
    await player.playQueue(const [Song(id: 's1', title: 'Dream On'), Song(id: 's2', title: 'Other')]);
    // As in the app: services and shortcuts above the navigator, the page below.
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('pt')],
        builder: (context, child) => ServicesScope(
          services: services,
          child: PlaybackShortcuts(mediaKeys: mediaKeys, child: child!),
        ),
        home: page,
      ),
    );
  }

  testWidgets('space plays and pauses, from any page', (tester) async {
    await pumpApp(tester, const Scaffold(body: Text('library')));
    expect(player.playing, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(player.playing, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(player.playing, isTrue);
  });

  testWidgets('space typed in a text field stays there', (tester) async {
    await pumpApp(tester, const Scaffold(body: TextField(autofocus: true)));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(player.playing, isTrue);
    FocusManager.instance.primaryFocus?.unfocus(); // done typing: space is play/pause again
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(player.playing, isFalse);
  });

  testWidgets('where they come as keys, the media keys play, pause and skip, even while typing', (tester) async {
    await pumpApp(tester, const Scaffold(body: TextField(autofocus: true)), mediaKeys: true);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
    await tester.pump();
    expect(player.playing, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
    await tester.pump();
    expect(player.playing, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaTrackNext);
    await tester.pump();
    expect(player.index, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaTrackPrevious);
    await tester.pump();
    expect(player.index, 0);
  });

  testWidgets('where a system media session takes the media keys, the app leaves them to it', (tester) async {
    await pumpApp(tester, const Scaffold(body: Text('library')));
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
    await tester.pump();
    expect(player.playing, isTrue);
  });

  group('the arrow left', () {
    /// The library, with the shortcuts above the navigator, as in the app. [television] as on a TV.
    Future<void> pumpLibrary(WidgetTester tester, {bool television = false}) => tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('pt')],
        builder: (context, child) => DirectionalNavigation(
          enabled: television,
          child: TextFieldArrowShortcuts(child: BackShortcut(child: child!)),
        ),
        home: const Scaffold(body: Text('library')),
      ),
    );

    Future<void> push(WidgetTester tester, Route<void> route) async {
      unawaited(tester.state<NavigatorState>(find.byType(Navigator)).push(route));
      await tester.pumpAndSettle();
    }

    /// Opens a page as an album's or an artist's opens, with a back arrow in its app bar.
    Future<void> pushPage(WidgetTester tester, {Widget body = const SizedBox()}) => push(
      tester,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('album')),
          body: body,
        ),
      ),
    );

    Future<void> pressLeft(WidgetTester tester) async {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
    }

    testWidgets('goes back from a page with a back arrow, as the arrow does', (tester) async {
      await pumpLibrary(tester);
      await pushPage(tester);
      expect(find.byType(BackButton), findsOneWidget);
      await pressLeft(tester);
      expect(find.text('album'), findsNothing);
      expect(find.text('library'), findsOneWidget);

      // Also with a button of the page focused.
      await pushPage(
        tester,
        body: TextButton(autofocus: true, onPressed: () {}, child: const Text('play')),
      );
      await pressLeft(tester);
      expect(find.text('album'), findsNothing);
    });

    testWidgets('while typing, moves the caret instead', (tester) async {
      final controller = TextEditingController.fromValue(
        const TextEditingValue(text: 'abc', selection: TextSelection.collapsed(offset: 3)),
      );
      addTearDown(controller.dispose);
      await pumpLibrary(tester);
      await pushPage(tester, body: TextField(autofocus: true, controller: controller));
      await pressLeft(tester);
      expect(find.text('album'), findsOneWidget);
      expect(controller.selection, const TextSelection.collapsed(offset: 2));
    });

    testWidgets('leaves the full-screen player and sheets, which have no back arrow, open', (tester) async {
      await pumpLibrary(tester);
      // The full-screen player and the cover, which close with a button of their own and Esc.
      await push(tester, PageRouteBuilder(pageBuilder: (_, _, _) => const Scaffold(body: Text('player'))));
      await pressLeft(tester);
      expect(find.text('player'), findsOneWidget);

      await pushPage(tester);
      unawaited(
        showModalBottomSheet<void>(context: tester.element(find.text('album')), builder: (_) => const Text('devices')),
      );
      await tester.pumpAndSettle();
      await pressLeft(tester);
      expect(find.text('devices'), findsOneWidget);
      expect(find.text('album'), findsOneWidget);
    });

    testWidgets('on a TV, moves the focus, since the remote has a back button of its own', (tester) async {
      await pumpLibrary(tester, television: true);
      await pushPage(
        tester,
        body: Row(
          children: [
            TextButton(onPressed: () {}, child: const Text('play')),
            TextButton(autofocus: true, onPressed: () {}, child: const Text('shuffle')),
          ],
        ),
      );
      await pressLeft(tester);
      expect(find.text('album'), findsOneWidget);
      expect(Focus.of(tester.element(find.text('play'))).hasPrimaryFocus, isTrue);
    });
  });

  group('Esc', () {
    /// [body] as the library, with the shortcuts above the navigator, in the app's order. [television] as on a TV.
    Future<void> pumpPage(WidgetTester tester, Widget body, {bool television = false}) => tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('pt')],
        builder: (context, child) => DirectionalNavigation(
          enabled: television,
          child: UnfocusShortcut(child: BackShortcut(child: child!)),
        ),
        home: Scaffold(body: body),
      ),
    );

    /// Opens a page as an album's or an artist's opens, with a back arrow in its app bar, and [body].
    Future<void> pushPage(WidgetTester tester, Widget body) async {
      unawaited(
        tester
            .state<NavigatorState>(find.byType(Navigator))
            .push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('album')),
                  body: body,
                ),
              ),
            ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> pressEsc(WidgetTester tester) async {
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    }

    testWidgets('goes back from a page with a back arrow, as the arrow does, whatever on the page has the focus', (
      tester,
    ) async {
      await pumpPage(tester, const Text('library'));
      await pushPage(tester, const SizedBox());
      await pressEsc(tester);
      expect(find.text('album'), findsNothing);
      expect(find.text('library'), findsOneWidget);

      await pushPage(tester, TextButton(autofocus: true, onPressed: () {}, child: const Text('play')));
      expect(Focus.of(tester.element(find.text('play'))).hasPrimaryFocus, isTrue);
      await pressEsc(tester);
      expect(find.text('album'), findsNothing, reason: 'back at once, rather than taking the focus off the button');
    });

    testWidgets('in a text field on a page, leaves the field first, and the page then', (tester) async {
      await pumpPage(tester, const Text('library'));
      await pushPage(tester, const TextField(autofocus: true));
      final field = tester.state<EditableTextState>(find.byType(EditableText)).widget.focusNode;
      expect(field.hasFocus, isTrue);
      await pressEsc(tester);
      expect(field.hasFocus, isFalse);
      expect(find.text('album'), findsOneWidget);

      await pressEsc(tester);
      expect(find.text('album'), findsNothing);
    });

    testWidgets('goes back on a TV too, where the D-pad has no Esc to move the focus with', (tester) async {
      await pumpPage(tester, const Text('library'), television: true);
      await pushPage(tester, TextButton(autofocus: true, onPressed: () {}, child: const Text('play')));
      await pressEsc(tester);
      expect(find.text('album'), findsNothing);
    });

    testWidgets('closes a sheet over a page, the page staying', (tester) async {
      await pumpPage(tester, const Text('library'));
      await pushPage(tester, const SizedBox());
      unawaited(
        showModalBottomSheet<void>(context: tester.element(find.text('album')), builder: (_) => const Text('devices')),
      );
      await tester.pumpAndSettle();
      await pressEsc(tester);
      expect(find.text('devices'), findsNothing);
      expect(find.text('album'), findsOneWidget);
    });

    testWidgets('with no page to go back from, takes the focus off what has it, a button or a text field', (
      tester,
    ) async {
      await pumpPage(
        tester,
        Column(
          children: [
            TextButton(autofocus: true, onPressed: () {}, child: const Text('play')),
            const TextField(),
          ],
        ),
      );
      final button = Focus.of(tester.element(find.text('play')));
      expect(button.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(button.hasFocus, isFalse);

      await tester.tap(find.byType(TextField));
      await tester.pump();
      final field = tester.state<EditableTextState>(find.byType(EditableText)).widget.focusNode;
      expect(field.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(field.hasFocus, isFalse);
    });

    testWidgets('with nothing focused, closes a sheet, as ever', (tester) async {
      await pumpPage(tester, const Text('album'));
      unawaited(
        showModalBottomSheet<void>(context: tester.element(find.text('album')), builder: (_) => const Text('devices')),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('devices'), findsNothing);
    });
  });
}
