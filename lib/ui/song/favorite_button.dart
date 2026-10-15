import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../l10n/app_localizations.dart';
import '../../server/models.dart';
import '../../services.dart';
import '../widgets/errors.dart';
import '../widgets/themed_icon.dart';

/// Hugeicons' heart filled, for a favorite, where the heart alone ([HugeIcons.strokeRoundedFavourite]) is one to make:
/// its outline, filled in its color too. Hugeicons' free icons have only outlines.
final HugeIconData filledHeart = [
  for (final [tag, attributes] in HugeIcons.strokeRoundedFavourite)
    [
      tag,
      {...attributes as Map<String, dynamic>, 'fill': 'currentColor'},
    ],
];

/// Makes the [kind] whose id is [id] one of the user's favorites, or, unless [favorite], no longer one: in the app at
/// once, and on the media server, saying why where it doesn't.
Future<void> setFavorite(BuildContext context, FavoriteKind kind, String id, {required bool favorite}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final strings = AppLocalizations.of(context);

  try {
    await ServicesScope.of(context).favorites.set(kind, id, favorite: favorite);
  } on Object catch (error) {
    messenger?.showSnackBar(SnackBar(content: Text(strings.couldNotChangeFavorites(describeFailure(strings, error)))));
  }
}

/// A heart that makes the [kind] whose id is [id] one of the user's favorites, or no longer one: filled, in the theme's
/// color, while it is one. Its tooltip says what a press does.
class FavoriteButton extends StatelessWidget {
  const FavoriteButton(this.kind, this.id, {this.compact = false, super.key});

  final FavoriteKind kind;
  final String id;

  /// Smaller, as a button beside a line of text is.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final favorites = ServicesScope.of(context).favorites;
    final strings = AppLocalizations.of(context);

    return ListenableBuilder(
      listenable: favorites,
      builder: (context, _) {
        final favorite = favorites.contains(kind, id);

        return IconButton(
          tooltip: favorite ? strings.removeFromFavorites : strings.addToFavorites,
          isSelected: favorite,
          icon: const ThemedIcon(HugeIcons.strokeRoundedFavourite),
          selectedIcon: ThemedIcon(filledHeart),
          visualDensity: compact ? VisualDensity.compact : null,
          onPressed: () => setFavorite(context, kind, id, favorite: !favorite),
        );
      },
    );
  }
}
