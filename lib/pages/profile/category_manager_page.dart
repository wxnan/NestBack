import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/house_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/attribute_provider.dart';
import '../../database/database.dart';
import 'category_edit_page.dart';

class CategoryManagerPage extends StatefulWidget {
  const CategoryManagerPage({super.key});

  @override
  State<CategoryManagerPage> createState() => _CategoryManagerPageState();
}

class _CategoryManagerPageState extends State<CategoryManagerPage> {
  late Future<void> _loadFuture;
  final Map<String, bool> _categoryUsageCache = {};

  @override
  void initState() {
    super.initState();
    _loadFuture = _loadData();
  }

  Future<void> _loadData() async {
    final houseProvider = context.read<HouseProvider>();
    final categoryProvider = context.read<CategoryProvider>();
    final currentHouse = houseProvider.currentHouse;
    if (currentHouse != null) {
      await categoryProvider.loadCategories();
      await _refreshUsageCache(categoryProvider);
    }
  }

  Future<void> _refreshUsageCache(CategoryProvider provider) async {
    _categoryUsageCache.clear();
    for (final category in provider.categories) {
      _categoryUsageCache[category.id] = await provider.isCategoryUsedByItems(category.id);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('分类管理'),
      ),
      body: FutureBuilder(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          return Consumer<CategoryProvider>(
            builder: (context, provider, _) {
              // Refresh usage cache when categories change
              if (_categoryUsageCache.length != provider.categories.length) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _refreshUsageCache(provider);
                });
              }

              final categories = provider.categories;

              if (categories.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.category_outlined, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        '暂无分类',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: () => _showAddCategoryDialog(context),
                        icon: const Icon(Icons.add),
                        label: const Text('添加分类'),
                      ),
                    ],
                  ),
                );
              }

              return ReorderableListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: categories.length,
                itemBuilder: (context, index) {
                  final category = categories[index];
                  return _buildCategoryCard(context, provider, category);
                },
                onReorder: (oldIndex, newIndex) {
                  provider.reorderCategories(oldIndex, newIndex);
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddCategoryDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildCategoryCard(BuildContext context, CategoryProvider provider, Category category) {
    final isOther = category.name == '其他';

    return Card(
      key: ValueKey(category.id),
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: _buildCategoryIcon(category.name, category.icon),
        title: Text(
          category.name,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CategoryEditPage(category: category),
                  ),
                );
              },
              tooltip: '编辑',
            ),
            if (!isOther)
              IconButton(
                icon: Icon(
                  Icons.delete,
                  color: (_categoryUsageCache[category.id] ?? false) ? Colors.grey : Colors.red,
                ),
                onPressed: (_categoryUsageCache[category.id] ?? false)
                    ? () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('分类"${category.name}"已被物品使用，无法删除'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    : () => _confirmDeleteCategory(context, provider, category),
                tooltip: (_categoryUsageCache[category.id] ?? false) ? '该分类已被使用，无法删除' : '删除',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryIcon(String? categoryName, [String? categoryIcon]) {
    final icons = {
      '食品': Icons.local_dining,
      '药品': Icons.medication,
      '日用品': Icons.cleaning_services,
      '数码': Icons.devices,
      '美妆': Icons.spa,
      '其他': Icons.inventory_2,
    };
    final iconData = icons[categoryName] ?? Icons.category;
    final colors = {
      '食品': Colors.amber,
      '药品': Colors.green,
      '日用品': Colors.blue,
      '数码': Colors.purple,
      '美妆': Colors.pink,
      '其他': Colors.grey,
    };
    final iconColor = colors[categoryName] ?? Colors.grey;

    return CircleAvatar(
      backgroundColor: iconColor.withOpacity(0.15),
      child: Icon(
        iconData,
        color: iconColor,
      ),
    );
  }

  void _showAddCategoryDialog(BuildContext context) {
    final provider = context.read<CategoryProvider>();
    final houseProvider = context.read<HouseProvider>();
    final currentHouse = houseProvider.currentHouse;
    if (currentHouse == null) return;

    final controller = TextEditingController();
    String? errorText;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('添加分类'),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: '分类名称',
              hintText: '例如：食品、日用品',
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
                    errorText = '请输入分类名称';
                  });
                  return;
                }

                if (await provider.isCategoryNameExists(name)) {
                  setState(() {
                    errorText = '该分类名称已存在';
                  });
                  return;
                }

                await provider.addCategory(houseId: currentHouse.id, name: name);
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

  void _showEditCategoryDialog(BuildContext context, CategoryProvider provider, Category category) {
    final controller = TextEditingController(text: category.name);
    String? errorText;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('编辑分类'),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: '分类名称',
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
                    errorText = '请输入分类名称';
                  });
                  return;
                }

                if (name != category.name && await provider.isCategoryNameExists(name, excludeId: category.id)) {
                  setState(() {
                    errorText = '该分类名称已存在';
                  });
                  return;
                }

                await provider.updateCategory(category, name);
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

  void _confirmDeleteCategory(BuildContext context, CategoryProvider provider, Category category) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除分类'),
        content: Text('确定要删除"${category.name}"吗？\n\n删除后该分类下的物品将归类为"其他"。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              await provider.deleteCategory(category);
              await _refreshUsageCache(provider);
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _showCategoryAttributesDialog(BuildContext context, Category category) {
    final attributeProvider = context.read<AttributeProvider>();
    final currentHouse = context.read<HouseProvider>().currentHouse;
    if (currentHouse == null) return;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return FutureBuilder<List<Attribute>>(
            future: attributeProvider.getAttributesForCategory(category.id),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                attributeProvider.loadAttributes();
                return const AlertDialog(
                  title: Text('配置扩展属性'),
                  content: Center(child: CircularProgressIndicator()),
                );
              }

              final allAttributes = attributeProvider.attributes;
              final categoryAttributes = snapshot.data!;
              final selectedAttributeIds = categoryAttributes.map((a) => a.id).toSet();

              return AlertDialog(
                title: Text('配置"${category.name}"扩展属性'),
                content: SingleChildScrollView(
                  child: Column(
                    children: allAttributes
                        .map((attr) => CheckboxListTile(
                              title: Text(attr.name),
                              subtitle: Text(_getAttributeTypeName(attr.type)),
                              value: selectedAttributeIds.contains(attr.id),
                              onChanged: (value) {
                                setState(() {
                                  if (value == true) {
                                    selectedAttributeIds.add(attr.id);
                                  } else {
                                    selectedAttributeIds.remove(attr.id);
                                  }
                                });
                              },
                            ))
                        .toList(),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () async {
                      await attributeProvider.setCategoryAttributes(category.id, selectedAttributeIds.toList());
                      Navigator.pop(context);
                    },
                    child: const Text('保存'),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  String _getAttributeTypeName(String type) {
    switch (type) {
      case 'text':
        return '文本';
      case 'number':
        return '数字';
      case 'date':
        return '日期';
      case 'select':
        return '单选';
      case 'multi_select':
        return '多选';
      case 'duration':
        return '时长';
      case 'link':
        return '链接';
      default:
        return type;
    }
  }
}