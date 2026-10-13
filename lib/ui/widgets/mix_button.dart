import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../l10n/app_localizations.dart';
import '../../mixes.dart';
import '../../server/models.dart';
import '../../services.dart';
import 'errors.dart';
import 'spinner.dart';
import 'themed_icon.dart';

/// Plays [mix], with [first] first: the songs its tile shows. Says why where it can't: a mix without songs, or a radio
/// without any like it, and what failed.
Future<void> playMix(BuildContext context, Mix mix, {List<Song> first = const []}) async {
  final services = ServicesScope.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final strings = AppLocalizations.of(context);

  try {
    final songs = await mix.queue(services.api, first: first);

    // A song's radio has the song itself: none like it, it is none.
    final none = switch (mix) {
      SongRadio() => songs.length < 2,
      _ => songs.isEmpty,
    };

    if (none) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (mix) {
            RandomMix() => strings.mixEmpty,
            RadioMix() => strings.radioEmpty,
          }),
        ),
      );
      return;
    }

    final result = await services.connect.playSongs(songs, 0);

    if (!result.ok) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(strings, result.error))));
    }
  } on Object catch (error) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(switch (mix) {
          RandomMix() => strings.couldNotPlayMix('$error'),
          RadioMix() => strings.couldNotPlayRadio('$error'),
        }),
      ),
    );
  }
}

/// A button that plays [mix], a spinner in its icon's place while its songs come: a genre's mix, an artist's radio.
class MixButton extends StatefulWidget {
  const MixButton(this.mix, {super.key});

  final Mix mix;

  @override
  State<MixButton> createState() => _MixButtonState();
}

class _MixButtonState extends State<MixButton> {
  /// The mix's songs are on their way.
  bool _loading = false;

  Future<void> _play() async {
    // Pressed again meanwhile, nothing: the button stays enabled, so that the focus stays on it.
    if (_loading) {
      return;
    }

    setState(() => _loading = true);
    await playMix(context, widget.mix);

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final mix = widget.mix;

    return FilledButton.tonalIcon(
      onPressed: _play,
      icon: _loading
          ? Spinner(size: 18, strokeWidth: 2, color: Theme.of(context).colorScheme.onSecondaryContainer)
          : ThemedIcon(switch (mix) {
              RandomMix() => HugeIcons.strokeRoundedShuffle,
              RadioMix() => HugeIcons.strokeRoundedRadio,
            }),
      label: Text(switch (mix) {
        RandomMix() => strings.playMix,
        RadioMix() => mixName(strings, mix),
      }),
    );
  }
}
