import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/house_provider.dart';
import '../../providers/attribute_provider.dart';
import '../../database/database.dart';

class AttributeManagerPage extends StatelessWidget {
  const AttributeManagerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('属性管理'),
      ),
      body: Consumer2<AttributeProvider, HouseProvider>(
        builder: (context, attributeProvider, houseProvider, _) {
          final currentHouse = houseProvider.currentHouse;
          if (currentHouse == null) return const SizedBox();

          if (attributeProvider.attributes.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              attributeProvider.loadAttributes(currentHouse.id);
            });
          }

          if (attributeProvider.attributes.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.settings_applications_outlined, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    '暂无属性',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => _showAddAttributeDialog(context),
                    icon: const Icon(Icons.add),
                    label: const Text('添加属性'),
                  ),
                ],
              ),
            );
          }

          return ReorderableListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: attributeProvider.attributes.length,
            itemBuilder: (context, index) {
              final attribute = attributeProvider.attributes[index];
              return _buildAttributeCard(context, attributeProvider, attribute);
            },
            onReorder: (oldIndex, newIndex) {
              attributeProvider.reorderAttributes(oldIndex, newIndex);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddAttributeDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildAttributeCard(BuildContext context, AttributeProvider provider, Attribute attribute) {
    final options = provider.getAttributeOptions(attribute);
    final typeName = _getAttributeTypeName(attribute.type);
    final subtitle = options.isNotEmpty ? '$typeName（${options.join('、')}）' : typeName;

    return Card(
      key: ValueKey(attribute.id),
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: _buildAttributeIcon(attribute.type),
        title: Text(
          attribute.name,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: Colors.grey[600]),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => _showEditAttributeDialog(context, provider, attribute),
              tooltip: '编辑',
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _confirmDeleteAttribute(context, provider, attribute),
              tooltip: '删除',
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
      child: Icon(
        iconData,
        color: iconColor,
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
      default:
        return type;
    }
  }

  Widget _buildOptionsEditor({
    required List<String> options,
    required String label,
    required void Function(List<String>) onChanged,
  }) {
    final controller = TextEditingController();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: options.asMap().entries.map((entry) {
            final index = entry.key;
            final option = entry.value;
            return Chip(
              label: Text(option),
              onDeleted: () {
                final newOptions = List<String>.from(options);
                newOptions.removeAt(index);
                onChanged(newOptions);
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: '添加${label.replaceAll('（必填）', '').replaceAll('（至少1个）', '')}',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onSubmitted: (value) {
                  final trimmed = value.trim();
                  if (trimmed.isNotEmpty && !options.contains(trimmed)) {
                    onChanged([...options, trimmed]);
                    controller.clear();
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: () {
                final trimmed = controller.text.trim();
                if (trimmed.isNotEmpty && !options.contains(trimmed)) {
                  onChanged([...options, trimmed]);
                  controller.clear();
                }
              },
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ],
    );
  }

  void _showAddAttributeDialog(BuildContext context) {
    final nameController = TextEditingController();
    String selectedType = 'text';
    final hintController = TextEditingController();
    List<String> options = [];
    String? nameError;
    String? optionsError;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('添加属性'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: '属性名称',
                    errorText: nameError,
                  ),
                  autofocus: true,
                  onChanged: (value) {
                    if (nameError != null) {
                      setState(() {
                        nameError = null;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedType,
                  decoration: const InputDecoration(labelText: '类型'),
                  items: const [
                    DropdownMenuItem(value: 'text', child: Text('文本')),
                    DropdownMenuItem(value: 'number', child: Text('数字')),
                    DropdownMenuItem(value: 'date', child: Text('日期')),
                    DropdownMenuItem(value: 'select', child: Text('单选')),
                    DropdownMenuItem(value: 'multi_select', child: Text('多选')),
                    DropdownMenuItem(value: 'duration', child: Text('时长')),
                  ],
                  onChanged: (value) {
                    setState(() {
                      selectedType = value!;
                      if (selectedType != 'select' && selectedType != 'multi_select' && selectedType != 'duration') {
                        options = [];
                        optionsError = null;
                      }
                    });
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: hintController,
                  decoration: const InputDecoration(labelText: '提示文字（选填）'),
                ),
                if (selectedType == 'select' || selectedType == 'multi_select') ...[
                  const SizedBox(height: 16),
                  _buildOptionsEditor(
                    options: options,
                    label: '选项（至少1个）',
                    onChanged: (newOptions) {
                      setState(() {
                        options = newOptions;
                        optionsError = null;
                      });
                    },
                  ),
                  if (optionsError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(optionsError!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
                    ),
                ],
                if (selectedType == 'duration') ...[
                  const SizedBox(height: 16),
                  _buildOptionsEditor(
                    options: options,
                    label: '单位（至少1个）',
                    onChanged: (newOptions) {
                      setState(() {
                        options = newOptions;
                        optionsError = null;
                      });
                    },
                  ),
                  if (optionsError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(optionsError!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
                    ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final houseProvider = context.read<HouseProvider>();
                final attributeProvider = context.read<AttributeProvider>();
                final currentHouse = houseProvider.currentHouse;

                if (currentHouse == null) return;

                if (name.isEmpty) {
                  setState(() {
                    nameError = '请输入属性名称';
                  });
                  return;
                }

                if (await attributeProvider.isAttributeNameExists(currentHouse.id, name)) {
                  setState(() {
                    nameError = '该属性名称已存在';
                  });
                  return;
                }

                if ((selectedType == 'select' || selectedType == 'multi_select' || selectedType == 'duration') && options.isEmpty) {
                  setState(() {
                    optionsError = selectedType == 'duration' ? '请至少添加1个单位' : '请至少添加1个选项';
                  });
                  return;
                }

                await attributeProvider.addAttribute(
                  houseId: currentHouse.id,
                  name: name,
                  type: selectedType,
                  hint: hintController.text.isNotEmpty ? hintController.text : null,
                  options: (selectedType == 'select' || selectedType == 'multi_select' || selectedType == 'duration') && options.isNotEmpty ? options : null,
                  required: false,
                );

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

  void _showEditAttributeDialog(BuildContext context, AttributeProvider provider, Attribute attribute) {
    final nameController = TextEditingController(text: attribute.name);
    String selectedType = attribute.type;
    final hintController = TextEditingController(text: attribute.hint ?? '');
    List<String> options = provider.getAttributeOptions(attribute);
    String? nameError;
    String? optionsError;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('编辑属性'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: '属性名称',
                      errorText: nameError,
                    ),
                    autofocus: true,
                    onChanged: (value) {
                      if (nameError != null) {
                        setState(() {
                          nameError = null;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedType,
                    decoration: const InputDecoration(labelText: '类型'),
                    items: const [
                      DropdownMenuItem(value: 'text', child: Text('文本')),
                      DropdownMenuItem(value: 'number', child: Text('数字')),
                      DropdownMenuItem(value: 'date', child: Text('日期')),
                      DropdownMenuItem(value: 'select', child: Text('单选')),
                      DropdownMenuItem(value: 'multi_select', child: Text('多选')),
                      DropdownMenuItem(value: 'duration', child: Text('时长')),
                    ],
                    onChanged: (value) {
                      setState(() {
                        selectedType = value!;
                        if (selectedType != 'select' && selectedType != 'multi_select' && selectedType != 'duration') {
                          options = [];
                          optionsError = null;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: hintController,
                    decoration: const InputDecoration(labelText: '提示文字'),
                  ),
                  if (selectedType == 'select' || selectedType == 'multi_select') ...[
                    const SizedBox(height: 16),
                    _buildOptionsEditor(
                      options: options,
                      label: '选项（至少1个）',
                      onChanged: (newOptions) {
                        setState(() {
                          options = newOptions;
                          optionsError = null;
                        });
                      },
                    ),
                    if (optionsError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(optionsError!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
                      ),
                  ],
                  if (selectedType == 'duration') ...[
                    const SizedBox(height: 16),
                    _buildOptionsEditor(
                      options: options,
                      label: '单位（至少1个）',
                      onChanged: (newOptions) {
                        setState(() {
                          options = newOptions;
                          optionsError = null;
                        });
                      },
                    ),
                    if (optionsError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(optionsError!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
                      ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () async {
                  final name = nameController.text.trim();
                  if (name.isEmpty) {
                    setState(() {
                      nameError = '请输入属性名称';
                    });
                    return;
                  }

                  if (name != attribute.name && await provider.isAttributeNameExists(attribute.houseId, name, excludeId: attribute.id)) {
                    setState(() {
                      nameError = '该属性名称已存在';
                    });
                    return;
                  }

                  if ((selectedType == 'select' || selectedType == 'multi_select' || selectedType == 'duration') && options.isEmpty) {
                    setState(() {
                      optionsError = selectedType == 'duration' ? '请至少添加1个单位' : '请至少添加1个选项';
                    });
                    return;
                  }

                  await provider.updateAttribute(
                    attribute,
                    name: name,
                    type: selectedType,
                    hint: hintController.text.isNotEmpty ? hintController.text : null,
                    options: (selectedType == 'select' || selectedType == 'multi_select' || selectedType == 'duration') ? options : null,
                    required: false,
                  );

                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                  }
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDeleteAttribute(BuildContext context, AttributeProvider provider, Attribute attribute) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除属性'),
        content: Text('确定要删除"${attribute.name}"吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              provider.deleteAttribute(attribute);
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
