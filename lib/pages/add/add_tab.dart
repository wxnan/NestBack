import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'item_form_page.dart';
import 'barcode_scanner_page.dart';
import 'ai_vision_scan_page.dart';
import 'ai_chat_page.dart';
import '../home_page.dart';
import '../../providers/settings_provider.dart';
import '../../providers/ai_provider.dart';

class AddTab extends StatefulWidget {
  const AddTab({super.key});

  @override
  State<AddTab> createState() => _AddTabState();
}

class _AddTabState extends State<AddTab> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _ensureDataLoaded();
  }

  Future<void> _ensureDataLoaded() async {
    await HomePage.initializeDataIfNeeded(context);
    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 40),
              const Text(
                '选择录入方式',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 40),
              Expanded(
                child: ListView(
                  children: [
                    _buildAIInputCard(
                      Icons.camera_alt,
                      'AI识图录入',
                      '拍照或从相册选图，AI自动识别物品信息',
                      const Color(0xFF9356DC),
                      () => _navigateToAiVision(context),
                    ),
                    const SizedBox(height: 16),
                    _buildAIInputCard(
                      Icons.message,
                      'AI聊天录入',
                      '用自然语言描述，AI帮你整理录入',
                      const Color(0xFF00B5D6),
                      () => _navigateToAiChat(context),
                    ),
                    const SizedBox(height: 16),
                    _buildInputCard(
                      Icons.qr_code_scanner,
                      '扫码录入',
                      '扫描商品条码，自动填充品名信息',
                      const Color(0xFFFF9F43),
                      () => _navigateToScanner(context),
                    ),
                    const SizedBox(height: 16),
                    _buildInputCard(
                      Icons.edit_note,
                      '手动录入',
                      '手动填写名称、分类、位置等信息',
                      const Color(0xFF00D68F),
                      () => _navigateToItemForm(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAIInputCard(
    IconData icon,
    String title,
    String description,
    Color gradientColor,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [gradientColor, gradientColor.withOpacity(0.8)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.all(Radius.circular(16)),
              ),
              child: Icon(icon, size: 32, color: gradientColor),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white),
          ],
        ),
      ),
    );
  }

  Widget _buildInputCard(
    IconData icon,
    String title,
    String description,
    Color iconColor,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey[200]!),
          color: Colors.white,
        ),
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: const BorderRadius.all(Radius.circular(16)),
              ),
              child: Icon(icon, size: 32, color: iconColor),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  void _navigateToItemForm(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ItemFormPage(),
      ),
    );
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
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ItemFormPage(barcodeResult: result),
        ),
      );
    }
  }

  void _navigateToAiVision(BuildContext context) {
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

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AiVisionScanPage(),
      ),
    );
  }

  void _navigateToAiChat(BuildContext context) {
    final aiProvider = context.read<AiProviderProvider>();
    if (aiProvider.defaultChatModelId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请先在"我的 → AI设置"中配置默认聊天模型'),
          action: SnackBarAction(
            label: '去设置',
            onPressed: () => Navigator.pushNamed(context, '/ai-settings'),
          ),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AiChatPage(),
      ),
    );
  }
}