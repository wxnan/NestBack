import 'dart:convert';
import 'package:http/http.dart' as http;

class VersionChecker {
  static const String _githubApiUrl = 'https://api.github.com/repos/wxnan/nestback/releases/latest';

  static Future<String?> getLatestVersion() async {
    try {
      final response = await http.get(Uri.parse(_githubApiUrl));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        return data['tag_name']?.toString().replaceFirst('v', '');
      }
    } catch (e) {
      // ignore: avoid_print
      print('Failed to check version: $e');
    }
    return null;
  }

  static int _compareVersions(String version1, String version2) {
    final parts1 = version1.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final parts2 = version2.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final length = parts1.length > parts2.length ? parts1.length : parts2.length;

    for (int i = 0; i < length; i++) {
      final v1 = i < parts1.length ? parts1[i] : 0;
      final v2 = i < parts2.length ? parts2[i] : 0;
      if (v1 > v2) return 1;
      if (v1 < v2) return -1;
    }
    return 0;
  }

  static Future<UpdateResult> checkForUpdate(String currentVersion) async {
    final latestVersion = await getLatestVersion();
    if (latestVersion == null) {
      return UpdateResult(
        hasUpdate: false,
        currentVersion: currentVersion,
        latestVersion: currentVersion,
        error: '无法检查更新',
      );
    }

    final comparison = _compareVersions(latestVersion, currentVersion);
    return UpdateResult(
      hasUpdate: comparison > 0,
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      error: null,
    );
  }
}

class UpdateResult {
  final bool hasUpdate;
  final String currentVersion;
  final String latestVersion;
  final String? error;

  UpdateResult({
    required this.hasUpdate,
    required this.currentVersion,
    required this.latestVersion,
    this.error,
  });
}