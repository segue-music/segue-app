import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import 'directional_navigation.dart';

/// The letters a long list by name jumps to, in its order: the numbers and the other signs first, as the media servers
/// sort them.
final letters = ['#', ...'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('')];

/// The articles a name is sorted past, as Navidrome's "IgnoredArticles" are by default.
const _articles = ['the', 'el', 'la', 'los', 'las', 'le', 'les', 'os', 'as', 'o', 'a'];

/// Letters with an accent, or joined to another, each sorted with the one in the same place in [_plainLetters].
const _accentedLetters = 'àáâãäåæçèéêëìíîïñòóôõöøœùúûüýÿß';
const _plainLetters = 'aaaaaaaceeeeiiiinooooooouuuuyys';

/// The letter of [letters] [name] is listed under, as the media servers sort names: its first, past an article
/// (Navidrome's), without its accent; '#' for a number or a sign.
String letterOf(String name) {
  var sorted = name.trim().toLowerCase();

  for (final article in _articles) {
    if (sorted.startsWith('$article ') && sorted.length > article.length + 1) {
      sorted = sorted.substring(article.length + 1).trimLeft();
      break;
    }
  }

  if (sorted.isEmpty) {
    return letters.first;
  }

  final first = sorted.substring(0, 1);
  final accented = _accentedLetters.indexOf(first);
  final letter = (accented < 0 ? first : _plainLetters[accented]).toUpperCase();

  return letters.contains(letter) ? letter : letters.first;
}

/// Where the names listed under [letter] start, of those whose letters ([letterOf]) are [listed], in the server's
/// order; where there are none, the next letter's that has some. Each letter's after where the one before starts, so
/// that a name out of its letter's place (one whose article the server sorts it by, which the app leaves out, or the
/// other way round) doesn't take it there. Null where no letter from [letter] on is there: further down a list not all
/// come yet, or at its end.
int? letterStart(List<String> listed, String letter) {
  var from = 0;
  var reached = false;

  for (final each in letters) {
    reached = reached || each == letter;
    final at = listed.indexOf(each, from);

    if (at < 0) {
      continue;
    }

    if (reached) {
      return at;
    }

    from = at;
  }

  return null;
}

/// A long list's letters, beside it, which jump to where each starts ([onLetter]): with thousands of albums, the remote
/// would take long going down a row at a time, and the mouse's wheel too. The letter with the focus, or under the
/// pointer, shows big beside them, in a circle, as Material's ring would hardly show around one so small.
class LetterBar extends StatefulWidget {
  const LetterBar({required this.onLetter, super.key});

  final ValueChanged<String> onLetter;

  /// Whether the long lists by name have their letters beside them where [context] is: on a TV and on a computer. A
  /// finger goes down them fast enough, on a phone or a tablet.
  static bool shownIn(BuildContext context) =>
      DirectionalNavigation.of(context) ||
      switch (defaultTargetPlatform) {
        TargetPlatform.linux || TargetPlatform.macOS || TargetPlatform.windows => true,
        _ => false,
      };

  @override
  State<LetterBar> createState() => _LetterBarState();
}

class _LetterBarState extends State<LetterBar> {
  /// The letter with the focus.
  String? _focused;

  /// The letter under the pointer, which shows rather than the one with the focus.
  String? _hovered;

  static const _width = 36.0;

  /// The circle the letter shown shows big in.
  static const _bubble = 64.0;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final shown = _hovered ?? _focused;
    final style =
        TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: theme.textTheme.labelLarge,
        ).copyWith(
          side: const WidgetStatePropertyAll(BorderSide.none),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.focused) || states.contains(WidgetState.hovered)
                ? colors.primary
                : colors.onSurface,
          ),
        );

    // Under the top bar's last button, the settings': a Material icon button, 40 wide, and 48 where the theme gives
    // what is touched more room (a phone's, a TV's), as far from the screen's edge (a TV's, which it may cut off).
    final button = theme.materialTapTargetSize == MaterialTapTargetSize.padded ? kMinInteractiveDimension : 40.0;

    // As tall as the list, each letter as small as its share of that needs it, and no bigger.
    return Padding(
      padding: EdgeInsets.fromLTRB(0, 8, MediaQuery.paddingOf(context).right + (button - _width) / 2, 8),
      child: SizedBox(
        width: _width,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final share = constraints.maxHeight / letters.length;

            // Right of them is the screen's edge: rather than up to the top bar's last button, nowhere.
            return Shortcuts(
              shortcuts: const {SingleActivator(LogicalKeyboardKey.arrowRight): DoNothingAndStopPropagationIntent()},
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // As wide as the bar, each letter in its middle.
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final letter in letters)
                        Expanded(
                          child: Semantics(
                            label: strings.jumpToLetter(letter),
                            button: true,
                            excludeSemantics: true,
                            child: TextButton(
                              style: style,
                              // The next letter may take the focus, or the pointer, before this one says it lost it.
                              onFocusChange: (on) => setState(() {
                                if (on) {
                                  _focused = letter;
                                } else if (_focused == letter) {
                                  _focused = null;
                                }
                              }),
                              onHover: (on) => setState(() {
                                if (on) {
                                  _hovered = letter;
                                } else if (_hovered == letter) {
                                  _hovered = null;
                                }
                              }),
                              onPressed: () => widget.onLetter(letter),
                              child: FittedBox(fit: BoxFit.scaleDown, child: Text(letter)),
                            ),
                          ),
                        ),
                    ],
                  ),
                  // Over the list beside, at the letter's height.
                  if (shown != null)
                    Positioned(
                      right: _width + 8,
                      top: (letters.indexOf(shown) + 0.5) * share - _bubble / 2,
                      child: IgnorePointer(
                        child: Container(
                          width: _bubble,
                          height: _bubble,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: colors.primary, shape: BoxShape.circle),
                          child: Text(shown, style: theme.textTheme.headlineMedium?.copyWith(color: colors.onPrimary)),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
