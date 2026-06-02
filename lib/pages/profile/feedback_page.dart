import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class FeedbackPage extends StatelessWidget {
  const FeedbackPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('建议反馈'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildFeedbackOption(
            context,
            icon: Icons.bug_report,
            title: 'GitHub Issues',
            subtitle: '提交问题或功能建议',
            onTap: () => _launchUrl(context, 'https://github.com/wxnan/nestback/issues'),
          ),
          const SizedBox(height: 12),
          _buildFeedbackOption(
            context,
            icon: Icons.email,
            title: '邮箱反馈',
            subtitle: 'xiaon_ooossltsbk@aka.yeah.net',
            onTap: () => _launchEmail(context),
          ),
          const SizedBox(height: 12),
          _buildFeedbackOption(
            context,
            icon: Icons.article,
            title: '在线表单',
            subtitle: '填写反馈问卷',
            onTap: () => _launchUrl(context, 'https://wj.qq.com/s2/26848069/6be1/'),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedbackOption(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon, size: 28),
        title: Text(title, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  Future<void> _launchUrl(BuildContext context, String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法打开链接，请检查浏览器设置')),
        );
      }
    }
  }

  Future<void> _launchEmail(BuildContext context) async {
    const email = 'xiaon_ooossltsbk@aka.yeah.net';
    const subject = '归巢 - 建议反馈';
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: email,
      queryParameters: {'subject': subject},
    );
    if (!await launchUrl(emailUri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法打开邮箱应用，请检查是否已安装邮箱客户端')),
        );
      }
    }
  }
}
