import 'package:package_info_plus/package_info_plus.dart';

class AppInfo {
  static PackageInfo? _packageInfo;

  static Future<void> init() async {
    _packageInfo = await PackageInfo.fromPlatform();
  }

  static String get version {
    return _packageInfo?.version ?? '1.0.0';
  }

  static String get buildNumber {
    return _packageInfo?.buildNumber ?? '1';
  }

  static String get versionWithBuild {
    return '$version+$buildNumber';
  }
}