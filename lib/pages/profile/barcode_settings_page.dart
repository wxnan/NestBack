import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/settings_provider.dart';
import '../../services/barcode_service.dart';

class BarcodeSettingsPage extends StatefulWidget {
  const BarcodeSettingsPage({super.key});

  @override
  State<BarcodeSettingsPage> createState() => _BarcodeSettingsPageState();
}

class _BarcodeSettingsPageState extends State<BarcodeSettingsPage> {
  final _apiKeyController = TextEditingController();
  bool _obscureApiKey = true;
  bool _obscureAppSecret = true;
  final _rollapiAppIdController = TextEditingController();
  final _rollapiAppSecretController = TextEditingController();
  final _testBarcodeController = TextEditingController(text: '6921168509256');
  bool _isTesting = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    final provider = context.read<SettingsProvider>();
    final currentProvider = provider.barcodeApiProvider;
    if (currentProvider == 'rollapi') {
      _loadRollapiKeys(provider.getBarcodeApiKey('rollapi'));
    } else {
      _apiKeyController.text = provider.getBarcodeApiKey(currentProvider);
    }
  }

  void _loadRollapiKeys(String combinedKey) {
    if (combinedKey.contains(',')) {
      final parts = combinedKey.split(',');
      _rollapiAppIdController.text = parts[0].trim();
      _rollapiAppSecretController.text = parts[1].trim();
    }
  }

  String _getRollapiCombinedKey() {
    return '${_rollapiAppIdController.text.trim()},${_rollapiAppSecretController.text.trim()}';
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _rollapiAppIdController.dispose();
    _rollapiAppSecretController.dispose();
    _testBarcodeController.dispose();
    super.dispose();
  }

  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _testApi(SettingsProvider settingsProvider) async {
    final barcode = _testBarcodeController.text.trim();
    if (barcode.isEmpty) {
      setState(() => _testResult = '请输入测试条码');
      return;
    }

    final currentProvider = settingsProvider.barcodeApiProvider;
    final currentKey = currentProvider == 'rollapi'
        ? _getRollapiCombinedKey()
        : _apiKeyController.text.trim();

    if (currentProvider == 'apibyte' && currentKey.isEmpty) {
      setState(() => _testResult = 'apibyte 需要 API Key');
      return;
    }

    if (currentProvider == 'rollapi') {
      if (_rollapiAppIdController.text.trim().isEmpty ||
          _rollapiAppSecretController.text.trim().isEmpty) {
        setState(() => _testResult = 'rollapi 需要 App ID 和 App Secret');
        return;
      }
    }

    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    try {
      final result = await BarcodeService.queryBarcode(
        provider: currentProvider,
        apiKey: currentKey,
        barcode: barcode,
      );

      if (mounted) {
        setState(() {
          _isTesting = false;
          if (result.found) {
            _testResult = '查询成功：${result.name ?? '未知商品'}';
          } else {
            _testResult = '查询完成，未找到该商品';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTesting = false;
          _testResult = '查询失败：$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('扫码设置'),
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settingsProvider, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildProviderSelector(settingsProvider),
              const SizedBox(height: 16),
              _buildProviderInfoCard(settingsProvider),
              const SizedBox(height: 16),
              _buildApiKeyCard(settingsProvider),
              const SizedBox(height: 16),
              _buildTestCard(settingsProvider),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProviderSelector(SettingsProvider settingsProvider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'API 提供商',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: settingsProvider.barcodeApiProvider,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'apizero',
                  child: Text('apizero'),
                ),
                DropdownMenuItem(
                  value: 'apizero-pro',
                  child: Text('apizero-pro'),
                ),
                DropdownMenuItem(
                  value: 'apibyte',
                  child: Text('apibyte'),
                ),
                DropdownMenuItem(
                  value: 'rollapi',
                  child: Text('rollapi'),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                _saveCurrentKey(settingsProvider);
                settingsProvider.setBarcodeApiProvider(value);
                _loadProviderKey(settingsProvider, value);
                setState(() => _testResult = null);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _saveCurrentKey(SettingsProvider settingsProvider) {
    final currentProvider = settingsProvider.barcodeApiProvider;
    if (currentProvider == 'rollapi') {
      settingsProvider.setBarcodeApiKey(currentProvider, _getRollapiCombinedKey());
    } else {
      settingsProvider.setBarcodeApiKey(currentProvider, _apiKeyController.text.trim());
    }
  }

  void _loadProviderKey(SettingsProvider settingsProvider, String provider) {
    final key = settingsProvider.getBarcodeApiKey(provider);
    if (provider == 'rollapi') {
      _apiKeyController.clear();
      _loadRollapiKeys(key);
    } else {
      _apiKeyController.text = key;
      _rollapiAppIdController.clear();
      _rollapiAppSecretController.clear();
    }
  }

  Widget _buildProviderInfoCard(SettingsProvider settingsProvider) {
    final provider = settingsProvider.barcodeApiProvider;
    final providerInfo = _getProviderInfo(provider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '${providerInfo['name']} 详情',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoRow('接口地址', providerInfo['url']!),
            const SizedBox(height: 8),
            _buildInfoRow('免费额度', providerInfo['quota']!),
            const SizedBox(height: 8),
            _buildInfoRow('API Key', providerInfo['keyRequired']!),
            const SizedBox(height: 8),
            _buildInfoRow('数据源', providerInfo['source']!),
            const SizedBox(height: 8),
            _buildInfoRow('支持条码', providerInfo['barcode']!),
            const SizedBox(height: 12),
            _buildApplyUrlRow(provider),
          ],
        ),
      ),
    );
  }

  Widget _buildApplyUrlRow(String provider) {
    final applyUrl = _getApplyUrl(provider);
    if (applyUrl == null) return const SizedBox.shrink();

    return InkWell(
      onTap: () => _launchUrl(applyUrl),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.open_in_new,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '前往申请 API Key',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 14,
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }

  String? _getApplyUrl(String provider) {
    switch (provider) {
      case 'apizero':
        return 'https://apizero.cn/marketplace/barcode-lookup';
      case 'apizero-pro':
        return 'https://apizero.cn/marketplace/barcode-gs1';
      case 'apibyte':
        return 'https://apibyte.cn/marketplace/barcode';
      case 'rollapi':
        return 'https://www.mxnzp.com?ic=WTBYLO';
      default:
        return null;
    }
  }

  Map<String, String> _getProviderInfo(String provider) {
    switch (provider) {
      case 'apizero':
        return {
          'name': 'apizero',
          'url': 'https://v1.apizero.cn/api/barcode-lookup',
          'quota': '无 Key：每日 20 次 · QPS 1\n有 Key：每日 200 次 · QPS 2',
          'keyRequired': '可选（无 Key 也可使用）',
          'source': '聚合数据源，覆盖国内日常消费品',
          'barcode': 'EAN-13、UPC-A、EAN-8、UPC-E',
        };
      case 'apizero-pro':
        return {
          'name': 'apizero-pro',
          'url': 'https://v1.apizero.cn/api/barcode-gs1',
          'quota': '每日 20 次 · QPS 2（匿名/登录相同）',
          'keyRequired': '可选（无 Key 也可使用）',
          'source': 'GS1 中国官方数据库，权威可追溯',
          'barcode': 'EAN-13、GTIN-14、EAN-8 等',
        };
      case 'apibyte':
        return {
          'name': 'apibyte',
          'url': 'https://apione.apibyte.cn/api/barcode',
          'quota': '需 Key：每日 100 次 · QPS 5',
          'keyRequired': '必填',
          'source': '聚合数据源',
          'barcode': 'EAN-13、UPC-A、EAN-8、UPC-E',
        };
      case 'rollapi':
        return {
          'name': 'rollapi',
          'url': 'https://www.mxnzp.com/api/barcode/goods/details',
          'quota': '需 Key：每日 1000 次 · QPS 1',
          'keyRequired': '必填（App ID + App Secret）',
          'source': '聚合数据源',
          'barcode': 'EAN-13、EAN-8、UPC-A 等',
        };
      default:
        return {
          'name': 'apizero',
          'url': 'https://v1.apizero.cn/api/barcode-lookup',
          'quota': '无 Key：每日 20 次 · QPS 1\n有 Key：每日 200 次 · QPS 2',
          'keyRequired': '可选（无 Key 也可使用）',
          'source': '聚合数据源，覆盖国内日常消费品',
          'barcode': 'EAN-13、UPC-A、EAN-8、UPC-E',
        };
    }
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildApiKeyCard(SettingsProvider settingsProvider) {
    final provider = settingsProvider.barcodeApiProvider;
    final isKeyRequired = provider == 'apibyte' || provider == 'rollapi';

    if (provider == 'rollapi') {
      return _buildRollapiKeyCard(settingsProvider);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.key,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Text(
                  'API Key',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                if (isKeyRequired) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '必填',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _apiKeyController,
              obscureText: _obscureApiKey,
              decoration: InputDecoration(
                hintText: isKeyRequired ? '输入 API Key' : '输入 API Key（可选，不填则按 IP 限制）',
                border: const OutlineInputBorder(),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(_obscureApiKey ? Icons.visibility_off : Icons.visibility, size: 20),
                      onPressed: () => setState(() => _obscureApiKey = !_obscureApiKey),
                    ),
                    if (_apiKeyController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _apiKeyController.clear();
                          settingsProvider.setBarcodeApiKey(settingsProvider.barcodeApiProvider, '');
                          setState(() {});
                        },
                      ),
                  ],
                ),
              ),
              onChanged: (value) {
                settingsProvider.setBarcodeApiKey(settingsProvider.barcodeApiProvider, value);
                setState(() {});
              },
            ),
            if (!isKeyRequired) ...[
              const SizedBox(height: 8),
              Text(
                provider == 'apizero'
                    ? '未填写 Key 时每日可查询 20 次；填写 Key 后每日可查询 200 次'
                    : '未填写 Key 时每日可查询 20 次',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRollapiKeyCard(SettingsProvider settingsProvider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.key,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Text(
                  'API 凭证',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '必填',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _rollapiAppIdController,
              decoration: InputDecoration(
                hintText: '输入 App ID',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.badge, size: 20),
                suffixIcon: _rollapiAppIdController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _rollapiAppIdController.clear();
                          settingsProvider.setBarcodeApiKey('rollapi', _getRollapiCombinedKey());
                          setState(() {});
                        },
                      )
                    : null,
              ),
              onChanged: (value) {
                settingsProvider.setBarcodeApiKey('rollapi', _getRollapiCombinedKey());
                setState(() {});
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _rollapiAppSecretController,
              obscureText: _obscureAppSecret,
              decoration: InputDecoration(
                hintText: '输入 App Secret',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lock, size: 20),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(_obscureAppSecret ? Icons.visibility_off : Icons.visibility, size: 20),
                      onPressed: () => setState(() => _obscureAppSecret = !_obscureAppSecret),
                    ),
                    if (_rollapiAppSecretController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _rollapiAppSecretController.clear();
                          settingsProvider.setBarcodeApiKey('rollapi', _getRollapiCombinedKey());
                          setState(() {});
                        },
                      ),
                  ],
                ),
              ),
              onChanged: (value) {
                settingsProvider.setBarcodeApiKey('rollapi', _getRollapiCombinedKey());
                setState(() {});
              },
            ),
            const SizedBox(height: 8),
            Text(
              '注册后可在控制台获取 App ID 和 App Secret',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTestCard(SettingsProvider settingsProvider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.science,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Text(
                  '连通性测试',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _testBarcodeController,
              decoration: const InputDecoration(
                hintText: '输入测试条码（8~13位数字）',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isTesting ? null : () => _testApi(settingsProvider),
                icon: _isTesting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(_isTesting ? '测试中...' : '测试查询'),
              ),
            ),
            if (_testResult != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _testResult!.startsWith('查询成功')
                      ? Colors.green.withValues(alpha: 0.1)
                      : _testResult!.startsWith('查询完成')
                          ? Colors.orange.withValues(alpha: 0.1)
                          : Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      _testResult!.startsWith('查询成功')
                          ? Icons.check_circle
                          : _testResult!.startsWith('查询完成')
                              ? Icons.info
                              : Icons.error,
                      size: 20,
                      color: _testResult!.startsWith('查询成功')
                          ? Colors.green
                          : _testResult!.startsWith('查询完成')
                              ? Colors.orange
                              : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _testResult!,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
