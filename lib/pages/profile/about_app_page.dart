import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../../utils/app_info.dart';
import '../../utils/version_checker.dart';

class AboutAppPage extends StatefulWidget {
  const AboutAppPage({super.key});

  @override
  State<AboutAppPage> createState() => _AboutAppPageState();
}

class _AboutAppPageState extends State<AboutAppPage> {
  bool _isChecking = false;
  String? _updateStatus;

  Future<void> _checkForUpdates() async {
    setState(() {
      _isChecking = true;
      _updateStatus = null;
    });

    final result = await VersionChecker.checkForUpdate(AppInfo.version);

    setState(() {
      _isChecking = false;
    });

    if (!mounted) return;

    if (result.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error!)),
      );
      return;
    }

    if (result.hasUpdate) {
      _showUpdateDialog(result);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前已是最新版本')),
      );
    }
  }

  void _showUpdateDialog(UpdateResult result) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('发现新版本'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当前版本: ${result.currentVersion}'),
            const SizedBox(height: 8),
            Text('最新版本: ${result.latestVersion}'),
            const SizedBox(height: 16),
            const Text('请前往 GitHub Releases 下载更新。'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await _launchUrl('https://github.com/wxnan/nestback/releases');
            },
            child: const Text('立即更新'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('关于应用'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SizedBox(height: 24),
            _buildAppInfo(context),
            const SizedBox(height: 24),
            _buildActionsSection(context),
          ],
        ),
      ),
    );
  }

  Widget _buildAppInfo(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'assets/logo.png',
                width: 80,
                height: 80,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '归巢',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text('版本 ${AppInfo.version}'),
            const SizedBox(height: 16),
            const Text(
              '一个本地优先、数据安全、永久免费、高自由度的家庭物品收纳提醒 App。\n\n'
              '支持AI录入、扫码录入、层级空间、过期提醒、数据统计、导入导出、数据备份、实时同步、家庭协作等功能。\n\n'
              '物有归巢，心有所安；\n家有温暖，爱有归处。\n愿你有充满爱的家庭，愿你是恋巢的鸟儿。',
              textAlign: TextAlign.center,
              style: TextStyle(height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsSection(BuildContext context) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('开源代码'),
            subtitle: const Text('查看 GitHub 仓库'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _launchUrl('https://github.com/wxnan/nestback'),
          ),
          const Divider(),
          ListTile(
            leading: _isChecking
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.update),
            title: const Text('检查更新'),
            subtitle: _updateStatus != null
                ? Text(_updateStatus!)
                : const Text('点击检查更新'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _isChecking ? null : _checkForUpdates,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.share),
            title: const Text('分享应用'),
            subtitle: const Text('推荐给朋友'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _shareApp,
          ),
        ],
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _shareApp() async {
    await Share.share(
      '推荐一款超好用的家庭物品收纳管理工具 - 归巢\n\n'
      'GitHub：https://github.com/wxnan/nestback\n'
      '百度网盘：https://pan.baidu.com/s/1xAmufnzGhy4003HOZwd69Q?pwd=7ycp',
    );
  }
}