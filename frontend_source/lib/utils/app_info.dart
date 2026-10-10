import 'package:package_info_plus/package_info_plus.dart';

/// The running app's version, read from the platform (so it can never drift from
/// pubspec.yaml). Filled in once at start-up by [AppInfo.init]; until then (or if
/// the platform call fails) it reads 0 / '?', which every consumer treats as
/// "unknown" and never as "too old".
class AppInfo {
  static String version = '?';
  static int build = 0;

  /// `1.0.0+6`
  static String get full => build == 0 ? version : '$version+$build';

  static Future<void> init() async {
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version;
      build = int.tryParse(info.buildNumber) ?? 0;
    } catch (_) {
      // Leave the "unknown" defaults.
    }
  }
}
