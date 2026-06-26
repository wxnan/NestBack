import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../database/database.dart';

class AiProviderProvider extends ChangeNotifier {
  final AppDatabase _db;
  static const _uuid = Uuid();

  static const String _keyDefaultChatModelId = 'default_chat_model_id';
  static const String _keyDefaultVisionModelId = 'default_vision_model_id';

  List<AiProvider> _providers = [];
  List<AiModel> _models = [];
  String _defaultChatModelId = '';
  String _defaultVisionModelId = '';

  List<AiProvider> get providers => _providers;
  List<AiModel> get models => _models;
  String get defaultChatModelId => _defaultChatModelId;
  String get defaultVisionModelId => _defaultVisionModelId;

  List<AiModel> get enabledModels {
    final enabled = _models.where((m) {
      if (!m.isEnabled) return false;
      final provider = getProvider(m.providerId);
      return provider != null && provider.isEnabled && getEffectiveApiKey(provider).isNotEmpty;
    }).toList();
    // 按提供商顺序排序，同一提供商内按模型sortOrder排序
    final providerOrder = {for (var i = 0; i < _providers.length; i++) _providers[i].id: i};
    enabled.sort((a, b) {
      final orderA = providerOrder[a.providerId] ?? 999999;
      final orderB = providerOrder[b.providerId] ?? 999999;
      if (orderA != orderB) return orderA.compareTo(orderB);
      return a.sortOrder.compareTo(b.sortOrder);
    });
    return enabled;
  }
  List<AiModel> get chatModels => enabledModels;
  List<AiModel> get visionModels => enabledModels.where((m) => m.type == 'vision').toList();

  AiProviderProvider(this._db);

  /// 获取有效的 API Key：用户填写的优先，否则使用内置 Key
  String getEffectiveApiKey(AiProvider provider) {
    if (provider.apiKey.isNotEmpty) return provider.apiKey;
    return provider.builtInApiKey;
  }

  /// 提供商是否有内置 API Key
  bool hasBuiltInApiKey(AiProvider provider) {
    return provider.builtInApiKey.isNotEmpty;
  }

  Future<void> init() async {
    await _loadProviders();
    await _loadModels();
    await _loadDefaultModelSettings();
    if (_providers.isEmpty) {
      await _seedDefaultProviders();
      await _loadProviders();
      await _loadModels();
      // 首次启动：设置默认模型为 MiniCPM-V-4.6-Instruct
      await _setDefaultModelsIfFirstLaunch();
    } else {
      // 升级场景：补充缺失的种子数据（如新增的提供商/模型）
      await _seedMissingProviders();
      // 升级场景：更新内置提供商的 API 地址、内置密钥等配置
      await _updateBuiltInProviderConfigs();
    }
    notifyListeners();
  }

  /// 补充缺失的种子数据（用于 APP 升级后新增提供商的场景）
  Future<void> _seedMissingProviders() async {
    final existingNames = _providers.map((p) => p.name).toSet();
    final now = DateTime.now();
    final models = _defaultModelsData;
    final providers = _defaultProvidersData;
    bool hasNew = false;

    for (int i = 0; i < providers.length; i++) {
      final p = providers[i];
      if (existingNames.contains(p['name'] as String)) continue;

      final providerId = _uuid.v4();
      await _db.into(_db.aiProviders).insert(AiProvidersCompanion.insert(
            id: providerId,
            name: p['name'] as String,
            apiBaseUrl: p['apiBaseUrl'] as String,
            isBuiltIn: const Value(true),
            isEnabled: Value(p['isEnabledByDefault'] as bool? ?? false),
            builtInApiKey: Value(p['builtInApiKey'] as String? ?? ''),
            customHeaders: Value(p['customHeaders'] as String? ?? '{}'),
            rateLimit: Value(p['rateLimit'] as String?),
            registerUrl: Value(p['registerUrl'] as String?),
            freeQuota: Value(p['freeQuota'] as String?),
            sortOrder: Value(_providers.length + i),
            createdAt: now,
            updatedAt: now,
          ));

      final providerModels = models[p['key']] as List<Map<String, String>>;
      for (final m in providerModels) {
        await _db.into(_db.aiModels).insert(AiModelsCompanion.insert(
              id: _uuid.v4(),
              providerId: providerId,
              modelId: (m['modelId'] ?? m['name']) as String,
              name: m['name'] as String,
              type: Value(m['type'] ?? 'chat'),
              isBuiltIn: const Value(true),
              isEnabled: const Value(true),
              createdAt: now,
              updatedAt: now,
            ));
      }
      hasNew = true;
    }

    if (hasNew) {
      await _loadProviders();
      await _loadModels();
      // 如果默认模型未设置，尝试设置
      await _setDefaultModelsIfFirstLaunch();
    }
  }

  /// APP 升级后更新内置提供商的配置（API 地址、内置密钥等）
  Future<void> _updateBuiltInProviderConfigs() async {
    final now = DateTime.now();
    bool hasUpdate = false;

    for (final p in _defaultProvidersData) {
      final name = p['name'] as String;
      AiProvider? existing;
      try {
        existing = _providers.firstWhere((provider) => provider.name == name && provider.isBuiltIn);
      } catch (_) {
        existing = null;
      }
      if (existing == null) continue;

      final newApiBaseUrl = p['apiBaseUrl'] as String;
      final newBuiltInApiKey = (p['builtInApiKey'] as String?) ?? '';

      if (existing.apiBaseUrl != newApiBaseUrl || existing.builtInApiKey != newBuiltInApiKey) {
        await (_db.update(_db.aiProviders)..where((t) => t.id.equals(existing!.id))).write(
          AiProvidersCompanion(
            apiBaseUrl: Value(newApiBaseUrl),
            builtInApiKey: Value(newBuiltInApiKey),
            updatedAt: Value(now),
          ),
        );
        hasUpdate = true;
      }
    }

    if (hasUpdate) {
      await _loadProviders();
    }
  }

  Future<void> _setDefaultModelsIfFirstLaunch() async {
    // 找到面壁智能的 MiniCPM-V-4.6-Instruct 模型
    final targetModel = _models.firstWhere(
      (m) => m.modelId == 'MiniCPM-V-4.6-Instruct' || m.name == 'MiniCPM-V-4.6-Instruct',
      orElse: () => _models.isNotEmpty ? _models.first : AiModel(
        id: '',
        providerId: '',
        modelId: '',
        name: '',
        type: 'chat',
        isBuiltIn: true,
        isEnabled: true,
        sortOrder: 0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    if (targetModel.id.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      if (_defaultChatModelId.isEmpty) {
        _defaultChatModelId = targetModel.id;
        await prefs.setString(_keyDefaultChatModelId, targetModel.id);
      }
      if (_defaultVisionModelId.isEmpty) {
        _defaultVisionModelId = targetModel.id;
        await prefs.setString(_keyDefaultVisionModelId, targetModel.id);
      }
    }
  }

  Future<void> _loadProviders() async {
    _providers = await (_db.select(_db.aiProviders)
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
  }

  Future<void> _loadModels() async {
    _models = await _db.select(_db.aiModels).get();
  }

  Future<void> _loadDefaultModelSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _defaultChatModelId = prefs.getString(_keyDefaultChatModelId) ?? '';
    _defaultVisionModelId = prefs.getString(_keyDefaultVisionModelId) ?? '';
  }

  AiProvider? getProvider(String id) {
    try {
      return _providers.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  List<AiModel> getModelsForProvider(String providerId) {
    return _models.where((m) => m.providerId == providerId).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  AiModel? getModel(String id) {
    try {
      return _models.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }

  AiModel? get defaultChatModel => getModel(_defaultChatModelId);
  AiModel? get defaultVisionModel => getModel(_defaultVisionModelId);

  bool get isAiConfigured {
    return _defaultChatModelId.isNotEmpty && getModel(_defaultChatModelId) != null;
  }

  Future<void> setDefaultChatModelId(String modelId) async {
    _defaultChatModelId = modelId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDefaultChatModelId, modelId);
    notifyListeners();
  }

  Future<void> setDefaultVisionModelId(String modelId) async {
    _defaultVisionModelId = modelId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDefaultVisionModelId, modelId);
    notifyListeners();
  }

  Future<void> addProvider({
    required String name,
    required String apiBaseUrl,
    String apiPath = '/chat/completions',
    String apiKey = '',
    String? rateLimit,
    String? registerUrl,
    String? freeQuota,
  }) async {
    final now = DateTime.now();
    final maxSort = _providers.fold<int>(0, (max, p) => p.sortOrder > max ? p.sortOrder : max);
    await _db.into(_db.aiProviders).insert(AiProvidersCompanion.insert(
          id: _uuid.v4(),
          name: name,
          apiBaseUrl: apiBaseUrl,
          apiPath: Value(apiPath),
          apiKey: Value(apiKey),
          rateLimit: Value(rateLimit),
          registerUrl: Value(registerUrl),
          freeQuota: Value(freeQuota),
          sortOrder: Value(maxSort + 1),
          createdAt: now,
          updatedAt: now,
        ));
    await _loadProviders();
    notifyListeners();
  }

  Future<void> updateProvider(AiProvider provider) async {
    await (_db.update(_db.aiProviders)).replace(provider);
    await _loadProviders();
    notifyListeners();
  }

  Future<void> reorderProviders(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) newIndex -= 1;
    final list = List<AiProvider>.from(_providers);
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    for (var i = 0; i < list.length; i++) {
      await (_db.update(_db.aiProviders)).replace(list[i].copyWith(sortOrder: i, updatedAt: DateTime.now()));
    }
    await _loadProviders();
    notifyListeners();
  }

  Future<void> deleteProvider(String providerId) async {
    final provider = getProvider(providerId);
    if (provider != null && provider.isBuiltIn) return;

    // 删除该提供商下的所有模型
    await (_db.delete(_db.aiModels)
          ..where((t) => t.providerId.equals(providerId)))
        .go();
    await (_db.delete(_db.aiProviders)
          ..where((t) => t.id.equals(providerId)))
        .go();

    // 清理默认模型引用
    if (_defaultChatModelId.isNotEmpty) {
      final chatModel = getModel(_defaultChatModelId);
      if (chatModel != null && chatModel.providerId == providerId) {
        await setDefaultChatModelId('');
      }
    }
    if (_defaultVisionModelId.isNotEmpty) {
      final visionModel = getModel(_defaultVisionModelId);
      if (visionModel != null && visionModel.providerId == providerId) {
        await setDefaultVisionModelId('');
      }
    }

    await _loadProviders();
    await _loadModels();
    notifyListeners();
  }

  Future<void> toggleProviderEnabled(String providerId, bool enabled) async {
    final provider = getProvider(providerId);
    if (provider == null) return;
    await updateProvider(provider.copyWith(isEnabled: enabled, updatedAt: DateTime.now()));
  }

  Future<void> updateProviderApiKey(String providerId, String apiKey) async {
    final provider = getProvider(providerId);
    if (provider == null) return;
    // 填写 API Key 时自动启用，清空时：如果有内置 Key 则保持启用，否则禁用
    final shouldEnable = apiKey.isNotEmpty || provider.builtInApiKey.isNotEmpty;
    await updateProvider(provider.copyWith(
      apiKey: apiKey,
      isEnabled: shouldEnable,
      updatedAt: DateTime.now(),
    ));

    // 如果禁用了提供商，清理该提供商下模型的默认引用
    if (!shouldEnable) {
      if (_defaultChatModelId.isNotEmpty) {
        final chatModel = getModel(_defaultChatModelId);
        if (chatModel != null && chatModel.providerId == providerId) {
          await setDefaultChatModelId('');
        }
      }
      if (_defaultVisionModelId.isNotEmpty) {
        final visionModel = getModel(_defaultVisionModelId);
        if (visionModel != null && visionModel.providerId == providerId) {
          await setDefaultVisionModelId('');
        }
      }
    }
  }

  Future<void> addModel({
    required String providerId,
    required String modelId,
    required String name,
    String type = 'chat',
  }) async {
    final now = DateTime.now();
    await _db.into(_db.aiModels).insert(AiModelsCompanion.insert(
          id: _uuid.v4(),
          providerId: providerId,
          modelId: modelId,
          name: name,
          type: Value(type),
          createdAt: now,
          updatedAt: now,
        ));
    await _loadModels();
    notifyListeners();
  }

  Future<void> updateModel(AiModel model) async {
    await (_db.update(_db.aiModels)).replace(model);
    await _loadModels();
    notifyListeners();
  }

  Future<void> reorderModels(String providerId, int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) newIndex -= 1;
    final list = List<AiModel>.from(getModelsForProvider(providerId));
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    for (var i = 0; i < list.length; i++) {
      await (_db.update(_db.aiModels)).replace(list[i].copyWith(sortOrder: i, updatedAt: DateTime.now()));
    }
    await _loadModels();
    notifyListeners();
  }

  Future<void> deleteModel(String modelId) async {
    await (_db.delete(_db.aiModels)
          ..where((t) => t.id.equals(modelId)))
        .go();

    if (_defaultChatModelId == modelId) {
      await setDefaultChatModelId('');
    }
    if (_defaultVisionModelId == modelId) {
      await setDefaultVisionModelId('');
    }

    await _loadModels();
    notifyListeners();
  }

  Future<void> toggleModelEnabled(String modelId, bool enabled) async {
    final model = getModel(modelId);
    if (model == null) return;
    await updateModel(model.copyWith(isEnabled: enabled, updatedAt: DateTime.now()));

    if (!enabled) {
      if (_defaultChatModelId == modelId) {
        await setDefaultChatModelId('');
      }
      if (_defaultVisionModelId == modelId) {
        await setDefaultVisionModelId('');
      }
    }
  }

  Future<void> _seedDefaultProviders() async {
    final now = DateTime.now();
    final providers = _defaultProvidersData;
    final models = _defaultModelsData;

    for (int i = 0; i < providers.length; i++) {
      final p = providers[i];
      final providerId = _uuid.v4();
      await _db.into(_db.aiProviders).insert(AiProvidersCompanion.insert(
            id: providerId,
            name: p['name'] as String,
            apiBaseUrl: p['apiBaseUrl'] as String,
            isBuiltIn: const Value(true),
            isEnabled: Value(p['isEnabledByDefault'] as bool? ?? false),
            builtInApiKey: Value(p['builtInApiKey'] as String? ?? ''),
            customHeaders: Value(p['customHeaders'] as String? ?? '{}'),
            rateLimit: Value(p['rateLimit'] as String?),
            registerUrl: Value(p['registerUrl'] as String?),
            freeQuota: Value(p['freeQuota'] as String?),
            sortOrder: Value(i),
            createdAt: now,
            updatedAt: now,
          ));

      final providerModels = models[p['key']] as List<Map<String, String>>;
      for (final m in providerModels) {
        await _db.into(_db.aiModels).insert(AiModelsCompanion.insert(
              id: _uuid.v4(),
              providerId: providerId,
              modelId: (m['modelId'] ?? m['name']) as String,
              name: m['name'] as String,
              type: Value(m['type'] ?? 'chat'),
              isBuiltIn: const Value(true),
              isEnabled: const Value(true),
              createdAt: now,
              updatedAt: now,
            ));
      }
    }
  }

  static const _defaultProvidersData = [
    {
      'key': 'siliconflow',
      'name': '硅基流动 / SiliconFlow',
      'apiBaseUrl': 'https://api.siliconflow.cn/v1',
      'rateLimit': '1000 RPM (each model)',
      'registerUrl': 'https://cloud.siliconflow.cn/i/QKaurfVC',
      'freeQuota': '部分 9B 以下模型永久免费',
    },
    {
      'key': 'bigmodel',
      'name': '智谱AI / Bigmodel',
      'apiBaseUrl': 'https://open.bigmodel.cn/api/paas/v4',
      'rateLimit': '只有并发数限制（1~20）',
      'registerUrl': 'https://www.bigmodel.cn/invite?icode=RROS7WdhUeyLGNlc98yHd33uFJ1nZ0jLLgipQkYjpcA%3D',
      'freeQuota': '部分 Flash 模型永久免费',
    },
    {
      'key': 'modelscope',
      'name': '魔搭社区 / ModelScope',
      'apiBaseUrl': 'https://api-inference.modelscope.cn/v1',
      'rateLimit': '2000次/天，每个模型≤500次/天',
      'registerUrl': 'https://www.modelscope.cn/register?inviteCode=dawnan&invitorName=dawnan',
      'freeQuota': null,
    },
    {
      'key': 'aihubmix',
      'name': 'AIHubMix',
      'apiBaseUrl': 'https://aihubmix.com/v1',
      'rateLimit': '5 RPM / 500 RPD',
      'registerUrl': 'https://aihubmix.com/?aff=702v',
      'freeQuota': '带有 free 标签的模型可以免费调用，使用 APP-Code 可优惠10%',
      'customHeaders': '{"APP-Code":"KHYF5028"}',
    },
    {
      'key': 'nvidia',
      'name': 'NVIDIA NIM',
      'apiBaseUrl': 'https://integrate.api.nvidia.com/v1',
      'rateLimit': '40 RPM',
      'registerUrl': 'https://build.nvidia.com/models',
      'freeQuota': null,
    },
    {
      'key': 'openrouter',
      'name': 'OpenRouter',
      'apiBaseUrl': 'https://openrouter.ai/api/v1',
      'rateLimit': '20 RPM / 50 RPD',
      'registerUrl': 'https://openrouter.ai',
      'freeQuota': '带有 free 标签的模型可以免费调用',
    },
    {
      'key': 'openbmb',
      'name': '面壁智能 / OpenBMB',
      'apiBaseUrl': 'https://api.modelbest.co/v1',
      'rateLimit': '未知',
      'registerUrl': 'https://github.com/OpenBMB',
      'freeQuota': '官方公开免费的 API 密钥',
      'builtInApiKey': 'lis_sk_298cf78155f231c7_DkrDcNLHnK8dJRnfFrJCd4JGDbBLMkHrC3T-wLpvC9zy0BPemsyFuQ',
      'isEnabledByDefault': true,
    },
  ];

  static const _defaultModelsData = {
    'siliconflow': [
      {'name': 'deepseek-ai/DeepSeek-R1-0528-Qwen3-8B', 'type': 'chat'},
      {'name': 'Qwen/Qwen3-8B', 'type': 'chat'},
      {'name': 'Qwen/Qwen3.5-4B', 'type': 'vision'},
      {'name': 'THUDM/GLM-4-9B-0414', 'type': 'chat'},
      {'name': 'THUDM/GLM-Z1-9B-0414', 'type': 'chat'},
    ],
    'bigmodel': [
      {'name': 'GLM-4-Flash', 'type': 'chat'},
      {'name': 'GLM-4-Flash-250414', 'type': 'chat'},
      {'name': 'GLM-4V-Flash', 'type': 'vision'},
      {'name': 'GLM-4.1V-Thinking-Flash', 'type': 'vision'},
      {'name': 'GLM-4.6V-Flash', 'type': 'vision'},
      {'name': 'GLM-4.7-Flash', 'type': 'chat'},
    ],
    'modelscope': [
      {'name': 'deepseek-ai/DeepSeek-V4-Pro', 'type': 'chat'},
      {'name': 'deepseek-ai/DeepSeek-V4-Flash', 'type': 'chat'},
      {'name': 'ZhipuAI/GLM-5.1', 'type': 'chat'},
      {'name': 'ZhipuAI/GLM-5', 'type': 'chat'},
      {'name': 'moonshotai/Kimi-K2.6', 'type': 'vision'},
      {'name': 'moonshotai/Kimi-K2.5', 'type': 'vision'},
      {'name': 'MiniMax/MiniMax-M2.7', 'type': 'chat'},
      {'name': 'MiniMax/MiniMax-M2.5', 'type': 'chat'},
      {'name': 'Qwen/Qwen3.5-397B-A17B', 'type': 'vision'},
      {'name': 'Qwen/Qwen3.5-35B-A3B', 'type': 'vision'},
    ],
    'aihubmix': [
      {'name': 'gpt-5.5-free', 'type': 'vision'},
      {'name': 'gpt-4o-free', 'type': 'vision'},
      {'name': 'gemini-3-flash-preview-free', 'type': 'vision'},
      {'name': 'coding-glm-5.1-free', 'type': 'chat'},
      {'name': 'coding-glm-5-free', 'type': 'chat'},
      {'name': 'xiaomi-mimo-v2.5-pro-free', 'type': 'vision'},
      {'name': 'k2.6-code-preview-free', 'type': 'chat'},
      {'name': 'step-3.7-flash-free', 'type': 'vision'},
      {'name': 'coding-minimax-m3-free', 'type': 'chat'},
    ],
    'nvidia': [
      {'name': 'deepseek-ai/deepseek-v4-pro', 'type': 'chat'},
      {'name': 'deepseek-ai/deepseek-v4-flash', 'type': 'chat'},
      {'name': 'z-ai/glm-5.1', 'type': 'chat'},
      {'name': 'moonshotai/kimi-k2.6', 'type': 'vision'},
      {'name': 'minimaxai/minimax-m2.7', 'type': 'chat'},
      {'name': 'stepfun-ai/step-3.7-flash', 'type': 'vision'},
      {'name': 'qwen/qwen3.5-397b-a17b', 'type': 'vision'},
      {'name': 'qwen/qwen3.5-122b-a10b', 'type': 'vision'},
      {'name': 'google/gemma-4-31b-it', 'type': 'vision'},
      {'name': 'openai/gpt-oss-120b', 'type': 'chat'},
    ],
    'openrouter': [
      {'name': 'openrouter/free', 'type': 'chat'},
      {'name': 'deepseek/deepseek-v4-flash:free', 'type': 'chat'},
      {'name': 'moonshotai/kimi-k2.6:free', 'type': 'vision'},
      {'name': 'minimax/minimax-m2.5:free', 'type': 'chat'},
      {'name': 'google/gemma-4-31b-it:free', 'type': 'vision'},
      {'name': 'openai/gpt-oss-120b:free', 'type': 'chat'},
    ],
    'openbmb': [
      {'name': 'MiniCPM-V-4.6-Instruct', 'type': 'vision'},
      {'name': 'MiniCPM-V-4.6-Thinking', 'type': 'vision'},
      {'name': 'MiniCPM-o-4.5', 'type': 'vision'},
    ],
  };

  /// 从提供商 API 获取可用模型列表，返回模型 ID 列表
  Future<List<String>> fetchAvailableModels(String providerId) async {
    final provider = getProvider(providerId);
    if (provider == null) throw Exception('提供商不存在');
    final effectiveApiKey = getEffectiveApiKey(provider);
    if (effectiveApiKey.isEmpty) throw Exception('请先填写 API Key');

    final baseUrl = provider.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final url = Uri.parse('$baseUrl/models');

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $effectiveApiKey',
    };

    // 添加自定义 Headers
    if (provider.customHeaders.isNotEmpty && provider.customHeaders != '{}') {
      try {
        final custom = jsonDecode(provider.customHeaders) as Map<String, dynamic>;
        custom.forEach((k, v) => headers[k] = v.toString());
      } catch (_) {}
    }

    final response = await http.get(url, headers: headers).timeout(const Duration(seconds: 30));

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
    final dataList = responseBody['data'] as List<dynamic>;
    return dataList.map((item) => item['id'] as String).toList();
  }

  /// 测试提供商连接，返回 (success, message)
  Future<(bool, String)> testConnection(String providerId, String modelId) async {
    final provider = getProvider(providerId);
    if (provider == null) return (false, '提供商不存在');
    final effectiveApiKey = getEffectiveApiKey(provider);
    if (effectiveApiKey.isEmpty) return (false, '请先填写 API Key');

    try {
      final baseUrl = provider.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
      final path = provider.apiPath.startsWith('/') ? provider.apiPath : '/${provider.apiPath}';
      final url = Uri.parse('$baseUrl$path');

      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $effectiveApiKey',
      };

      // 添加自定义 Headers
      if (provider.customHeaders.isNotEmpty && provider.customHeaders != '{}') {
        try {
          final custom = jsonDecode(provider.customHeaders) as Map<String, dynamic>;
          custom.forEach((k, v) => headers[k] = v.toString());
        } catch (_) {}
      }

      final body = jsonEncode({
        'model': modelId,
        'messages': [
          {'role': 'user', 'content': 'Hi'}
        ],
        'max_tokens': 5,
      });

      final response = await http.post(url, headers: headers, body: body).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return (true, '连接成功');
      } else {
        String errorMsg = 'HTTP ${response.statusCode}';
        try {
          final errorBody = jsonDecode(response.body) as Map<String, dynamic>;
          final msg = errorBody['error']?['message'] ?? errorBody['message'] ?? '';
          if (msg.isNotEmpty) errorMsg = msg;
        } catch (_) {}
        return (false, errorMsg);
      }
    } catch (e) {
      return (false, '连接失败：$e');
    }
  }
}
