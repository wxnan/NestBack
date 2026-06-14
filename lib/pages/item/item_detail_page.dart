import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import '../../database/database.dart';
import '../../providers/item_provider.dart';
import '../../providers/space_provider.dart';
import '../../providers/attribute_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/house_provider.dart';
import '../../providers/tag_provider.dart';
import '../../providers/settings_provider.dart';

class ItemDetailPage extends StatefulWidget {
  final Item item;
  final bool isCopy;
  final bool isSplit;

  const ItemDetailPage({
    super.key,
    required this.item,
    this.isCopy = false,
    this.isSplit = false,
  });

  @override
  State<ItemDetailPage> createState() => _ItemDetailPageState();
}

class _ItemDetailPageState extends State<ItemDetailPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _quantityController = TextEditingController();
  final _unitController = TextEditingController();
  final _priceController = TextEditingController();
  final _totalPriceController = TextEditingController();
  final _noteController = TextEditingController();

  String? _selectedCategory;
  String? _selectedCategoryId;
  String? _selectedSubcategoryId;
  String? _selectedSpaceId;
  List<String> _selectedTags = [];
  Map<String, String> _customAttributes = {};
  String? _imagePath;
  bool _enableLowStockReminder = false;

  bool _isCalculating = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.item.name;
    _quantityController.text = (widget.isCopy || widget.isSplit) ? '1' : widget.item.quantity.toString();
    _unitController.text = widget.item.unit ?? '件';
    _priceController.text = widget.item.price?.toString() ?? '';
    if (widget.item.price != null) {
      _totalPriceController.text = (widget.item.price! * widget.item.quantity).toStringAsFixed(2);
    }
    _noteController.text = widget.item.note ?? '';
    _selectedCategory = widget.item.category ?? '其他';
    _selectedCategoryId = widget.item.categoryId;
    _selectedSubcategoryId = widget.item.subcategoryId;
    _selectedSpaceId = widget.item.spaceId;
    _selectedTags = widget.item.tags != null 
        ? (widget.item.tags!.split(',').where((t) => t.isNotEmpty).toList()) 
        : [];
    _imagePath = widget.item.imagePath;
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final categoryProvider = context.read<CategoryProvider>();
      if (_selectedCategoryId != null && _selectedCategoryId!.isNotEmpty) {
        categoryProvider.loadSubcategories(_selectedCategoryId!);
      }
    });
    
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final itemProvider = context.read<ItemProvider>();
      final attrs = await itemProvider.getItemAttributes(widget.item.id);
      if (mounted) {
        setState(() {
          _customAttributes = attrs;
          _enableLowStockReminder = attrs['_low_stock_reminder'] == 'true';
        });
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    _unitController.dispose();
    _priceController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String title = '物品详情';
    if (widget.isCopy) {
      title = '复制物品';
    } else if (widget.isSplit) {
      title = '拆分物品';
    }
    
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (!widget.isCopy && !widget.isSplit)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _showDeleteDialog(context),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildBasicInfoSection(),
            const SizedBox(height: 16),
            _buildExtendedInfoSection(),
            const SizedBox(height: 16),
            if (!widget.isCopy && !widget.isSplit) ...[
              _buildMoveButton(),
              const SizedBox(height: 8),
              _buildMoveToOtherHouseButton(),
              const SizedBox(height: 16),
            ],
            const SizedBox(height: 100),
          ],
        ),
      ),
      bottomNavigationBar: _buildSubmitButton(),
    );
  }

  Widget _buildBasicInfoSection() {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
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
            _buildCoverSection(),
            const SizedBox(height: 16),
            _buildNameField(),
            const SizedBox(height: 16),
            _buildLocationSelector(),
            const SizedBox(height: 16),
            _buildCategorySelector(),
            const SizedBox(height: 16),
            _buildSubcategorySelector(),
            const SizedBox(height: 16),
            _buildQuantitySection(),
            const SizedBox(height: 16),
            _buildLowStockReminderSection(),
            const SizedBox(height: 16),
            _buildPriceSection(),
            const SizedBox(height: 16),
            _buildTagSection(),
            const SizedBox(height: 16),
            _buildNoteField(),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('封面'),
        const SizedBox(height: 8),
        Row(
          children: [
            InkWell(
              onTap: _imagePath != null ? () => _showImagePreview() : null,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _imagePath != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(File(_imagePath!), fit: BoxFit.cover),
                      )
                    : IconButton(
                        icon: Icon(Icons.add_a_photo, size: 40, color: Colors.grey[400]),
                        onPressed: () => _showImagePicker(),
                      ),
              ),
            ),
            const SizedBox(width: 16),
            if (_imagePath != null)
              Column(
                children: [
                  TextButton(
                    onPressed: () => _showImagePicker(),
                    child: const Text('更换封面'),
                  ),
                  TextButton(
                    onPressed: () => _removeImage(),
                    child: const Text('删除封面'),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _showImagePicker() async {
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
        
        await _compressAndSaveImage(pickedFile.path, targetPath);
        
        setState(() {
          _imagePath = targetPath;
        });
      }
    }
  }

  Future<void> _compressAndSaveImage(String sourcePath, String targetPath) async {
    try {
      final result = await FlutterImageCompress.compressAndGetFile(
        sourcePath,
        targetPath,
        quality: 70,
        minWidth: 1200,
        minHeight: 1200,
        format: CompressFormat.jpeg,
      );
      
      if (result == null) {
        await File(sourcePath).copy(targetPath);
      }
    } catch (e) {
      await File(sourcePath).copy(targetPath);
    }
  }

  void _removeImage() {
    setState(() {
      _imagePath = null;
    });
  }

  void _showImagePreview() {
    showDialog(
      context: context,
      barrierColor: Colors.black,
      builder: (context) => GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.black,
          child: Center(
            child: InteractiveViewer(
              child: Image.file(
                File(_imagePath!),
                fit: BoxFit.contain,
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNameField() {
    return TextFormField(
      controller: _nameController,
      decoration: InputDecoration(
        labelText: '物品名称 *',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        prefixIcon: const Icon(Icons.inventory_2),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return '请输入物品名称';
        }
        return null;
      },
    );
  }

  Widget _buildCategorySelector() {
    return Consumer2<CategoryProvider, HouseProvider>(
      builder: (context, categoryProvider, houseProvider, _) {
        final currentHouse = houseProvider.currentHouse;
        if (currentHouse == null) return const SizedBox();

        // Ensure _selectedCategory exists in current categories and sync _selectedCategoryId
        final categoryNames = categoryProvider.categories.map((c) => c.name).toList();
        if (_selectedCategory != null && !categoryNames.contains(_selectedCategory)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _selectedCategory = categoryNames.isNotEmpty ? categoryNames.first : null;
                _selectedCategoryId = categoryNames.isNotEmpty
                    ? categoryProvider.categories.first.id
                    : null;
              });
              if (_selectedCategoryId != null) {
                categoryProvider.loadSubcategories(_selectedCategoryId!);
              }
            }
          });
        } else if (_selectedCategory != null && (_selectedCategoryId == null || _selectedCategoryId!.isEmpty)) {
          // Category name exists but ID is not set, look it up
          final matchedCategory = categoryProvider.categories.firstWhereOrNull((c) => c.name == _selectedCategory);
          if (matchedCategory != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _selectedCategoryId = matchedCategory.id;
                });
                categoryProvider.loadSubcategories(matchedCategory.id);
              }
            });
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('分类 *', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: categoryProvider.categories.map((category) {
                final isSelected = _selectedCategory == category.name;
                return FilterChip(
                  label: Text(category.name),
                  selected: isSelected,
                  showCheckmark: false,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        if (category.name != _selectedCategory) {
                          _selectedSubcategoryId = null;
                        }
                        _selectedCategory = category.name;
                        _selectedCategoryId = category.id;
                        categoryProvider.loadSubcategories(category.id);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSubcategorySelector() {
    return Consumer2<CategoryProvider, HouseProvider>(
      builder: (context, categoryProvider, houseProvider, _) {
        if (_selectedCategoryId == null || _selectedCategoryId!.isEmpty) {
          if (_selectedSubcategoryId != null && _selectedSubcategoryId!.isNotEmpty) {
            return FutureBuilder<String>(
              future: _loadSubcategoryName(_selectedSubcategoryId!),
              builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('二级分类', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilterChip(
                          label: Text(snapshot.data!),
                          selected: true,
                          showCheckmark: false,
                          onSelected: (selected) {
                            setState(() {
                              _selectedSubcategoryId = null;
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                );
              }
              return const SizedBox();
            },
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('二级分类（选填）', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              const SizedBox(height: 8),
              Text('请先选择分类', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
            ],
          );
        }

        final subcategories = categoryProvider.getSubcategoriesForCategory(_selectedCategoryId!);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('二级分类（选填）', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                const Spacer(),
                TextButton.icon(
                  onPressed: () async {
                    final newName = await _showAddSubcategoryDialog(context, categoryProvider, houseProvider.currentHouse);
                    if (newName != null && newName.isNotEmpty) {
                      // Auto-select the newly added subcategory
                      final subs = categoryProvider.getSubcategoriesForCategory(_selectedCategoryId!);
                      final newSub = subs.firstWhereOrNull((s) => s.name == newName);
                      setState(() {
                        _selectedSubcategoryId = newSub?.id;
                      });
                    }
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('添加'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (subcategories.isEmpty)
              Text('暂无二级分类', style: TextStyle(color: Colors.grey[400], fontSize: 13))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: subcategories.map((subcategory) {
                  final isSelected = _selectedSubcategoryId == subcategory.id;
                  return FilterChip(
                    label: Text(subcategory.name),
                    selected: isSelected,
                    showCheckmark: false,
                    onSelected: (selected) {
                      setState(() {
                        _selectedSubcategoryId = selected ? subcategory.id : null;
                      });
                    },
                  );
                }).toList(),
              ),
          ],
        );
      },
    );
  }


  Future<String?> _showAddSubcategoryDialog(
    BuildContext context,
    CategoryProvider categoryProvider,
    House? currentHouse,
  ) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加二级分类'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '二级分类名称',
            hintText: '请输入二级分类名称',
          ),
          autofocus: true,
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.pop(context, value.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              
              if (currentHouse != null && _selectedCategoryId != null) {
                await categoryProvider.addSubcategory(
                  categoryId: _selectedCategoryId!,
                  name: name,
                );
              }
              Navigator.pop(context, name);
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  Future<String> _loadSubcategoryName(String subcategoryId) async {
    final categoryProvider = context.read<CategoryProvider>();
    final allSubcategories = categoryProvider.subcategories;
    final match = allSubcategories.where((s) => s.id == subcategoryId).toList();
    if (match.isNotEmpty) return match.first.name;

    final db = AppDatabase();
    final results = await (db.select(db.subcategories)
          ..where((t) => t.id.equals(subcategoryId)))
        .get();
    return results.isNotEmpty ? results.first.name : '';
  }

  Widget _buildLocationSelector() {
    return Consumer2<SpaceProvider, HouseProvider>(
      builder: (context, spaceProvider, houseProvider, _) {
        final currentHouse = houseProvider.currentHouse;
        if (currentHouse == null) {
          return const SizedBox();
        }

        final spaces = spaceProvider.spaces
            .where((s) => s.houseId == currentHouse.id && s.type != 'trash')
            .toList();

        final selectedSpace = _selectedSpaceId != null
            ? spaceProvider.getSpaceById(_selectedSpaceId)
            : null;
        final spacePath = selectedSpace != null
            ? spaceProvider.getSpacePath(selectedSpace, includeSelf: true)
            : '请选择位置';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('位置 *', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => _showSpacePickerBottomSheet(spaceProvider, currentHouse.id),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.place, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        spacePath,
                        style: TextStyle(
                          color: selectedSpace != null ? null : Colors.grey,
                        ),
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showSpacePickerBottomSheet(SpaceProvider spaceProvider, String houseId) {
    final allSpaces = spaceProvider.getAllSpacesExceptSpecial(houseId);
    final pendingSpace = spaceProvider.getPendingSpace(houseId);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  const Text('选择位置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(8),
                children: [
                  if (pendingSpace != null)
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.only(left: 16, right: 16),
                      leading: Icon(
                        _selectedSpaceId == pendingSpace.id ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        color: _selectedSpaceId == pendingSpace.id ? Theme.of(context).colorScheme.primary : Colors.grey,
                      ),
                      title: Text(
                        '待整理',
                        style: TextStyle(
                          fontWeight: _selectedSpaceId == pendingSpace.id ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      trailing: const Icon(Icons.inbox, size: 18, color: Colors.grey),
                      onTap: () async {
                        final confirmed = await _showMoveConfirmDialog('待整理');
                        if (confirmed) {
                          setState(() {
                            _selectedSpaceId = pendingSpace.id;
                            _onSpaceChanged(pendingSpace);
                          });
                        }
                        if (context.mounted) {
                          Navigator.pop(context);
                        }
                      },
                    ),
                  ..._buildSpaceTreeItems(allSpaces, null, 0, context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSpaceTreeItems(List<Space> allSpaces, String? parentId, int level, BuildContext sheetContext) {
    final children = allSpaces.where((s) => s.parentId == parentId).toList();
    return children.map((space) {
      final subChildren = allSpaces.where((s) => s.parentId == space.id).toList();
      final isSelected = _selectedSpaceId == space.id;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.only(left: 16.0 * level + 16, right: 16),
            leading: Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey,
            ),
            title: Text(
              space.name,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            trailing: subChildren.isNotEmpty
                ? const Icon(Icons.folder, size: 18, color: Colors.grey)
                : null,
            onTap: () async {
              final targetSpace = space;
              final confirmed = await _showMoveConfirmDialog(targetSpace.name);
              if (confirmed) {
                setState(() {
                  _selectedSpaceId = space.id;
                  _onSpaceChanged(space);
                });
              }
              if (sheetContext.mounted) {
                Navigator.pop(sheetContext);
              }
            },
          ),
          ..._buildSpaceTreeItems(allSpaces, space.id, level + 1, sheetContext),
        ],
      );
    }).toList();
  }

  void _onSpaceChanged(Space space) {
    // Auto-fill category from space's default category
    if (space.defaultCategoryId != null && space.defaultCategoryId!.isNotEmpty) {
      final categoryProvider = context.read<CategoryProvider>();
      final currentCategory = _selectedCategory;
      // Only auto-fill if current category is "其他"
      if (currentCategory == '其他' || currentCategory == null) {
        final defaultCategory = categoryProvider.categories
            .where((c) => c.id == space.defaultCategoryId)
            .firstOrNull;
        if (defaultCategory != null) {
          setState(() {
            _selectedCategory = defaultCategory.name;
            _selectedCategoryId = defaultCategory.id;
            _selectedSubcategoryId = null;
          });
          categoryProvider.loadSubcategories(defaultCategory.id);
        }
      }
    }
  }

  Future<bool> _showMoveConfirmDialog(String targetSpaceName) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移动物品'),
        content: Text('确定将物品移动到 "$targetSpaceName" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    ) ?? false;
  }

  Widget _buildQuantitySection() {
    final maxQuantity = widget.isSplit ? widget.item.quantity - 1 : null;
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: TextFormField(
            controller: _quantityController,
            decoration: InputDecoration(
              labelText: widget.isSplit ? '拆分数量（最大${maxQuantity}）' : '数量 *',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: const Icon(Icons.numbers),
            ),
            keyboardType: TextInputType.number,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '请输入数量';
              }
              final qty = int.tryParse(value);
              if (qty == null || qty <= 0) {
                return '请输入有效的数量';
              }
              if (widget.isSplit) {
                if (qty >= widget.item.quantity) {
                  return '拆分数量必须小于原数量（${widget.item.quantity}）';
                }
                if (qty > maxQuantity!) {
                  return '拆分数量不能超过$maxQuantity';
                }
              }
              return null;
            },
            onChanged: (value) => setState(() {}),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: _buildUnitSelector(),
        ),
      ],
    );
  }

  Widget _buildLowStockReminderSection() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text('最低库存提醒'),
        Switch(
          value: _enableLowStockReminder,
          onChanged: (value) {
            setState(() {
              _enableLowStockReminder = value;
            });
          },
        ),
      ],
    );
  }

  final List<String> _commonUnits = ['件', '个', '瓶', '盒', '箱', '包', '袋', '罐', '支', '本', '台', '套'];

  Widget _buildUnitSelector() {
    final isInCommonUnits = _commonUnits.contains(_unitController.text);
    
    return DropdownButtonFormField<String>(
      value: isInCommonUnits ? _unitController.text : null,
      decoration: InputDecoration(
        labelText: '单位',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 15),
      ),
      hint: Text(_unitController.text.isNotEmpty ? _unitController.text : '单位'),
      items: [
        ..._commonUnits.map((unit) => DropdownMenuItem<String>(
              value: unit,
              child: SizedBox(
                width: 70,
                child: Text(unit, textAlign: TextAlign.center),
              ),
            )),
        const DropdownMenuItem<String>(
          value: '_custom',
          child: SizedBox(
            width: 70,
            child: Text('自定义...', textAlign: TextAlign.center),
          ),
        ),
      ],
      onChanged: (value) async {
        if (value == '_custom') {
          final customUnit = await _showCustomUnitDialog();
          if (customUnit != null && customUnit.isNotEmpty) {
            setState(() {
              _unitController.text = customUnit;
            });
          }
        } else if (value != null) {
          setState(() {
            _unitController.text = value;
          });
        }
      },
      menuMaxHeight: 200,
      isExpanded: true,
    );
  }

  Future<String?> _showCustomUnitDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('自定义单位'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '单位',
            hintText: '请输入单位',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceSection() {
    return Column(
      children: [
        TextFormField(
          controller: _priceController,
          decoration: InputDecoration(
            labelText: '单价（选填，不填则归入等待估值）',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            prefixIcon: const Icon(Icons.attach_money),
            prefixText: '¥ ',
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (value) {
            if (_isCalculating) return;
            _isCalculating = true;
            setState(() {
              final price = double.tryParse(value);
              final quantity = int.tryParse(_quantityController.text) ?? 1;
              if (price != null) {
                _totalPriceController.text = (price * quantity).toStringAsFixed(2);
              } else {
                _totalPriceController.clear();
              }
            });
            _isCalculating = false;
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _totalPriceController,
          decoration: InputDecoration(
            labelText: '总价（选填）',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            prefixIcon: const Icon(Icons.money),
            prefixText: '¥ ',
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (value) {
            if (_isCalculating) return;
            _isCalculating = true;
            setState(() {
              final total = double.tryParse(value);
              final quantity = int.tryParse(_quantityController.text) ?? 1;
              if (total != null && quantity > 0) {
                _priceController.text = (total / quantity).toStringAsFixed(2);
              } else {
                _priceController.clear();
              }
            });
            _isCalculating = false;
          },
        ),
      ],
    );
  }

  Widget _buildTagSection() {
    return Consumer2<TagProvider, HouseProvider>(
      builder: (context, tagProvider, houseProvider, _) {
        final currentHouse = houseProvider.currentHouse;
        if (currentHouse != null && tagProvider.tags.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            tagProvider.loadTags();
          });
        }

        final tags = tagProvider.tags;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('标签（选填）', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _showAddTagDialog(tagProvider, currentHouse),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('添加'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: tags.map((tag) {
                final isSelected = _selectedTags.contains(tag.name);
                return FilterChip(
                  label: Text(tag.name),
                  selected: isSelected,
                  showCheckmark: false,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        if (!_selectedTags.contains(tag.name)) {
                          _selectedTags.add(tag.name);
                        }
                      } else {
                        _selectedTags.remove(tag.name);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showAddTagDialog(TagProvider tagProvider, House? currentHouse) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加新标签'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '标签名称',
            hintText: '请输入标签名称',
          ),
          autofocus: true,
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.pop(context, value.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && currentHouse != null) {
      setState(() {
        if (!_selectedTags.contains(result)) {
          _selectedTags.add(result);
        }
      });
      await tagProvider.addTag(houseId: currentHouse.id, name: result);
    }
  }

  Widget _buildNoteField() {
    return TextFormField(
      controller: _noteController,
      decoration: InputDecoration(
        labelText: '备注',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        prefixIcon: const Icon(Icons.note),
      ),
      maxLines: 2,
    );
  }

  Widget _buildExtendedInfoSection() {
    return Consumer3<AttributeProvider, CategoryProvider, HouseProvider>(
      builder: (context, attributeProvider, categoryProvider, houseProvider, _) {
        final currentHouse = houseProvider.currentHouse;
        if (currentHouse == null) return const SizedBox();

        final category = categoryProvider.categories.firstWhere(
          (c) => c.name == _selectedCategory,
          orElse: () => Category(id: '', houseId: currentHouse.id, name: '其他', icon: null, sortOrder: 0, createdAt: DateTime.now()),
        );

        return FutureBuilder<List<Attribute>>(
          future: attributeProvider.getAttributesForCategory(category.id),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }

            final attributes = snapshot.data!;
            
            if (attributes.isEmpty) {
              return const SizedBox();
            }

            return Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '扩展信息',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    ...attributes.map((attr) => _buildAttributeField(attr)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAttributeField(Attribute attribute) {
    final options = attribute.options?.split(';') ?? [];
    final currentValue = _customAttributes[attribute.id] ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(attribute.name),
          if (attribute.hint != null)
            Text(attribute.hint!, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
          const SizedBox(height: 8),
          _buildAttributeInput(attribute, currentValue, options),
        ],
      ),
    );
  }

  Widget _buildAttributeInput(Attribute attribute, String currentValue, List<String> options) {
    switch (attribute.type) {
      case 'number':
        return TextFormField(
          initialValue: currentValue,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (value) => _customAttributes[attribute.id] = value,
        );
      case 'duration':
        if (attribute.name == '保质期') {
          return _buildDurationField(attribute, currentValue, options, '过期日期', '生产日期');
        } else if (attribute.name == '保修期') {
          return _buildDurationField(attribute, currentValue, options, '过保日期', '购买日期');
        }
        return _buildDurationField(attribute, currentValue, options, '', '');
      case 'date':
        return InkWell(
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: currentValue.isNotEmpty
                  ? DateTime.parse(currentValue)
                  : DateTime.now(),
              firstDate: DateTime.now().subtract(const Duration(days: 365 * 10)),
              lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
            );
            if (date != null) {
              setState(() {
                _customAttributes[attribute.id] = _formatDate(date);
                _tryCalculateTargetDate(attribute.name);
              });
            }
          },
          child: InputDecorator(
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  currentValue.isNotEmpty ? currentValue : '请选择',
                  style: TextStyle(color: currentValue.isNotEmpty ? null : Colors.grey),
                ),
                const Icon(Icons.calendar_today),
              ],
            ),
          ),
        );
      case 'select':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: options.map((opt) {
                final isSelected = currentValue == opt;
                return FilterChip(
                  label: Text(opt),
                  selected: isSelected,
                  showCheckmark: false,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _customAttributes[attribute.id] = opt;
                      } else {
                        _customAttributes.remove(attribute.id);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: () => _showAddAttributeOptionDialog(attribute),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('添加选项'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        );
      case 'multi_select':
        final selectedValues = currentValue.isNotEmpty ? currentValue.split(';') : <String>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: options.map((opt) {
                final isSelected = selectedValues.contains(opt);
                return FilterChip(
                  label: Text(opt),
                  selected: isSelected,
                  showCheckmark: false,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        selectedValues.add(opt);
                      } else {
                        selectedValues.remove(opt);
                      }
                      if (selectedValues.isNotEmpty) {
                        _customAttributes[attribute.id] = selectedValues.join(';');
                      } else {
                        _customAttributes.remove(attribute.id);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: () => _showAddAttributeOptionDialog(attribute),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('添加选项'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        );
      case 'link':
        return TextFormField(
          initialValue: currentValue,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            prefixIcon: const Icon(Icons.link),
            hintText: '请输入链接地址',
            suffixIcon: currentValue.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.open_in_new),
                    tooltip: '打开链接',
                    onPressed: () => _launchUrl(currentValue),
                  )
                : null,
          ),
          keyboardType: TextInputType.url,
          maxLines: 1,
          onChanged: (value) => _customAttributes[attribute.id] = value,
        );
      default:
        return TextFormField(
          initialValue: currentValue,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onChanged: (value) => _customAttributes[attribute.id] = value,
        );
    }
  }

  Future<void> _showAddAttributeOptionDialog(Attribute attribute) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('添加${attribute.name}选项'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '选项名称',
            hintText: '请输入选项名称',
          ),
          autofocus: true,
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.pop(context, value.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final attributeProvider = context.read<AttributeProvider>();
      final currentOptions = attribute.options ?? '';
      final newOptions = currentOptions.isEmpty ? result : '$currentOptions;$result';
      await attributeProvider.updateAttributeOptions(attribute.id, newOptions);
      setState(() {});
    }
  }

  Widget _buildDurationField(Attribute attribute, String currentValue, List<String> options, String targetDateField, String sourceDateField) {
    final valueParts = currentValue.split('|');
    final durationValue = valueParts.length > 0 ? valueParts[0] : '';
    final selectedUnit = valueParts.length > 1 ? valueParts[1] : options.first;

    void _updateTargetDate() {
      if (targetDateField.isEmpty || sourceDateField.isEmpty) return;
      
      final sourceDateAttr = _findAttributeByName(sourceDateField);
      final targetDateAttr = _findAttributeByName(targetDateField);
      
      if (sourceDateAttr == null || targetDateAttr == null) return;
      
      final sourceDateStr = _customAttributes[sourceDateAttr.id];
      if (sourceDateStr == null || sourceDateStr.isEmpty) return;
      
      final durationStr = _customAttributes[attribute.id];
      if (durationStr == null || durationStr.isEmpty) return;
      
      final durationParts = durationStr.split('|');
      final durationValue = durationParts.length > 0 ? durationParts[0] : '';
      final selectedUnit = durationParts.length > 1 ? durationParts[1] : '天';
      
      final duration = int.tryParse(durationValue);
      if (duration == null || duration <= 0) return;
      
      try {
        final sourceDate = DateTime.parse(sourceDateStr);
        DateTime targetDate;
        
        switch (selectedUnit) {
          case '天':
            targetDate = sourceDate.add(Duration(days: duration));
            break;
          case '月':
            targetDate = sourceDate.add(Duration(days: duration * 30));
            break;
          case '年':
            targetDate = sourceDate.add(Duration(days: duration * 365));
            break;
          default:
            targetDate = sourceDate.add(Duration(days: duration));
        }
        
        setState(() {
          _customAttributes[targetDateAttr.id] = _formatDate(targetDate);
        });
      } catch (_) {
        // 日期解析失败
      }
    }

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: TextFormField(
            initialValue: durationValue,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            keyboardType: TextInputType.number,
            onChanged: (value) {
              _customAttributes[attribute.id] = '$value|$selectedUnit';
              _updateTargetDate();
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 1,
          child: DropdownButtonFormField<String>(
            value: selectedUnit,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            items: options.map((opt) => DropdownMenuItem<String>(
              value: opt,
              child: Text(opt),
            )).toList(),
            onChanged: (value) {
              if (value != null) {
                _customAttributes[attribute.id] = '$durationValue|$value';
                _updateTargetDate();
              }
            },
          ),
        ),
      ],
    );
  }

  Attribute? _findAttributeByName(String name) {
    final attributeProvider = Provider.of<AttributeProvider>(context, listen: false);
    final categoryProvider = Provider.of<CategoryProvider>(context, listen: false);
    final houseProvider = Provider.of<HouseProvider>(context, listen: false);
    
    if (houseProvider.currentHouse == null) return null;
    
    final category = categoryProvider.categories.firstWhere(
      (c) => c.name == _selectedCategory,
      orElse: () => Category(id: '', houseId: houseProvider.currentHouse!.id, name: '其他', icon: null, sortOrder: 0, createdAt: DateTime.now()),
    );
    
    return attributeProvider.attributes.firstWhere(
      (a) => a.name == name,
      orElse: () => Attribute(
        id: '',
        houseId: houseProvider.currentHouse!.id,
        name: '',
        type: '',
        hint: null,
        options: null,
        required: false,
        sortOrder: 0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
  }

  void _tryCalculateTargetDate(String sourceDateName) {
    String? durationName;
    String? targetDateName;
    
    if (sourceDateName == '生产日期') {
      durationName = '保质期';
      targetDateName = '过期日期';
    } else if (sourceDateName == '购买日期') {
      durationName = '保修期';
      targetDateName = '过保日期';
    }
    
    if (durationName == null || targetDateName == null) return;
    
    final sourceDateAttr = _findAttributeByName(sourceDateName);
    final durationAttr = _findAttributeByName(durationName);
    final targetDateAttr = _findAttributeByName(targetDateName);
    
    if (sourceDateAttr == null || durationAttr == null || targetDateAttr == null) return;
    
    final sourceDateStr = _customAttributes[sourceDateAttr.id];
    final durationStr = _customAttributes[durationAttr.id];
    
    if (sourceDateStr == null || sourceDateStr.isEmpty) return;
    if (durationStr == null || durationStr.isEmpty) return;
    
    final durationParts = durationStr.split('|');
    final durationValue = durationParts.length > 0 ? durationParts[0] : '';
    final durationUnit = durationParts.length > 1 ? durationParts[1] : '天';
    
    final duration = int.tryParse(durationValue);
    if (duration == null || duration <= 0) return;
    
    try {
      final sourceDate = DateTime.parse(sourceDateStr);
      DateTime targetDate;
      
      switch (durationUnit) {
        case '天':
          targetDate = sourceDate.add(Duration(days: duration));
          break;
        case '月':
          targetDate = sourceDate.add(Duration(days: duration * 30));
          break;
        case '年':
          targetDate = sourceDate.add(Duration(days: duration * 365));
          break;
        default:
          targetDate = sourceDate.add(Duration(days: duration));
      }
      
      setState(() {
        _customAttributes[targetDateAttr.id] = _formatDate(targetDate);
      });
    } catch (_) {
      // 日期解析失败
    }
  }

  Widget _buildMoveButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _moveToSpace(context),
        icon: const Icon(Icons.drive_file_move),
        label: const Text('移动到其他空间'),
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  Widget _buildMoveToOtherHouseButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _moveToOtherHouse(context),
        icon: const Icon(Icons.home_outlined),
        label: const Text('移动到其他家庭'),
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    String buttonText = '保存修改';
    if (widget.isCopy) {
      buttonText = '复制物品';
    } else if (widget.isSplit) {
      buttonText = '拆分物品';
    }
    
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _saveChanges,
          icon: const Icon(Icons.save),
          label: Text(buttonText),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _moveToSpace(BuildContext context) async {
    final spaceProvider = context.read<SpaceProvider>();
    final itemProvider = context.read<ItemProvider>();

    await spaceProvider.loadSpaces(widget.item.houseId);
    final spaces = spaceProvider.spaces
        .where((s) => s.type != 'trash')
        .toList();

    if (!mounted) return;

    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => ListView.builder(
        itemCount: spaces.length,
        itemBuilder: (context, index) {
          final space = spaces[index];
          return ListTile(
            leading: Icon(_getSpaceIcon(space.type)),
            title: Text(space.name),
            subtitle: Text(_getSpaceTypeName(space.type)),
            onTap: () => Navigator.pop(context, space.id),
          );
        },
      ),
    );

    if (result != null) {
      await itemProvider.moveItem(widget.item, result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('物品已移动')),
        );
        setState(() {
          _selectedSpaceId = result;
        });
      }
    }
  }

  Future<void> _moveToOtherHouse(BuildContext context) async {
    final houseProvider = context.read<HouseProvider>();
    final spaceProvider = context.read<SpaceProvider>();
    final itemProvider = context.read<ItemProvider>();

    // 获取除当前家庭外的其他家庭
    final otherHouses = houseProvider.houses
        .where((h) => h.id != widget.item.houseId)
        .toList();

    if (otherHouses.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有其他家庭可移动')),
        );
      }
      return;
    }

    if (!mounted) return;

    // 第一步：选择目标家庭
    final selectedHouse = await showModalBottomSheet<House>(
      context: context,
      isScrollControlled: true,
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  const Text('选择目标家庭', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: otherHouses.length,
                itemBuilder: (context, index) {
                  final house = otherHouses[index];
                  return ListTile(
                    leading: const Icon(Icons.home_outlined),
                    title: Text(house.name),
                    onTap: () => Navigator.pop(context, house),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (selectedHouse == null || !mounted) return;

    // 第二步：加载目标家庭的空间列表
    await spaceProvider.loadSpaces(selectedHouse.id);
    final spaces = spaceProvider.spaces
        .where((s) => s.type != 'trash')
        .toList();

    if (spaces.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${selectedHouse.name} 中没有可用空间')),
        );
      }
      return;
    }

    if (!mounted) return;

    // 第三步：选择目标空间
    final selectedSpaceId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Text('选择 ${selectedHouse.name} 中的空间', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: spaces.length,
                itemBuilder: (context, index) {
                  final space = spaces[index];
                  return ListTile(
                    leading: Icon(_getSpaceIcon(space.type)),
                    title: Text(space.name),
                    subtitle: Text(_getSpaceTypeName(space.type)),
                    onTap: () => Navigator.pop(context, space.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (selectedSpaceId != null) {
      await itemProvider.moveItem(
        widget.item,
        selectedSpaceId,
        targetHouseId: selectedHouse.id,
      );

      // 切换到目标家庭并加载物品和空间数据
      houseProvider.switchHouse(selectedHouse);
      await itemProvider.loadItems(selectedHouse.id);
      await spaceProvider.loadSpaces(selectedHouse.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('物品已移动到 ${selectedHouse.name}')),
        );
        Navigator.pop(context);
      }
    }
  }

  String _getSpaceTypeName(String type) {
    switch (type) {
      case 'room':
        return '房间';
      case 'container':
        return '容器';
      case 'sub_container':
        return '子容器';
      case 'pending':
        return '待整理';
      default:
        return type;
    }
  }

  IconData _getSpaceIcon(String type) {
    switch (type) {
      case 'room':
        return Icons.meeting_room;
      case 'container':
        return Icons.inventory_2;
      case 'sub_container':
        return Icons.luggage;
      case 'pending':
        return Icons.pending;
      case 'trash':
        return Icons.delete;
      case 'recycle':
        return Icons.delete_outline;
      default:
        return Icons.folder;
    }
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    debugPrint('[_saveChanges] _selectedSubcategoryId: $_selectedSubcategoryId');
    debugPrint('[_saveChanges] _selectedCategoryId: $_selectedCategoryId');
    debugPrint('[_saveChanges] widget.item.subcategoryId: ${widget.item.subcategoryId}');

    final itemProvider = context.read<ItemProvider>();
    final tagProvider = context.read<TagProvider>();

    // 自动同步新标签到数据库
    if (_selectedTags.isNotEmpty) {
      final existingTagNames = tagProvider.tags.map((t) => t.name).toList();
      for (final tagName in _selectedTags) {
        if (!existingTagNames.contains(tagName)) {
          await tagProvider.addTag(houseId: widget.item.houseId, name: tagName);
        }
      }
    }

    // 获取过期日期和过保日期
    DateTime? expireDate;
    DateTime? warrantyExpireDate;
    
    if (_selectedCategory != null) {
      final expireDateAttr = _findAttributeByName('过期日期');
      final warrantyExpireDateAttr = _findAttributeByName('过保日期');
      
      if (expireDateAttr != null && expireDateAttr.id.isNotEmpty) {
        final expireDateStr = _customAttributes[expireDateAttr.id];
        if (expireDateStr != null && expireDateStr.isNotEmpty) {
          try {
            expireDate = DateTime.parse(expireDateStr);
          } catch (_) {
          }
        }
      }
      
      if (warrantyExpireDateAttr != null && warrantyExpireDateAttr.id.isNotEmpty) {
        final warrantyExpireDateStr = _customAttributes[warrantyExpireDateAttr.id];
        if (warrantyExpireDateStr != null && warrantyExpireDateStr.isNotEmpty) {
          try {
            warrantyExpireDate = DateTime.parse(warrantyExpireDateStr);
          } catch (_) {
          }
        }
      }
    }

    final finalExpireDate = expireDate ?? warrantyExpireDate;
    final expireDateSource = expireDate != null
        ? 'expire'
        : (warrantyExpireDate != null ? 'warranty' : null);
    final newQuantity = int.tryParse(_quantityController.text) ?? 1;

    // 如果启用了最低库存提醒，添加到自定义属性
    if (_enableLowStockReminder) {
      final settingsProvider = context.read<SettingsProvider>();
      final threshold = settingsProvider.lowStockThreshold;
      _customAttributes['_low_stock_reminder'] = 'true';
      _customAttributes['_low_stock_threshold'] = threshold.toString();
    } else {
      _customAttributes.remove('_low_stock_reminder');
      _customAttributes.remove('_low_stock_threshold');
    }

    // 复制模式：创建新物品，原物品不变
    if (widget.isCopy) {
      await itemProvider.addItem(
        houseId: widget.item.houseId,
        spaceId: _selectedSpaceId ?? widget.item.spaceId,
        name: _nameController.text,
        quantity: newQuantity,
        unit: _unitController.text.isNotEmpty ? _unitController.text : '件',
        price: _priceController.text.isNotEmpty
            ? double.tryParse(_priceController.text)
            : null,
        category: _selectedCategory ?? widget.item.category,
        categoryId: _selectedCategoryId,
        subcategoryId: _selectedSubcategoryId,
        tags: _selectedTags.isNotEmpty ? _selectedTags : null,
        imagePath: _imagePath,
        note: _noteController.text.isNotEmpty ? _noteController.text : null,
        expireDate: finalExpireDate,
        customAttributes: _customAttributes.isNotEmpty ? _customAttributes : null,
        expireDateSource: expireDateSource,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('物品已复制')),
        );
        Navigator.pop(context);
      }
      return;
    }

    // 拆分模式：创建新物品，原物品数量减少
    if (widget.isSplit) {
      final newItemId = await itemProvider.addItem(
        houseId: widget.item.houseId,
        spaceId: _selectedSpaceId ?? widget.item.spaceId,
        name: _nameController.text,
        quantity: newQuantity,
        unit: _unitController.text.isNotEmpty ? _unitController.text : '件',
        price: _priceController.text.isNotEmpty
            ? double.tryParse(_priceController.text)
            : null,
        category: _selectedCategory ?? widget.item.category,
        categoryId: _selectedCategoryId,
        subcategoryId: _selectedSubcategoryId,
        tags: _selectedTags.isNotEmpty ? _selectedTags : null,
        imagePath: _imagePath,
        note: _noteController.text.isNotEmpty ? _noteController.text : null,
        expireDate: finalExpireDate,
        customAttributes: _customAttributes.isNotEmpty ? _customAttributes : null,
        expireDateSource: expireDateSource,
      );
      
      // 减少原物品数量
      final remainingQuantity = widget.item.quantity - newQuantity;
      if (remainingQuantity > 0) {
        final updatedItem = Item(
          id: widget.item.id,
          houseId: widget.item.houseId,
          spaceId: widget.item.spaceId,
          name: widget.item.name,
          quantity: remainingQuantity,
          unit: widget.item.unit,
          price: widget.item.price,
          category: widget.item.category,
          categoryId: widget.item.categoryId,
          tags: widget.item.tags,
          imagePath: widget.item.imagePath,
          note: widget.item.note,
          creatorId: widget.item.creatorId,
          modifierId: 'user',
          createdAt: widget.item.createdAt,
          updatedAt: DateTime.now(),
        );
        await itemProvider.updateItem(updatedItem, expireDate: widget.item.expireDate);
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('物品已拆分，剩余 $remainingQuantity 个')),
        );
        Navigator.pop(context);
      }
      return;
    }

    // 普通模式：直接更新物品
    final tagsStr = _selectedTags.isNotEmpty ? _selectedTags.join(',') : null;
    
    final updatedItem = Item(
      id: widget.item.id,
      houseId: widget.item.houseId,
      spaceId: _selectedSpaceId ?? widget.item.spaceId,
      name: _nameController.text,
      quantity: newQuantity,
      unit: _unitController.text.isNotEmpty ? _unitController.text : '件',
      price: _priceController.text.isNotEmpty
          ? double.tryParse(_priceController.text)
          : null,
      category: _selectedCategory ?? widget.item.category,
      categoryId: _selectedCategoryId,
      subcategoryId: _selectedSubcategoryId ?? widget.item.subcategoryId,
      tags: tagsStr,
      imagePath: _imagePath,
      note: _noteController.text.isNotEmpty ? _noteController.text : null,
      creatorId: widget.item.creatorId,
      modifierId: 'user',
      createdAt: widget.item.createdAt,
      updatedAt: DateTime.now(),
    );

    await itemProvider.updateItem(updatedItem, customAttributes: _customAttributes, expireDate: finalExpireDate, subcategoryId: _selectedSubcategoryId, expireDateSource: expireDateSource);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('修改已保存')),
      );
      Navigator.pop(context);
    }
  }

  void _showDeleteDialog(BuildContext context) {
    final spaceProvider = Provider.of<SpaceProvider>(context, listen: false);
    final space = spaceProvider.spaces.firstWhereOrNull((s) => s.id == widget.item.spaceId);
    final isInSpecialSpace = space != null && (space.type == 'recycle' || space.type == 'trash');

    String title = '删除物品';
    String message;
    String buttonText;
    
    if (isInSpecialSpace) {
      title = '彻底删除';
      message = '确定要彻底删除这个物品吗？此操作无法撤销。';
      buttonText = '彻底删除';
    } else {
      message = '确定将物品移至回收站吗？';
      buttonText = '移至回收站';
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final itemProvider = Provider.of<ItemProvider>(context, listen: false);
              if (isInSpecialSpace) {
                await itemProvider.permanentDeleteItem(widget.item);
              } else {
                await itemProvider.deleteItem(widget.item);
              }
              if (mounted) {
                Navigator.pop(context);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(isInSpecialSpace ? '物品已彻底删除' : '物品已移至回收站'),
                  ),
                );
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: isInSpecialSpace ? Colors.red : null,
            ),
            child: Text(buttonText),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _launchUrl(String url) async {
    var uri = Uri.tryParse(url);
    if (uri == null || (!uri.hasScheme)) {
      uri = Uri.tryParse('https://$url');
    }
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开链接: $url')),
        );
      }
    }
  }
}
