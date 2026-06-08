import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../database/database.dart';
import '../../providers/ai_provider.dart';

class AiModelEditPage extends StatefulWidget {
  final String providerId;
  final AiModel? model; // null 表示添加，非 null 表示编辑

  const AiModelEditPage({super.key, required this.providerId, this.model});

  @override
  State<AiModelEditPage> createState() => _AiModelEditPageState();
}

class _AiModelEditPageState extends State<AiModelEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _modelIdController = TextEditingController();
  final _nameController = TextEditingController();
  String _type = 'chat';

  bool get _isEditing => widget.model != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _modelIdController.text = widget.model!.modelId;
      _nameController.text = widget.model!.name;
      _type = widget.model!.type;
    }
  }

  @override
  void dispose() {
    _modelIdController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '编辑模型' : '添加模型'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!_isEditing) ...[
              _buildFetchFromApiCard(context),
              const SizedBox(height: 16),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _modelIdController,
                      decoration: const InputDecoration(
                        labelText: '模型 ID',
                        hintText: '如：deepseek-ai/DeepSeek-V4-Pro',
                        border: OutlineInputBorder(),
                        helperText: '调用 API 时使用的模型标识',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return '请输入模型 ID';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: '模型名称',
                        hintText: '如：DeepSeek V4 Pro',
                        border: OutlineInputBorder(),
                        helperText: '仅用于显示，方便识别',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return '请输入模型名称';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '模型类型',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _type,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'chat',
                          child: Row(
                            children: [
                              Icon(Icons.chat_bubble_outline, size: 18),
                              SizedBox(width: 8),
                              Text('聊天'),
                            ],
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'vision',
                          child: Row(
                            children: [
                              Icon(Icons.image_outlined, size: 18),
                              SizedBox(width: 8),
                              Text('识图'),
                            ],
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _type = value);
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _type == 'chat'
                          ? '聊天模型：仅支持文本对话'
                          : '识图模型：支持图片识别和文本对话',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFetchFromApiCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_download, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                const Text(
                  '从 API 获取模型',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '通过 /models 接口获取该提供商可用的模型列表，选择后自动填充模型 ID 和名称',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _fetchAndShowModels(context),
                icon: const Icon(Icons.download, size: 18),
                label: const Text('获取模型列表'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _fetchAndShowModels(BuildContext context) async {
    final aiProvider = context.read<AiProviderProvider>();
    final provider = aiProvider.getProvider(widget.providerId);
    if (provider == null) return;

    final effectiveApiKey = aiProvider.getEffectiveApiKey(provider);
    if (effectiveApiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填写 API Key')),
      );
      return;
    }

    // 显示加载弹窗
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator()),
      ),
    );

    try {
      final modelIds = await aiProvider.fetchAvailableModels(widget.providerId);

      // 关闭加载弹窗
      if (context.mounted) Navigator.pop(context);

      if (modelIds.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('该提供商暂无可用模型')),
          );
        }
        return;
      }

      // 获取已添加的模型 ID，用于标记
      final existingModelIds = aiProvider.models
          .where((m) => m.providerId == widget.providerId)
          .map((m) => m.modelId)
          .toSet();

      if (context.mounted) {
        _showModelSelectionDialog(context, modelIds, existingModelIds, aiProvider);
      }
    } catch (e) {
      // 关闭加载弹窗
      if (context.mounted) Navigator.pop(context);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('获取模型列表失败：$e')),
        );
      }
    }
  }

  void _showModelSelectionDialog(
    BuildContext context,
    List<String> modelIds,
    Set<String> existingModelIds,
    AiProviderProvider aiProvider,
  ) {
    // 已选中的模型（用于批量添加）
    final selectedModelIds = <String>{};
    String searchQuery = '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final filteredModels = modelIds.where((id) {
            if (searchQuery.isEmpty) return true;
            return id.toLowerCase().contains(searchQuery.toLowerCase());
          }).toList();

          return AlertDialog(
            title: const Text('选择模型'),
            content: SizedBox(
              width: double.maxFinite,
              height: 500,
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: '搜索模型...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      isDense: true,
                    ),
                    onChanged: (value) {
                      setDialogState(() => searchQuery = value);
                    },
                  ),
                  const SizedBox(height: 8),
                  if (selectedModelIds.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Text(
                            '已选择 ${selectedModelIds.length} 个模型',
                            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => setDialogState(() => selectedModelIds.clear()),
                            child: const Text('清空', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filteredModels.length,
                      itemBuilder: (ctx, index) {
                        final modelId = filteredModels[index];
                        final isExisting = existingModelIds.contains(modelId);
                        final isSelected = selectedModelIds.contains(modelId);

                        return CheckboxListTile(
                          value: isSelected,
                          onChanged: isExisting
                              ? null
                              : (checked) {
                                  setDialogState(() {
                                    if (checked == true) {
                                      selectedModelIds.add(modelId);
                                    } else {
                                      selectedModelIds.remove(modelId);
                                    }
                                  });
                                },
                          title: Text(
                            modelId,
                            style: TextStyle(
                              fontSize: 13,
                              color: isExisting ? Colors.grey : null,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            softWrap: false,
                          ),
                          subtitle: isExisting
                              ? Text('已添加', style: TextStyle(fontSize: 11, color: Colors.grey[400]))
                              : null,
                          controlAffinity: ListTileControlAffinity.leading,
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: selectedModelIds.isEmpty
                    ? null
                    : () {
                        Navigator.pop(ctx);
                        _addSelectedModels(selectedModelIds, aiProvider);
                      },
                child: Text('添加 (${selectedModelIds.length})'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _addSelectedModels(Set<String> selectedModelIds, AiProviderProvider aiProvider) {
    for (final modelId in selectedModelIds) {
      aiProvider.addModel(
        providerId: widget.providerId,
        modelId: modelId,
        name: modelId,
        type: 'chat', // 默认聊天类型，用户可后续编辑
      );
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已添加 ${selectedModelIds.length} 个模型')),
    );
    Navigator.pop(context); // 返回提供商详情页
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final aiProvider = context.read<AiProviderProvider>();

    if (_isEditing) {
      final updated = widget.model!.copyWith(
        modelId: _modelIdController.text.trim(),
        name: _nameController.text.trim(),
        type: _type,
        updatedAt: DateTime.now(),
      );
      aiProvider.updateModel(updated);
    } else {
      aiProvider.addModel(
        providerId: widget.providerId,
        modelId: _modelIdController.text.trim(),
        name: _nameController.text.trim(),
        type: _type,
      );
    }

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_isEditing ? '模型已更新' : '模型已添加')),
    );
  }
}
