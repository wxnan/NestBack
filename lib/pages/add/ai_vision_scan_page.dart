import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../../providers/ai_provider.dart';
import '../../providers/category_provider.dart';
import 'item_form_page.dart';

class AiVisionScanPage extends StatefulWidget {
  const AiVisionScanPage({super.key});

  @override
  State<AiVisionScanPage> createState() => _AiVisionScanPageState();
}

class _AiVisionScanPageState extends State<AiVisionScanPage> {
  File? _selectedImage;
  String? _compressedImagePath;
  bool _isProcessing = false;
  String _statusText = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 识图录入'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildImageSection(),
          const SizedBox(height: 16),
          _buildVisionModelSelector(context),
          const SizedBox(height: 16),
          if (_selectedImage != null) _buildActionButtons(),
          if (_isProcessing) ...[
            const SizedBox(height: 16),
            _buildProcessingIndicator(),
          ],
          if (_statusText.isNotEmpty && !_isProcessing) ...[
            const SizedBox(height: 16),
            Text(
              _statusText,
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 24),
          _buildTips(),
        ],
      ),
    );
  }

  Widget _buildVisionModelSelector(BuildContext context) {
    final aiProvider = context.watch<AiProviderProvider>();
    final visionModels = aiProvider.visionModels;
    final currentModelId = aiProvider.defaultVisionModelId;
    final currentModel = currentModelId.isNotEmpty ? aiProvider.getModel(currentModelId) : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                const Text(
                  '默认识图模型',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (visionModels.isEmpty)
              Text(
                '暂无可用识图模型，请先在"我的 → AI设置"中配置',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              )
            else
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: currentModelId.isNotEmpty && visionModels.any((m) => m.id == currentModelId)
                    ? currentModelId
                    : null,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: '选择识图模型',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  prefixIcon: currentModel != null
                      ? Padding(
                          padding: const EdgeInsets.only(left: 12, right: 4),
                          child: Chip(
                            label: Text(
                              aiProvider.getProvider(currentModel.providerId)?.name.split('/').first ?? '',
                              style: const TextStyle(fontSize: 10),
                            ),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                          ),
                        )
                      : null,
                  prefixIconConstraints: const BoxConstraints(minWidth: 0),
                ),
                items: visionModels.map((m) {
                  final provider = aiProvider.getProvider(m.providerId);
                  final providerName = provider?.name.split('/').first ?? '';
                  return DropdownMenuItem(
                    value: m.id,
                    child: Text(
                      '$providerName / ${m.name}',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      softWrap: false,
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    aiProvider.setDefaultVisionModelId(value);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageSection() {
    if (_selectedImage != null) {
      return Card(
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Image.file(
              _selectedImage!,
              width: double.infinity,
              height: 300,
              fit: BoxFit.contain,
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: _isProcessing ? null : () {
                  setState(() {
                    _selectedImage = null;
                    _compressedImagePath = null;
                    _statusText = '';
                  });
                },
                icon: const Icon(Icons.close),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.add_a_photo, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              '拍照或从相册选择物品图片',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('拍照'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('相册'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    final bool recognitionFailed = _statusText.startsWith('识别失败');
    final buttons = <Widget>[
      Expanded(
        child: OutlinedButton.icon(
          onPressed: _isProcessing ? null : () => _pickImage(ImageSource.camera),
          icon: const Icon(Icons.camera_alt),
          label: const Text('重拍'),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: OutlinedButton.icon(
          onPressed: _isProcessing ? null : () => _pickImage(ImageSource.gallery),
          icon: const Icon(Icons.photo_library),
          label: const Text('重选'),
        ),
      ),
    ];
    if (recognitionFailed) {
      buttons.addAll([
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: _isProcessing ? null : _startRecognition,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('识别'),
          ),
        ),
      ]);
    }
    return Row(children: buttons);
  }

  Widget _buildProcessingIndicator() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              _statusText.isEmpty ? '正在识别...' : _statusText,
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTips() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lightbulb_outline, size: 18, color: Colors.amber[700]),
                const SizedBox(width: 8),
                const Text(
                  '使用提示',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '1. 请先在"我的 → AI设置"中配置识图模型\n'
              '2. 拍照时请确保物品在画面中清晰可见\n'
              '3. 单个物品识别效果最佳\n'
              '4. 识别结果可手动修改\n'
              '5. 不推荐使用具有推理能力的识图模型',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source, maxWidth: 2400, maxHeight: 2400);
    if (pickedFile == null) return;

    setState(() {
      _isProcessing = true;
      _statusText = '正在压缩图片...';
    });

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final targetPath = '${appDir.path}/$fileName';

      await _compressAndSaveImage(pickedFile.path, targetPath);

      setState(() {
        _selectedImage = File(targetPath);
        _compressedImagePath = targetPath;
      });

      // 自动开始识别
      await _startRecognition();
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusText = '图片处理失败：$e';
      });
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

  Future<void> _startRecognition() async {
    if (_compressedImagePath == null) return;

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

    final visionModel = aiProvider.getModel(aiProvider.defaultVisionModelId);
    if (visionModel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('识图模型不存在，请重新配置')),
      );
      return;
    }

    final provider = aiProvider.getProvider(visionModel.providerId);
    if (provider == null || aiProvider.getEffectiveApiKey(provider).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('提供商未配置 API Key，请先配置')),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusText = '正在识别物品...';
    });

    try {
      // 读取图片并转为 base64
      final imageBytes = await File(_compressedImagePath!).readAsBytes();
      final base64Image = base64Encode(imageBytes);

      // 构建 API 请求
      final baseUrl = provider.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
      final path = provider.apiPath.startsWith('/') ? provider.apiPath : '/${provider.apiPath}';
      final url = Uri.parse('$baseUrl$path');

      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${aiProvider.getEffectiveApiKey(provider)}',
      };

      // 添加自定义 Headers
      if (provider.customHeaders.isNotEmpty && provider.customHeaders != '{}') {
        try {
          final custom = jsonDecode(provider.customHeaders) as Map<String, dynamic>;
          custom.forEach((k, v) => headers[k] = v.toString());
        } catch (_) {}
      }

      // 获取用户分类列表及二级分类
      final categoryProvider = context.read<CategoryProvider>();
      final categoryNames = categoryProvider.categories.map((c) => c.name).toList();
      final categoryList = categoryNames.isNotEmpty ? categoryNames.join('/') : '食品/药品/美妆/日用品/数码/其他';

      // 构建分类-二级分类映射
      final categorySubcategoryMap = <String, List<String>>{};
      for (final category in categoryProvider.categories) {
        final subs = categoryProvider.getSubcategoriesForCategory(category.id);
        categorySubcategoryMap[category.name] = subs.map((s) => s.name).toList();
      }
      final subcategoryInfo = categorySubcategoryMap.entries
          .where((e) => e.value.isNotEmpty)
          .map((e) => '${e.key}: ${e.value.join('/')}')
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

      // 解析 AI 返回的 JSON
      final result = _parseAiResponse(content);

      setState(() {
        _isProcessing = false;
        _statusText = '';
      });

      if (result != null && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ItemFormPage(visionResult: result),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusText = '识别失败：$e';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('识别失败：$e')),
        );
      }
    }
  }

  VisionScanResult? _parseAiResponse(String content) {
    try {
      String jsonStr = content.trim();

      // 移除 <think>...</think> 标签及其内容
      jsonStr = jsonStr.replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '');

      // 尝试提取 JSON 部分（AI 可能返回 markdown 代码块包裹的 JSON）
      final jsonMatch = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(jsonStr);
      if (jsonMatch != null) {
        jsonStr = jsonMatch.group(1)!.trim();
      }

      // 尝试找到 JSON 对象
      final braceStart = jsonStr.indexOf('{');
      final braceEnd = jsonStr.lastIndexOf('}');
      if (braceStart >= 0 && braceEnd > braceStart) {
        jsonStr = jsonStr.substring(braceStart, braceEnd + 1);
      }

      // 尝试解析 JSON
      try {
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        return _parseFromJson(json);
      } catch (_) {
        // JSON 解析失败，尝试解析键值对格式
        return _parseFromKeyValue(content);
      }
    } catch (e) {
      debugPrint('解析 AI 响应失败: $e\n原始内容: $content');
      setState(() {
        _isProcessing = false;
        _statusText = '';
      });
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('AI 响应解析失败'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('异常信息：$e'),
                  const SizedBox(height: 12),
                  const Text('AI 原始响应：', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      content,
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('确定')),
            ],
          ),
        );
      }
      return null;
    }
  }

  VisionScanResult _parseFromJson(Map<String, dynamic> json) {
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
      imagePath: _compressedImagePath ?? '',
    );
  }

  VisionScanResult? _parseFromKeyValue(String content) {
    try {
      // 移除 <think>...</think> 标签及其内容
      String text = content.replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '');

      final Map<String, String> data = {};
      
      // 按行解析键值对
      final lines = text.split('\n');
      for (final line in lines) {
        final trimmedLine = line.trim();
        if (trimmedLine.isEmpty) continue;
        
        // 匹配 key: value 格式
        final match = RegExp(r'^\s*(\w+)\s*[:：]\s*(.+)$').firstMatch(trimmedLine);
        if (match != null) {
          final key = match.group(1)!.toLowerCase().trim();
          final value = match.group(2)!.trim();
          data[key] = value;
        }
      }

      if (data.isEmpty) {
        return null;
      }

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
        imagePath: _compressedImagePath ?? '',
      );
    } catch (e) {
      debugPrint('解析键值对格式失败: $e');
      return null;
    }
  }
}

class VisionScanResult {
  final String name;
  final String category;
  final String subcategory;
  final String brand;
  final String manufacturer;
  final String spec;
  final String color;
  final double? price;
  final String description;
  final String imagePath;

  VisionScanResult({
    required this.name,
    required this.category,
    required this.subcategory,
    required this.brand,
    required this.manufacturer,
    required this.spec,
    required this.color,
    this.price,
    required this.description,
    required this.imagePath,
  });
}
