import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class DonationPage extends StatelessWidget {
  const DonationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('捐赠支持'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 32),
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Icon(
                      Icons.favorite,
                      size: 64,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '感谢您的支持',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '您的捐赠将帮助我们持续开发和维护归巢',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '赞助方式',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    _buildDonationOption(
                      context,
                      icon: Icons.qr_code,
                      title: '支付宝',
                      subtitle: '扫码捐赠',
                      color: Colors.blue,
                      onTap: () => _showQRCodeDialog(context, '支付宝', 'assets/支付宝.jpg'),
                    ),
                    const Divider(),
                    _buildDonationOption(
                      context,
                      icon: Icons.qr_code,
                      title: '微信支付',
                      subtitle: '扫码捐赠',
                      color: Colors.green,
                      onTap: () => _showQRCodeDialog(context, '微信支付', 'assets/微信支付.png'),
                    ),
                    const Divider(),
                    _buildDonationOption(
                      context,
                      icon: Icons.shopping_cart,
                      title: '省钱优惠',
                      subtitle: '领取优惠券',
                      color: Colors.orange,
                      onTap: () => _launchUrl('https://www.yuque.com/dawnan/sheng/shengqian?singleDoc#%20%E3%80%8A%E7%9C%81%E9%92%B1%E4%BC%98%E6%83%A0%E3%80%8B'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildDonationOption(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  void _showQRCodeDialog(BuildContext context, String title, String imagePath) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                imagePath,
                width: 280,
                height: 280,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 16),
              const Text('扫码完成捐赠'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  void _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}