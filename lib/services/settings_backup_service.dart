import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:drift/drift.dart';
import 'package:encrypt/encrypt.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;
import '../database/database.dart';

class SettingsBackupService {
  final AppDatabase _db;

  /// 设置备份的远程子目录名
  static const String settingsFolderName = '设置';

  SettingsBackupService(this._db);

  /// 导出所有设置为 JSON 字符串
  Future<String> exportSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final data = <String, dynamic>{};

    // 版本号
    data['version'] = 1;
    data['exportTime'] = DateTime.now().toIso8601String();

    // 扫码设置
    data['barcode'] = {
      'provider': prefs.getString('barcode_api_provider') ?? 'apizero',
      'apiKeyApizero': prefs.getString('barcode_api_key_apizero') ?? '',
      'apiKeyApizeroPro': prefs.getString('barcode_api_key_apizero_pro') ?? '',
      'apiKeyApibyte': prefs.getString('barcode_api_key_apibyte') ?? '',
      'apiKeyRollapi': prefs.getString('barcode_api_key_rollapi') ?? '',
    };

    // AI 设置 - 提供商
    final providers = await (_db.select(_db.aiProviders)
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
    data['aiProviders'] = providers.map((p) => {
      'id': p.id,
      'name': p.name,
      'apiBaseUrl': p.apiBaseUrl,
      'apiPath': p.apiPath,
      'apiKey': p.apiKey,
      'builtInApiKey': p.builtInApiKey,
      'customHeaders': p.customHeaders,
      'isBuiltIn': p.isBuiltIn,
      'isEnabled': p.isEnabled,
      'rateLimit': p.rateLimit,
      'registerUrl': p.registerUrl,
      'freeQuota': p.freeQuota,
      'sortOrder': p.sortOrder,
    }).toList();

    // AI 设置 - 模型
    final models = await (_db.select(_db.aiModels)
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
    data['aiModels'] = models.map((m) => {
      'id': m.id,
      'providerId': m.providerId,
      'modelId': m.modelId,
      'name': m.name,
      'type': m.type,
      'isBuiltIn': m.isBuiltIn,
      'isEnabled': m.isEnabled,
      'sortOrder': m.sortOrder,
    }).toList();

    // AI 设置 - 默认模型
    data['aiDefaults'] = {
      'defaultChatModelId': prefs.getString('default_chat_model_id') ?? '',
      'defaultVisionModelId': prefs.getString('default_vision_model_id') ?? '',
    };

    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// 导入设置从 JSON 字符串，返回 (success, message)
  Future<(bool, String)> importSettings(String jsonStr) async {
    try {
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      // 导入扫码设置
      if (data.containsKey('barcode')) {
        final barcode = data['barcode'] as Map<String, dynamic>;
        final prefs = await SharedPreferences.getInstance();
        if (barcode.containsKey('provider')) {
          await prefs.setString('barcode_api_provider', barcode['provider'] as String);
        }
        if (barcode.containsKey('apiKeyApizero')) {
          await prefs.setString('barcode_api_key_apizero', barcode['apiKeyApizero'] as String);
        }
        if (barcode.containsKey('apiKeyApizeroPro')) {
          await prefs.setString('barcode_api_key_apizero_pro', barcode['apiKeyApizeroPro'] as String);
        }
        if (barcode.containsKey('apiKeyApibyte')) {
          await prefs.setString('barcode_api_key_apibyte', barcode['apiKeyApibyte'] as String);
        }
        if (barcode.containsKey('apiKeyRollapi')) {
          await prefs.setString('barcode_api_key_rollapi', barcode['apiKeyRollapi'] as String);
        }
      }

      // 导入 AI 提供商 - 按 name 匹配，更新已有或新增
      if (data.containsKey('aiProviders')) {
        final providerList = data['aiProviders'] as List<dynamic>;
        final existingProviders = await (_db.select(_db.aiProviders)).get();
        final existingByName = {for (var p in existingProviders) p.name: p};

        for (final pData in providerList) {
          final pMap = pData as Map<String, dynamic>;
          final name = pMap['name'] as String;

          if (existingByName.containsKey(name)) {
            final existing = existingByName[name]!;
            await (_db.update(_db.aiProviders)).replace(AiProvidersCompanion(
              id: Value(existing.id),
              name: Value(name),
              apiBaseUrl: Value(pMap['apiBaseUrl'] as String),
              apiPath: Value(pMap['apiPath'] as String? ?? '/chat/completions'),
              apiKey: Value(pMap['apiKey'] as String? ?? ''),
              builtInApiKey: Value(pMap['builtInApiKey'] as String? ?? ''),
              customHeaders: Value(pMap['customHeaders'] as String? ?? '{}'),
              isBuiltIn: Value(pMap['isBuiltIn'] as bool? ?? false),
              isEnabled: Value(pMap['isEnabled'] as bool? ?? false),
              // 提供商信息以本地为准
              rateLimit: Value(existing.rateLimit),
              registerUrl: Value(existing.registerUrl),
              freeQuota: Value(existing.freeQuota),
              sortOrder: Value(pMap['sortOrder'] as int? ?? 0),
              createdAt: Value(existing.createdAt),
              updatedAt: Value(DateTime.now()),
            ));
          } else {
            await _db.into(_db.aiProviders).insert(AiProvidersCompanion.insert(
              id: pMap['id'] as String,
              name: name,
              apiBaseUrl: pMap['apiBaseUrl'] as String,
              apiPath: Value(pMap['apiPath'] as String? ?? '/chat/completions'),
              apiKey: Value(pMap['apiKey'] as String? ?? ''),
              builtInApiKey: Value(pMap['builtInApiKey'] as String? ?? ''),
              customHeaders: Value(pMap['customHeaders'] as String? ?? '{}'),
              isBuiltIn: Value(pMap['isBuiltIn'] as bool? ?? false),
              isEnabled: Value(pMap['isEnabled'] as bool? ?? false),
              rateLimit: Value(pMap['rateLimit'] as String?),
              registerUrl: Value(pMap['registerUrl'] as String?),
              freeQuota: Value(pMap['freeQuota'] as String?),
              sortOrder: Value(pMap['sortOrder'] as int? ?? 0),
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ));
          }
        }
      }

      // 导入 AI 模型 - 按 providerId + modelId 匹配
      if (data.containsKey('aiModels')) {
        final modelList = data['aiModels'] as List<dynamic>;
        final existingModels = await (_db.select(_db.aiModels)).get();
        final existingByKey = {for (var m in existingModels) '${m.providerId}_${m.modelId}': m};

        final existingProviders = await (_db.select(_db.aiProviders)).get();
        final providerIdMap = <String, String>{};
        for (final ep in existingProviders) {
          providerIdMap[ep.id] = ep.id;
        }
        final providerByName = {for (var p in existingProviders) p.name: p};
        if (data.containsKey('aiProviders')) {
          for (final pData in data['aiProviders'] as List<dynamic>) {
            final pMap = pData as Map<String, dynamic>;
            final oldId = pMap['id'] as String;
            final name = pMap['name'] as String;
            if (providerByName.containsKey(name)) {
              providerIdMap[oldId] = providerByName[name]!.id;
            }
          }
        }

        for (final mData in modelList) {
          final mMap = mData as Map<String, dynamic>;
          final oldProviderId = mMap['providerId'] as String;
          final currentProviderId = providerIdMap[oldProviderId] ?? oldProviderId;
          final modelId = mMap['modelId'] as String;
          final key = '${currentProviderId}_$modelId';

          if (existingByKey.containsKey(key)) {
            // 更新已有模型 - 删除旧的，插入新的（使用备份中的 ID）
            final existing = existingByKey[key]!;
            await (_db.delete(_db.aiModels)..where((t) => t.id.equals(existing.id))).go();
            await _db.into(_db.aiModels).insert(AiModelsCompanion.insert(
              id: mMap['id'] as String,
              providerId: currentProviderId,
              modelId: modelId,
              name: mMap['name'] as String,
              type: Value(mMap['type'] as String? ?? 'chat'),
              isBuiltIn: Value(mMap['isBuiltIn'] as bool? ?? false),
              isEnabled: Value(mMap['isEnabled'] as bool? ?? true),
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ));
          } else {
            await _db.into(_db.aiModels).insert(AiModelsCompanion.insert(
              id: mMap['id'] as String,
              providerId: currentProviderId,
              modelId: modelId,
              name: mMap['name'] as String,
              type: Value(mMap['type'] as String? ?? 'chat'),
              isBuiltIn: Value(mMap['isBuiltIn'] as bool? ?? false),
              isEnabled: Value(mMap['isEnabled'] as bool? ?? true),
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ));
          }
        }
      }

      // 导入 AI 默认模型设置
      if (data.containsKey('aiDefaults')) {
        final aiDefaults = data['aiDefaults'] as Map<String, dynamic>;
        final prefs = await SharedPreferences.getInstance();
        final chatModelId = aiDefaults['defaultChatModelId'] as String? ?? '';
        final visionModelId = aiDefaults['defaultVisionModelId'] as String? ?? '';
        if (chatModelId.isNotEmpty) {
          await prefs.setString('default_chat_model_id', chatModelId);
        }
        if (visionModelId.isNotEmpty) {
          await prefs.setString('default_vision_model_id', visionModelId);
        }
      }

      return (true, '设置已恢复');
    } catch (e) {
      return (false, '导入失败：$e');
    }
  }

  /// 生成设置 ZIP 文件的本地路径
  Future<String> _createSettingsZip() async {
    final jsonStr = await exportSettings();
    final timestamp = _formatTimestamp(DateTime.now());

    // 创建 ZIP
    final archive = Archive();
    final jsonBytes = utf8.encode(jsonStr);
    archive.addFile(ArchiveFile('settings.json', jsonBytes.length, jsonBytes));

    final zipData = ZipEncoder().encode(archive);

    final tempDir = await getTemporaryDirectory();
    final zipPath = p.join(tempDir.path, 'settings_$timestamp.zip');
    await File(zipPath).writeAsBytes(zipData);

    return zipPath;
  }

  /// 从 ZIP 文件中读取 settings.json 并导入
  Future<(bool, String)> _importFromZip(String zipPath) async {
    final zipBytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(zipBytes);

    String? jsonStr;
    for (final file in archive) {
      if (file.name == 'settings.json') {
        // 使用 UTF-8 解码，避免乱码问题
        final content = file.content as List<int>;
        jsonStr = utf8.decode(content);
        break;
      }
    }

    if (jsonStr == null) {
      return (false, 'ZIP 文件中未找到 settings.json');
    }

    return importSettings(jsonStr);
  }

  /// 备份设置到 WebDAV（ZIP 格式，存入"设置"子目录）
  Future<void> backupSettingsToWebDav({
    required String serverUrl,
    required String username,
    required String password,
    required String remotePath,
    String? encryptionKey,
  }) async {
    final client = webdav.newClient(
      serverUrl,
      user: username,
      password: password,
      debug: false,
    );
    client.setHeaders({'accept-encoding': 'gzip'});

    // 设置备份子目录
    final settingsPath = p.join(remotePath, settingsFolderName).replaceAll('\\', '/');

    // 确保远程路径存在
    try {
      await client.readDir(settingsPath);
    } catch (_) {
      await client.mkdir(settingsPath);
    }

    // 生成 ZIP
    final zipPath = await _createSettingsZip();
    final zipFile = File(zipPath);
    List<int> bytes = await zipFile.readAsBytes();

    // 可选加密
    if (encryptionKey != null && encryptionKey.isNotEmpty) {
      bytes = _encryptData(bytes, encryptionKey);
    }

    // 生成文件名
    final timestamp = _formatTimestamp(DateTime.now());
    final suffix = (encryptionKey != null && encryptionKey.isNotEmpty) ? '.zip.enc' : '.zip';
    final fileName = 'settings_$timestamp$suffix';
    final remoteFilePath = p.join(settingsPath, fileName).replaceAll('\\', '/');

    // 写入临时文件后上传
    final tempDir = await getTemporaryDirectory();
    final tempPath = p.join(tempDir.path, fileName);
    await File(tempPath).writeAsBytes(bytes);

    try {
      await client.writeFromFile(tempPath, remoteFilePath);
    } finally {
      try {
        await File(tempPath).delete();
      } catch (_) {}
      try {
        await zipFile.delete();
      } catch (_) {}
    }
  }

  /// 从 WebDAV 列出设置备份（从"设置"子目录）
  Future<List<SettingsBackupInfo>> listSettingsBackups({
    required String serverUrl,
    required String username,
    required String password,
    required String remotePath,
  }) async {
    final client = webdav.newClient(
      serverUrl,
      user: username,
      password: password,
      debug: false,
    );
    client.setHeaders({'accept-encoding': 'gzip'});

    final settingsPath = p.join(remotePath, settingsFolderName).replaceAll('\\', '/');

    try {
      final files = await client.readDir(settingsPath);
      final backups = <SettingsBackupInfo>[];

      for (final file in files) {
        final name = file.name ?? '';
        if (name.startsWith('settings_') && (name.endsWith('.zip') || name.endsWith('.zip.enc'))) {
          final isEncrypted = name.endsWith('.enc');
          final path = file.path ?? '$settingsPath/$name';
          final size = file.size ?? 0;
          final modified = file.mTime ?? DateTime.now();

          backups.add(SettingsBackupInfo(
            name: name,
            path: path,
            size: size,
            modifiedTime: modified,
            isEncrypted: isEncrypted,
          ));
        }
      }

      backups.sort((a, b) => b.modifiedTime.compareTo(a.modifiedTime));
      return backups;
    } catch (e) {
      throw Exception('获取备份列表失败：$e');
    }
  }

  /// 从 WebDAV 恢复设置
  Future<(bool, String)> restoreSettingsFromWebDav({
    required String serverUrl,
    required String username,
    required String password,
    required String remoteFilePath,
    String? encryptionKey,
  }) async {
    final client = webdav.newClient(
      serverUrl,
      user: username,
      password: password,
      debug: false,
    );
    client.setHeaders({'accept-encoding': 'gzip'});

    final bytes = await client.read(remoteFilePath);

    // 根据文件扩展名判断是否加密
    final isEncrypted = remoteFilePath.endsWith('.zip.enc');

    try {
      List<int> zipBytes;
      if (isEncrypted) {
        if (encryptionKey == null || encryptionKey.isEmpty) {
          return (false, '备份文件已加密，请提供加密密钥');
        }
        // 解密
        try {
          zipBytes = _decryptData(bytes, encryptionKey);
        } catch (e) {
          return (false, '解密失败：$e');
        }
      } else {
        zipBytes = bytes;
      }

      final tempDir = await getTemporaryDirectory();
      final tempFileName = p.basename(remoteFilePath);
      final decryptedZipPath = p.join(tempDir.path, 'decrypted_${tempFileName.replaceAll('.enc', '')}');
      await File(decryptedZipPath).writeAsBytes(zipBytes);

      try {
        return await _importFromZip(decryptedZipPath);
      } finally {
        try {
          await File(decryptedZipPath).delete();
        } catch (_) {}
      }
    } catch (e) {
      return (false, '恢复失败：$e');
    }
  }

  /// 删除 WebDAV 上的设置备份
  Future<void> deleteSettingsBackup({
    required String serverUrl,
    required String username,
    required String password,
    required String remoteFilePath,
  }) async {
    final client = webdav.newClient(
      serverUrl,
      user: username,
      password: password,
      debug: false,
    );
    client.setHeaders({'accept-encoding': 'gzip'});
    await client.remove(remoteFilePath);
  }

  /// AES-CBC 加密
  List<int> _encryptData(List<int> data, String key) {
    final keyBytes = Uint8List.fromList(utf8.encode(key.padRight(32, '0').substring(0, 32)));
    final iv = IV.fromSecureRandom(16);
    final encrypter = Encrypter(AES(Key(keyBytes), mode: AESMode.cbc));
    final encrypted = encrypter.encryptBytes(Uint8List.fromList(data), iv: iv);
    return [...iv.bytes, ...encrypted.bytes];
  }

  /// AES-CBC 解密
  List<int> _decryptData(List<int> data, String key) {
    if (data.length < 17) {
      throw Exception('无效的加密数据');
    }
    final keyBytes = Uint8List.fromList(utf8.encode(key.padRight(32, '0').substring(0, 32)));
    final ivBytes = Uint8List.fromList(data.sublist(0, 16));
    final iv = IV(ivBytes);
    final encryptedBytes = Uint8List.fromList(data.sublist(16));
    final encrypter = Encrypter(AES(Key(keyBytes), mode: AESMode.cbc));
    return encrypter.decryptBytes(Encrypted(encryptedBytes), iv: iv);
  }

  String _formatTimestamp(DateTime dt) {
    return '${dt.year}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}'
        '_${dt.hour.toString().padLeft(2, '0')}${dt.minute.toString().padLeft(2, '0')}${dt.second.toString().padLeft(2, '0')}';
  }
}

class SettingsBackupInfo {
  final String name;
  final String path;
  final int size;
  final DateTime modifiedTime;
  final bool isEncrypted;

  SettingsBackupInfo({
    required this.name,
    required this.path,
    required this.size,
    required this.modifiedTime,
    required this.isEncrypted,
  });

  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get formattedTime {
    return '${modifiedTime.year.toString().padLeft(4, '0')}-'
        '${modifiedTime.month.toString().padLeft(2, '0')}-'
        '${modifiedTime.day.toString().padLeft(2, '0')} '
        '${modifiedTime.hour.toString().padLeft(2, '0')}:'
        '${modifiedTime.minute.toString().padLeft(2, '0')}';
  }
}
