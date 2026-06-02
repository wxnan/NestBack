import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/barcode_service.dart';

class BarcodeScannerPage extends StatefulWidget {
  const BarcodeScannerPage({super.key});

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage> with WidgetsBindingObserver {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    formats: [BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.upcA, BarcodeFormat.upcE],
  );
  bool _isProcessing = false;
  bool _hasScanned = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_controller.value.hasCameraPermission) return;
    switch (state) {
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _controller.stop();
        break;
      case AppLifecycleState.resumed:
        _controller.start();
        break;
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _onBarcodeDetected(BarcodeCapture capture) {
    if (_isProcessing || _hasScanned) return;

    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    _hasScanned = true;
    _controller.stop();

    _handleBarcode(barcode.rawValue!);
  }

  Future<void> _handleBarcode(String barcode) async {
    setState(() => _isProcessing = true);

    final settingsProvider = context.read<SettingsProvider>();

    if (!settingsProvider.isBarcodeConfigured) {
      if (mounted) {
        setState(() => _isProcessing = false);
        Navigator.pop(context, BarcodeScanResult(barcode: barcode, found: false));
      }
      return;
    }

    try {
      final result = await BarcodeService.queryBarcode(
        provider: settingsProvider.barcodeApiProvider,
        apiKey: settingsProvider.getBarcodeApiKey(settingsProvider.barcodeApiProvider),
        barcode: barcode,
      );

      if (mounted) {
        setState(() => _isProcessing = false);
        Navigator.pop(context, BarcodeScanResult(
          barcode: result.barcode,
          found: result.found,
          name: result.name,
          brand: result.brand,
          manufacturer: result.manufacturer,
          spec: result.spec,
          price: result.price,
          category: result.category,
          description: result.description,
          imageUrl: result.imageUrl,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        Navigator.pop(context, BarcodeScanResult(barcode: barcode, found: false));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onBarcodeDetected,
          ),
          _buildScanOverlay(),
          if (_isProcessing) _buildLoadingOverlay(),
          _buildTopBar(),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildScanOverlay() {
    return ColorFiltered(
      colorFilter: ColorFilter.mode(
        Colors.black.withValues(alpha: 0.5),
        BlendMode.srcOut,
      ),
      child: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              color: Colors.black,
              backgroundBlendMode: BlendMode.dstOut,
            ),
          ),
          Center(
            child: Container(
              width: 280,
              height: 160,
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
            ),
            const Expanded(
              child: Text(
                '扫描商品条码',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Text(
                '将条码放入框内，自动识别',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildActionButton(
                    icon: Icons.flash_off,
                    activeIcon: Icons.flash_on,
                    label: '闪光灯',
                    isActive: false,
                    onTap: () => _controller.toggleTorch(),
                  ),
                  _buildActionButton(
                    icon: Icons.camera_rear,
                    activeIcon: Icons.camera_front,
                    label: '翻转',
                    isActive: false,
                    onTap: () => _controller.switchCamera(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(
              isActive ? activeIcon : icon,
              color: Colors.white,
              size: 28,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Card(
          margin: const EdgeInsets.all(32),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text(
                  '正在查询商品信息...',
                  style: TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BarcodeScanResult {
  final String barcode;
  final bool found;
  final String? name;
  final String? brand;
  final String? manufacturer;
  final String? spec;
  final double? price;
  final String? category;
  final String? description;
  final String? imageUrl;

  BarcodeScanResult({
    required this.barcode,
    required this.found,
    this.name,
    this.brand,
    this.manufacturer,
    this.spec,
    this.price,
    this.category,
    this.description,
    this.imageUrl,
  });
}
