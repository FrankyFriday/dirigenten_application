import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Utility class for platform-specific operations.
class PlatformUtils {
  /// Checks if the current platform is Windows.
  static bool get isWindows => Platform.isWindows;

  /// Checks if the current platform is Android.
  static bool get isAndroid => Platform.isAndroid;

  /// Gets the file extension for the installer based on platform.
  static String getInstallerExtension() {
    if (isWindows) return '.exe';
    if (isAndroid) return '.apk';
    return '';
  }

  /// Gets the download directory path.
  static Future<String> getDownloadPath() async {
    if (isWindows) {
      // Use Downloads folder on Windows
      final home = Platform.environment['USERPROFILE'];
      return '$home\\Downloads';
    } else if (isAndroid) {
      // Use external storage downloads on Android
      final downloads = Directory('/storage/emulated/0/Download');
      if (await downloads.exists()) {
        return downloads.path;
      }
      // Fallback to app documents
      final directory = await getApplicationDocumentsDirectory();
      return directory.path;
    }
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }
}