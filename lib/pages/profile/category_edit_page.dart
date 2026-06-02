import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/house_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/attribute_provider.dart';
import '../../database/database.dart';

class CategoryEditPage extends StatefulWidget {
  final Category category;

  const CategoryEditPage({super.key, required this.category});

  @override
  State<CategoryEditPage> createState() => _CategoryEditPageState();
}

class _CategoryEditPageState extends State<CategoryEditPage> {
  late TextEditingController _nameController;
  late Set<String> _selectedAttributeIds;
  late Future<List<Attribute>> _attributesFuture;
  late Future<List<Attribute>> _categoryAttributesFuture;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category.name);
    _selectedAttributeIds = {};

    final attributeProvider = context.read<AttributeProvider>();
    final categoryProvider = context.read<CategoryProvider>();
    final houseProvider = context.read<HouseProvider>();
    final currentHouse = houseProvider.currentHouse;

    if (currentHouse != null) {
      _attributesFuture = Future.value(attributeProvider.attributes);
      _categoryAttributesFuture = attributeProvider.getAttributesForCategory(widget.category.id);

      Future.wait([_attributesFuture, _categoryAttributesFuture]).then((results) {
        if (mounted) {
          setState(() {
            final categoryAttributes = results[1];
            _selectedAttributeIds = categoryAttributes.map((a) => a.id).toSet();
            _isLoading = false;
          });
        }
      });

      categoryProvider.loadSubcategories(widget.category.id);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoryProvider = context.read<CategoryProvider>();
    final isDefault = categoryProvider.isDefaultCategory(widget.category.name);

    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑分类'),
        actions: [
          TextButton(
            onPressed: _saveChanges,
            child: const Text('保存'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '基本信息',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _nameController,
                            decoration: InputDecoration(
                              labelText: '分类名称',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            enabled: !isDefault,
                          ),
                          if (isDefault)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                '默认分类名称不可修改',
                                style: TextStyle(color: Colors.grey[600], fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '二级分类',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              TextButton.icon(
                                onPressed: () => _showAddSubcategoryDialog(),
                                icon: const Icon(Icons.add),
                                label: const Text('添加'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '添加该分类下的二级分类',
                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                          ),
                          const SizedBox(height: 16),
                          Consumer<CategoryProvider>(
                            builder: (context, provider, child) {
                              final subcategories = provider.getSubcategoriesForCategory(widget.category.id);
                              if (subcategories.isEmpty) {
                                return Center(
                                  child: Column(
                                    children: [
                                      Icon(Icons.category_outlined,
                                          size: 48, color: Colors.grey[400]),
                                      const SizedBox(height: 8),
                                      Text('暂无二级分类，点击上方添加按钮创建',
                                          style: TextStyle(color: Colors.grey[600])),
                                    ],
                                  ),
                                );
                              }

                              return ReorderableListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: subcategories.length,
                                onReorder: (oldIndex, newIndex) {
                                  provider.reorderSubcategories(oldIndex, newIndex, widget.category.id);
                                },
                                itemBuilder: (context, index) {
                                  final subcategory = subcategories[index];
                                  return ListTile(
                                    key: ValueKey(subcategory.id),
                                    title: Text(subcategory.name),
                                    leading: ReorderableDragStartListener(
                                      index: index,
                                      child: const Icon(Icons.drag_handle),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.edit_outlined),
                                          onPressed: () => _showEditSubcategoryDialog(subcategory),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline),
                                          onPressed: () => _showDeleteSubcategoryDialog(subcategory),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '扩展属性',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '选择该分类物品的扩展属性',
                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                          ),
                          const SizedBox(height: 16),
                          FutureBuilder<List<Attribute>>(
                            future: _attributesFuture,
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) {
                                return const Center(child: CircularProgressIndicator());
                              }

                              final allAttributes = snapshot.data!;
                              if (allAttributes.isEmpty) {
                                return Center(
                                  child: Column(
                                    children: [
                                      Icon(Icons.settings_applications_outlined,
                                          size: 48, color: Colors.grey[400]),
                                      const SizedBox(height: 8),
                                      Text('暂无属性，请先添加属性',
                                          style: TextStyle(color: Colors.grey[600])),
                                    ],
                                  ),
                                );
                              }

                              return Column(
                                children: allAttributes.map((attr) {
                                  final isSelected = _selectedAttributeIds.contains(attr.id);
                                  return CheckboxListTile(
                                    title: Text(attr.name),
                                    subtitle: Text(_getAttributeTypeName(attr.type)),
                                    secondary: _buildAttributeIcon(attr.type),
                                    value: isSelected,
                                    onChanged: (value) {
                                      setState(() {
                                        if (value == true) {
                                          _selectedAttributeIds.add(attr.id);
                                        } else {
                                          _selectedAttributeIds.remove(attr.id);
                                        }
                                      });
                                    },
                                  );
                                }).toList(),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saveChanges,
                      icon: const Icon(Icons.save),
                      label: const Text('保存修改'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildAttributeIcon(String type) {
    final icons = {
      'text': Icons.text_fields,
      'number': Icons.numbers,
      'date': Icons.calendar_today,
      'select': Icons.radio_button_checked,
      'multi_select': Icons.check_box,
      'duration': Icons.timer,
    };
    final colors = {
      'text': Colors.blue,
      'number': Colors.green,
      'date': Colors.orange,
      'select': Colors.purple,
      'multi_select': Colors.teal,
      'duration': Colors.amber,
    };
    final iconData = icons[type] ?? Icons.settings;
    final iconColor = colors[type] ?? Colors.grey;

    return CircleAvatar(
      backgroundColor: iconColor.withOpacity(0.15),
      radius: 20,
      child: Icon(iconData, color: iconColor, size: 20),
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
      default:
        return type;
    }
  }

  void _showAddSubcategoryDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加二级分类'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: '分类名称',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请输入分类名称')),
                );
                return;
              }
              Navigator.pop(context);
              final categoryProvider = context.read<CategoryProvider>();
              await categoryProvider.addSubcategory(
                categoryId: widget.category.id,
                name: name,
              );
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  void _showEditSubcategoryDialog(Subcategory subcategory) {
    final controller = TextEditingController(text: subcategory.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑二级分类'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: '分类名称',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请输入分类名称')),
                );
                return;
              }
              Navigator.pop(context);
              final categoryProvider = context.read<CategoryProvider>();
              await categoryProvider.updateSubcategory(subcategory, name);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showDeleteSubcategoryDialog(Subcategory subcategory) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除二级分类'),
        content: Text('确定要删除"${subcategory.name}"吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              final categoryProvider = context.read<CategoryProvider>();
              await categoryProvider.deleteSubcategory(subcategory);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveChanges() async {
    final categoryProvider = context.read<CategoryProvider>();
    final attributeProvider = context.read<AttributeProvider>();

    final newName = _nameController.text.trim();
    if (newName.isNotEmpty && newName != widget.category.name) {
      await categoryProvider.updateCategory(widget.category, newName);
    }

    await attributeProvider.setCategoryAttributes(
      widget.category.id,
      _selectedAttributeIds.toList(),
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('分类已更新')),
      );
      Navigator.pop(context);
    }
  }
}