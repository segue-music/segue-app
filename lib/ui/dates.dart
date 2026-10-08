import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../server/models.dart';

/// [date] as precisely as it is known: "8 de abril de 1975", "abril de 1975", "1975". The month's name is intl's,
/// in the app's language.
String formatDate(AppLocalizations strings, ReleaseDate date) {
  final ReleaseDate(:year, :month, :day) = date;

  if (month == null || month > 12) {
    return '$year';
  }

  final name = _monthName(strings, year, month);
  return switch (day) {
    null => strings.releaseMonth(name, '$year'),
    _ => strings.releaseDay(day, name, '$year'),
  };
}

/// The days from [begin] to [end] (either null where it isn't known), as precisely as suits the span: a day ("21 de
/// julho de 1969"), a month ("julho de 1969"), months of a year ("julho – agosto de 1969"), of several ("setembro de
/// 1995 – março de 1997"), or years; empty where neither is known.
String formatPeriod(AppLocalizations strings, ReleaseDate? begin, ReleaseDate? end) => switch ((begin, end)) {
  (null, null) => '',
  (final date?, null) || (null, final date?) => formatDate(strings, date),
  (final begin?, final end?) when (begin.year, begin.month, begin.day) == (end.year, end.month, end.day) => formatDate(
    strings,
    begin,
  ),
  (ReleaseDate(:final year, month: final int first), ReleaseDate(year: final last, month: final int month))
      when year == last && first <= 12 && month <= 12 =>
    first == month
        ? formatDate(strings, ReleaseDate(year, month: month))
        : strings.datePeriod(_monthName(strings, year, first), formatDate(strings, ReleaseDate(year, month: month))),
  (final begin?, final end?) when begin.year == end.year => '${begin.year}',
  (final begin?, final end?) => strings.datePeriod(
    formatDate(strings, ReleaseDate(begin.year, month: begin.month)),
    formatDate(strings, ReleaseDate(end.year, month: end.month)),
  ),
};

/// The name of the month [month] of [year], intl's, in the app's language: "julho".
String _monthName(AppLocalizations strings, int year, int month) =>
    DateFormat.MMMM(strings.localeName).format(DateTime(year, month));
