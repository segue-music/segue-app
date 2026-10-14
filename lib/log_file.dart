import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// The errors no code caught, which Flutter prints itself ([FlutterError.presentError], the engine): the console has
/// them already, so only the log file takes them.
final _uncaught = Logger('uncaught');

/// Has what the loggers say printed ([printRecord]) and written down in the log file ([LogFile]), with the errors no
/// code caught. Its first line says which build wrote what follows ([packageInfo]). Gives the file, where it could open
/// one.
Future<LogFile?> startLogging(PackageInfo packageInfo) async {
  Logger.root.onRecord.listen((record) {
    if (record.loggerName != _uncaught.name) {
      printRecord(record);
    }
  });

  LogFile? file;

  try {
    file = await LogFile.open(await logDirectory());
    Logger.root.onRecord.listen(file.write);
  } on Object catch (e) {
    Logger('LogFile').warning('no log file', e);
  }

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    _uncaught.severe(details.context?.toDescription() ?? 'Flutter error', details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    _uncaught.severe('uncaught', error, stack);

    // The engine's own then prints it, as it did before.
    return false;
  };

  final system = Platform.operatingSystem;
  final version = Platform.operatingSystemVersion;

  // The system's version, which may start with its name (Linux's "Linux 7.2.10 ..."), or not (iOS's "Version 17.0 ...").
  Logger('Segue').info(
    '${packageInfo.version} (${packageInfo.buildNumber}) on '
    '${version.toLowerCase().startsWith(system) ? version : '$system $version'}',
  );

  return file;
}

/// Where the log file is: the app's support folder, or on Android its folder in the shared storage, which `adb pull`
/// reaches in a release build too (a TV's), where the other is the app's alone.
Future<Directory> logDirectory() async {
  final shared = Platform.isAndroid ? await getExternalStorageDirectory() : null;

  return Directory('${(shared ?? await getApplicationSupportDirectory()).path}/logs');
}

/// Prints [record] on the console, in a line.
void printRecord(LogRecord record) => debugPrint(redacted(_said(record)));

/// What [record] says, after the name of who said it.
String _said(LogRecord record) {
  final error = record.error;

  return '${record.loggerName}: ${record.message}${error == null ? '' : ': $error'}';
}

/// [text] without the credentials it may carry: the media server's addresses (a stream's, a cover's) have Subsonic's
/// token and salt, or an API key, or Jellyfin's token, in their query, which an error may quote, and a request's body
/// (a hello, a TV's sign-in) or Jellyfin's header has them by name. What the log says goes to whoever reads it.
String redacted(String text) => text.replaceAll(_credential, '***');

/// A credential, after what names it: a query's parameter, a JSON field, a field of Jellyfin's `Authorization` header.
final _credential = RegExp(
  r'(?<=[?&](?:t|s|p|apiKey|ApiKey|api_key)=)[^&#\s"]+'
  r'|(?<="(?:token|salt|apiKey|password|Pw|AccessToken)"\s*:\s*")[^"]*'
  r'|(?<=\bToken=")[^"]*',
);

/// [time] as the log has it: to the millisecond, and with its offset from UTC, so that a log read elsewhere, or written
/// where the time zone isn't the reader's, says when.
String logTime(DateTime time) {
  String digits(int number, [int width = 2]) => '$number'.padLeft(width, '0');

  final offset = time.timeZoneOffset;
  final minutes = offset.inMinutes.abs();

  return '${digits(time.year, 4)}-${digits(time.month)}-${digits(time.day)}'
      'T${digits(time.hour)}:${digits(time.minute)}:${digits(time.second)}.${digits(time.millisecond, 3)}'
      '${offset.isNegative ? '-' : '+'}${digits(minutes ~/ 60)}:${digits(minutes % 60)}';
}

/// The app's log, which a problem leaves behind where no console was (a release build, a TV, a phone away from its
/// cable): a line for each record, at its time and level, and its stack trace where it has one, in `segue.log`, which
/// past [limit] bytes becomes `segue.1.log`, the one before going. A record goes straight to the file, through no
/// buffer of the app's, so that an app that aborts right after has written it.
class LogFile {
  LogFile._(this.directory, this.limit, this._file, this._length);

  /// Opens the log in [directory], after what it has.
  static Future<LogFile> open(Directory directory, {int limit = 1 << 20}) async {
    await directory.create(recursive: true);

    final file = await File('${directory.path}/$_name').open(mode: FileMode.append);

    return LogFile._(directory, limit, file, await file.length());
  }

  static const _name = 'segue.log';
  static const _previousName = 'segue.1.log';

  /// Where its files are.
  final Directory directory;

  /// The bytes the file takes before it makes way for a new one.
  final int limit;

  RandomAccessFile? _file;
  int _length;

  /// Writes [record] down, as the loggers' stream gives it.
  void write(LogRecord record) {
    var file = _file;

    if (file == null) {
      return;
    }

    final line = utf8.encode(redacted(_line(record)));

    try {
      if (_length > 0 && _length + line.length > limit) {
        file.closeSync();
        File('${directory.path}/$_name').renameSync('${directory.path}/$_previousName');
        file = _file = File('${directory.path}/$_name').openSync(mode: FileMode.append);
        _length = 0;
      }

      file.writeFromSync(line);
      _length += line.length;
    } on Object {
      // A log that can't be written (a full disk) stops, rather than fail what logged.
      _file = null;
    }
  }

  /// What the log has, the file before first, as one.
  Future<Uint8List> read() async {
    final previous = File('${directory.path}/$_previousName');
    final bytes = BytesBuilder(copy: false);

    if (await previous.exists()) {
      bytes.add(await previous.readAsBytes());
    }

    bytes.add(await File('${directory.path}/$_name').readAsBytes());

    return bytes.takeBytes();
  }

  /// Closes the file, after which what comes goes nowhere.
  Future<void> close() async {
    final file = _file;

    _file = null;
    await file?.close();
  }

  /// [record] as the file has it: its time, its level and what it says, then its stack trace, where it has one.
  static String _line(LogRecord record) {
    final stackTrace = record.stackTrace;
    final line = '${logTime(record.time)} ${record.level.name} ${_said(record)}\n';

    return stackTrace == null ? line : '$line${'$stackTrace'.trimRight()}\n';
  }
}
