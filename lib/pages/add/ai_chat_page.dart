import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../providers/ai_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/space_provider.dart';
import '../../providers/house_provider.dart';
import '../../providers/item_provider.dart';
import '../../providers/attribute_provider.dart';
import '../../database/database.dart';
import 'ai_vision_scan_page.dart';
import 'item_form_page.dart';

class AiChatPage extends StatefulWidget {
  const AiChatPage({super.key});

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<_ChatMessage> _messages = [];
  bool _isProcessing = false;
  VisionScanResult? _extractedResult;
  String? _compressedImagePath;

  @override
  void initState() {
    super.initState();
    _addSystemMessage('你好！我是归巢AI助手，可以帮你快速录入物品。\n\n'
        '你可以用自然语言描述物品，例如：\n'
        '• "一盒鲜牛奶，9元，7天后过期，放在冰箱里"\n'
        '• "今天新买了一个充电宝，79元，保修1年"\n'
        '• "感冒药，生产日期2025年1月，保质期24个月"');
  }

  void _addSystemMessage(String text) {
    _messages.add(_ChatMessage(text: text, isUser: false, isSystem: true));
  }

  void _addUserMessage(String text) {
    _messages.add(_ChatMessage(text: text, isUser: true));
  }

  void _addAiMessage(String text) {
    _messages.add(_ChatMessage(text: text, isUser: false));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    final hasImage = _compressedImagePath != null;

    // 必须至少有一种输入
    if ((text.isEmpty && !hasImage) || _isProcessing) return;

    // 聊天模型（非识图模型）下，不能只发图片不发文字
    if (hasImage && text.isEmpty) {
      final aiProvider = context.read<AiProviderProvider>();
      final chatModel = aiProvider.getModel(aiProvider.defaultChatModelId);
      final isVisionModel = chatModel?.type == 'vision';
      if (!isVisionModel) {
        setState(() {
          _addAiMessage('当前使用的是文字聊天模型，无法识别图片内容。请用文字描述一下这个物品。');
        });
        _scrollToBottom();
        return;
      }
    }

    // 构建用户消息显示文本
    String displayText = text;
    if (hasImage && text.isEmpty) {
      displayText = '[图片]';
    } else if (hasImage) {
      displayText = '$text [图片]';
    }

    _textController.clear();
    _addUserMessage(displayText);
    _extractedResult = null;

    // 临时保存图片路径，发送后清空
    final imagePath = _compressedImagePath;
    setState(() {
      _isProcessing = true;
      _compressedImagePath = null;
    });
    _scrollToBottom();

    try {
      final result = await _callChatLlm(text, imagePath);
      setState(() {
        _isProcessing = false;
        if (result != null) {
          _extractedResult = result;
          _addAiMessage(_formatResultMessage(result));
        } else {
          _addAiMessage('抱歉，我没能理解你的描述。请尝试更详细地描述物品信息，例如名称、数量、分类等。');
        }
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _addAiMessage('处理失败：$e');
      });
    }
    _scrollToBottom();
  }

  String _formatResultMessage(VisionScanResult result) {
    final parts = <String>['已识别到以下物品信息：'];
    if (result.name.isNotEmpty) parts.add('名称：${result.name}');
    if (result.category.isNotEmpty) parts.add('分类：${result.category}');
    if (result.subcategory.isNotEmpty) parts.add('二级分类：${result.subcategory}');
    if (result.brand.isNotEmpty) parts.add('品牌：${result.brand}');
    if (result.manufacturer.isNotEmpty) parts.add('厂商：${result.manufacturer}');
    if (result.spec.isNotEmpty) parts.add('规格：${result.spec}');
    if (result.color.isNotEmpty) parts.add('颜色：${result.color}');
    if (result.price != null) parts.add('单价：${result.price}元');
    if (result.quantity != null) parts.add('数量：${result.quantity}${result.unit ?? "件"}');
    if (result.location != null && result.location!.isNotEmpty) parts.add('位置：${result.location}');
    if (result.productionDate != null && result.productionDate!.isNotEmpty) parts.add('生产日期：${result.productionDate}');
    if (result.shelfLife != null && result.shelfLife!.isNotEmpty) parts.add('保质期：${result.shelfLife}');
    if (result.expireDate != null && result.expireDate!.isNotEmpty) parts.add('过期日期：${result.expireDate}');
    if (result.purchaseDate != null && result.purchaseDate!.isNotEmpty) parts.add('购买日期：${result.purchaseDate}');
    if (result.warrantyPeriod != null && result.warrantyPeriod!.isNotEmpty) parts.add('保修期：${result.warrantyPeriod}');
    if (result.warrantyExpireDate != null && result.warrantyExpireDate!.isNotEmpty) parts.add('过保日期：${result.warrantyExpireDate}');
    if (result.description.isNotEmpty) parts.add('描述：${result.description}');
    parts.add('\n请确认信息是否正确，点击下方按钮录入。');
    return parts.join('\n');
  }

  Future<VisionScanResult?> _callChatLlm(String userMessage, String? imagePath) async {
    final aiProvider = context.read<AiProviderProvider>();
    final categoryProvider = context.read<CategoryProvider>();
    final hasImage = imagePath != null && imagePath.isNotEmpty;

    if (aiProvider.defaultChatModelId.isEmpty) {
      throw Exception('请先在"我的 → AI设置"中配置默认聊天模型');
    }

    final chatModel = aiProvider.getModel(aiProvider.defaultChatModelId);
    if (chatModel == null) {
      throw Exception('聊天模型不存在，请重新配置');
    }

    final provider = aiProvider.getProvider(chatModel.providerId);
    if (provider == null || aiProvider.getEffectiveApiKey(provider).isEmpty) {
      throw Exception('提供商未配置 API Key');
    }

    // 判断是否使用识图模型：有图片且当前模型支持vision
    final isVisionModel = chatModel.type == 'vision';
    final useVision = hasImage && isVisionModel;

    // 获取分类列表
    final categoryNames = categoryProvider.categories.map((c) => c.name).toList();
    final categoryList = categoryNames.isNotEmpty ? categoryNames.join('/') : '食品/药品/美妆/日用品/数码/其他';

    final categorySubcategoryMap = <String, List<String>>{};
    for (final category in categoryProvider.categories) {
      final subs = categoryProvider.getSubcategoriesForCategory(category.id);
      categorySubcategoryMap[category.name] = subs.map((s) => s.name).toList();
    }
    final subcategoryInfo = categorySubcategoryMap.entries
        .where((e) => e.value.isNotEmpty)
        .map((e) => '${e.key}: ${e.value.join("/")}')
        .join('\n');

    // 获取空间位置列表
    final spaceProvider = context.read<SpaceProvider>();
    final houseProvider = context.read<HouseProvider>();
    final currentHouse = houseProvider.currentHouse;
    final locationList = currentHouse != null
        ? spaceProvider.getAllSpacesExceptSpecial(currentHouse.id).map((s) => s.name).join('/')
        : '';

    final today = DateTime.now().toIso8601String().split('T').first;

    // 公共上下文信息
    final contextInfo = '可用一级分类：$categoryList\n'
        '已有二级分类：\n$subcategoryInfo\n'
        '${locationList.isNotEmpty ? "已有位置：$locationList\n" : ""}'
        '今天日期：$today\n';

    // JSON输出格式规范
    final jsonSpec = '严格按以下JSON格式输出，不要输出任何其他内容（不要markdown代码块、不要解释）：\n'
        '{\n'
        '  "name": "物品名称（必填）",\n'
        '  "category": "一级分类（必填，必须从上述列表选择）",\n'
        '  "subcategory": "二级分类（优先匹配已有，也可新建；无则为null）",\n'
        '  "brand": "品牌（无则为null）",\n'
        '  "manufacturer": "厂商（无则为null）",\n'
        '  "spec": "规格（无则为null）",\n'
        '  "color": "颜色（无则为null）",\n'
        '  "price": 单价数字或null,\n'
        '  "quantity": 数量数字或1,\n'
        '  "unit": "单位（瓶/个/盒/箱/包/袋/件等，默认件）",\n'
        '  "location": "位置（匹配已有位置，无则为null）",\n'
        '  "purchaseDate": "YYYY-MM-DD或null",\n'
        '  "warrantyPeriod": "保修期如12月/1年或null",\n'
        '  "warrantyExpireDate": "YYYY-MM-DD或null（购买日期+保修期推算）",\n'
        '  "productionDate": "YYYY-MM-DD或null",\n'
        '  "shelfLife": "保质期如7天/6月/2年或null",\n'
        '  "expireDate": "YYYY-MM-DD或null（生产日期+保质期推算，或用户直接说的过期日期）",\n'
        '  "description": "描述或null"\n'
        '}\n\n'
        '关键规则：\n'
        '1. name必填，category必须是一级分类列表中的值\n'
        '2. subcategory是一级分类下的细分，不能与一级分类同名\n'
        '3. 字符串用英文双引号，数字不加引号，无信息填null（不加引号）\n'
        '4. 日期格式YYYY-MM-DD，相对日期（今天/昨天/N天前/N个月后等）基于今天日期推算\n'
        '5. 保质期/保修期格式：数字+天/月/年，如"7天"、"6月"、"1年"，禁止使用"个月"，必须用"月"（如6个月→"6月"）\n'
        '6. expireDate：用户说过期日期时直接填；用户说保质期+生产日期时由你推算\n'
        '7. warrantyExpireDate：由购买日期+保修期推算\n';

    final String systemPrompt;
    if (useVision) {
      // 有图片时的提示词：强调视觉特征识别
      systemPrompt = '你是家庭物品信息提取器。根据用户发送的物品图片和文字描述，提取信息并严格按JSON格式返回，不要输出任何其他内容。\n\n'
          '$contextInfo'
          '$jsonSpec'
          '示例1：用户发送混合坚果仁罐装图片 → {"name":"混合坚果仁","category":"食品","subcategory":"零食","brand":null,"manufacturer":null,"spec":null,"color":"混合色","price":null,"quantity":1,"unit":"罐","location":null,"purchaseDate":null,"warrantyPeriod":null,"warrantyExpireDate":null,"productionDate":null,"shelfLife":null,"expireDate":null,"description":"透明罐装混合坚果仁，标签上有生产日期"}\n'
          '示例2：用户发送蓝色包装洗衣液图片 → {"name":"洗衣液","category":"日用品","subcategory":"清洁","brand":null,"manufacturer":null,"spec":null,"color":"蓝色","price":null,"quantity":1,"unit":"瓶","location":null,"purchaseDate":null,"warrantyPeriod":null,"warrantyExpireDate":null,"productionDate":null,"shelfLife":null,"expireDate":null,"description":"瓶装蓝色洗衣液，透明瓶身"}\n'
          '示例3：用户发送坚果仁图片并说"餐厅，生产日期20260122，保质期9个月" → {"name":"坚果仁","category":"食品","subcategory":"零食","brand":null,"manufacturer":null,"spec":null,"color":"混合色","price":null,"quantity":1,"unit":"罐","location":"餐厅","purchaseDate":null,"warrantyPeriod":null,"warrantyExpireDate":null,"productionDate":"2026-01-22","shelfLife":"9月","expireDate":"2026-10-22","description":"罐装混合坚果仁"}\n\n'
          '【图片识别重点】以下字段必须从图片视觉内容中识别，不能留null：\n'
          '- color：物品主体颜色或包装主色调\n'
          '- description：物品外观描述（包装形式、颜色、形状等）\n'
          '- name：图片中的品牌名、商品名\n'
          '- brand：图片包装上的品牌文字（有则必填）\n'
          '- spec：图片包装上的规格信息（有则必填）';
    } else {
      // 无图片时的提示词：基于文字描述
      systemPrompt = '你是家庭物品信息提取器。根据用户的文字描述，提取物品信息并严格按JSON格式返回，不要输出任何其他内容。\n\n'
          '$contextInfo'
          '$jsonSpec'
          '示例1：用户说"买了3瓶可口可乐，放在冰箱里" → {"name":"可口可乐","category":"食品","subcategory":"饮料","brand":null,"manufacturer":null,"spec":null,"color":null,"price":null,"quantity":3,"unit":"瓶","location":"冰箱","purchaseDate":null,"warrantyPeriod":null,"warrantyExpireDate":null,"productionDate":null,"shelfLife":null,"expireDate":null,"description":null}\n'
          '示例2：用户说"昨天新买了一个小米充电宝，79元，保修1年" → {"name":"小米充电宝","category":"数码","subcategory":null,"brand":"小米","manufacturer":null,"spec":null,"color":null,"price":79,"quantity":1,"unit":"个","location":null,"purchaseDate":"$today","warrantyPeriod":"1年","warrantyExpireDate":"${_addShelfLife(today, '1年') ?? today}","productionDate":null,"shelfLife":null,"expireDate":null,"description":null}\n'
          '示例3：用户说"感冒药，生产日期2025年1月，保质期24个月" → {"name":"感冒药","category":"药品","subcategory":null,"brand":null,"manufacturer":null,"spec":null,"color":null,"price":null,"quantity":1,"unit":"盒","location":null,"purchaseDate":null,"warrantyPeriod":null,"warrantyExpireDate":null,"productionDate":"2025-01-01","shelfLife":"24月","expireDate":"2027-01-01","description":null}\n'
          '示例4：用户说"买了1瓶牛奶，花了9元，10天后过期，放冰箱里了" → {"name":"牛奶","category":"食品","subcategory":"乳品","brand":null,"manufacturer":null,"spec":null,"color":null,"price":9,"quantity":1,"unit":"瓶","location":"冰箱","purchaseDate":null,"warrantyPeriod":null,"warrantyExpireDate":null,"productionDate":null,"shelfLife":null,"expireDate":"${_addShelfLife(today, '10天') ?? today}","description":null}';
    }

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

    late String body;

    if (useVision) {
      // 识图模型：发送文字+图片
      final imageBytes = await File(imagePath).readAsBytes();
      final base64Image = base64Encode(imageBytes);

      body = jsonEncode({
        'model': chatModel.modelId,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {
            'role': 'user',
            'content': [
              if (userMessage.isNotEmpty)
                {'type': 'text', 'text': userMessage}
              else
                {'type': 'text', 'text': '请识别图片中的物品'},
              {
                'type': 'image_url',
                'image_url': {'url': 'data:image/jpeg;base64,$base64Image'},
              },
            ],
          },
        ],
        'max_tokens': 1200,
      });
    } else {
      // 聊天模型：只发送文字（图片作为封面，不发给AI）
      body = jsonEncode({
        'model': chatModel.modelId,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userMessage.isNotEmpty ? userMessage : '请识别图片中的物品'},
        ],
        'max_tokens': 1200,
      });
    }

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

    return _parseAiResponse(content, userMessage, imagePath);
  }

  VisionScanResult? _parseAiResponse(String content, String userMessage, String? imagePath) {
    debugPrint('=== AI原始响应 ===');
    debugPrint(content);
    debugPrint('==================');

    try {
      String jsonStr = content.trim();

      // 移除 <think...</think 标签
      jsonStr = jsonStr.replaceAll(RegExp(r'<think[\s\S]*?</think', caseSensitive: false), '');

      // 尝试提取 JSON（AI 可能返回 markdown 代码块包裹的 JSON）
      final jsonMatch = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(jsonStr);
      if (jsonMatch != null) {
        jsonStr = jsonMatch.group(1)!.trim();
      }

      // 找到 JSON 对象
      final braceStart = jsonStr.indexOf('{');
      final braceEnd = jsonStr.lastIndexOf('}');
      if (braceStart >= 0 && braceEnd > braceStart) {
        jsonStr = jsonStr.substring(braceStart, braceEnd + 1);
      }

      debugPrint('提取后的JSON: $jsonStr');

      // 第一次尝试：直接解析
      try {
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        debugPrint('第一次解析成功: $json');
        return _parseFromJson(json, userMessage, imagePath);
      } catch (e) {
        debugPrint('第一次解析失败: $e');
      }

      // 第二次尝试：修复后解析
      final repairedJsonStr = _repairJson(jsonStr);
      debugPrint('修复后的JSON: $repairedJsonStr');
      try {
        final json = jsonDecode(repairedJsonStr) as Map<String, dynamic>;
        debugPrint('第二次解析成功: $json');
        return _parseFromJson(json, userMessage, imagePath);
      } catch (e) {
        debugPrint('第二次解析失败: $e');
      }

      // 第三次尝试：正则兜底提取键值对（支持字段名有引号或无引号）
      final extracted = _extractKeyValuePairs(jsonStr);
      if (extracted != null && extracted.isNotEmpty) {
        debugPrint('正则提取成功: $extracted');
        return _parseFromJson(extracted, userMessage, imagePath);
      }
      debugPrint('正则提取失败，未匹配到任何键值对');

      return null;
    } catch (e) {
      debugPrint('解析 AI 响应失败: $e\n原始内容: $content');
      return null;
    }
  }

  /// 修复 AI 返回的不规范 JSON
  String _repairJson(String jsonStr) {
    // 1. 去除中文引号/智能引号/全角引号/日文引号等各种非ASCII引号
    jsonStr = jsonStr
        .replaceAll('\u201C', '')  // "
        .replaceAll('\u201D', '')  // "
        .replaceAll('\u2018', '')  // '
        .replaceAll('\u2019', '')  // '
        .replaceAll('\uFF02', '')  // ＂全角双引号
        .replaceAll('\u300C', '')  // 「
        .replaceAll('\u300D', '')  // 」
        .replaceAll('\u300E', '')  // 『
        .replaceAll('\u300F', '')  // 』
        .replaceAll('\u301D', '')  // 〝
        .replaceAll('\u301E', '')  // 〞
        .replaceAll('\u301F', ''); // 〟

    // 2. 修复双重引号： "key": ""value"" → "key": "value"
    jsonStr = jsonStr.replaceAllMapped(
      RegExp(r'(:\s*)""([^",:}\]]*?)""'),
      (match) => '${match.group(1)}"${match.group(2)}"',
    );

    // 3. 修复字段名无引号的情况：name: "牛奶" → "name": "牛奶"
    jsonStr = jsonStr.replaceAllMapped(
      RegExp(r'(^|\{|,|\s)(\w+)(\s*:\s*)'),
      (match) => '${match.group(1)}"${match.group(2)}"${match.group(3)}',
    );

    // 4. 修复未加引号的字符串值： "unit": 瓶, → "unit": "瓶",
    // 注意：这一步要在字段名修复之后执行
    jsonStr = jsonStr.replaceAllMapped(
      RegExp(r'"(\w+)"\s*:\s*([^"\d\[\{n\-][^,}\s\]]*)'),
      (match) {
        final key = match.group(1)!;
        final value = match.group(2)!.trim();
        if (value == 'null' || value == 'true' || value == 'false') {
          return '"$key": $value';
        }
        return '"$key": "$value"';
      },
    );

    return jsonStr;
  }

  /// 正则兜底：从可能损坏的 JSON 中提取键值对
  /// 支持字段名有引号或无引号
  Map<String, dynamic>? _extractKeyValuePairs(String jsonStr) {
    final result = <String, dynamic>{};
    // 匹配 "key": value 或 key: value，value 可以是 "string"、number、null、true/false
    final pattern = RegExp(
      r'(?:"(\w+)"|(\w+))\s*:\s*(?:"([^"]*?)"|(\d+\.?\d*)|(null|true|false))',
      multiLine: true,
    );
    for (final match in pattern.allMatches(jsonStr)) {
      final key = match.group(1) ?? match.group(2)!;
      if (match.group(3) != null) {
        result[key] = match.group(3);
      } else if (match.group(4) != null) {
        final numStr = match.group(4)!;
        result[key] = numStr.contains('.') ? double.parse(numStr) : int.parse(numStr);
      } else if (match.group(5) != null) {
        final val = match.group(5)!;
        result[key] = val == 'null' ? null : val == 'true';
      }
    }
    return result.isNotEmpty ? result : null;
  }

  String _safeString(dynamic value) {
    if (value == null) return '';
    final str = value.toString();
    if (str.toLowerCase() == 'null') return '';
    return str;
  }

  VisionScanResult _parseFromJson(Map<String, dynamic> json, String userMessage, String? imagePath) {
    double? parsePrice(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      if (value is String) {
        final cleaned = value.replaceAll(RegExp(r'[^\d.]'), '');
        return double.tryParse(cleaned);
      }
      return null;
    }

    int? parseQuantity(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value);
      return null;
    }

    // 代码层面校验：防止AI把分类和二级分类填反或混写
    final categoryProvider = context.read<CategoryProvider>();
    final availableCategories = categoryProvider.categories.map((c) => c.name).toSet();
    String rawCategory = _safeString(json['category']);
    String rawSubcategory = _safeString(json['subcategory']);

    // 从subcategory中提取可能的一级分类（AI可能写成"食品: 零食"或"食品/零食"）
    String? extractedCategory;
    if (rawSubcategory.isNotEmpty) {
      // 尝试用常见分隔符分割
      final separators = RegExp(r'[:：/,，;；\-|]');
      final parts = rawSubcategory.split(separators);
      for (final part in parts) {
        final trimmed = part.trim();
        if (trimmed.isNotEmpty && availableCategories.contains(trimmed)) {
          extractedCategory = trimmed;
          break;
        }
      }
    }

    // 情况1：category不在可用列表中，但subcategory完整匹配某个可用分类
    if (rawCategory.isNotEmpty &&
        rawSubcategory.isNotEmpty &&
        !availableCategories.contains(rawCategory) &&
        availableCategories.contains(rawSubcategory)) {
      // 交换
      final tmp = rawCategory;
      rawCategory = rawSubcategory;
      rawSubcategory = tmp;
    }
    // 情况2：subcategory中嵌套了一级分类（如"食品: 零食"），需要拆分
    else if (extractedCategory != null &&
        extractedCategory != rawCategory &&
        availableCategories.contains(extractedCategory)) {
      // 用提取到的一级分类替换category
      rawCategory = extractedCategory;
      // 从subcategory中移除一级分类前缀，保留真正的二级分类
      final separators = RegExp(r'[:：/,，;；\-|]');
      final parts = rawSubcategory.split(separators).map((s) => s.trim()).toList();
      parts.remove(extractedCategory);
      rawSubcategory = parts.where((s) => s.isNotEmpty).join('/');
    }

    // 从用户输入中提取相对时间并计算正确日期
    // 购买日期：代码计算优先（AI经常把"昨天"算错）
    String? correctedPurchaseDate = _computePurchaseDateFromUserMessage(userMessage);
    String? aiPurchaseDate = _safeString(json['purchaseDate']);
    String? finalPurchaseDate = correctedPurchaseDate ?? (aiPurchaseDate.isNotEmpty ? aiPurchaseDate : null);

    String? correctedExpireDate = _computeExpireDateFromUserMessage(userMessage);
    String? aiExpireDate = _safeString(json['expireDate']);
    // 如果AI算的日期和代码算的不一致，以代码计算为准
    String? finalExpireDate = correctedExpireDate ?? (aiExpireDate.isNotEmpty ? aiExpireDate : null);

    // 根据保质期推算过期日期（如果有生产日期但没有过期日期）
    if (finalExpireDate == null || finalExpireDate.isEmpty) {
      final shelfLife = _safeString(json['shelfLife']);
      final productionDate = _safeString(json['productionDate']);
      if (shelfLife.isNotEmpty && productionDate.isNotEmpty) {
        finalExpireDate = _addShelfLife(productionDate, shelfLife);
      }
    }

    // 计算过保日期：代码计算优先（AI经常把日期算错）
    String? correctedWarrantyExpireDate;
    final warrantyPeriod = _safeString(json['warrantyPeriod']);
    if (finalPurchaseDate != null && warrantyPeriod.isNotEmpty) {
      correctedWarrantyExpireDate = _addShelfLife(finalPurchaseDate, warrantyPeriod);
    }
    String? aiWarrantyExpireDate = _safeString(json['warrantyExpireDate']);
    String? finalWarrantyExpireDate = correctedWarrantyExpireDate ?? (aiWarrantyExpireDate.isNotEmpty ? aiWarrantyExpireDate : null);

    return VisionScanResult(
      name: _safeString(json['name']),
      category: rawCategory.isNotEmpty ? rawCategory : '其他',
      subcategory: rawSubcategory,
      brand: _safeString(json['brand']),
      manufacturer: _safeString(json['manufacturer']),
      spec: _safeString(json['spec']),
      color: _safeString(json['color']),
      price: parsePrice(json['price']),
      description: _safeString(json['description']),
      imagePath: imagePath ?? '',
      quantity: parseQuantity(json['quantity']),
      unit: _safeString(json['unit']).isNotEmpty ? _safeString(json['unit']) : null,
      location: _safeString(json['location']).isNotEmpty ? _safeString(json['location']) : null,
      purchaseDate: finalPurchaseDate,
      warrantyPeriod: _safeString(json['warrantyPeriod']).isNotEmpty ? _safeString(json['warrantyPeriod']) : null,
      warrantyExpireDate: finalWarrantyExpireDate != null && finalWarrantyExpireDate.isNotEmpty ? finalWarrantyExpireDate : null,
      productionDate: _safeString(json['productionDate']).isNotEmpty ? _safeString(json['productionDate']) : null,
      shelfLife: _safeString(json['shelfLife']).isNotEmpty ? _safeString(json['shelfLife']) : null,
      expireDate: finalExpireDate,
    );
  }

  /// 从用户消息中提取相对时间并计算过期日期
  /// 支持：XX年XX月过期、N天后、N周后、N个月后、N年后、明天、后天
  String? _computeExpireDateFromUserMessage(String message) {
    final now = DateTime.now();

    // 匹配 "28年2月过期"、"2028年2月到期" 等具体年月过期
    final yearMonthExpireMatch = RegExp(r'(\d{2,4})\s*年\s*(\d{1,2})\s*月\s*(?:过期|到期)').firstMatch(message);
    if (yearMonthExpireMatch != null) {
      var year = int.parse(yearMonthExpireMatch.group(1)!);
      final month = int.parse(yearMonthExpireMatch.group(2)!);
      // 2位年份转4位：28 → 2028
      if (year < 100) year += 2000;
      return _formatDate(DateTime(year, month, 1));
    }

    // 匹配 "N天后"、"N天后过期"、"还有N天就过期了"
    final dayMatch = RegExp(r'(\d+)\s*天\s*后').firstMatch(message);
    if (dayMatch != null) {
      final days = int.parse(dayMatch.group(1)!);
      final date = now.add(Duration(days: days));
      return _formatDate(date);
    }

    // 匹配 "N周后"
    final weekMatch = RegExp(r'(\d+)\s*周\s*后').firstMatch(message);
    if (weekMatch != null) {
      final weeks = int.parse(weekMatch.group(1)!);
      final date = now.add(Duration(days: weeks * 7));
      return _formatDate(date);
    }

    // 匹配 "N个月后"
    final monthMatch = RegExp(r'(\d+)\s*个?月\s*后').firstMatch(message);
    if (monthMatch != null) {
      final months = int.parse(monthMatch.group(1)!);
      final date = DateTime(now.year, now.month + months, now.day);
      return _formatDate(date);
    }

    // 匹配 "N年后"
    final yearMatch = RegExp(r'(\d+)\s*年\s*后').firstMatch(message);
    if (yearMatch != null) {
      final years = int.parse(yearMatch.group(1)!);
      final date = DateTime(now.year + years, now.month, now.day);
      return _formatDate(date);
    }

    // 匹配 "明天"
    if (RegExp(r'明天').hasMatch(message)) {
      return _formatDate(now.add(const Duration(days: 1)));
    }

    // 匹配 "后天"
    if (RegExp(r'后天').hasMatch(message)) {
      return _formatDate(now.add(const Duration(days: 2)));
    }

    return null;
  }

  /// 从用户消息中提取相对购买日期
  /// 支持：今天、昨天、前天、N天前、N周前、N个月前、N年前
  String? _computePurchaseDateFromUserMessage(String message) {
    final now = DateTime.now();

    // 匹配 "N天前买了"、"N天前购买"
    final dayAgoMatch = RegExp(r'(\d+)\s*天\s*前').firstMatch(message);
    if (dayAgoMatch != null) {
      final days = int.parse(dayAgoMatch.group(1)!);
      return _formatDate(now.subtract(Duration(days: days)));
    }

    // 匹配 "N周前"
    final weekAgoMatch = RegExp(r'(\d+)\s*周\s*前').firstMatch(message);
    if (weekAgoMatch != null) {
      final weeks = int.parse(weekAgoMatch.group(1)!);
      return _formatDate(now.subtract(Duration(days: weeks * 7)));
    }

    // 匹配 "N个月前"
    final monthAgoMatch = RegExp(r'(\d+)\s*个?月\s*前').firstMatch(message);
    if (monthAgoMatch != null) {
      final months = int.parse(monthAgoMatch.group(1)!);
      return _formatDate(DateTime(now.year, now.month - months, now.day));
    }

    // 匹配 "N年前"
    final yearAgoMatch = RegExp(r'(\d+)\s*年\s*前').firstMatch(message);
    if (yearAgoMatch != null) {
      final years = int.parse(yearAgoMatch.group(1)!);
      return _formatDate(DateTime(now.year - years, now.month, now.day));
    }

    // 匹配 "昨天"
    if (RegExp(r'昨天').hasMatch(message)) {
      return _formatDate(now.subtract(const Duration(days: 1)));
    }

    // 匹配 "前天"
    if (RegExp(r'前天').hasMatch(message)) {
      return _formatDate(now.subtract(const Duration(days: 2)));
    }

    // 匹配 "今天"
    if (RegExp(r'今天').hasMatch(message)) {
      return _formatDate(now);
    }

    return null;
  }

  /// 根据起始日期和期限推算目标日期（支持天/月/年）
  String? _addShelfLife(String startDate, String duration) {
    try {
      final date = DateTime.parse(startDate);
      final match = RegExp(r'(\d+)\s*(?:个)?\s*(天|月|年)').firstMatch(duration);
      if (match == null) return null;
      final value = int.parse(match.group(1)!);
      final unit = match.group(2)!;
      DateTime result;
      if (unit == '年') {
        result = DateTime(date.year + value, date.month, date.day);
      } else if (unit == '月') {
        result = DateTime(date.year, date.month + value, date.day);
      } else { // 天
        result = date.add(Duration(days: value));
      }
      return _formatDate(result);
    } catch (_) {
      return null;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source);
    if (pickedFile == null) return;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final targetPath = p.join(appDir.path, 'ai_chat_images', '${DateTime.now().millisecondsSinceEpoch}.jpg');
      await Directory(p.dirname(targetPath)).create(recursive: true);
      await _compressAndSaveImage(pickedFile.path, targetPath);
      setState(() {
        _compressedImagePath = targetPath;
      });
    } catch (e) {
      debugPrint('图片压缩失败: $e');
      setState(() {
        _compressedImagePath = pickedFile.path;
      });
    }
  }

  void _showImageSourcePicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                '选择图片',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey[800]),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.camera_alt, color: Theme.of(context).colorScheme.primary),
              title: const Text('拍照'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: Icon(Icons.photo_library, color: Theme.of(context).colorScheme.primary),
              title: const Text('从相册选择'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
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
      _compressedImagePath = null;
    });
  }

  void _navigateToForm() {
    if (_extractedResult == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ItemFormPage(chatResult: _extractedResult),
      ),
    );
  }

  Future<void> _confirmAndSave() async {
    if (_extractedResult == null) return;

    final result = _extractedResult!;
    final houseProvider = context.read<HouseProvider>();
    final currentHouse = houseProvider.currentHouse;
    if (currentHouse == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先选择一个家庭')),
        );
      }
      return;
    }

    // 提前获取所有provider引用，避免async后使用context
    final categoryProvider = context.read<CategoryProvider>();
    final spaceProvider = context.read<SpaceProvider>();
    final attributeProvider = context.read<AttributeProvider>();
    final itemProvider = context.read<ItemProvider>();
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    // 匹配分类
    String categoryName = result.category.isNotEmpty ? result.category : '其他';
    String? categoryId;

    Category? matchedCategory;
    try {
      matchedCategory = categoryProvider.categories.firstWhere((c) => c.name == categoryName);
    } catch (_) {
      try {
        matchedCategory = categoryProvider.categories.firstWhere((c) => c.name == '其他');
      } catch (_) {}
    }
    if (matchedCategory != null && matchedCategory.id.isNotEmpty) {
      categoryId = matchedCategory.id;
      categoryName = matchedCategory.name;
    }

    // 匹配二级分类
    String? subcategoryId;
    if (result.subcategory.isNotEmpty && categoryId != null) {
      final subcategories = categoryProvider.getSubcategoriesForCategory(categoryId);
      Subcategory? matchedSub;
      try {
        matchedSub = subcategories.firstWhere((s) => s.name == result.subcategory);
      } catch (_) {}
      if (matchedSub != null) {
        subcategoryId = matchedSub.id;
      } else {
        await categoryProvider.addSubcategory(
          categoryId: categoryId,
          name: result.subcategory,
        );
        final newSubs = categoryProvider.getSubcategoriesForCategory(categoryId);
        try {
          final newSub = newSubs.firstWhere((s) => s.name == result.subcategory);
          subcategoryId = newSub.id;
        } catch (_) {}
      }
    }

    // 匹配位置
    String? spaceId;
    if (result.location != null && result.location!.isNotEmpty) {
      final allSpaces = spaceProvider.getAllSpacesExceptSpecial(currentHouse.id);
      Space? matchedSpace;
      try {
        matchedSpace = allSpaces.firstWhere((s) => s.name == result.location);
      } catch (_) {
        try {
          matchedSpace = allSpaces.firstWhere(
            (s) => s.name.contains(result.location!) || result.location!.contains(s.name),
          );
        } catch (_) {}
      }
      spaceId = matchedSpace?.id;
    }

    // 如果没有匹配到位置，使用默认位置
    if (spaceId == null || spaceId.isEmpty) {
      final pendingSpace = spaceProvider.getPendingSpace(currentHouse.id);
      if (pendingSpace != null) {
        spaceId = pendingSpace.id;
      } else {
        final spaces = spaceProvider.spaces
            .where((s) => s.houseId == currentHouse.id && s.type != 'trash')
            .toList();
        if (spaces.isNotEmpty) spaceId = spaces.first.id;
      }
    }

    if (spaceId == null || spaceId.isEmpty) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('无法确定物品位置，请先添加位置')),
        );
      }
      return;
    }

    // 构建扩展属性
    final customAttributes = <String, String>{};

    if (categoryId != null && categoryId.isNotEmpty) {
      final attributes = await attributeProvider.getAttributesForCategory(categoryId);
      final attributeNameMap = <String, Attribute>{};
      for (final attr in attributes) {
        attributeNameMap[attr.name] = attr;
      }

      // 将保质期/保修期字符串转换为 "数值|单位" 格式，与 _applyChatResult 保持一致
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

      for (final entry in fieldMap.entries) {
        if (entry.value != null && entry.value!.isNotEmpty) {
          final attr = attributeNameMap[entry.key];
          if (attr != null) {
            customAttributes[attr.id] = entry.value!;
          }
        }
      }
    }

    // 解析过期日期
    DateTime? expireDate;
    if (result.expireDate != null && result.expireDate!.isNotEmpty) {
      try {
        expireDate = DateTime.parse(result.expireDate!);
      } catch (_) {}
    }

    // 解析过保日期（如果有过保日期但没有过期日期，用过保日期作为expireDate）
    DateTime? warrantyExpireDate;
    String? expireDateSource;
    if (result.warrantyExpireDate != null && result.warrantyExpireDate!.isNotEmpty) {
      try {
        warrantyExpireDate = DateTime.parse(result.warrantyExpireDate!);
      } catch (_) {}
    }

    if (expireDate == null && warrantyExpireDate != null) {
      expireDate = warrantyExpireDate;
      expireDateSource = 'warranty';
    } else if (expireDate != null) {
      expireDateSource = 'expire';
    }

    // 保存物品
    await itemProvider.addItem(
      houseId: currentHouse.id,
      spaceId: spaceId,
      name: result.name.isNotEmpty ? result.name : '未知物品',
      quantity: result.quantity ?? 1,
      unit: result.unit ?? '件',
      price: result.price,
      category: categoryName,
      categoryId: categoryId,
      subcategoryId: subcategoryId,
      tags: null,
      imagePath: result.imagePath.isNotEmpty ? result.imagePath : null,
      note: result.description.isNotEmpty ? result.description : null,
      expireDate: expireDate,
      customAttributes: customAttributes.isNotEmpty ? customAttributes : null,
      expireDateSource: expireDateSource,
    );

    if (mounted) {
      // scaffoldMessenger.showSnackBar(
      //   const SnackBar(content: Text('物品添加成功')),
      // );

      // 清空识别结果，继续聊天
      setState(() {
        _extractedResult = null;
        _messages.add(_ChatMessage(
          text: '物品已录入成功！继续描述其他物品吧。',
          isUser: false,
        ));
      });
      _scrollToBottom();
    }
  }

  void _discardResult() {
    setState(() {
      _extractedResult = null;
    });
    _addAiMessage('已放弃本次录入。请继续描述其他物品，或点击右上角更换模型。');
    _scrollToBottom();
  }

  void _showModelPicker() {
    final aiProvider = context.read<AiProviderProvider>();
    final chatModels = aiProvider.chatModels;
    final currentModelId = aiProvider.defaultChatModelId;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  const Text('选择聊天模型', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (chatModels.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('暂无可用聊天模型，请先在"我的 → AI设置"中配置'),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.45),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: chatModels.length,
                  itemBuilder: (context, index) {
                    final model = chatModels[index];
                    final provider = aiProvider.getProvider(model.providerId);
                    final providerName = provider?.name.split('/').first ?? '';
                    final isSelected = model.id == currentModelId;
                    return ListTile(
                      leading: Icon(
                        isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey,
                      ),
                      title: Text(model.name),
                      subtitle: Text(providerName, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      selected: isSelected,
                      onTap: () {
                        aiProvider.setDefaultChatModelId(model.id);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aiProvider = context.watch<AiProviderProvider>();
    final currentModel = aiProvider.defaultChatModelId.isNotEmpty
        ? aiProvider.getModel(aiProvider.defaultChatModelId)
        : null;
    final providerName = currentModel != null
        ? aiProvider.getProvider(currentModel.providerId)?.name.split('/').first ?? ''
        : '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 聊天录入'),
        actions: [
          TextButton.icon(
            onPressed: _showModelPicker,
            icon: Icon(Icons.auto_awesome, size: 18, color: Theme.of(context).colorScheme.primary),
            label: Text(
              currentModel != null ? '$providerName / ${currentModel.name}' : '选择模型',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.primary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildChatList()),
          if (_extractedResult != null) _buildConfirmBar(),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildChatList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length + (_isProcessing ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length) {
          return _buildTypingIndicator();
        }
        final message = _messages[index];
        return _buildMessageBubble(message);
      },
    );
  }

  Widget _buildMessageBubble(_ChatMessage message) {
    if (message.isSystem) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message.text,
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
            ),
          ],
        ),
      );
    }

    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isUser ? const Radius.circular(16) : Radius.zero,
            bottomRight: isUser ? Radius.zero : const Radius.circular(16),
          ),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            fontSize: 14,
            color: isUser
                ? Theme.of(context).colorScheme.onPrimary
                : Theme.of(context).colorScheme.onSecondaryContainer,
          ),
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.onSecondaryContainer),
            ),
            const SizedBox(width: 8),
            Text(
              '正在分析...',
              style: TextStyle(color: Theme.of(context).colorScheme.onSecondaryContainer, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  '已识别物品信息，请选择操作',
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _confirmAndSave,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('确认'),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _navigateToForm,
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('修改'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextButton.icon(
                    onPressed: _discardResult,
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('放弃'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      foregroundColor: Colors.grey[600],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    final hasImage = _compressedImagePath != null;

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(top: BorderSide(color: Colors.grey[200]!)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 图片预览
            if (hasImage)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                height: 80,
                child: Stack(
                  alignment: Alignment.topRight,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(_compressedImagePath!),
                        height: 80,
                        width: 80,
                        fit: BoxFit.cover,
                      ),
                    ),
                    GestureDetector(
                      onTap: _removeImage,
                      child: Container(
                        margin: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                // 图片选择按钮
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: hasImage
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    onPressed: _isProcessing ? null : _showImageSourcePicker,
                    icon: Icon(
                      hasImage ? Icons.image : Icons.image_outlined,
                      size: 22,
                      color: hasImage
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(width: 8),
                // 文本输入框
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: InputDecoration(
                      hintText: hasImage ? '补充描述（可选）...' : '描述你的物品...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                // 发送按钮
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _isProcessing
                        ? Theme.of(context).disabledColor
                        : Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    onPressed: _isProcessing ? null : _sendMessage,
                    icon: Icon(Icons.send, size: 20, color: Theme.of(context).colorScheme.onPrimary),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatMessage {
  final String text;
  final bool isUser;
  final bool isSystem;

  _ChatMessage({
    required this.text,
    required this.isUser,
    this.isSystem = false,
  });
}
