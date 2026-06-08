import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../database/database.dart';
import '../../providers/ai_provider.dart';
import 'ai_model_edit_page.dart';

class AiProviderDetailPage extends StatefulWidget {
  final String providerId;

  const AiProviderDetailPage({super.key, required this.providerId});

  @override
  State<AiProviderDetailPage> createState() => _AiProviderDetailPageState();
}

class _AiProviderDetailPageState extends State<AiProviderDetailPage> {
  late TextEditingController _apiBaseUrlController;
  late TextEditingController _apiPathController;
  late TextEditingController _apiKeyController;
  bool _obscureApiKey = true;

  @override
  void initState() {
    super.initState();
    _apiBaseUrlController = TextEditingController();
    _apiPathController = TextEditingController();
    _apiKeyController = TextEditingController();
    // 延迟初始化 controller 的值
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final aiProvider = context.read<AiProviderProvider>();
      final provider = aiProvider.getProvider(widget.providerId);
      if (provider != null) {
        _apiBaseUrlController.text = provider.apiBaseUrl;
        _apiPathController.text = provider.apiPath;
        _apiKeyController.text = provider.apiKey;
        _obscureApiKey = provider.apiKey.isNotEmpty;
      }
    });
  }

  @override
  void dispose() {
    _apiBaseUrlController.dispose();
    _apiPathController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AiProviderProvider>(
      builder: (context, aiProvider, _) {
        final provider = aiProvider.getProvider(widget.providerId);
        if (provider == null) {
          return const Scaffold(
            body: Center(child: Text('提供商不存在')),
          );
        }
        final models = aiProvider.getModelsForProvider(widget.providerId);

        return Scaffold(
          appBar: AppBar(
            title: Text(provider.name),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildApiConfigCard(context, aiProvider, provider),
              const SizedBox(height: 12),
              _buildTestConnectionButton(context, aiProvider, provider, models),
              const SizedBox(height: 16),
              _buildProviderInfoCard(context, provider),
              const SizedBox(height: 16),
              _buildModelsCard(context, aiProvider, provider, models),
              if (!provider.isBuiltIn) ...[
                const SizedBox(height: 24),
                _buildDeleteButton(context, aiProvider, provider),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildTestConnectionButton(BuildContext context, AiProviderProvider aiProvider, AiProvider provider, List<AiModel> models) {
    final canTest = provider.apiKey.isNotEmpty && models.isNotEmpty;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: canTest ? () => _showTestConnectionDialog(context, aiProvider, provider, models) : null,
        icon: const Icon(Icons.wifi_tethering),
        label: const Text('测试连接'),
      ),
    );
  }

  void _showTestConnectionDialog(BuildContext context, AiProviderProvider aiProvider, AiProvider provider, List<AiModel> models) {
    AiModel? selectedModel;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('测试连接'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('选择一个模型进行测试：'),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '选择模型',
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: models.map((m) => DropdownMenuItem(
                  value: m.id,
                  child: Text(
                    m.name,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    softWrap: false,
                  ),
                )).toList(),
                onChanged: (value) {
                  setDialogState(() {
                    selectedModel = models.firstWhere((m) => m.id == value);
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: selectedModel == null ? null : () async {
                Navigator.pop(ctx);
                _runTestConnection(context, aiProvider, provider, selectedModel!);
              },
              child: const Text('测试'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runTestConnection(BuildContext context, AiProviderProvider aiProvider, AiProvider provider, AiModel model) async {
    // 显示加载弹窗
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator()),
      ),
    );

    final (success, message) = await aiProvider.testConnection(provider.id, model.modelId);

    // 关闭加载弹窗
    if (context.mounted) Navigator.pop(context);

    // 显示结果
    if (context.mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(
                success ? Icons.check_circle : Icons.error,
                color: success ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 8),
              Text(success ? '连接成功' : '连接失败'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('模型：${model.name}'),
              const SizedBox(height: 4),
              Text(message),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('确定')),
          ],
        ),
      );
    }
  }

  Widget _buildApiConfigCard(BuildContext context, AiProviderProvider aiProvider, AiProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.api,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Text(
                  'API 配置',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _apiBaseUrlController,
              decoration: const InputDecoration(
                labelText: 'API 地址',
                hintText: '如：https://api.siliconflow.cn/v1',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                aiProvider.updateProvider(provider.copyWith(
                  apiBaseUrl: value.trim(),
                  updatedAt: DateTime.now(),
                ));
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _apiPathController,
              decoration: const InputDecoration(
                labelText: 'API 路径',
                hintText: '/chat/completions',
                border: OutlineInputBorder(),
                helperText: '拼接到 API 地址后的路径',
              ),
              onChanged: (value) {
                aiProvider.updateProvider(provider.copyWith(
                  apiPath: value.trim(),
                  updatedAt: DateTime.now(),
                ));
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _apiKeyController,
              obscureText: _obscureApiKey,
              decoration: InputDecoration(
                labelText: 'API Key',
                hintText: aiProvider.hasBuiltInApiKey(provider)
                    ? '已内置 API Key，填写后将覆盖内置 Key'
                    : '输入 API Key',
                border: const OutlineInputBorder(),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(_obscureApiKey ? Icons.visibility_off : Icons.visibility, size: 20),
                      onPressed: () => setState(() => _obscureApiKey = !_obscureApiKey),
                    ),
                    if (_apiKeyController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _apiKeyController.clear();
                          aiProvider.updateProviderApiKey(provider.id, '');
                          setState(() {});
                        },
                      ),
                  ],
                ),
              ),
              onChanged: (value) {
                aiProvider.updateProviderApiKey(provider.id, value);
                setState(() {});
              },
            ),
            const SizedBox(height: 8),
            if (aiProvider.hasBuiltInApiKey(provider))
              Row(
                children: [
                  Icon(Icons.verified, size: 14, color: Colors.green[700]),
                  const SizedBox(width: 4),
                  Text(
                    '已内置 API Key',
                    style: TextStyle(fontSize: 12, color: Colors.green[700]),
                  ),
                ],
              )
            else
              Text(
                'API Key 仅存储在本地，不会上传至任何服务器',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            const SizedBox(height: 16),
            _buildCustomHeadersSection(context, aiProvider, provider),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomHeadersSection(BuildContext context, AiProviderProvider aiProvider, AiProvider provider) {
    Map<String, String> headers = {};
    try {
      final decoded = jsonDecode(provider.customHeaders) as Map<String, dynamic>;
      headers = decoded.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {}

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '自定义 Headers',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _addHeader(context, aiProvider, provider, headers),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('添加', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        if (headers.isEmpty)
          Text(
            '无自定义 Headers',
            style: TextStyle(fontSize: 12, color: Colors.grey[400]),
          )
        else
          ...headers.entries.map((entry) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    entry.key,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onTertiaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    entry.value,
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  onPressed: () => _editHeader(context, aiProvider, provider, headers, entry.key),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () {
                    final newHeaders = Map<String, String>.from(headers);
                    newHeaders.remove(entry.key);
                    aiProvider.updateProvider(provider.copyWith(
                      customHeaders: jsonEncode(newHeaders),
                      updatedAt: DateTime.now(),
                    ));
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ],
            ),
          )),
      ],
    );
  }

  void _addHeader(BuildContext context, AiProviderProvider aiProvider, AiProvider provider, Map<String, String> headers) {
    final keyController = TextEditingController();
    final valueController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加 Header'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: keyController,
              decoration: const InputDecoration(
                labelText: 'Header 名称',
                hintText: '如：APP-Code',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: valueController,
              decoration: const InputDecoration(
                labelText: 'Header 值',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              if (keyController.text.trim().isEmpty) return;
              final newHeaders = Map<String, String>.from(headers);
              newHeaders[keyController.text.trim()] = valueController.text.trim();
              aiProvider.updateProvider(provider.copyWith(
                customHeaders: jsonEncode(newHeaders),
                updatedAt: DateTime.now(),
              ));
              Navigator.pop(ctx);
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  void _editHeader(BuildContext context, AiProviderProvider aiProvider, AiProvider provider, Map<String, String> headers, String key) {
    final keyController = TextEditingController(text: key);
    final valueController = TextEditingController(text: headers[key] ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑 Header'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: keyController,
              decoration: const InputDecoration(
                labelText: 'Header 名称',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: valueController,
              decoration: const InputDecoration(
                labelText: 'Header 值',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              if (keyController.text.trim().isEmpty) return;
              final newHeaders = Map<String, String>.from(headers);
              newHeaders.remove(key);
              newHeaders[keyController.text.trim()] = valueController.text.trim();
              aiProvider.updateProvider(provider.copyWith(
                customHeaders: jsonEncode(newHeaders),
                updatedAt: DateTime.now(),
              ));
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderInfoCard(BuildContext context, AiProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Text(
                  '提供商信息',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoRow(context, '调用地址', '${provider.apiBaseUrl.replaceAll(RegExp(r'/+$'), '')}${provider.apiPath}'),
            if (provider.rateLimit != null) ...[
              const SizedBox(height: 8),
              _buildInfoRow(context, '速率限制', provider.rateLimit!),
            ],
            if (provider.freeQuota != null) ...[
              const SizedBox(height: 8),
              _buildInfoRow(context, '免费额度', provider.freeQuota!),
            ],
            if (provider.registerUrl != null) ...[
              const SizedBox(height: 12),
              _buildRegisterUrlRow(context, provider.registerUrl!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildRegisterUrlRow(BuildContext context, String url) {
    return InkWell(
      onTap: () async {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.open_in_new,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '前往注册获取 API Key',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 14,
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModelsCard(BuildContext context, AiProviderProvider aiProvider, AiProvider provider, List<AiModel> models) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(
                  Icons.model_training,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Text(
                  '模型列表',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  '${models.where((m) => m.isEnabled).length}/${models.length}',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          SwitchListTile(
            title: const Text('启用此提供商'),
            subtitle: Text(
              aiProvider.getEffectiveApiKey(provider).isEmpty
                  ? '请先填写 API Key 以启用'
                  : (provider.isEnabled ? '已启用' : '已禁用'),
            ),
            value: provider.isEnabled,
            onChanged: aiProvider.getEffectiveApiKey(provider).isEmpty
                ? null
                : (value) {
                    aiProvider.toggleProviderEnabled(provider.id, value);
                  },
          ),
          const Divider(height: 1),
          if (models.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('暂无模型'),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: models.length,
              onReorder: (oldIndex, newIndex) {
                aiProvider.reorderModels(provider.id, oldIndex, newIndex);
              },
              proxyDecorator: (child, index, animation) {
                return AnimatedBuilder(
                  animation: animation,
                  builder: (context, _) {
                    final animValue = Curves.easeInOut.transform(animation.value);
                    return Transform.scale(
                      scale: 1.0 + animValue * 0.02,
                      child: Material(
                        elevation: 6.0 * animValue,
                        borderRadius: BorderRadius.circular(8),
                        child: child,
                      ),
                    );
                  },
                );
              },
              itemBuilder: (context, index) {
                final model = models[index];
                return _buildModelTile(context, aiProvider, model, index);
              },
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _addModel(context, provider.id),
                icon: const Icon(Icons.add),
                label: const Text('添加模型'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelTile(BuildContext context, AiProviderProvider aiProvider, AiModel model, int index) {
    return Slidable(
      key: ValueKey(model.id),
      endActionPane: ActionPane(
        motion: const ScrollMotion(),
        extentRatio: 0.35,
        children: [
          SlidableAction(
            onPressed: (_) => _editModel(context, model),
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
            icon: Icons.edit_outlined,
            label: '编辑',
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
          ),
          SlidableAction(
            onPressed: (_) => _confirmDeleteModel(context, aiProvider, model),
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
            icon: Icons.delete_outline,
            label: '删除',
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
          ),
        ],
      ),
      child: ListTile(
        dense: true,
        title: Text(
          model.name,
          style: TextStyle(
            fontSize: 13,
            color: model.isEnabled ? null : Colors.grey,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: model.type == 'vision'
                    ? Colors.purple.withValues(alpha: 0.1)
                    : Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                model.type == 'vision' ? '识图' : '聊天',
                style: TextStyle(
                  fontSize: 11,
                  color: model.type == 'vision' ? Colors.purple : Colors.blue,
                ),
              ),
            ),
            Switch(
              value: model.isEnabled,
              onChanged: (value) {
                aiProvider.toggleModelEnabled(model.id, value);
              },
            ),
            ReorderableDragStartListener(
              index: index,
              child: const Icon(Icons.drag_handle, size: 18, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeleteButton(BuildContext context, AiProviderProvider aiProvider, AiProvider provider) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _confirmDeleteProvider(context, aiProvider, provider),
        icon: const Icon(Icons.delete_outline, color: Colors.red),
        label: const Text('删除此提供商', style: TextStyle(color: Colors.red)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.red),
        ),
      ),
    );
  }

  void _addModel(BuildContext context, String providerId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AiModelEditPage(providerId: providerId),
      ),
    );
  }

  void _editModel(BuildContext context, AiModel model) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AiModelEditPage(providerId: model.providerId, model: model),
      ),
    );
  }

  void _confirmDeleteModel(BuildContext context, AiProviderProvider aiProvider, AiModel model) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除模型'),
        content: Text('确定要删除模型「${model.name}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              aiProvider.deleteModel(model.id);
              Navigator.pop(context);
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteProvider(BuildContext context, AiProviderProvider aiProvider, AiProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除提供商'),
        content: Text('确定要删除提供商「${provider.name}」及其所有模型吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              aiProvider.deleteProvider(provider.id);
              Navigator.pop(context); // 关闭对话框
              Navigator.pop(this.context); // 返回上一页
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
