import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ai_provider.dart';

class AiProviderEditPage extends StatefulWidget {
  const AiProviderEditPage({super.key});

  @override
  State<AiProviderEditPage> createState() => _AiProviderEditPageState();
}

class _AiProviderEditPageState extends State<AiProviderEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _apiBaseUrlController = TextEditingController();
  final _apiPathController = TextEditingController(text: '/chat/completions');
  final _apiKeyController = TextEditingController();
  bool _obscureApiKey = true;
  final _rateLimitController = TextEditingController();
  final _registerUrlController = TextEditingController();
  final _freeQuotaController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _apiBaseUrlController.dispose();
    _apiPathController.dispose();
    _apiKeyController.dispose();
    _rateLimitController.dispose();
    _registerUrlController.dispose();
    _freeQuotaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('添加自定义提供商'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '基本信息',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: '提供商名称',
                        hintText: '如：我的 OpenAI',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return '请输入提供商名称';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _apiBaseUrlController,
                      decoration: const InputDecoration(
                        labelText: 'API 地址',
                        hintText: '如：https://api.openai.com/v1',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return '请输入 API 地址';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _apiPathController,
                      decoration: const InputDecoration(
                        labelText: 'API 路径',
                        hintText: '/chat/completions',
                        border: OutlineInputBorder(),
                        helperText: '拼接到 API 地址后的路径',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _apiKeyController,
                      decoration: InputDecoration(
                        labelText: 'API Key',
                        hintText: '可选，稍后配置',
                        border: OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureApiKey ? Icons.visibility_off : Icons.visibility, size: 20),
                          onPressed: () => setState(() => _obscureApiKey = !_obscureApiKey),
                        ),
                      ),
                      obscureText: _obscureApiKey,
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
                    const Text(
                      '补充信息（可选）',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _rateLimitController,
                      decoration: const InputDecoration(
                        labelText: '速率限制',
                        hintText: '如：60 RPM',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _registerUrlController,
                      decoration: const InputDecoration(
                        labelText: '注册地址',
                        hintText: '如：https://example.com/register',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _freeQuotaController,
                      decoration: const InputDecoration(
                        labelText: '免费额度',
                        hintText: '如：每月 1000 次',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final aiProvider = context.read<AiProviderProvider>();
    aiProvider.addProvider(
      name: _nameController.text.trim(),
      apiBaseUrl: _apiBaseUrlController.text.trim(),
      apiPath: _apiPathController.text.trim().isEmpty ? '/chat/completions' : _apiPathController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      rateLimit: _rateLimitController.text.trim().isEmpty ? null : _rateLimitController.text.trim(),
      registerUrl: _registerUrlController.text.trim().isEmpty ? null : _registerUrlController.text.trim(),
      freeQuota: _freeQuotaController.text.trim().isEmpty ? null : _freeQuotaController.text.trim(),
    );

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('提供商已添加')),
    );
  }
}
