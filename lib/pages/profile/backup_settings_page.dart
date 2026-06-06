import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/house_provider.dart';
import '../../providers/space_provider.dart';
import '../../providers/item_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/tag_provider.dart';
import '../../providers/attribute_provider.dart';
import '../../database/database.dart';
import '../../services/webdav_backup_service.dart';
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
  List<BackupFileInfo>? _backupList;
  List<HouseBackupInfo>? _allHouseBackups;
  WebDavBackupService? _backupService;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  void _loadConfig() {
    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    _serverUrlController.text = settingsProvider.webDavServerUrl;
    _usernameController.text = settingsProvider.webDavUsername;
    _passwordController.text = settingsProvider.webDavPassword;
    _pathController.text = settingsProvider.webDavPath;
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

  Future<void> _testConnection() async {
    if (_serverUrlController.text.isEmpty ||
        _usernameController.text.isEmpty ||
        _passwordController.text.isEmpty) {
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

  Future<void> _backup() async {
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
      final remotePath = await _backupService!.backup(currentHouse.id, currentHouse.name);
      _showSnackBar('备份成功！', isError: false);
      await _loadBackupList();
    } catch (e) {
      _showSnackBar('备份失败：$e', isError: true);
    } finally {
      setState(() => _isBackingUp = false);
    }
  }

  Future<void> _restore(BackupFileInfo backup, {String? sourceHouseName}) async {
    final houseProvider = Provider.of<HouseProvider>(context, listen: false);
    final currentHouse = houseProvider.currentHouse;

    if (currentHouse == null) {
      _showSnackBar('请先选择一个家庭', isError: true);
      return;
    }

    final isCrossHouse = sourceHouseName != null && sourceHouseName != currentHouse.name;
    
    // 确认对话框
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
      // 恢复成功后刷新所有 Provider 数据
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
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
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

  /// 显示所有家庭备份的弹窗
  Future<void> _showAllHouseBackups() async {
    await _loadAllHouseBackups();
    if (_allHouseBackups == null || _allHouseBackups!.isEmpty) {
      _showSnackBar('未找到任何备份', isError: true);
      return;
    }

    if (!mounted) return;

    // 选择家庭
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
                      Text(
                        house.displayName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (house.createdAt != null)
                        Text(
                          '创建于 ${_formatDate(house.createdAt!)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
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

    // 加载该家庭的备份列表
    setState(() => _isLoadingBackups = true);
    try {
      final backups = await _backupService!.listBackups(selectedHouse.dirName);
      if (backups.isEmpty) {
        _showSnackBar('该家庭暂无备份文件', isError: true);
        return;
      }

      // 选择备份文件
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
                        Text(
                          backup.formattedTime,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        Text(
                          backup.formattedSize,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
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

      // 执行恢复
      await _restore(selectedBackup, sourceHouseName: selectedHouse.dirName);
    } catch (e) {
      _showSnackBar('加载备份失败：$e', isError: true);
    } finally {
      setState(() => _isLoadingBackups = false);
    }
  }

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

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final houseProvider = Provider.of<HouseProvider>(context);
    final currentHouse = houseProvider.currentHouse;

    return Scaffold(
      appBar: AppBar(
        title: const Text('备份设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 显示当前家庭信息
          if (currentHouse != null)
            Card(
              color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.home,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '当前家庭',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            currentHouse.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '备份将存入同名目录',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (currentHouse != null) const SizedBox(height: 16),
          _buildConfigSection(settingsProvider),
          const SizedBox(height: 16),
          _buildActionSection(),
          const SizedBox(height: 16),
          _buildBackupListSection(),
        ],
      ),
    );
  }

  Widget _buildConfigSection(SettingsProvider settingsProvider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'WebDAV 配置',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _serverUrlController,
              decoration: const InputDecoration(
                labelText: '服务器地址',
                hintText: '例如: https://dav.jianguoyun.com/dav/',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: '用户名',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: '密码',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pathController,
              decoration: const InputDecoration(
                labelText: '备份路径',
                hintText: '例如: /nestback_backup',
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
                suffixIcon: IconButton(
                  icon: Icon(_obscureEncryptionKey ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscureEncryptionKey = !_obscureEncryptionKey),
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
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
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
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final isConfigured = settingsProvider.isWebDavConfigured;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '备份操作',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (isConfigured && !_isBackingUp) ? _backup : null,
                    icon: _isBackingUp
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.backup),
                    label: const Text('立即备份'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (isConfigured && !_isLoadingBackups) ? _loadBackupList : null,
                    icon: _isLoadingBackups
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.list),
                    label: const Text('当前备份'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: (isConfigured && !_isLoadingAllHouses) ? _showAllHouseBackups : null,
                icon: _isLoadingAllHouses
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_download),
                label: const Text('从其他家庭恢复'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackupListSection() {
    final houseProvider = Provider.of<HouseProvider>(context);
    final currentHouse = houseProvider.currentHouse;

    if (_backupList == null || _backupList!.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(
                Icons.cloud_off,
                size: 48,
                color: Colors.grey,
              ),
              const SizedBox(height: 8),
              Text(
                currentHouse != null
                    ? '"${currentHouse.name}" 暂无备份文件'
                    : '暂无备份文件',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
              ),
              const SizedBox(height: 4),
              Text(
                '点击"从其他家庭恢复"可查看所有备份',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(
                  '备份列表',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${_backupList!.length}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _backupList!.length,
            itemBuilder: (context, index) {
              final backup = _backupList![index];
              return ListTile(
                leading: const Icon(Icons.archive),
                title: Text(backup.formattedTime),
                subtitle: Text(backup.formattedSize),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.restore),
                      tooltip: '恢复',
                      onPressed: _isRestoring ? null : () => _restore(backup),
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
}
