import 'package:version/version.dart';

/// Service for comparing semantic versions.
class VersionChecker {
  /// Compares two version strings using semantic versioning.
  /// Returns:
  /// - 1 if version1 > version2
  /// - 0 if version1 == version2
  /// - -1 if version1 < version2
  static int compareVersions(String version1, String version2) {
    try {
      final v1 = Version.parse(version1);
      final v2 = Version.parse(version2);
      return v1.compareTo(v2);
    } catch (e) {
      // If parsing fails, treat as strings
      return version1.compareTo(version2);
    }
  }

  /// Checks if version1 is greater than version2.
  static bool isNewerVersion(String currentVersion, String newVersion) {
    return compareVersions(newVersion, currentVersion) > 0;
  }
}