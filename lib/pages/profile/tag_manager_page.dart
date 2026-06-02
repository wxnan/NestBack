import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/house_provider.dart';
import '../../providers/tag_provider.dart';
import '../../database/database.dart';

class TagManagerPage extends StatefulWidget {
  const TagManagerPage({super.key});

  @override
  State<TagManagerPage> createState() => _TagManagerPageState();
}

class _TagManagerPageState extends State<TagManagerPage> {
  late Future<void> _loadFuture;

  @override
  void initState() {
    super.initState();
    _loadFuture = _loadData();
  }

  Future<void> _loadData() async {
    final houseProvider = context.read<HouseProvider>();
    final tagProvider = context.read<TagProvider>();
    final currentHouse = houseProvider.currentHouse;
    if (currentHouse != null) {
      await tagProvider.loadTags(currentHouse.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('标签管理'),
      ),
      body: FutureBuilder(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          return Consumer<TagProvider>(
            builder: (context, provider, _) {
              final tags = provider.tags;

              if (tags.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.label_outline, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        '暂无标签',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: () => _showAddTagDialog(context),
                        icon: const Icon(Icons.add),
                        label: const Text('添加标签'),
                      ),
                    ],
                  ),
                );
              }

              return ReorderableListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: tags.length,
                itemBuilder: (context, index) {
                  final tag = tags[index];
                  return _buildTagCard(context, provider, tag);
                },
                onReorder: (oldIndex, newIndex) {
                  provider.reorderTags(oldIndex, newIndex);
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddTagDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildTagCard(BuildContext context, TagProvider provider, Tag tag) {
    return Card(
      key: ValueKey(tag.id),
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: _buildTagIcon(),
        title: Text(
          tag.name,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => _showEditTagDialog(context, provider, tag),
              tooltip: '编辑',
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _confirmDeleteTag(context, provider, tag),
              tooltip: '删除',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTagIcon() {
    return CircleAvatar(
      backgroundColor: Colors.blue.withOpacity(0.15),
      child: const Icon(
        Icons.label,
        color: Colors.blue,
      ),
    );
  }

  void _showAddTagDialog(BuildContext context) {
    final provider = context.read<TagProvider>();
    final houseProvider = context.read<HouseProvider>();
    final currentHouse = houseProvider.currentHouse;
    if (currentHouse == null) return;

    final controller = TextEditingController();
    String? errorText;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('添加标签'),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: '标签名称',
              hintText: '例如：易碎、常用',
              errorText: errorText,
            ),
            autofocus: true,
            onChanged: (value) {
              if (errorText != null) {
                setState(() {
                  errorText = null;
                });
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isEmpty) {
                  setState(() {
                    errorText = '请输入标签名称';
                  });
                  return;
                }

                if (await provider.isTagNameExists(currentHouse.id, name)) {
                  setState(() {
                    errorText = '该标签名称已存在';
                  });
                  return;
                }

                await provider.addTag(houseId: currentHouse.id, name: name);
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              },
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditTagDialog(BuildContext context, TagProvider provider, Tag tag) {
    final controller = TextEditingController(text: tag.name);
    String? errorText;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('编辑标签'),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: '标签名称',
              errorText: errorText,
            ),
            autofocus: true,
            onChanged: (value) {
              if (errorText != null) {
                setState(() {
                  errorText = null;
                });
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isEmpty) {
                  setState(() {
                    errorText = '请输入标签名称';
                  });
                  return;
                }

                if (name != tag.name && await provider.isTagNameExists(tag.houseId, name, excludeId: tag.id)) {
                  setState(() {
                    errorText = '该标签名称已存在';
                  });
                  return;
                }

                await provider.updateTag(tag, name);
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteTag(BuildContext context, TagProvider provider, Tag tag) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除标签'),
        content: Text('确定要删除"${tag.name}"吗？\n\n删除后该标签将从所有物品上移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              provider.deleteTag(tag);
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
