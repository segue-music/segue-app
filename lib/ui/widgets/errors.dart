import '../../l10n/app_localizations.dart';
import '../../server/server.dart';

/// What an error from a command or a transfer means, in words for the user. The names are the hub's
/// (SPEC.md, section 5) and the players' own; anything else shows as it came.
String describeError(AppLocalizations strings, String? error) => switch (error) {
  'no such track' => strings.errorNoSuchTrack,
  'current track' => strings.errorCurrentTrack,
  'nothing playable' => strings.errorNothingPlayable,
  'offline' => strings.errorOffline,
  'timeout' => strings.errorTimeout,
  'unsupported' => strings.errorUnsupported,
  'notPlayer' => strings.errorNotPlayer,
  'unknownDevice' => strings.errorUnknownDevice,
  'nothingToTransfer' => strings.errorNothingToTransfer,
  'failed' => strings.errorFailed,
  'closed' => strings.errorClosed,
  null => strings.errorUnknown,
  _ => error,
};

/// What [error] says, in the user's language where the app words it itself ([ServerError.reason]); anything else as it
/// came, the media server's own words.
String describeFailure(AppLocalizations strings, Object? error) => switch (error) {
  ServerError(reason: ServerErrorReason.unreachable) => strings.errorServerUnreachable,
  ServerError(reason: ServerErrorReason.signInRefused) => strings.errorSignInRefused,
  ServerError(reason: ServerErrorReason.notAllowed) => strings.errorNotAllowed,
  _ => '$error',
};
