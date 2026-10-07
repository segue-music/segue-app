import '../server/models.dart';

/// [type]'s name, as a label by an album's name: "Álbum", "EP", "Single", "Coletânea".
String releaseTypeName(ReleaseType type) => switch (type) {
  ReleaseType.album => 'Álbum',
  ReleaseType.ep => 'EP',
  ReleaseType.single => 'Single',
  ReleaseType.compilation => 'Coletânea',
};

/// An album of [type] as a sentence names it, with its article: "o álbum", "o EP", "o single", "a coletânea". One the
/// server says nothing of (null) is an album.
String albumWithArticle(ReleaseType? type) => switch (type) {
  null || ReleaseType.album => 'o álbum',
  ReleaseType.ep => 'o EP',
  ReleaseType.single => 'o single',
  ReleaseType.compilation => 'a coletânea',
};
