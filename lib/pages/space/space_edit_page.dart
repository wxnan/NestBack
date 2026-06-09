import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'dart:io';
import '../../database/database.dart';
import '../../providers/space_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/house_provider.dart';

class SpaceEditPage extends StatefulWidget {
  final bool isAdd;
  final Space? space;
  final String? houseId;
  final String? parentId;

  const SpaceEditPage({
    super.key,
    required this.isAdd,
    this.space,
    this.houseId,
    this.parentId,
  });

  @override
  State<SpaceEditPage> createState() => _SpaceEditPageState();
}

class _SpaceEditPageState extends State<SpaceEditPage> {
  final _nameController = TextEditingController();
  String? _selectedIcon;
  String? _selectedParentId;
  String? _imagePath;
  String? _selectedDefaultCategoryId;

  final List<Map<String, dynamic>> _iconOptions = [
    {'name': '文件夹', 'icon': Icons.folder},
    {'name': '房间', 'icon': Icons.meeting_room},
    {'name': '容器', 'icon': Icons.inventory_2},
    {'name': '箱子', 'icon': Icons.luggage},
    {'name': '书架', 'icon': Icons.book},
    {'name': '抽屉', 'icon': Icons.view_agenda},
    {'name': '柜子', 'icon': Icons.store},
    {'name': '盒子', 'icon': Icons.inbox},
    {'name': '沙发', 'icon': Icons.weekend},
    {'name': '床', 'icon': Icons.bed},
    {'name': '餐具', 'icon': Icons.restaurant},
    {'name': '马桶', 'icon': Icons.wc},
  ];

  @override
  void initState() {
    super.initState();
    if (widget.isAdd) {
      _selectedParentId = widget.parentId;
      // Inherit default category from parent space
      if (_selectedParentId != null) {
        final spaceProvider = context.read<SpaceProvider>();
        final parentSpace = spaceProvider.getSpaceById(_selectedParentId);
        if (parentSpace != null && parentSpace.defaultCategoryId != null) {
          _selectedDefaultCategoryId = parentSpace.defaultCategoryId;
        }
      }
    } else {
      _nameController.text = widget.space?.name ?? '';
      _selectedIcon = widget.space?.icon;
      _selectedParentId = widget.space?.parentId;
      _imagePath = widget.space?.imagePath;
      _selectedDefaultCategoryId = widget.space?.defaultCategoryId;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _isContainer {
    if (widget.isAdd) {
      return _selectedParentId != null;
    }
    return widget.space?.type == 'container' || widget.space?.type == 'sub_container';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isAdd ? '添加空间' : '编辑空间'),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(widget.isAdd ? '添加' : '保存'),
          ),
        ],
      ),
      body: SingleChildScrollView(
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
                    Text('基本信息', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: '空间名称',
                        hintText: '例如：客厅、厨房、冰箱',
                        border: OutlineInputBorder(),
                      ),
                      autofocus: widget.isAdd,
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
                    Text('外观', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 16),
                    if (_isContainer) ...[
                      const Text('封面图片', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 8),
                      _buildImagePicker(),
                      const SizedBox(height: 16),
                    ],
                    const Text('选择图标', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      child: _buildIconSelector(),
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
                    Text('位置与分类', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 16),
                    const Text('选择位置（父空间）', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 8),
                    _buildParentSpaceSelector(),
                    const SizedBox(height: 16),
                    const Text('默认分类（选填）', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 4),
                    Text('选择空间后物品分类自动填充', style: TextStyle(fontSize: 10, color: Colors.grey[400])),
                    const SizedBox(height: 8),
                    _buildDefaultCategorySelector(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePicker() {
    return Row(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: _imagePath != null && _imagePath!.isNotEmpty
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(File(_imagePath!), fit: BoxFit.cover),
                )
              : IconButton(
                  icon: const Icon(Icons.add_a_photo, color: Colors.grey),
                  onPressed: _pickImage,
                ),
        ),
        const SizedBox(width: 12),
        if (_imagePath != null && _imagePath!.isNotEmpty)
          TextButton(
            onPressed: () => setState(() => _imagePath = null),
            child: const Text('删除图片'),
          ),
      ],
    );
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择图片来源'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, ImageSource.camera),
            child: const Text('相机'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ImageSource.gallery),
            child: const Text('相册'),
          ),
        ],
      ),
    );

    if (source != null) {
      final pickedFile = await picker.pickImage(source: source);
      if (pickedFile != null) {
        final appDir = await getApplicationDocumentsDirectory();
        final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
        final targetPath = '${appDir.path}/$fileName';
        try {
          final result = await FlutterImageCompress.compressAndGetFile(
            pickedFile.path, targetPath, quality: 70, minWidth: 800, minHeight: 800, format: CompressFormat.jpeg,
          );
          if (mounted) {
            setState(() {
              _imagePath = result?.path ?? targetPath;
            });
          }
        } catch (_) {
          if (mounted) {
            setState(() {
              _imagePath = pickedFile.path;
            });
          }
        }
      }
    }
  }

  Widget _buildIconSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _iconOptions.map((option) {
        final isSelected = _selectedIcon == option['name'];
        return GestureDetector(
          onTap: () => setState(() => _selectedIcon = option['name']),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isSelected ? Theme.of(context).colorScheme.primaryContainer : Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
              border: isSelected ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2) : null,
            ),
            child: Icon(
              option['icon'],
              color: isSelected ? Theme.of(context).colorScheme.onPrimaryContainer : Colors.grey[700],
              size: 28,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildParentSpaceSelector() {
    final houseProvider = context.read<HouseProvider>();
    final spaceProvider = context.read<SpaceProvider>();
    final currentHouse = houseProvider.currentHouse;
    if (currentHouse == null) return const SizedBox();

    final allSpaces = spaceProvider.getAllSpacesExceptSpecial(currentHouse.id);
    final parentSpace = spaceProvider.getSpaceById(_selectedParentId);

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: () {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('选择父空间'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      title: const Text('顶层空间（我的家）'),
                      leading: const Icon(Icons.home),
                      selected: _selectedParentId == null,
                      onTap: () {
                        setState(() => _selectedParentId = null);
                        Navigator.pop(context);
                      },
                    ),
                    ..._buildSpaceTreeOptions(allSpaces, null),
                  ],
                ),
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.location_on, color: Colors.grey),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  parentSpace != null
                      ? spaceProvider.getSpacePath(parentSpace, includeSelf: true)
                      : '顶层空间（我的家）',
                ),
              ),
              const Icon(Icons.arrow_drop_down, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSpaceTreeOptions(List<Space> allSpaces, String? parentId, [int level = 0]) {
    final children = allSpaces.where((s) => s.parentId == parentId).toList();
    return children.map((space) {
      final excludeId = widget.space?.id;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.only(left: 16.0 * level + 16, right: 16),
            title: Text(space.name),
            leading: const Icon(Icons.folder),
            selected: _selectedParentId == space.id,
            enabled: excludeId == null || space.id != excludeId,
            onTap: () {
              setState(() => _selectedParentId = space.id);
              Navigator.pop(context);
            },
          ),
          ..._buildSpaceTreeOptions(allSpaces, space.id, level + 1),
        ],
      );
    }).toList();
  }

  Widget _buildDefaultCategorySelector() {
    return Consumer<CategoryProvider>(
      builder: (context, categoryProvider, _) {
        final categories = categoryProvider.categories;
        final selectedCategory = _selectedDefaultCategoryId != null
            ? categories.where((c) => c.id == _selectedDefaultCategoryId).firstOrNull
            : null;

        return Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: InkWell(
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('选择默认分类'),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          title: const Text('不选择'),
                          leading: const Icon(Icons.block),
                          selected: _selectedDefaultCategoryId == null,
                          onTap: () {
                            setState(() => _selectedDefaultCategoryId = null);
                            Navigator.pop(context);
                          },
                        ),
                        ...categories.map((category) => ListTile(
                          title: Text(category.name),
                          leading: Icon(_getCategoryIcon(category.name)),
                          selected: _selectedDefaultCategoryId == category.id,
                          onTap: () {
                            setState(() => _selectedDefaultCategoryId = category.id);
                            Navigator.pop(context);
                          },
                        )),
                      ],
                    ),
                  ),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.category, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(selectedCategory?.name ?? '不选择'),
                  ),
                  const Icon(Icons.arrow_drop_down, color: Colors.grey),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  IconData _getCategoryIcon(String categoryName) {
    const icons = {
      '食品': Icons.local_dining,
      '药品': Icons.medication,
      '日用品': Icons.cleaning_services,
      '数码': Icons.devices,
      '美妆': Icons.spa,
      '其他': Icons.inventory_2,
    };
    return icons[categoryName] ?? Icons.category;
  }

  Future<void> _save() async {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入空间名称')),
      );
      return;
    }

    final spaceProvider = context.read<SpaceProvider>();

    if (widget.isAdd) {
      await spaceProvider.addSpace(
        houseId: widget.houseId!,
        name: _nameController.text,
        parentId: _selectedParentId,
        icon: _selectedIcon,
        imagePath: _imagePath,
        defaultCategoryId: _selectedDefaultCategoryId,
      );
    } else {
      await spaceProvider.updateSpace(
        widget.space!,
        newName: _nameController.text,
        newIcon: _selectedIcon,
        newImagePath: _imagePath,
        defaultCategoryId: _selectedDefaultCategoryId,
      );
      if (_selectedParentId != widget.space!.parentId) {
        await spaceProvider.moveSpace(widget.space!.id, _selectedParentId);
      }
    }

    if (mounted) {
      Navigator.pop(context);
    }
  }
}
