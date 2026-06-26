import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import '../../providers/house_provider.dart';
import '../../providers/space_provider.dart';
import '../../providers/item_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/tag_provider.dart';
import '../../providers/attribute_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/ai_provider.dart';
import '../../database/database.dart';
import 'barcode_scanner_page.dart';
import 'ai_vision_scan_page.dart';
import 'ai_chat_page.dart';
import '../profile/category_edit_page.dart';

class ItemFormPage extends StatefulWidget {
  final BarcodeScanResult? barcodeResult;
  final VisionScanResult? visionResult;
  final VisionScanResult? chatResult;

  const ItemFormPage({super.key, this.barcodeResult, this.visionResult, this.chatResult});

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
  final _lowStockThresholdController = TextEditingController();

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

    if (widget.visionResult != null) {
      _applyVisionResult(widget.visionResult!);
    }

    if (widget.chatResult != null) {
      _applyChatResult(widget.chatResult!);
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

  Future<void> _applyVisionResult(VisionScanResult result) async {
    final categoryProvider = context.read<CategoryProvider>();
    final attributeProvider = context.read<AttributeProvider>();

    // 设置名称
    if (result.name.isNotEmpty) {
      _nameController.text = result.name;
    }

    // 设置单价
    if (result.price != null) {
      _priceController.text = result.price.toString();
      _totalPriceController.text = result.price.toString();
    }

    // 设置封面图片
    if (result.imagePath.isNotEmpty) {
      _imagePath = result.imagePath;
    }

    // 匹配分类
    if (result.category.isNotEmpty) {
      final matchedCategory = categoryProvider.categories.firstWhere(
        (c) => c.name == result.category,
        orElse: () => Category(
          id: '',
          houseId: '',
          name: '',
          icon: null,
          sortOrder: 0,
          createdAt: DateTime.now(),
        ),
      );
      if (matchedCategory.id.isNotEmpty) {
        setState(() {
          _selectedCategory = matchedCategory.name;
          _selectedCategoryId = matchedCategory.id;
        });
      } else {
        // 不属于现有分类，默认"其他"
        final otherCategory = categoryProvider.categories.firstWhere(
          (c) => c.name == '其他',
          orElse: () => Category(
            id: '',
            houseId: '',
            name: '其他',
            icon: null,
            sortOrder: 0,
            createdAt: DateTime.now(),
          ),
        );
        if (otherCategory.id.isNotEmpty) {
          setState(() {
            _selectedCategory = '其他';
            _selectedCategoryId = otherCategory.id;
          });
        }
      }
    }

    // 匹配二级分类，不存在则自动创建
    if (result.subcategory.isNotEmpty && _selectedCategoryId != null) {
      final subcategories = categoryProvider.getSubcategoriesForCategory(_selectedCategoryId!);
      final matchedSub = subcategories.firstWhereOrNull(
        (s) => s.name == result.subcategory,
      );
      if (matchedSub != null) {
        setState(() {
          _selectedSubcategoryId = matchedSub.id;
        });
      } else {
        // 自动创建新的二级分类
        final currentHouse = context.read<HouseProvider>().currentHouse;
        if (currentHouse != null) {
          await categoryProvider.addSubcategory(
            categoryId: _selectedCategoryId!,
            name: result.subcategory,
          );
          final newSubs = categoryProvider.getSubcategoriesForCategory(_selectedCategoryId!);
          final newSub = newSubs.firstWhereOrNull((s) => s.name == result.subcategory);
          if (newSub != null) {
            setState(() {
              _selectedSubcategoryId = newSub.id;
            });
          }
        }
      }
    }

    // 填充扩展属性
    final categoryId = _selectedCategoryId;
    if (categoryId != null && categoryId.isNotEmpty) {
      final attributes = await attributeProvider.getAttributesForCategory(categoryId);
      final attributeNameMap = <String, Attribute>{};
      for (final attr in attributes) {
        attributeNameMap[attr.name] = attr;
      }

      final fieldMap = <String, String?>{
        '品牌': result.brand.isNotEmpty ? result.brand : null,
        '厂商': result.manufacturer.isNotEmpty ? result.manufacturer : null,
        '规格': result.spec.isNotEmpty ? result.spec : null,
        '颜色': result.color.isNotEmpty ? result.color : null,
      };

      final matchedFieldNames = <String>{};
      for (final entry in fieldMap.entries) {
        if (entry.value != null && entry.value!.isNotEmpty) {
          final attr = attributeNameMap[entry.key];
          if (attr != null) {
            _customAttributes[attr.id] = entry.value!;
            matchedFieldNames.add(entry.key);
          }
        }
      }

      // 未匹配到的属性和描述写入备注
      final remarkParts = <String>[];
      for (final entry in fieldMap.entries) {
        if (!matchedFieldNames.contains(entry.key) && entry.value != null && entry.value!.isNotEmpty) {
          remarkParts.add('${entry.key}: ${entry.value}');
        }
      }
      if (result.description.isNotEmpty) {
        remarkParts.add(result.description);
      }
      if (remarkParts.isNotEmpty) {
        _noteController.text = remarkParts.join('\n');
      }
    } else {
      // 没有分类时，所有信息写入备注
      final noteParts = <String>[];
      if (result.brand.isNotEmpty) noteParts.add('品牌: ${result.brand}');
      if (result.manufacturer.isNotEmpty) noteParts.add('厂商: ${result.manufacturer}');
      if (result.spec.isNotEmpty) noteParts.add('规格: ${result.spec}');
      if (result.color.isNotEmpty) noteParts.add('颜色: ${result.color}');
      if (result.description.isNotEmpty) noteParts.add(result.description);
      if (noteParts.isNotEmpty) {
        _noteController.text = noteParts.join('\n');
      }
    }

    setState(() {});
  }

  Future<void> _applyChatResult(VisionScanResult result) async {
    final categoryProvider = context.read<CategoryProvider>();
    final attributeProvider = context.read<AttributeProvider>();
    final spaceProvider = context.read<SpaceProvider>();
    final houseProvider = context.read<HouseProvider>();

    // 设置名称
    if (result.name.isNotEmpty) {
      _nameController.text = result.name;
    }

    // 设置数量
    if (result.quantity != null && result.quantity! > 0) {
      _quantityController.text = result.quantity.toString();
    }

    // 设置单位
    if (result.unit != null && result.unit!.isNotEmpty) {
      _unitController.text = result.unit!;
    }

    // 设置单价
    if (result.price != null) {
      _priceController.text = result.price.toString();
      final quantity = result.quantity ?? 1;
      _totalPriceController.text = (result.price! * quantity).toStringAsFixed(2);
    }

    // 匹配位置/空间
    if (result.location != null && result.location!.isNotEmpty) {
      final currentHouse = houseProvider.currentHouse;
      if (currentHouse != null) {
        final allSpaces = spaceProvider.getAllSpacesExceptSpecial(currentHouse.id);
        // 精确匹配或模糊匹配空间名称
        Space? matchedSpace;
        try {
          matchedSpace = allSpaces.firstWhere((s) => s.name == result.location);
        } catch (_) {
          // 模糊匹配：空间名称包含用户描述的位置
          try {
            matchedSpace = allSpaces.firstWhere(
              (s) => s.name.contains(result.location!) || result.location!.contains(s.name),
            );
          } catch (_) {}
        }
        if (matchedSpace != null) {
          setState(() {
            _selectedSpaceId = matchedSpace!.id;
          });
          _onSpaceChanged(matchedSpace);
        }
      }
    }

    // 匹配分类
    if (result.category.isNotEmpty) {
      final matchedCategory = categoryProvider.categories.firstWhere(
        (c) => c.name == result.category,
        orElse: () => Category(
          id: '',
          houseId: '',
          name: '',
          icon: null,
          sortOrder: 0,
          createdAt: DateTime.now(),
        ),
      );
      if (matchedCategory.id.isNotEmpty) {
        setState(() {
          _selectedCategory = matchedCategory.name;
          _selectedCategoryId = matchedCategory.id;
        });
      } else {
        final otherCategory = categoryProvider.categories.firstWhere(
          (c) => c.name == '其他',
          orElse: () => Category(
            id: '',
            houseId: '',
            name: '其他',
            icon: null,
            sortOrder: 0,
            createdAt: DateTime.now(),
          ),
        );
        if (otherCategory.id.isNotEmpty) {
          setState(() {
            _selectedCategory = '其他';
            _selectedCategoryId = otherCategory.id;
          });
        }
      }
    }

    // 设置封面图片
    if (result.imagePath.isNotEmpty) {
      _imagePath = result.imagePath;
    }

    // 匹配二级分类
    if (result.subcategory.isNotEmpty && _selectedCategoryId != null) {
      final subcategories = categoryProvider.getSubcategoriesForCategory(_selectedCategoryId!);
      final matchedSub = subcategories.firstWhereOrNull(
        (s) => s.name == result.subcategory,
      );
      if (matchedSub != null) {
        setState(() {
          _selectedSubcategoryId = matchedSub.id;
        });
      } else {
        final currentHouse = houseProvider.currentHouse;
        if (currentHouse != null) {
          await categoryProvider.addSubcategory(
            categoryId: _selectedCategoryId!,
            name: result.subcategory,
          );
          final newSubs = categoryProvider.getSubcategoriesForCategory(_selectedCategoryId!);
          final newSub = newSubs.firstWhereOrNull((s) => s.name == result.subcategory);
          if (newSub != null) {
            setState(() {
              _selectedSubcategoryId = newSub.id;
            });
          }
        }
      }
    }

    // 填充扩展属性
    final categoryId = _selectedCategoryId;
    if (categoryId != null && categoryId.isNotEmpty) {
      final attributes = await attributeProvider.getAttributesForCategory(categoryId);
      final attributeNameMap = <String, Attribute>{};
      for (final attr in attributes) {
        attributeNameMap[attr.name] = attr;
      }

      // 将保质期/保修期字符串转换为 "数值|单位" 格式，适配 _buildDurationField
      String? formatDuration(String? value) {
        if (value == null || value.isEmpty) return null;
        final match = RegExp(r'(\d+)\s*(?:个)?\s*(天|月|年)').firstMatch(value);
        if (match != null) {
          return '${match.group(1)}|${match.group(2)}';
        }
        return value;
      }

      final fieldMap = <String, String?>{
        '品牌': result.brand.isNotEmpty ? result.brand : null,
        '厂商': result.manufacturer.isNotEmpty ? result.manufacturer : null,
        '规格': result.spec.isNotEmpty ? result.spec : null,
        '颜色': result.color.isNotEmpty ? result.color : null,
        '生产日期': result.productionDate,
        '保质期': formatDuration(result.shelfLife),
        '过期日期': result.expireDate,
        '购买日期': result.purchaseDate,
        '保修期': formatDuration(result.warrantyPeriod),
        '过保日期': result.warrantyExpireDate,
      };

      final matchedFieldNames = <String>{};
      for (final entry in fieldMap.entries) {
        if (entry.value != null && entry.value!.isNotEmpty) {
          final attr = attributeNameMap[entry.key];
          if (attr != null) {
            _customAttributes[attr.id] = entry.value!;
            matchedFieldNames.add(entry.key);
          }
        }
      }

      final remarkParts = <String>[];
      for (final entry in fieldMap.entries) {
        if (!matchedFieldNames.contains(entry.key) && entry.value != null && entry.value!.isNotEmpty) {
          remarkParts.add('${entry.key}: ${entry.value}');
        }
      }
      if (result.description.isNotEmpty) {
        remarkParts.add(result.description);
      }
      if (remarkParts.isNotEmpty) {
        _noteController.text = remarkParts.join('\n');
      }
    } else {
      final noteParts = <String>[];
      if (result.brand.isNotEmpty) noteParts.add('品牌: ${result.brand}');
      if (result.manufacturer.isNotEmpty) noteParts.add('厂商: ${result.manufacturer}');
      if (result.spec.isNotEmpty) noteParts.add('规格: ${result.spec}');
      if (result.color.isNotEmpty) noteParts.add('颜色: ${result.color}');
      if (result.productionDate != null) noteParts.add('生产日期: ${result.productionDate}');
      if (result.shelfLife != null) noteParts.add('保质期: ${result.shelfLife}');
      if (result.expireDate != null) noteParts.add('过期日期: ${result.expireDate}');
      if (result.purchaseDate != null) noteParts.add('购买日期: ${result.purchaseDate}');
      if (result.warrantyPeriod != null) noteParts.add('保修期: ${result.warrantyPeriod}');
      if (result.warrantyExpireDate != null) noteParts.add('过保日期: ${result.warrantyExpireDate}');
      if (result.description.isNotEmpty) noteParts.add(result.description);
      if (noteParts.isNotEmpty) {
        _noteController.text = noteParts.join('\n');
      }
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
    _lowStockThresholdController.dispose();
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

  Future<void> _navigateToAiVision(BuildContext context) async {
    final aiProvider = context.read<AiProviderProvider>();
    if (aiProvider.defaultVisionModelId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请先在"我的 → AI设置"中配置默认识图模型'),
          action: SnackBarAction(
            label: '去设置',
            onPressed: () => Navigator.pushNamed(context, '/ai-settings'),
          ),
        ),
      );
      return;
    }

    String? imagePath = _imagePath;
    if (imagePath == null || imagePath.isEmpty) {
      imagePath = await _pickVisionImage(context);
    }

    if (imagePath == null || imagePath.isEmpty) return;

    if (!mounted) return;

    if (_imagePath == null || _imagePath!.isEmpty) {
      setState(() {
        _imagePath = imagePath;
      });
    }

    await _startAiVisionRecognition(imagePath);
  }

  Future<String?> _pickVisionImage(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('拍照'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('从相册选择'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return null;
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source, maxWidth: 2400, maxHeight: 2400);
    if (pickedFile == null) return null;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final targetPath = '${appDir.path}/$fileName';

      await _compressAndSaveImage(pickedFile.path, targetPath);
      return targetPath;
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('图片处理失败：$e')),
        );
      }
      return null;
    }
  }

  Future<void> _startAiVisionRecognition(String imagePath) async {
    final aiProvider = context.read<AiProviderProvider>();
    final categoryProvider = context.read<CategoryProvider>();

    final visionModel = aiProvider.getModel(aiProvider.defaultVisionModelId);
    if (visionModel == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('识图模型不存在，请重新配置')),
        );
      }
      return;
    }

    final provider = aiProvider.getProvider(visionModel.providerId);
    if (provider == null || aiProvider.getEffectiveApiKey(provider).isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('提供商未配置 API Key，请先配置')),
        );
      }
      return;
    }

    bool dialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('正在识别物品...'),
          ],
        ),
      ),
    ).then((_) => dialogOpen = false);

    try {
      final imageBytes = await File(imagePath).readAsBytes();
      final base64Image = base64Encode(imageBytes);

      final baseUrl = provider.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
      final apiPath = provider.apiPath.startsWith('/') ? provider.apiPath : '/${provider.apiPath}';
      final url = Uri.parse('$baseUrl$apiPath');

      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${aiProvider.getEffectiveApiKey(provider)}',
      };

      if (provider.customHeaders.isNotEmpty && provider.customHeaders != '{}') {
        try {
          final custom = jsonDecode(provider.customHeaders) as Map<String, dynamic>;
          custom.forEach((k, v) => headers[k] = v.toString());
        } catch (_) {}
      }

      final categoryNames = categoryProvider.categories.map((c) => c.name).toList();
      final categoryList = categoryNames.isNotEmpty ? categoryNames.join('/') : '食品/药品/美妆/日用品/数码/其他';

      final categorySubcategoryMap = <String, List<String>>{};
      for (final category in categoryProvider.categories) {
        final subs = categoryProvider.getSubcategoriesForCategory(category.id);
        categorySubcategoryMap[category.name] = subs.map((s) => s.name).toList();
      }
      final subcategoryInfo = categorySubcategoryMap.entries
          .where((e) => e.value.isNotEmpty)
          .map((e) => '${e.key}: ${e.value.join('/')}'
          )
          .join('\n');

      final prompt = '请识别图片中的物品，并以JSON格式返回以下信息（不要返回任何其他内容，只返回JSON）：\n'
          '{\n'
          '  "name": "物品名称",\n'
          '  "category": "分类（$categoryList 之一）",\n'
          '  "subcategory": "二级分类（可参考已有二级分类，也可返回新的二级分类。已有二级分类参考：$subcategoryInfo 。）",\n'
          '  "brand": "品牌（如无则为null）",\n'
          '  "manufacturer": "厂商（如无则为null）",\n'
          '  "spec": "规格（如无则为null）",\n'
          '  "color": "颜色（如无则为null）",\n'
          '  "price": "单价（如无则为null）",\n'
          '  "description": "物品描述（如无则为null）"\n'
          '}\n'
          '注意：若某字段无信息，其值应为null，不要返回"无品牌"、"无厂商"等文字，也不要返回空字符串。';

      final body = jsonEncode({
        'model': visionModel.modelId,
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': prompt},
              {
                'type': 'image_url',
                'image_url': {'url': 'data:image/jpeg;base64,$base64Image'},
              },
            ],
          },
        ],
        'max_tokens': 500,
      });

      final response = await http.post(url, headers: headers, body: body).timeout(const Duration(seconds: 60));

      if (dialogOpen && mounted) {
        dialogOpen = false;
        Navigator.pop(context);
      }

      if (response.statusCode != 200) {
        String errorMsg = 'HTTP ${response.statusCode}';
        try {
          final errorBody = jsonDecode(response.body) as Map<String, dynamic>;
          final msg = errorBody['error']?['message'] ?? errorBody['message'] ?? '';
          if (msg.isNotEmpty) errorMsg = msg;
        } catch (_) {}
        throw Exception(errorMsg);
      }

      final responseBody = jsonDecode(response.body) as Map<String, dynamic>;
      final content = responseBody['choices']?[0]?['message']?['content'] as String? ?? '';

      final result = _parseAiVisionResponse(content, imagePath);
      if (result != null && mounted) {
        await _applyVisionResult(result);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('识别完成')),
          );
        }
      }
    } catch (e) {
      if (dialogOpen && mounted) {
        dialogOpen = false;
        Navigator.pop(context);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('识别失败：$e')),
        );
      }
    }
  }

  VisionScanResult? _parseAiVisionResponse(String content, String imagePath) {
    try {
      String jsonStr = content.trim();
      jsonStr = jsonStr.replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '');
      final jsonMatch = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(jsonStr);
      if (jsonMatch != null) {
        jsonStr = jsonMatch.group(1)!.trim();
      }
      final braceStart = jsonStr.indexOf('{');
      final braceEnd = jsonStr.lastIndexOf('}');
      if (braceStart >= 0 && braceEnd > braceStart) {
        jsonStr = jsonStr.substring(braceStart, braceEnd + 1);
      }
      try {
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        return _parseVisionResultFromJson(json, imagePath);
      } catch (_) {
        return _parseVisionResultFromKeyValue(content, imagePath);
      }
    } catch (e) {
      debugPrint('解析 AI 响应失败: $e\n原始内容: $content');
      return null;
    }
  }

  VisionScanResult _parseVisionResultFromJson(Map<String, dynamic> json, String imagePath) {
    double? parsePrice(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      if (value is String) {
        final cleaned = value.replaceAll(RegExp(r'[^\d.]'), '');
        return double.tryParse(cleaned);
      }
      return null;
    }

    return VisionScanResult(
      name: json['name'] as String? ?? '',
      category: json['category'] as String? ?? '其他',
      subcategory: json['subcategory'] as String? ?? '',
      brand: json['brand'] as String? ?? '',
      manufacturer: json['manufacturer'] as String? ?? '',
      spec: json['spec'] as String? ?? '',
      color: json['color'] as String? ?? '',
      price: parsePrice(json['price']),
      description: json['description'] as String? ?? '',
      imagePath: imagePath,
    );
  }

  VisionScanResult? _parseVisionResultFromKeyValue(String content, String imagePath) {
    try {
      String text = content.replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '');
      final Map<String, String> data = {};
      final lines = text.split('\n');
      for (final line in lines) {
        final trimmedLine = line.trim();
        if (trimmedLine.isEmpty) continue;
        final match = RegExp(r'^\s*(\w+)\s*[:：]\s*(.+)$').firstMatch(trimmedLine);
        if (match != null) {
          final key = match.group(1)!.toLowerCase().trim();
          final value = match.group(2)!.trim();
          data[key] = value;
        }
      }
      if (data.isEmpty) return null;

      double? parsePrice(String? value) {
        if (value == null || value.isEmpty) return null;
        final cleaned = value.replaceAll(RegExp(r'[^\d.]'), '');
        return double.tryParse(cleaned);
      }

      return VisionScanResult(
        name: data['name'] ?? '',
        category: data['category'] ?? '其他',
        subcategory: data['subcategory'] ?? '',
        brand: data['brand'] ?? '',
        manufacturer: data['manufacturer'] ?? '',
        spec: data['spec'] ?? '',
        color: data['color'] ?? '',
        price: parsePrice(data['price']),
        description: data['description'] ?? '',
        imagePath: imagePath,
      );
    } catch (e) {
      debugPrint('解析键值对格式失败: $e');
      return null;
    }
  }

  Future<void> _navigateToScanner(BuildContext context) async {
    final settingsProvider = context.read<SettingsProvider>();
    if (!settingsProvider.isBarcodeConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请先在"我的 → 扫码设置"中配置商品 API'),
          action: SnackBarAction(
            label: '去设置',
            onPressed: () {
              Navigator.pushNamed(context, '/barcode-settings');
            },
          ),
        ),
      );
      return;
    }

    final result = await Navigator.push<BarcodeScanResult>(
      context,
      MaterialPageRoute(
        builder: (context) => const BarcodeScannerPage(),
      ),
    );

    if (result != null && mounted) {
      await _applyBarcodeResult(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('录入物品'),
        actions: [
          IconButton(
            icon: const Icon(Icons.camera_alt_outlined),
            tooltip: 'AI识图',
            onPressed: () => _navigateToAiVision(context),
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: '扫码录入',
            onPressed: () => _navigateToScanner(context),
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
        final currentHouse = houseProvider.currentHouse;
        if (currentHouse == null) return const SizedBox();

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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('位置 *', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              const SizedBox(height: 8),
              Text('暂无可选空间，请先创建空间', style: TextStyle(color: Colors.grey[400])),
            ],
          );
        }

        // Set default space if not selected
        if (_selectedSpaceId == null) {
          final pendingSpace = spaceProvider.getPendingSpace(currentHouse.id);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _selectedSpaceId == null) {
              setState(() {
                _selectedSpaceId = pendingSpace?.id ?? spaces.first.id;
              });
            }
          });
        }

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
                      onTap: () {
                        setState(() {
                          _selectedSpaceId = pendingSpace.id;
                          _onSpaceChanged(pendingSpace);
                        });
                        Navigator.pop(context);
                      },
                    ),
                  ..._buildSpaceTreeItems(allSpaces, null, spaceProvider, 0, context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSpaceTreeItems(List<Space> allSpaces, String? parentId, SpaceProvider spaceProvider, int level, BuildContext sheetContext) {
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
            onTap: () {
              setState(() {
                _selectedSpaceId = space.id;
                _onSpaceChanged(space);
              });
              Navigator.pop(sheetContext);
            },
          ),
          ..._buildSpaceTreeItems(allSpaces, space.id, spaceProvider, level + 1, sheetContext),
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
            onChanged: (value) {
              if (_isCalculating) return;
              _isCalculating = true;
              setState(() {
                final quantity = int.tryParse(value) ?? 0;
                final price = double.tryParse(_priceController.text);
                if (price != null && quantity > 0) {
                  _totalPriceController.text = (price * quantity).toStringAsFixed(2);
                }
              });
              _isCalculating = false;
            },
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
    return TextFormField(
      controller: _lowStockThresholdController,
      decoration: InputDecoration(
        labelText: '最低库存阈值（选填）',
        hintText: '数量小于等于该值时提醒',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        prefixIcon: const Icon(Icons.notifications_none),
      ),
      keyboardType: TextInputType.number,
      validator: (value) {
        if (value != null && value.isNotEmpty) {
          final threshold = int.tryParse(value);
          if (threshold == null || threshold < 0) {
            return '请输入有效的非负整数';
          }
        }
        return null;
      },
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '扩展信息',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18),
                          tooltip: '编辑分类',
                          onPressed: () {
                            final categoryProvider = context.read<CategoryProvider>();
                            final category = categoryProvider.categories.firstWhereOrNull(
                              (c) => c.id == _selectedCategoryId,
                            );
                            if (category != null) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => CategoryEditPage(category: category),
                                ),
                              );
                            }
                          },
                        ),
                      ],
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
          ),
          keyboardType: TextInputType.url,
          maxLines: 1,
          onChanged: (value) => _customAttributes[attribute.id] = value,
        );
      case 'text':
        return TextFormField(
          initialValue: currentValue,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          minLines: 2,
          maxLines: null,
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
          maxLines: 1,
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
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _submitForm(stayOnPage: true),
              icon: const Icon(Icons.save),
              label: const Text('保存继续'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: () => _submitForm(stayOnPage: false),
              icon: const Icon(Icons.save),
              label: const Text('保存返回'),
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

  Future<void> _submitForm({required bool stayOnPage}) async {
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

    final thresholdText = _lowStockThresholdController.text.trim();
    if (thresholdText.isNotEmpty) {
      final threshold = int.tryParse(thresholdText);
      if (threshold != null && threshold >= 0) {
        _customAttributes['_low_stock_threshold'] = threshold.toString();
      }
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

      if (stayOnPage) {
        // 保存继续：保留位置、分类、二级分类，重置其他字段
        final savedSpaceId = _selectedSpaceId;
        final savedCategory = _selectedCategory;
        final savedCategoryId = _selectedCategoryId;
        final savedSubcategoryId = _selectedSubcategoryId;

        _nameController.clear();
        _quantityController.text = '1';
        _unitController.text = '件';
        _priceController.clear();
        _totalPriceController.clear();
        _noteController.clear();

        setState(() {
          _selectedSpaceId = savedSpaceId;
          _selectedCategory = savedCategory;
          _selectedCategoryId = savedCategoryId;
          _selectedSubcategoryId = savedSubcategoryId;
          _selectedTags = [];
          _customAttributes = {};
          _imagePath = null;
          _lowStockThresholdController.clear();
        });
      } else {
        // 保存返回：AI识图录入返回识图页面，AI聊天录入返回聊天页面，其他返回上一页
        if (widget.visionResult != null) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const AiVisionScanPage()),
          );
        } else if (widget.chatResult != null) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const AiChatPage()),
          );
        } else {
          Navigator.pop(context);
        }
      }
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
