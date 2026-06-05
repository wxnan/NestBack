import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:encrypt/encrypt.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;
import '../database/database.dart';
import 'import_export_service.dart';

class WebDavBackupService {
  final AppDatabase _db;
  final ImportExportService _importExportService;

  WebDavBackupService(this._db, this._importExportService);

  webdav.Client? _client;
  String? _remotePath;
  String? _encryptionKey;

  void configure({
    required String serverUrl,
    required String username,
    required String password,
    required String remotePath,
    String? encryptionKey,
  }) {
    _client = webdav.newClient(
      serverUrl,
      user: username,
      password: password,
      debug: false,
    );
    _client!.setHeaders({'accept-encoding': 'gzip'});
    _remotePath = remotePath;
    _encryptionKey = encryptionKey;
  }

  Future<bool> testConnection() async {
    if (_client == null) {
      throw Exception('WebDAV客户端未配置');
    }

    try {
      await _client!.ping();
      
      // 检查远程路径是否存在，不存在则创建
      try {
        await _client!.readDir(_remotePath!);
      } catch (e) {
        // 路径不存在，尝试创建
        await _client!.mkdir(_remotePath!);
      }
      
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<String> backup(String houseId) async {
    if (_client == null || _remotePath == null) {
      throw Exception('WebDAV未配置');
    }

    // 创建家庭专属目录路径
    final houseBackupPath = p.join(_remotePath!, houseId).replaceAll('\\', '/');
    
    // 确保家庭目录存在
    try {
      await _client!.readDir(houseBackupPath);
    } catch (e) {
      // 目录不存在，创建它
      await _client!.mkdir(houseBackupPath);
    }

    // 导出数据为ZIP
    final zipPath = await _importExportService.exportToZip(houseId);
    final zipFile = File(zipPath);
    final zipBytes = await zipFile.readAsBytes();

    // 生成远程文件名
    final timestamp = _formatTimestamp(DateTime.now());
    final remoteFileName = 'nestback_backup_$timestamp.zip';
    final remoteFilePath = p.join(houseBackupPath, remoteFileName).replaceAll('\\', '/');

    // 上传到WebDAV
    if (_encryptionKey != null && _encryptionKey!.isNotEmpty) {
      // 加密并上传
      final encryptedBytes = _encryptData(zipBytes, _encryptionKey!);
      final tempDir = await getTemporaryDirectory();
      final encryptedPath = p.join(tempDir.path, 'encrypted_$timestamp.zip');
      await File(encryptedPath).writeAsBytes(encryptedBytes);
      
      await _client!.writeFromFile(
        encryptedPath,
        remoteFilePath,
        onProgress: (count, total) {
          // 可用于显示进度
        },
      );
      
      // 清理加密临时文件
      try {
        await File(encryptedPath).delete();
      } catch (_) {}
    } else {
      // 直接上传原始ZIP文件
      await _client!.writeFromFile(
        zipPath,
        remoteFilePath,
        onProgress: (count, total) {
          // 可用于显示进度
        },
      );
    }

    // 清理本地临时文件
    try {
      await zipFile.delete();
    } catch (_) {}

    return remoteFilePath;
  }

  Future<String> restore(String houseId, String remoteFileName, {String? sourceHouseId}) async {
    if (_client == null || _remotePath == null) {
      throw Exception('WebDAV未配置');
    }

    // 确定源目录（支持从其他家庭恢复）
    final sourceHouse = sourceHouseId ?? houseId;
    final houseBackupPath = p.join(_remotePath!, sourceHouse).replaceAll('\\', '/');
    final remoteFilePath = p.join(houseBackupPath, remoteFileName).replaceAll('\\', '/');
    
    // 下载文件
    final tempDir = await getTemporaryDirectory();
    final localPath = p.join(tempDir.path, remoteFileName);
    
    await _client!.read2File(
      remoteFilePath,
      localPath,
      onProgress: (count, total) {
        // 可用于显示进度
      },
    );

    final downloadedFile = File(localPath);
    final downloadedBytes = await downloadedFile.readAsBytes();

    // 写入解密后的ZIP文件
    final decryptedPath = p.join(tempDir.path, 'decrypted_$remoteFileName');
    
    if (_encryptionKey != null && _encryptionKey!.isNotEmpty) {
      // 尝试解密
      try {
        final decrypted = _decryptData(downloadedBytes, _encryptionKey!);
        await File(decryptedPath).writeAsBytes(decrypted);
      } catch (e) {
        // 解密失败，可能是未加密的文件，尝试直接使用
        await File(decryptedPath).writeAsBytes(downloadedBytes);
      }
    } else {
      // 无密钥，直接使用下载的文件
      await File(decryptedPath).writeAsBytes(downloadedBytes);
    }

    // 导入数据到目标家庭
    final result = await _importExportService.importFromZip(decryptedPath, houseId);

    // 清理临时文件
    try {
      await downloadedFile.delete();
      await File(decryptedPath).delete();
    } catch (_) {}

    return result.message;
  }

  Future<List<BackupFileInfo>> listBackups(String houseId) async {
    if (_client == null || _remotePath == null) {
      throw Exception('WebDAV未配置');
    }

    final houseBackupPath = p.join(_remotePath!, houseId).replaceAll('\\', '/');

    try {
      // 先检查目录是否存在
      await _client!.readDir(houseBackupPath);
      
      final files = await _client!.readDir(houseBackupPath);
      final backups = files
          .where((f) => f.name?.endsWith('.zip') ?? false)
          .where((f) => f.name?.startsWith('nestback_backup_') ?? false)
          .map((f) => BackupFileInfo(
                name: f.name!,
                path: f.path!,
                size: f.size ?? 0,
                modifiedTime: f.mTime ?? DateTime.now(),
                houseId: houseId,
              ))
          .toList();

      // 按修改时间降序排序
      backups.sort((a, b) => b.modifiedTime.compareTo(a.modifiedTime));
      return backups;
    } catch (e) {
      // 目录不存在，返回空列表
      return [];
    }
  }

  /// 列出所有有备份的家庭目录
  Future<List<HouseBackupInfo>> listAllHouses() async {
    if (_client == null || _remotePath == null) {
      throw Exception('WebDAV未配置');
    }

    try {
      final files = await _client!.readDir(_remotePath!);
      final houses = files
          .where((f) => f.isDir ?? false)
          .map((f) => HouseBackupInfo(
                houseId: f.name!,
                path: f.path!,
              ))
          .toList();
      return houses;
    } catch (e) {
      return [];
    }
  }

  Future<void> deleteBackup(String houseId, String remoteFileName) async {
    if (_client == null || _remotePath == null) {
      throw Exception('WebDAV未配置');
    }

    final houseBackupPath = p.join(_remotePath!, houseId).replaceAll('\\', '/');
    final remoteFilePath = p.join(houseBackupPath, remoteFileName).replaceAll('\\', '/');
    await _client!.remove(remoteFilePath);
  }

  /// 删除某个家庭的所有备份
  Future<void> deleteHouseBackups(String houseId) async {
    if (_client == null || _remotePath == null) {
      throw Exception('WebDAV未配置');
    }

    final houseBackupPath = p.join(_remotePath!, houseId).replaceAll('\\', '/');
    try {
      await _client!.remove(houseBackupPath);
    } catch (e) {
      // 目录可能不存在
    }
  }

  List<int> _encryptData(List<int> data, String key) {
    final keyBytes = Uint8List.fromList(utf8.encode(key.padRight(32, '0').substring(0, 32)));
    final iv = IV.fromLength(16);
    final encrypter = Encrypter(AES(Key(keyBytes), mode: AESMode.cbc));
    
    final encrypted = encrypter.encryptBytes(Uint8List.fromList(data), iv: iv);
    // 将IV添加到加密数据前面
    return [...iv.bytes, ...encrypted.bytes];
  }

  List<int> _decryptData(List<int> data, String key) {
    if (data.length < 17) {
      throw Exception('无效的加密数据');
    }
    
    final keyBytes = Uint8List.fromList(utf8.encode(key.padRight(32, '0').substring(0, 32)));
    // 从数据中提取IV
    final ivBytes = Uint8List.fromList(data.sublist(0, 16));
    final iv = IV(ivBytes);
    final encryptedBytes = Uint8List.fromList(data.sublist(16));
    
    final encrypter = Encrypter(AES(Key(keyBytes), mode: AESMode.cbc));
    final decrypted = encrypter.decryptBytes(Encrypted(encryptedBytes), iv: iv);
    return decrypted;
  }

  String _formatTimestamp(DateTime dt) {
    return '${dt.year}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}_${dt.hour.toString().padLeft(2, '0')}${dt.minute.toString().padLeft(2, '0')}${dt.second.toString().padLeft(2, '0')}';
  }
}

class BackupFileInfo {
  final String name;
  final String path;
  final int size;
  final DateTime modifiedTime;
  final String houseId;

  BackupFileInfo({
    required this.name,
    required this.path,
    required this.size,
    required this.modifiedTime,
    required this.houseId,
  });

  String get formattedSize {
    if (size < 1024) {
      return '$size B';
    } else if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }

  String get formattedTime {
    return '${modifiedTime.year}-${modifiedTime.month.toString().padLeft(2, '0')}-${modifiedTime.day.toString().padLeft(2, '0')} ${modifiedTime.hour.toString().padLeft(2, '0')}:${modifiedTime.minute.toString().padLeft(2, '0')}';
  }
}

class HouseBackupInfo {
  final String houseId;
  final String path;

  HouseBackupInfo({
    required this.houseId,
    required this.path,
  });
}