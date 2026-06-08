import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../database/database.dart';
import '../../providers/ai_provider.dart';
import 'ai_provider_detail_page.dart';
import 'ai_provider_edit_page.dart';

class AiSettingsPage extends StatelessWidget {
  const AiSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 设置'),
      ),
      body: Consumer<AiProviderProvider>(
        builder: (context, aiProvider, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildDefaultModelSection(context, aiProvider),
              const SizedBox(height: 16),
              _buildProviderSection(context, aiProvider),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDefaultModelSection(BuildContext context, AiProviderProvider aiProvider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.star,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '默认模型',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildModelSelector(
              context,
              label: '默认聊天模型',
              models: aiProvider.chatModels,
              selectedModelId: aiProvider.defaultChatModelId,
              onChanged: (modelId) {
                if (modelId != null) {
                  aiProvider.setDefaultChatModelId(modelId);
                }
              },
              providers: aiProvider.providers,
            ),
            const SizedBox(height: 12),
            _buildModelSelector(
              context,
              label: '默认识图模型',
              models: aiProvider.visionModels,
              selectedModelId: aiProvider.defaultVisionModelId,
              onChanged: (modelId) {
                if (modelId != null) {
                  aiProvider.setDefaultVisionModelId(modelId);
                }
              },
              providers: aiProvider.providers,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModelSelector(
    BuildContext context, {
    required String label,
    required List<AiModel> models,
    required String selectedModelId,
    required ValueChanged<String?> onChanged,
    required List<AiProvider> providers,
  }) {
    final hasSelection = selectedModelId.isNotEmpty && models.any((m) => m.id == selectedModelId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: hasSelection ? selectedModelId : null,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            hintText: '未选择',
          ),
          items: models.map((model) {
            final provider = providers.where((p) => p.id == model.providerId).firstOrNull;
            final providerName = provider?.name.split(' / ').first ?? '';
            return DropdownMenuItem(
              value: model.id,
              child: Text(
                providerName.isNotEmpty ? '${model.name} ($providerName)' : model.name,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                softWrap: false,
              ),
            );
          }).toList(),
          onChanged: models.isEmpty ? null : onChanged,
        ),
        if (models.isEmpty) ...[
          const SizedBox(height: 4),
          Text(
            '暂无可用模型，请先启用提供商和模型',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ],
    );
  }

  Widget _buildProviderSection(BuildContext context, AiProviderProvider aiProvider) {
    final providers = aiProvider.providers;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(
                  Icons.dns,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '大模型提供商',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
          if (providers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('暂无提供商'),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: providers.length,
              onReorder: (oldIndex, newIndex) {
                aiProvider.reorderProviders(oldIndex, newIndex);
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
                final provider = providers[index];
                final modelCount = aiProvider.getModelsForProvider(provider.id).length;
                final enabledModelCount = aiProvider.getModelsForProvider(provider.id).where((m) => m.isEnabled).length;
                return ListTile(
                  key: ValueKey(provider.id),
                  leading: Icon(
                    provider.isEnabled ? Icons.cloud : Icons.cloud_off,
                    color: provider.isEnabled ? null : Colors.grey,
                  ),
                  title: Text(provider.name),
                  subtitle: Text(
                    provider.isEnabled
                        ? '$enabledModelCount/$modelCount 个模型可用'
                        : '已禁用',
                    style: TextStyle(
                      color: provider.isEnabled ? null : Colors.grey,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: provider.isEnabled && provider.apiKey.isNotEmpty
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Colors.grey[300],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          provider.isEnabled && provider.apiKey.isNotEmpty ? '已配置' : '未配置',
                          style: TextStyle(
                            fontSize: 12,
                            color: provider.isEnabled && provider.apiKey.isNotEmpty
                                ? Theme.of(context).colorScheme.onPrimaryContainer
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ReorderableDragStartListener(
                        index: index,
                        child: const Icon(Icons.drag_handle, color: Colors.grey),
                      ),
                    ],
                  ),
                  onTap: () => _showProviderDetail(context, provider.id),
                );
              },
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _addCustomProvider(context),
                icon: const Icon(Icons.add),
                label: const Text('添加自定义提供商'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showProviderDetail(BuildContext context, String providerId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AiProviderDetailPage(providerId: providerId),
      ),
    );
  }

  void _addCustomProvider(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AiProviderEditPage(),
      ),
    );
  }
}
