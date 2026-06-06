import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import '../../providers/house_provider.dart';
import '../../providers/space_provider.dart';
import '../../providers/item_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/tag_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/attribute_provider.dart';
import '../../database/database.dart';
import 'barcode_scanner_page.dart';

class ItemFormPage extends StatefulWidget {
  final BarcodeScanResult? barcodeResult;

  const ItemFormPage({super.key, this.barcodeResult});

  @override
  State<ItemFormPage> createState() => _ItemFormPageState();
}

class _ItemFormPageState extends State<ItemFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _unitController = TextEditingController(text: '件');
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeDefaults();
    });
  }

  void _initializeDefaults() {
    final houseProvider = context.read<HouseProvider>();
    final spaceProvider = context.read<SpaceProvider>();
    final categoryProvider = context.read<CategoryProvider>();
    final currentHouse = houseProvider.currentHouse;

    if (currentHouse != null) {
      final otherCategory = categoryProvider.categories.firstWhere(
        (c) => c.name == '其他',
        orElse: () => Category(id: '', houseId: currentHouse.id, name: '其他', icon: null, sortOrder: 0, createdAt: DateTime.now()),
      );
      setState(() {
        _selectedCategory = '其他';
        _selectedCategoryId = otherCategory.id;
      });
    }

    if (widget.barcodeResult != null) {
      _applyBarcodeResult(widget.barcodeResult!);
    }
  }

  Future<void> _applyBarcodeResult(BarcodeScanResult result) async {
    final categoryProvider = context.read<CategoryProvider>();
    final attributeProvider = context.read<AttributeProvider>();

    if (result.name != null && result.name!.isNotEmpty) {
      _nameController.text = result.name!;
    } else {
      _nameController.text = result.barcode;
    }

    if (result.price != null) {
      _priceController.text = result.price.toString();
      _totalPriceController.text = result.price.toString();
    }

    if (result.category != null && result.category!.isNotEmpty) {
      final matchedCategory = categoryProvider.categories.firstWhere(
        (c) => c.name == result.category,
        orElse: () => Category(id: '', houseId: '', name: '', icon: null, sortOrder: 0, createdAt: DateTime.now()),
      );
      if (matchedCategory.id.isNotEmpty) {
        setState(() {
          _selectedCategory = matchedCategory.name;
          _selectedCategoryId = matchedCategory.id;
        });
      }
    }

    final categoryId = _selectedCategoryId;
    if (categoryId != null && categoryId.isNotEmpty) {
      final attributes = await attributeProvider.getAttributesForCategory(categoryId);

      final attributeNameMap = <String, Attribute>{};
      for (final attr in attributes) {
        attributeNameMap[attr.name] = attr;
      }

      final barcodeFieldMap = <String, String?>{
        '品牌': result.brand,
        '厂商': result.manufacturer,
        '规格': result.spec,
        '条形码': result.barcode,
        '描述': result.description,
      };

      final matchedFieldNames = <String>{};
      for (final entry in barcodeFieldMap.entries) {
        if (entry.value != null && entry.value!.isNotEmpty) {
          final attr = attributeNameMap[entry.key];
          if (attr != null) {
            _customAttributes[attr.id] = entry.value!;
            matchedFieldNames.add(entry.key);
          }
        }
      }

      final remarkParts = <String>[];
      for (final entry in barcodeFieldMap.entries) {
        if (!matchedFieldNames.contains(entry.key) &&
            entry.value != null &&
            entry.value!.isNotEmpty) {
          remarkParts.add('${entry.key}: ${entry.value}');
        }
      }
      if (result.category != null && result.category!.isNotEmpty) {
        final categoryAttr = attributeNameMap['分类'];
        if (categoryAttr == null) {
          remarkParts.add('分类: ${result.category}');
        }
      }
      if (result.imageUrl != null && result.imageUrl!.isNotEmpty) {
        remarkParts.add('图片: ${result.imageUrl}');
      }

      if (remarkParts.isNotEmpty) {
        _noteController.text = remarkParts.join('\n');
      }
    } else {
      final noteParts = <String>[];
      if (result.brand != null && result.brand!.isNotEmpty) {
        noteParts.add('品牌: ${result.brand}');
      }
      if (result.manufacturer != null && result.manufacturer!.isNotEmpty) {
        noteParts.add('厂商: ${result.manufacturer}');
      }
      if (result.spec != null && result.spec!.isNotEmpty) {
        noteParts.add('规格: ${result.spec}');
      }
      noteParts.add('条码: ${result.barcode}');
      if (result.description != null && result.description!.isNotEmpty) {
        noteParts.add('备注: ${result.description}');
      }
      if (result.category != null && result.category!.isNotEmpty) {
        noteParts.add('分类: ${result.category}');
      }
      if (result.imageUrl != null && result.imageUrl!.isNotEmpty) {
        noteParts.add('图片: ${result.imageUrl}');
      }
      _noteController.text = noteParts.join('\n');
    }

    if (result.imageUrl != null && result.imageUrl!.isNotEmpty) {
      _downloadAndSetImage(result.imageUrl!);
    }

    setState(() {});
  }

  Future<void> _downloadAndSetImage(String imageUrl) async {
    try {
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        final appDir = await getApplicationDocumentsDirectory();
        final tempFileName = 'temp_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final tempPath = '${appDir.path}/$tempFileName';
        final tempFile = File(tempPath);
        await tempFile.writeAsBytes(response.bodyBytes);

        final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
        final targetPath = '${appDir.path}/$fileName';
        await _compressAndSaveImage(tempPath, targetPath);

        if (await tempFile.exists()) {
          await tempFile.delete();
        }

        final targetFile = File(targetPath);
        final exists = await targetFile.exists();
        final length = exists ? await targetFile.length() : 0;
        debugPrint('图片下载压缩: $imageUrl -> $targetPath (exists=$exists, size=$length)');
        if (mounted && exists && length > 0) {
          setState(() {
            _imagePath = targetPath;
          });
        }
      } else {
        debugPrint('图片下载失败: statusCode=${response.statusCode}, bodyLength=${response.bodyBytes.length}');
      }
    } catch (e) {
      debugPrint('图片下载异常: $e');
    }
  }

  void _updateDefaultSpace() {
    // 如果已经选择了位置，不再更新
    if (_selectedSpaceId != null) return;
    
    final houseProvider = context.read<HouseProvider>();
    final spaceProvider = context.read<SpaceProvider>();
    final currentHouse = houseProvider.currentHouse;

    if (currentHouse != null) {
      // 确保空间数据已加载
      if (spaceProvider.spaces.isEmpty) {
        // 如果空间数据为空，不尝试设置，用户需要自己选择
        return;
      }
      
      final pendingSpace = spaceProvider.getPendingSpace(currentHouse.id);
      if (pendingSpace != null) {
        setState(() {
          _selectedSpaceId = pendingSpace.id;
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    _unitController.dispose();
    _priceController.dispose();
    _totalPriceController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  double? get _totalPrice {
    final quantity = int.tryParse(_quantityController.text) ?? 0;
    final price = double.tryParse(_priceController.text);
    if (price != null) {
      return quantity * price;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('录入物品'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildBasicInfoSection(),
            const SizedBox(height: 16),
            _buildExtendedInfoSection(),
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
            _buildCategorySelector(),
            const SizedBox(height: 16),
            _buildSubcategorySelector(),
            const SizedBox(height: 16),
            _buildLocationSelector(),
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
        Container(
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
        if (_imagePath != null)
          TextButton(
            onPressed: () => setState(() => _imagePath = null),
            child: const Text('移除封面'),
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
        return DropdownButtonFormField<String>(
          value: _selectedCategory,
          decoration: InputDecoration(
            labelText: '分类 *',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            prefixIcon: const Icon(Icons.category),
          ),
          items: [
            ...categoryProvider.categories.map((category) {
              return DropdownMenuItem<String>(
                value: category.name,
                child: Text(category.name),
              );
            }),
          ],
          onChanged: (value) {
            setState(() {
              if (value != null && value != _selectedCategory) {
                _selectedSubcategoryId = null;
              }
              _selectedCategory = value;
              final currentHouse = houseProvider.currentHouse;
              if (currentHouse != null && value != null) {
                final category = categoryProvider.categories.firstWhere(
                  (c) => c.name == value,
                  orElse: () => Category(id: '', houseId: currentHouse.id, name: '其他', icon: null, sortOrder: 0, createdAt: DateTime.now()),
                );
                _selectedCategoryId = category.id;
                if (category.id.isNotEmpty) {
                  categoryProvider.loadSubcategories(category.id);
                }
              }
            });
          },
          validator: (value) {
            if (value == null || value.isEmpty) {
              return '请选择分类';
            }
            return null;
          },
        );
      },
    );
  }

  Widget _buildSubcategorySelector() {
    return Consumer2<CategoryProvider, HouseProvider>(
      builder: (context, categoryProvider, houseProvider, _) {
        final currentHouse = houseProvider.currentHouse;
        
        if (_selectedCategoryId == null || _selectedCategoryId!.isEmpty) {
          return TextFormField(
            enabled: false,
            decoration: InputDecoration(
              labelText: '二级分类（选填）',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: const Icon(Icons.category_outlined),
              hintText: '请先选择分类',
            ),
          );
        }

        final subcategories = categoryProvider.getSubcategoriesForCategory(_selectedCategoryId!);
        final validValue = subcategories.any((s) => s.id == _selectedSubcategoryId)
            ? _selectedSubcategoryId
            : null;

        return DropdownButtonFormField<String>(
          value: validValue,
          decoration: InputDecoration(
            labelText: '二级分类（选填）',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            prefixIcon: const Icon(Icons.category_outlined),
          ),
          items: [
            const DropdownMenuItem<String>(
              value: '',
              child: Text('不选择'),
            ),
            ...subcategories.map((subcategory) {
              return DropdownMenuItem<String>(
                value: subcategory.id,
                child: Text(subcategory.name),
              );
            }),
            const DropdownMenuItem<String>(
              value: '_add_new',
              child: Text('+ 添加新二级分类'),
            ),
          ],
          onChanged: (value) async {
            if (value == '_add_new') {
              final newName = await _showAddSubcategoryDialog(context, categoryProvider, currentHouse);
              if (newName != null && newName.isNotEmpty) {
                setState(() {});
              }
            } else {
              setState(() {
                _selectedSubcategoryId = (value != null && value.isNotEmpty) ? value : null;
              });
            }
          },
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

        if (spaces.isEmpty) {
          return Column(
            children: [
              const Text('暂无可选空间，请先创建空间'),
              const SizedBox(height: 8),
              TextFormField(
                enabled: false,
                decoration: InputDecoration(
                  labelText: '位置 *',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  hintText: '暂无可用空间',
                ),
                validator: (_) => '请先创建空间',
              ),
            ],
          );
        }

        String? defaultSpaceId = _selectedSpaceId;
        if (defaultSpaceId == null) {
          final pendingSpace = spaceProvider.getPendingSpace(currentHouse.id);
          if (pendingSpace != null) {
            defaultSpaceId = pendingSpace.id;
          } else {
            defaultSpaceId = spaces.first.id;
          }
        }

        return DropdownButtonFormField<String>(
          value: defaultSpaceId,
          decoration: InputDecoration(
            labelText: '位置 *',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            prefixIcon: const Icon(Icons.place),
          ),
          items: spaces.map((space) {
            return DropdownMenuItem<String>(
              value: space.id,
              child: Text(space.name),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              _selectedSpaceId = value;
            });
          },
          validator: (value) {
            if (value == null || value.isEmpty) {
              return '请选择存放位置';
            }
            return null;
          },
        );
      },
    );
  }

  Widget _buildQuantitySection() {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: TextFormField(
            controller: _quantityController,
            decoration: InputDecoration(
              labelText: '数量 *',
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
              if (int.tryParse(value) == null || int.parse(value) <= 0) {
                return '请输入有效的数量';
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

  bool _isCalculating = false;

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
            const Text('标签（选填）'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ..._selectedTags.map((tagName) {
                  return Chip(
                    label: Text(tagName),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () {
                      setState(() {
                        _selectedTags.remove(tagName);
                      });
                    },
                  );
                }).toList(),
                InkWell(
                  onTap: () => _showAddTagDialog(tagProvider, currentHouse),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, size: 16),
                        SizedBox(width: 4),
                        Text('添加标签'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('已有标签'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
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
      key: ValueKey('attr_${attribute.id}_$currentValue'),
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
        return DropdownButtonFormField<String>(
          value: currentValue.isNotEmpty ? currentValue : null,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          items: [
            const DropdownMenuItem<String>(
              value: '',
              child: Text('请选择'),
            ),
            ...options.map((opt) => DropdownMenuItem<String>(
                  value: opt,
                  child: Text(opt),
                )),
          ],
          onChanged: (value) {
            setState(() {
              _customAttributes[attribute.id] = value ?? '';
            });
          },
        );
      case 'multi_select':
        return Column(
          children: [
            Wrap(
              spacing: 8,
              children: options.map((opt) {
                final isSelected = currentValue.contains(opt);
                return FilterChip(
                  label: Text(opt),
                  selected: isSelected,
                  showCheckmark: false,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        if (currentValue.isEmpty) {
                          _customAttributes[attribute.id] = opt;
                        } else if (!currentValue.contains(opt)) {
                          _customAttributes[attribute.id] = '$currentValue;$opt';
                        }
                      } else {
                        if (currentValue.contains(';$opt')) {
                          _customAttributes[attribute.id] = currentValue.replaceAll(';$opt', '');
                        } else if (currentValue.contains('$opt;')) {
                          _customAttributes[attribute.id] = currentValue.replaceAll('$opt;', '');
                        } else {
                          _customAttributes[attribute.id] = currentValue.replaceAll(opt, '');
                        }
                        if (_customAttributes[attribute.id]!.isEmpty) {
                          _customAttributes.remove(attribute.id);
                        }
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ],
        );
      default:
        return TextFormField(
          initialValue: currentValue,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          maxLines: 1,
          onChanged: (value) => _customAttributes[attribute.id] = value,
        );
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
      if (durationParts.length < 2) return;
      
      final duration = int.tryParse(durationParts[0]);
      if (duration == null || duration <= 0) return;
      
      final durationUnit = durationParts[1];
      
      try {
        final sourceDate = DateTime.parse(sourceDateStr);
        DateTime targetDate;
        
        switch (durationUnit) {
          case '月':
            targetDate = DateTime(sourceDate.year, sourceDate.month + duration, sourceDate.day);
            break;
          case '年':
            targetDate = DateTime(sourceDate.year + duration, sourceDate.month, sourceDate.day);
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
              final parts = _customAttributes[attribute.id]?.split('|') ?? [];
              final currentUnit = parts.length > 1 ? parts[1] : selectedUnit;
              _customAttributes[attribute.id] = '$value|$currentUnit';
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
                final parts = _customAttributes[attribute.id]?.split('|') ?? [];
                final currentDuration = parts.isNotEmpty ? parts[0] : durationValue;
                _customAttributes[attribute.id] = '$currentDuration|$value';
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
    if (durationParts.length < 2) return;
    
    final duration = int.tryParse(durationParts[0]);
    if (duration == null || duration <= 0) return;
    
    final durationUnit = durationParts[1];
    
    try {
      final sourceDate = DateTime.parse(sourceDateStr);
      DateTime targetDate;
      
      switch (durationUnit) {
        case '月':
          targetDate = DateTime(sourceDate.year, sourceDate.month + duration, sourceDate.day);
          break;
        case '年':
          targetDate = DateTime(sourceDate.year + duration, sourceDate.month, sourceDate.day);
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

  Widget _buildSubmitButton() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _submitForm,
          icon: const Icon(Icons.save),
          label: const Text('保存物品'),
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

  List<String> _validateRequiredFields() {
    final errors = <String>[];

    // 验证物品名称
    if (_nameController.text.trim().isEmpty) {
      errors.add('请输入物品名称');
    }

    // 验证分类
    if (_selectedCategory == null || _selectedCategory!.isEmpty) {
      errors.add('请选择物品分类');
    }

    // 验证位置
    if (_selectedSpaceId == null || _selectedSpaceId!.isEmpty) {
      final houseProvider = Provider.of<HouseProvider>(context, listen: false);
      final spaceProvider = Provider.of<SpaceProvider>(context, listen: false);
      final currentHouse = houseProvider.currentHouse;

      if (currentHouse != null) {
        final pendingSpace = spaceProvider.getPendingSpace(currentHouse.id);
        if (pendingSpace != null) {
          _selectedSpaceId = pendingSpace.id;
        } else {
          final spaces = spaceProvider.spaces
              .where((s) => s.houseId == currentHouse.id && s.type != 'trash')
              .toList();
          if (spaces.isNotEmpty) {
            _selectedSpaceId = spaces.first.id;
          }
        }
      }

      if (_selectedSpaceId == null || _selectedSpaceId!.isEmpty) {
        errors.add('请选择物品位置');
      }
    }

    // 验证数量
    final quantity = int.tryParse(_quantityController.text);
    if (quantity == null || quantity <= 0) {
      errors.add('请输入有效的物品数量（大于0）');
    }

    return errors;
  }

  Future<void> _submitForm() async {
    debugPrint('[_submitForm] _selectedSubcategoryId: $_selectedSubcategoryId');
    debugPrint('[_submitForm] _selectedCategoryId: $_selectedCategoryId');

    final validationErrors = _validateRequiredFields();
    if (validationErrors.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(validationErrors.join('\n')),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final houseProvider = context.read<HouseProvider>();
    final spaceProvider = context.read<SpaceProvider>();
    final itemProvider = context.read<ItemProvider>();
    final tagProvider = context.read<TagProvider>();
    final currentHouse = houseProvider.currentHouse;

    if (currentHouse == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择一个家庭')),
      );
      return;
    }

    // 自动同步新标签到数据库
    if (_selectedTags.isNotEmpty) {
      final existingTagNames = tagProvider.tags.map((t) => t.name).toList();
      for (final tagName in _selectedTags) {
        if (!existingTagNames.contains(tagName)) {
          await tagProvider.addTag(houseId: currentHouse.id, name: tagName);
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
            // 解析失败时忽略
          }
        }
      }
      
      if (warrantyExpireDateAttr != null && warrantyExpireDateAttr.id.isNotEmpty) {
        final warrantyExpireDateStr = _customAttributes[warrantyExpireDateAttr.id];
        if (warrantyExpireDateStr != null && warrantyExpireDateStr.isNotEmpty) {
          try {
            warrantyExpireDate = DateTime.parse(warrantyExpireDateStr);
          } catch (_) {
            // 解析失败时忽略
          }
        }
      }
    }

    final finalExpireDate = expireDate ?? warrantyExpireDate;
    final expireDateSource = expireDate != null
        ? 'expire'
        : (warrantyExpireDate != null ? 'warranty' : null);

    if (_enableLowStockReminder) {
      final settingsProvider = context.read<SettingsProvider>();
      final threshold = settingsProvider.lowStockThreshold;
      _customAttributes['_low_stock_reminder'] = 'true';
      _customAttributes['_low_stock_threshold'] = threshold.toString();
    }

    await itemProvider.addItem(
      houseId: currentHouse.id,
      spaceId: _selectedSpaceId!,
      name: _nameController.text,
      quantity: int.tryParse(_quantityController.text) ?? 1,
      unit: _unitController.text.isNotEmpty ? _unitController.text : '件',
      price: _priceController.text.isNotEmpty
          ? double.tryParse(_priceController.text)
          : null,
      category: _selectedCategory ?? '其他',
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
        const SnackBar(content: Text('物品添加成功')),
      );
      Navigator.pop(context);
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
