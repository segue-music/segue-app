import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:logging/logging.dart';

import '../../l10n/app_localizations.dart';
import '../../mixes.dart';
import '../../server/models.dart';
import '../../services.dart';
import 'errors.dart';
import 'spinner.dart';
import 'themed_icon.dart';

final _log = Logger('MixButton');

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
    _log.warning('mix not played', error);
    messenger.showSnackBar(
      SnackBar(
        content: Text(switch (mix) {
          RandomMix() => strings.couldNotPlayMix(describeFailure(strings, error)),
          RadioMix() => strings.couldNotPlayRadio(describeFailure(strings, error)),
        }),
      ),
    );
  }
}

/// A button that plays [mix], a spinner in its icon's place while its songs come: a genre's mix, an artist's radio.
class MixButton extends StatefulWidget {
  const MixButton(this.mix, {super.key}) : _round = false;

  /// The button round and big, its icon alone, its words in its tooltip: as a music app's play button, at the end of an
  /// artist's name over their picture, on a phone.
  const MixButton.round(this.mix, {super.key}) : _round = true;

  final Mix mix;
  final bool _round;

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
    final colors = Theme.of(context).colorScheme;
    final mix = widget.mix;
    final icon = ThemedIcon(switch (mix) {
      RandomMix() => HugeIcons.strokeRoundedShuffle,
      RadioMix() => HugeIcons.strokeRoundedRadio,
    });
    final label = switch (mix) {
      RandomMix() => strings.playMix,
      RadioMix() => mixName(strings, mix),
    };

    if (widget._round) {
      return IconButton.filled(
        onPressed: _play,
        tooltip: label,
        style: IconButton.styleFrom(minimumSize: const Size.square(48)),
        icon: _loading ? Spinner(size: 20, strokeWidth: 2, color: colors.onPrimary) : icon,
      );
    }

    return FilledButton.tonalIcon(
      onPressed: _play,
      icon: _loading ? Spinner(size: 18, strokeWidth: 2, color: colors.onSecondaryContainer) : icon,
      label: Text(label),
    );
  }
}
