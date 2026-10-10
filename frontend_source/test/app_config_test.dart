import 'package:flutter_test/flutter_test.dart';
import 'package:chalbroo/services/app_config_service.dart';

void main() {
  group('AppConfig.fromMap', () {
    test('a missing document means no restriction at all', () {
      final c = AppConfig.fromMap(null);
      expect(c.maintenanceMode, false);
      expect(c.allowNewRegistrations, true);
      expect(c.minBuildNumber, 0);
      expect(c.priceProblem(1), isNull);
      expect(c.needsUpdate(build: 1, isWeb: false), false);
    });

    test('an empty document is also harmless', () {
      final c = AppConfig.fromMap({});
      expect([c.maintenanceMode, c.allowNewRegistrations, c.minTaskPrice, c.maxTaskPrice], [false, true, 0, 0]);
    });

    test('reads the admin panel\'s fields', () {
      final c = AppConfig.fromMap({
        'maintenanceMode': true,
        'maintenanceMessage': 'Back soon',
        'minBuildNumber': 6,
        'allowNewRegistrations': false,
        'minTaskPrice': 50,
        'maxTaskPrice': 50000,
      });
      expect(c.maintenanceMode, true);
      expect(c.maintenanceMessage, 'Back soon');
      expect(c.minBuildNumber, 6);
      expect(c.allowNewRegistrations, false);
      expect(c.minTaskPrice, 50);
      expect(c.maxTaskPrice, 50000);
    });

    test('numbers stored as text or doubles do not break it', () {
      final c = AppConfig.fromMap({'minBuildNumber': '5', 'minTaskPrice': 49.6, 'maxTaskPrice': 'abc'});
      expect(c.minBuildNumber, 5);
      expect(c.minTaskPrice, 50);
      expect(c.maxTaskPrice, 0);
    });

    test('only an explicit false closes sign-ups', () {
      expect(AppConfig.fromMap({'allowNewRegistrations': false}).allowNewRegistrations, false);
      expect(AppConfig.fromMap({'allowNewRegistrations': null}).allowNewRegistrations, true);
      expect(AppConfig.fromMap({'allowNewRegistrations': 'no'}).allowNewRegistrations, true);
    });
  });

  group('AppConfig.needsUpdate', () {
    const c = AppConfig(minBuildNumber: 6);

    test('older builds are told to update, current and newer are not', () {
      expect(c.needsUpdate(build: 5, isWeb: false), true);
      expect(c.needsUpdate(build: 6, isWeb: false), false);
      expect(c.needsUpdate(build: 7, isWeb: false), false);
    });

    test('an unreadable build number (0) never locks anyone out', () {
      expect(c.needsUpdate(build: 0, isWeb: false), false);
    });

    test('the web version is always the newest, so it is never blocked', () {
      expect(c.needsUpdate(build: 1, isWeb: true), false);
    });

    test('no minimum set means nobody is blocked', () {
      expect(const AppConfig().needsUpdate(build: 1, isWeb: false), false);
    });
  });

  group('AppConfig.priceProblem', () {
    const c = AppConfig(minTaskPrice: 50, maxTaskPrice: 5000);

    test('inside the limits is fine, at the limits is fine', () {
      expect(c.priceProblem(50), isNull);
      expect(c.priceProblem(300), isNull);
      expect(c.priceProblem(5000), isNull);
    });

    test('below the minimum and above the maximum are explained', () {
      expect(c.priceProblem(49), contains('lowest'));
      expect(c.priceProblem(49), contains('50'));
      expect(c.priceProblem(5001), contains('highest'));
      expect(c.priceProblem(5001), contains('5000'));
    });

    test('0 means no limit on that side', () {
      expect(const AppConfig(minTaskPrice: 0, maxTaskPrice: 100).priceProblem(1), isNull);
      expect(const AppConfig(minTaskPrice: 10, maxTaskPrice: 0).priceProblem(1000000), isNull);
    });
  });
}
