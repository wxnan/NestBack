import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/house_provider.dart';
import '../../providers/space_provider.dart';
import '../../providers/item_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/tag_provider.dart';
import '../../providers/attribute_provider.dart';
import '../../providers/ai_provider.dart';
import '../../database/database.dart';
import '../../services/webdav_backup_service.dart';
import '../../services/settings_backup_service.dart';
import '../../services/import_export_service.dart';

class BackupSettingsPage extends StatefulWidget {
  const BackupSettingsPage({super.key});

  @override
  State<BackupSettingsPage> createState() => _BackupSettingsPageState();
}

class _BackupSettingsPageState extends State<BackupSettingsPage> {
  final _serverUrlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _pathController = TextEditingController();
  final _encryptionKeyController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureEncryptionKey = true;
  bool _isTesting = false;
  bool _isBackingUp = false;
  bool _isRestoring = false;
  bool _isLoadingBackups = false;
  bool _isLoadingAllHouses = false;
  bool _isBackingUpSettings = false;
  bool _isLoadingSettingsBackups = false;
  List<BackupFileInfo>? _backupList;
  List<HouseBackupInfo>? _allHouseBackups;
  List<SettingsBackupInfo> _settingsBackups = [];
  WebDavBackupService? _backupService;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  void _loadConfig() {
    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    _serverUrlController.text = settingsProvider.webDavServerUrl.isNotEmpty
        ? settingsProvider.webDavServerUrl
        : 'https://dav.jianguoyun.com/dav/';
    _usernameController.text = settingsProvider.webDavUsername;
    _passwordController.text = settingsProvider.webDavPassword;
    _pathController.text = settingsProvider.webDavPath.isNotEmpty
        ? settingsProvider.webDavPath
        : '/nestback_backup';
    _encryptionKeyController.text = settingsProvider.webDavEncryptionKey;
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _pathController.dispose();
    _encryptionKeyController.dispose();
    super.dispose();
  }

  bool get _isConfigured {
    return _serverUrlController.text.isNotEmpty &&
        _usernameController.text.isNotEmpty &&
        _passwordController.text.isNotEmpty;
  }

  Future<void> _testConnection() async {
    if (!_isConfigured) {
      _showSnackBar('请填写服务器地址、用户名和密码', isError: true);
      return;
    }

    setState(() => _isTesting = true);

    try {
      final db = Provider.of<AppDatabase>(context, listen: false);
      final importExportService = ImportExportService(db);
      final service = WebDavBackupService(db, importExportService);

      service.configure(
        serverUrl: _serverUrlController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text.trim(),
        remotePath: _pathController.text.trim().isEmpty ? '/nestback_backup' : _pathController.text.trim(),
        encryptionKey: _encryptionKeyController.text.trim(),
      );

      final success = await service.testConnection();

      if (success) {
        _showSnackBar('连接成功！', isError: false);
        _backupService = service;
        await _loadBackupList();
      } else {
        _showSnackBar('连接失败，请检查配置', isError: true);
      }
    } catch (e) {
      _showSnackBar('连接测试失败：$e', isError: true);
    } finally {
      setState(() => _isTesting = false);
    }
  }

  Future<void> _saveConfig() async {
    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    await settingsProvider.setWebDavConfig(
      serverUrl: _serverUrlController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text.trim(),
      path: _pathController.text.trim().isEmpty ? '/nestback_backup' : _pathController.text.trim(),
      encryptionKey: _encryptionKeyController.text.trim(),
    );

    // 重新初始化备份服务
    final db = Provider.of<AppDatabase>(context, listen: false);
    final importExportService = ImportExportService(db);
    _backupService = WebDavBackupService(db, importExportService);
    _backupService!.configure(
      serverUrl: settingsProvider.webDavServerUrl,
      username: settingsProvider.webDavUsername,
      password: settingsProvider.webDavPassword,
      remotePath: settingsProvider.webDavPath,
      encryptionKey: settingsProvider.webDavEncryptionKey,
    );

    _showSnackBar('配置已保存', isError: false);
  }

  Future<void> _ensureBackupService() async {
    if (_backupService != null) return;

    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    if (!settingsProvider.isWebDavConfigured) return;

    final db = Provider.of<AppDatabase>(context, listen: false);
    final importExportService = ImportExportService(db);
    _backupService = WebDavBackupService(db, importExportService);
    _backupService!.configure(
      serverUrl: settingsProvider.webDavServerUrl,
      username: settingsProvider.webDavUsername,
      password: settingsProvider.webDavPassword,
      remotePath: settingsProvider.webDavPath,
      encryptionKey: settingsProvider.webDavEncryptionKey,
    );
  }

  // ===== 家庭数据备份 =====

  Future<void> _loadBackupList() async {
    final houseProvider = Provider.of<HouseProvider>(context, listen: false);
    final currentHouse = houseProvider.currentHouse;

    if (currentHouse == null) {
      _showSnackBar('请先选择一个家庭', isError: true);
      return;
    }

    await _ensureBackupService();
    if (_backupService == null) return;

    setState(() => _isLoadingBackups = true);

    try {
      final backups = await _backupService!.listBackups(currentHouse.name);
      setState(() => _backupList = backups);
    } catch (e) {
      _showSnackBar('加载备份列表失败：$e', isError: true);
    } finally {
      setState(() => _isLoadingBackups = false);
    }
  }

  Future<void> _loadAllHouseBackups() async {
    await _ensureBackupService();
    if (_backupService == null) return;

    setState(() => _isLoadingAllHouses = true);

    try {
      final houses = await _backupService!.listAllHouses();
      setState(() => _allHouseBackups = houses);
    } catch (e) {
      _showSnackBar('加载家庭列表失败：$e', isError: true);
    } finally {
      setState(() => _isLoadingAllHouses = false);
    }
  }

  Future<void> _backupHouse() async {
    final houseProvider = Provider.of<HouseProvider>(context, listen: false);
    final currentHouse = houseProvider.currentHouse;

    if (currentHouse == null) {
      _showSnackBar('请先选择一个家庭', isError: true);
      return;
    }

    await _ensureBackupService();
    if (_backupService == null) {
      _showSnackBar('请先配置并测试WebDAV连接', isError: true);
      return;
    }

    setState(() => _isBackingUp = true);

    try {
      await _backupService!.backup(currentHouse.id, currentHouse.name);
      _showSnackBar('家庭数据备份成功！', isError: false);
      await _loadBackupList();
    } catch (e) {
      _showSnackBar('备份失败：$e', isError: true);
    } finally {
      setState(() => _isBackingUp = false);
    }
  }

  Future<void> _restoreHouse(BackupFileInfo backup, {String? sourceHouseName}) async {
    final houseProvider = Provider.of<HouseProvider>(context, listen: false);
    final currentHouse = houseProvider.currentHouse;

    if (currentHouse == null) {
      _showSnackBar('请先选择一个家庭', isError: true);
      return;
    }

    final isCrossHouse = sourceHouseName != null && sourceHouseName != currentHouse.name;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认恢复'),
        content: Text(isCrossHouse
            ? '确定要从家庭 "$sourceHouseName" 的备份 "${backup.name}" 恢复数据吗？\n\n数据将导入到当前家庭 "${currentHouse.name}" 中。'
            : '确定要从备份 "${backup.name}" 恢复数据吗？\n\n数据将导入到当前家庭 "${currentHouse.name}" 中。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isRestoring = true);

    try {
      final message = await _backupService!.restore(
        currentHouse.id,
        currentHouse.name,
        backup.name,
        sourceHouseName: sourceHouseName ?? backup.houseName,
      );
      await _refreshAllProviders();
      _showSnackBar(message, isError: false);
    } catch (e) {
      _showSnackBar('恢复失败：$e', isError: true);
    } finally {
      setState(() => _isRestoring = false);
    }
  }

  Future<void> _deleteBackup(BackupFileInfo backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除备份 "${backup.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _backupService!.deleteBackup(backup.houseName, backup.name);
      _showSnackBar('备份已删除', isError: false);
      await _loadBackupList();
    } catch (e) {
      _showSnackBar('删除失败：$e', isError: true);
    }
  }

  Future<void> _showAllHouseBackups() async {
    await _loadAllHouseBackups();
    if (_allHouseBackups == null || _allHouseBackups!.isEmpty) {
      _showSnackBar('未找到任何备份', isError: true);
      return;
    }

    if (!mounted) return;

    final selectedHouse = await showDialog<HouseBackupInfo>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择要恢复的备份来源'),
        children: _allHouseBackups!.map((house) => SimpleDialogOption(
          onPressed: () => Navigator.pop(context, house),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.folder, color: Colors.amber),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(house.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (house.createdAt != null)
                        Text('创建于 ${_formatDate(house.createdAt!)}', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        )).toList(),
      ),
    );

    if (selectedHouse == null || !mounted) return;

    setState(() => _isLoadingBackups = true);
    try {
      final backups = await _backupService!.listBackups(selectedHouse.dirName);
      if (backups.isEmpty) {
        _showSnackBar('该家庭暂无备份文件', isError: true);
        return;
      }

      final selectedBackup = await showDialog<BackupFileInfo>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text('"${selectedHouse.displayName}" 的备份列表'),
          children: backups.map((backup) => SimpleDialogOption(
            onPressed: () => Navigator.pop(context, backup),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.archive, color: Colors.blue),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(backup.formattedTime, style: const TextStyle(fontWeight: FontWeight.w500)),
                        Text(backup.formattedSize, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )).toList(),
        ),
      );

      if (selectedBackup == null || !mounted) return;

      await _restoreHouse(selectedBackup, sourceHouseName: selectedHouse.dirName);
    } catch (e) {
      _showSnackBar('加载备份失败：$e', isError: true);
    } finally {
      setState(() => _isLoadingBackups = false);
    }
  }

  // ===== 设置备份 =====

  Future<void> _backupSettings() async {
    if (!_isConfigured) {
      _showSnackBar('请先配置 WebDAV', isError: true);
      return;
    }

    setState(() => _isBackingUpSettings = true);

    try {
      final db = Provider.of<AppDatabase>(context, listen: false);
      final service = SettingsBackupService(db);
      await service.backupSettingsToWebDav(
        serverUrl: _serverUrlController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text.trim(),
        remotePath: _pathController.text.trim().isEmpty ? '/nestback_backup' : _pathController.text.trim(),
        encryptionKey: _encryptionKeyController.text.trim().isNotEmpty ? _encryptionKeyController.text.trim() : null,
      );
      _showSnackBar('设置已备份到云端', isError: false);
      _loadSettingsBackups();
    } catch (e) {
      _showSnackBar('设置备份失败：$e', isError: true);
    } finally {
      setState(() => _isBackingUpSettings = false);
    }
  }

  Future<void> _loadSettingsBackups() async {
    if (!_isConfigured) return;

    setState(() => _isLoadingSettingsBackups = true);

    try {
      final db = Provider.of<AppDatabase>(context, listen: false);
      final service = SettingsBackupService(db);
      final backups = await service.listSettingsBackups(
        serverUrl: _serverUrlController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text.trim(),
        remotePath: _pathController.text.trim().isEmpty ? '/nestback_backup' : _pathController.text.trim(),
      );
      if (mounted) {
        setState(() {
          _settingsBackups = backups;
          _isLoadingSettingsBackups = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingSettingsBackups = false);
        _showSnackBar('获取设置备份列表失败：$e', isError: true);
      }
    }
  }

  Future<void> _restoreSettings(SettingsBackupInfo backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复设置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('确定要从该备份恢复设置吗？'),
            const SizedBox(height: 8),
            Text('备份时间：${backup.formattedTime}', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            if (backup.isEncrypted) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.lock, size: 14, color: Colors.amber[700]),
                  const SizedBox(width: 4),
                  Text('加密备份，将使用当前加密密钥解密', style: TextStyle(fontSize: 12, color: Colors.amber[700])),
                ],
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              '注意：恢复将覆盖当前的 AI 设置和扫码设置',
              style: TextStyle(fontSize: 12, color: Colors.red),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('恢复')),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isRestoring = true);

    try {
      final db = Provider.of<AppDatabase>(context, listen: false);
      final service = SettingsBackupService(db);
      final (success, message) = await service.restoreSettingsFromWebDav(
        serverUrl: _serverUrlController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text.trim(),
        remoteFilePath: backup.path,
        encryptionKey: backup.isEncrypted && _encryptionKeyController.text.trim().isNotEmpty
            ? _encryptionKeyController.text.trim()
            : null,
      );

      if (success && mounted) {
        final aiProvider = context.read<AiProviderProvider>();
        await aiProvider.init();
        final settings = context.read<SettingsProvider>();
        await settings.init();
      }

      if (mounted) {
        _showSnackBar(message, isError: !success);
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('恢复失败：$e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isRestoring = false);
      }
    }
  }

  Future<void> _deleteSettingsBackup(SettingsBackupInfo backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除设置备份'),
        content: Text('确定要删除 ${backup.formattedTime} 的设置备份吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final db = Provider.of<AppDatabase>(context, listen: false);
      final service = SettingsBackupService(db);
      await service.deleteSettingsBackup(
        serverUrl: _serverUrlController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text.trim(),
        remoteFilePath: backup.path,
      );
      _showSnackBar('设置备份已删除', isError: false);
      _loadSettingsBackups();
    } catch (e) {
      _showSnackBar('删除失败：$e', isError: true);
    }
  }

  // ===== 通用方法 =====

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  Future<void> _refreshAllProviders() async {
    final houseProvider = Provider.of<HouseProvider>(context, listen: false);
    await houseProvider.init();

    final house = houseProvider.currentHouse;
    if (house != null) {
      final houseId = house.id;
      await Future.wait([
        Provider.of<SpaceProvider>(context, listen: false).loadSpaces(houseId),
        Provider.of<ItemProvider>(context, listen: false).loadItems(houseId),
        Provider.of<CategoryProvider>(context, listen: false).loadCategories(),
        Provider.of<TagProvider>(context, listen: false).loadTags(),
        Provider.of<AttributeProvider>(context, listen: false).loadAttributes(),
      ]);
    }
  }

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }

  void _showSwitchHouseDialog(BuildContext context) {
    final houseProvider = Provider.of<HouseProvider>(context, listen: false);
    final houses = houseProvider.houses;
    if (houses.length <= 1) {
      _showSnackBar('当前只有一个家庭，无法切换', isError: true);
      return;
    }

    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择当前家庭'),
        children: houses.map((house) {
          final isCurrent = house.id == houseProvider.currentHouse?.id;
          return SimpleDialogOption(
            onPressed: () async {
              Navigator.pop(context);
              await houseProvider.switchHouse(house);
              if (!mounted) return;
              await _refreshAllProviders();
              if (!mounted) return;
              await _loadBackupList();
              if (!mounted) return;
              _showSnackBar('已切换到"${house.name}"', isError: false);
            },
            child: Row(
              children: [
                Icon(
                  isCurrent ? Icons.check_circle : Icons.circle_outlined,
                  color: isCurrent ? Theme.of(context).colorScheme.primary : Colors.grey,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(
                  house.name,
                  style: TextStyle(
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                if (isCurrent) ...[
                  const SizedBox(width: 8),
                  Text(
                    '(当前)',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final houseProvider = Provider.of<HouseProvider>(context);
    final currentHouse = houseProvider.currentHouse;

    return Scaffold(
      appBar: AppBar(
        title: const Text('备份设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (currentHouse != null)
            Card(
              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _showSwitchHouseDialog(context),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.home, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('当前家庭', style: Theme.of(context).textTheme.bodySmall),
                            Text(currentHouse.name, style: Theme.of(context).textTheme.titleMedium),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('备份将存入同名目录', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (currentHouse != null) const SizedBox(height: 16),
          _buildConfigSection(),
          const SizedBox(height: 16),
          _buildActionSection(),
          const SizedBox(height: 16),
          _buildBackupListSection(),
          const SizedBox(height: 16),
          _buildSettingsBackupSection(),
        ],
      ),
    );
  }

  Widget _buildConfigSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('WebDAV 配置', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            TextField(
              controller: _serverUrlController,
              decoration: const InputDecoration(
                labelText: '服务器地址',
                hintText: 'https://dav.jianguoyun.com/dav/',
                border: OutlineInputBorder(),
                helperText: '坚果云默认地址已填入',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: '用户名',
                hintText: '坚果云为邮箱地址',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: '密码',
                hintText: '坚果云为应用专用密码',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pathController,
              decoration: const InputDecoration(
                labelText: '备份路径',
                hintText: '/nestback_backup',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _encryptionKeyController,
              obscureText: _obscureEncryptionKey,
              decoration: InputDecoration(
                labelText: '加密密钥（可选）',
                hintText: '设置后将加密备份文件',
                border: const OutlineInputBorder(),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(_obscureEncryptionKey ? Icons.visibility_off : Icons.visibility, size: 20),
                      onPressed: () => setState(() => _obscureEncryptionKey = !_obscureEncryptionKey),
                    ),
                    if (_encryptionKeyController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _encryptionKeyController.clear();
                          setState(() {});
                        },
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isTesting ? null : _testConnection,
                    icon: _isTesting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.wifi_find),
                    label: const Text('测试连接'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saveConfig,
                    icon: const Icon(Icons.save),
                    label: const Text('保存配置'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('备份操作', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            // 家庭数据备份/恢复
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (_isConfigured && !_isBackingUp) ? _backupHouse : null,
                    icon: _isBackingUp
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.backup),
                    label: const Text('备份家庭'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (_isConfigured && !_isLoadingBackups) ? _loadBackupList : null,
                    icon: _isLoadingBackups
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.restore),
                    label: const Text('恢复家庭'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: (_isConfigured && !_isLoadingAllHouses) ? _showAllHouseBackups : null,
                icon: _isLoadingAllHouses
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cloud_download),
                label: const Text('从其他家庭恢复'),
              ),
            ),
            const Divider(height: 32),
            // 设置备份/恢复
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (_isConfigured && !_isBackingUpSettings) ? _backupSettings : null,
                    icon: _isBackingUpSettings
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.backup),
                    label: const Text('备份设置'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (_isConfigured && !_isLoadingSettingsBackups) ? _loadSettingsBackups : null,
                    icon: _isLoadingSettingsBackups
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.restore),
                    label: const Text('恢复设置'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackupListSection() {
    final houseProvider = Provider.of<HouseProvider>(context);
    final currentHouse = houseProvider.currentHouse;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text('家庭备份列表', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${_backupList?.length ?? 0}',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSecondaryContainer),
                  ),
                ),
              ],
            ),
          ),
          if (_backupList == null || _backupList!.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                    const SizedBox(height: 8),
                    Text(
                      currentHouse != null ? '"${currentHouse.name}" 暂无备份文件' : '暂无备份文件',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '点击"恢复家庭"可查看并恢复备份',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _backupList!.length,
              itemBuilder: (context, index) {
                final backup = _backupList![index];
                return ListTile(
                  leading: Icon(
                    backup.isEncrypted ? Icons.lock : Icons.archive,
                    color: backup.isEncrypted ? Colors.amber[700] : null,
                  ),
                  title: Text(backup.formattedTime),
                  subtitle: Row(
                    children: [
                      Text(backup.formattedSize),
                      if (backup.isEncrypted) ...[
                        const SizedBox(width: 8),
                        Text(
                          '已加密',
                          style: TextStyle(fontSize: 12, color: Colors.amber[700]),
                        ),
                      ],
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.restore),
                        tooltip: '恢复',
                        onPressed: _isRestoring ? null : () => _restoreHouse(backup),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        tooltip: '删除',
                        onPressed: () => _deleteBackup(backup),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildSettingsBackupSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('设置备份列表', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${_settingsBackups.length}',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSecondaryContainer),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'AI设置、扫码设置备份（${SettingsBackupService.settingsFolderName} 文件夹）',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            if (_isLoadingSettingsBackups)
              const Center(child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ))
            else if (_settingsBackups.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                      const SizedBox(height: 8),
                      Text(
                        _isConfigured ? '“设置”暂无备份文件' : '请先配置 WebDAV',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '点击"恢复设置"可查看并恢复备份',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              )
            else
              ..._settingsBackups.map((backup) => ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: Icon(
                  backup.isEncrypted ? Icons.lock : Icons.archive,
                  color: backup.isEncrypted ? Colors.amber[700] : null,
                  size: 24,
                ),
                title: Text(backup.formattedTime, style: const TextStyle(fontSize: 14)),
                subtitle: Row(
                  children: [
                    Text(backup.formattedSize, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    if (backup.isEncrypted) ...[
                      const SizedBox(width: 8),
                      Text('已加密', style: TextStyle(fontSize: 11, color: Colors.amber[700])),
                    ],
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.restore),
                      tooltip: '恢复',
                      onPressed: _isRestoring ? null : () => _restoreSettings(backup),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete),
                      tooltip: '删除',
                      onPressed: () => _deleteSettingsBackup(backup),
                    ),
                  ],
                ),
              )),
          ],
        ),
      ),
    );
  }
}
