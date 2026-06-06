import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../database/database.dart';
import '../../providers/house_provider.dart';
import '../../providers/item_provider.dart';
import '../../providers/space_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/tag_provider.dart';
import '../../providers/attribute_provider.dart';
import '../../services/import_export_service.dart';

class ImportExportPage extends StatefulWidget {
  const ImportExportPage({super.key});

  @override
  State<ImportExportPage> createState() => _ImportExportPageState();
}

class _ImportExportPageState extends State<ImportExportPage> {
  bool _isProcessing = false;
  String _statusMessage = '';
  double _progress = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('导入导出'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildExportSection(context),
          const SizedBox(height: 24),
          _buildImportSection(context),
          if (_isProcessing) ...[
            const SizedBox(height: 24),
            _buildProgressIndicator(),
          ],
          if (_statusMessage.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildStatusMessage(),
          ],
        ],
      ),
    );
  }

  Widget _buildExportSection(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.upload_file,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('导出数据',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        '将当前家庭的数据导出为文件',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('导出为 JSON'),
            subtitle: const Text('完整数据，包含空间、分类、标签等所有关系'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _isProcessing ? null : () => _handleExport('json'),
          ),
          ListTile(
            leading: const Icon(Icons.table_chart),
            title: const Text('导出为 CSV'),
            subtitle: const Text('物品列表，可用 Excel 打开编辑'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _isProcessing ? null : () => _handleExport('csv'),
          ),
          ListTile(
            leading: const Icon(Icons.folder_zip),
            title: const Text('导出为 ZIP'),
            subtitle: const Text('完整数据 + 物品图片，适合备份迁移'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _isProcessing ? null : () => _handleExport('zip'),
          ),
        ],
      ),
    );
  }

  Widget _buildImportSection(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.download,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('导入数据',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        '从文件恢复数据到当前家庭',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('导入 JSON'),
            subtitle: const Text('从 JSON 文件恢复完整家庭数据'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _isProcessing ? null : () => _handleImport('json'),
          ),
          ListTile(
            leading: const Icon(Icons.table_chart),
            title: const Text('导入 CSV'),
            subtitle: const Text('从 CSV 文件导入物品到当前家庭'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _isProcessing ? null : () => _handleImport('csv'),
          ),
          ListTile(
            leading: const Icon(Icons.folder_zip),
            title: const Text('导入 ZIP'),
            subtitle: const Text('从 ZIP 文件恢复数据及图片'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _isProcessing ? null : () => _handleImport('zip'),
          ),

        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            LinearProgressIndicator(value: _progress > 0 ? _progress : null),
            const SizedBox(height: 12),
            Text(
              _isProcessing ? '正在处理...' : '处理完成',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusMessage() {
    final isSuccess = _statusMessage.startsWith('成功');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              isSuccess ? Icons.check_circle : Icons.error,
              color: isSuccess ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _statusMessage,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleExport(String format) async {
    final houseProvider = context.read<HouseProvider>();
    final house = houseProvider.currentHouse;
    if (house == null) {
      _showMessage('请先选择一个家庭');
      return;
    }

    final confirmed = await _showConfirmDialog(
      '确认导出',
      '将「${house.name}」的数据导出为 ${format.toUpperCase()} 格式？',
    );
    if (confirmed != true) return;

    setState(() {
      _isProcessing = true;
      _progress = 0;
      _statusMessage = '';
    });

    try {
      final service = ImportExportService(context.read<AppDatabase>());
      String filePath;

      setState(() => _progress = 0.3);

      switch (format) {
        case 'json':
          filePath = await service.exportToJson(house.id);
          break;
        case 'csv':
          filePath = await service.exportToCsv(house.id);
          break;
        case 'zip':
          filePath = await service.exportToZip(house.id);
          break;
        default:
          throw Exception('不支持的格式');
      }

      setState(() => _progress = 1.0);

      final file = File(filePath);
      if (await file.exists()) {
        await Share.shareXFiles(
          [XFile(filePath)],
          subject: '归巢数据导出',
        );
      }

      setState(() {
        _statusMessage = '成功导出 ${format.toUpperCase()} 文件';
      });
    } catch (e) {
      setState(() {
        _statusMessage = '导出失败：$e';
      });
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleImport(String format) async {
    List<String> allowedExtensions;
    switch (format) {
      case 'json':
        allowedExtensions = ['json'];
        break;
      case 'csv':
        allowedExtensions = ['csv'];
        break;
      case 'zip':
        allowedExtensions = ['zip'];
        break;
      default:
        return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
    );

    if (result == null || result.files.isEmpty) return;
    final filePath = result.files.single.path;
    if (filePath == null) {
      _showMessage('无法获取文件路径');
      return;
    }

    final houseProvider = context.read<HouseProvider>();
    final house = houseProvider.currentHouse;
    if (house == null) {
      _showMessage('请先选择一个家庭');
      return;
    }

    final confirmMessage = '将 ${format.toUpperCase()} 文件导入到「${house.name}」？';

    final confirmed = await _showConfirmDialog('确认导入', confirmMessage);
    if (confirmed != true) return;

    setState(() {
      _isProcessing = true;
      _progress = 0;
      _statusMessage = '';
    });

    try {
      final service = ImportExportService(context.read<AppDatabase>());
      ImportResult importResult;

      setState(() => _progress = 0.3);

      switch (format) {
        case 'json':
          importResult = await service.importFromJson(filePath, house!.id);
          break;
        case 'csv':
          importResult = await service.importFromCsv(filePath, house!.id);
          break;
        case 'zip':
          importResult = await service.importFromZip(filePath, house!.id);
          break;
        default:
          throw Exception('不支持的格式');
      }

      setState(() => _progress = 0.8);

      await _refreshAllProviders();

      setState(() {
        _progress = 1.0;
        _statusMessage = importResult.message;
      });
    } catch (e) {
      setState(() {
        _statusMessage = '导入失败：$e';
      });
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _refreshAllProviders() async {
    final houseProvider = context.read<HouseProvider>();
    await houseProvider.init();

    final house = houseProvider.currentHouse;
    if (house != null) {
      final houseId = house.id;
      await Future.wait([
        context.read<SpaceProvider>().loadSpaces(houseId),
        context.read<ItemProvider>().loadItems(houseId),
        context.read<CategoryProvider>().loadCategories(),
        context.read<TagProvider>().loadTags(),
        context.read<AttributeProvider>().loadAttributes(),
      ]);
    }
  }

  Future<bool?> _showConfirmDialog(String title, String message) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
