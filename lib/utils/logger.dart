import 'dart:developer' as developer;
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Simple logging utility for the update system.
/// Logs to console in debug mode and to file in release mode.
class UpdateLogger {
  static const String _logFileName = 'update_log.txt';

  /// Logs an info message.
  static void info(String message) {
    _log('INFO', message);
  }

  /// Logs a warning message.
  static void warning(String message) {
    _log('WARNING', message);
  }

  /// Logs an error message.
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    _log('ERROR', message);
    if (error != null) {
      _log('ERROR', 'Error: $error');
    }
    if (stackTrace != null) {
      _log('ERROR', 'StackTrace: $stackTrace');
    }
  }

  /// Internal logging method.
  static void _log(String level, String message) {
    final timestamp = DateTime.now().toIso8601String();
    final logMessage = '[$timestamp] [$level] $message';

    developer.log(logMessage, name: 'marschpad');

    // In release mode, also write to file (using kReleaseMode)
    if (const bool.fromEnvironment('dart.vm.product')) {
      _writeToFile(logMessage);
    }
  }

  /// Writes log message to file asynchronously.
  static Future<void> _writeToFile(String message) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_logFileName');
      await file.writeAsString('$message\n', mode: FileMode.append);
    } catch (e) {
      developer.log(
        'Failed to write log to file: $e',
        name: 'marschpad',
        level: 1000,
      );
    }
  }

  /// Clears the log file.
  static Future<void> clearLogs() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_logFileName');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      error('Failed to clear logs', e);
    }
  }
}
