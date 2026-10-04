import 'package:flutter_test/flutter_test.dart';
import 'package:marschpad/config/app_config.dart';
import 'package:marschpad/services/version_checker.dart';

void main() {
  test('keeps the configured app id and accepts the server canonical id', () {
    expect(AppConfig.appId, 'dirigenten_application');
    expect(AppConfig.matchesServerAppId('dirigenten_app'), isTrue);
  });

  group('VersionChecker', () {
    test('compares numeric version components', () {
      expect(
        VersionChecker.compareVersions('1.10.0', '1.9.0'),
        greaterThan(0),
      );
    });

    test('does not report equal or older releases as newer', () {
      expect(VersionChecker.isNewerVersion('1.2.3', '1.2.3'), isFalse);
      expect(VersionChecker.isNewerVersion('1.2.4', '1.2.3'), isFalse);
      expect(VersionChecker.isNewerVersion('1.2.3', '1.2.4'), isTrue);
    });
  });
}
