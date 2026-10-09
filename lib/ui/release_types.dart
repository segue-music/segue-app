import '../l10n/app_localizations.dart';
import '../server/models.dart';

/// [type]'s name, as a label by an album's name: "Álbum", "EP", "Single", "Coletânea".
String releaseTypeName(AppLocalizations strings, ReleaseType type) => switch (type) {
  ReleaseType.album => strings.releaseTypeAlbum,
  ReleaseType.ep => strings.releaseTypeEp,
  ReleaseType.single => strings.releaseTypeSingle,
  ReleaseType.compilation => strings.releaseTypeCompilation,
};

/// [type] as the messages that name an album by its type take it (`playRelease`, `couldNotOpenRelease`, ...), whose
/// words for it differ, as its article does in Portuguese ("o álbum", "a coletânea"). One the server says nothing of
/// (null) is an album.
String releaseSelector(ReleaseType? type) => (type ?? ReleaseType.album).name;

/// [album]'s year, and its type where it isn't an album: "2020 · EP". What goes under its cover where its artist goes
/// without saying, among their albums.
String yearAndReleaseType(AppLocalizations strings, Album album) => [
  if (album.year case final year?) '$year',
  if (album.releaseType case final type? when type != ReleaseType.album) releaseTypeName(strings, type),
].join(' · ');
