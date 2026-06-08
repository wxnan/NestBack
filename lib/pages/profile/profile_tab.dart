import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/house_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/tag_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/ai_provider.dart';
import '../../utils/app_info.dart';
import 'attribute_manager_page.dart';
import 'category_manager_page.dart';
import 'tag_manager_page.dart';
import 'reminder_settings_page.dart';
import 'donation_page.dart';
import 'about_app_page.dart';
import 'house_manager_page.dart';
import 'feedback_page.dart';
import 'barcode_settings_page.dart';
import 'import_export_page.dart';
import 'backup_settings_page.dart';
import 'ai_settings_page.dart';

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildUserCard(context),
          const SizedBox(height: 16),
          _buildHouseManagement(context),
          const SizedBox(height: 16),
          _buildItemManagement(context),
          const SizedBox(height: 16),
          _buildDataManagementSection(context),
          const SizedBox(height: 16),
          _buildAboutSection(context),
        ],
      ),
    );
  }

  Widget _buildUserCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(
                Icons.person,
                size: 32,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '归巢用户',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '开始整理您的生活物品',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHouseManagement(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '家庭管理',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Consumer<HouseProvider>(
            builder: (context, houseProvider, _) {
              return Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.home),
                    title: const Text('当前家庭'),
                    subtitle: Text(houseProvider.currentHouse?.name ?? '未选择'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showHouseManager(context),
                  ),
                  ListTile(
                    leading: const Icon(Icons.people),
                    title: const Text('成员管理'),
                    subtitle: const Text('查看当前家庭成员及角色'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showFeatureComingSoon(context, '成员管理'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.person_add),
                    title: const Text('邀请成员'),
                    subtitle: const Text('生成邀请码'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showFeatureComingSoon(context, '邀请成员'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.login),
                    title: const Text('加入家庭'),
                    subtitle: const Text('输入邀请码加入'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showFeatureComingSoon(context, '加入家庭'),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildItemManagement(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '物品管理',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Consumer3<CategoryProvider, TagProvider, SettingsProvider>(
            builder: (context, categoryProvider, tagProvider, settingsProvider, _) {
              return Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.category),
                    title: const Text('分类管理'),
                    subtitle: Text('${categoryProvider.categories.length} 个分类'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showCategoryManager(context),
                  ),
                  ListTile(
                    leading: const Icon(Icons.tune),
                    title: const Text('属性管理'),
                    subtitle: const Text('管理动态扩展属性'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showAttributeManager(context),
                  ),
                  ListTile(
                    leading: const Icon(Icons.label),
                    title: const Text('标签管理'),
                    subtitle: const Text('管理物品标签'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showTagManager(context),
                  ),
                  ListTile(
                    leading: const Icon(Icons.notifications),
                    title: const Text('提醒设置'),
                    subtitle: Text('即将过期${settingsProvider.expiringThresholdDays}天、库存阈值${settingsProvider.lowStockThreshold}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showSettingsManager(context),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDataManagementSection(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '数据管理',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Column(
            children: [
              _buildSettingTile(
                context,
                icon: Icons.cloud,
                title: '同步设置',
                subtitle: 'Supabase 配置',
                onTap: () => _showFeatureComingSoon(context, '同步设置'),
              ),
              Consumer<SettingsProvider>(
                builder: (context, settingsProvider, _) {
                  return _buildSettingTile(
                    context,
                    icon: Icons.backup,
                    title: '备份设置',
                    subtitle: 'WebDAV 配置',
                    configured: settingsProvider.isWebDavConfigured,
                    statusText: settingsProvider.isWebDavConfigured ? '已配置' : '未配置',
                    onTap: () => _showBackupSettings(context),
                  );
                },
              ),
              Consumer2<SettingsProvider, AiProviderProvider>(
                builder: (context, settingsProvider, aiProvider, _) {
                  return _buildSettingTile(
                    context,
                    icon: Icons.smart_toy,
                    title: 'AI 设置',
                    subtitle: 'LLM API 配置',
                    configured: aiProvider.isAiConfigured,
                    statusText: aiProvider.isAiConfigured ? '已配置' : '未配置',
                    onTap: () => _showAiSettings(context),
                  );
                },
              ),
              Consumer<SettingsProvider>(
                builder: (context, settingsProvider, _) {
                  return _buildSettingTile(
                    context,
                    icon: Icons.qr_code,
                    title: '扫码设置',
                    subtitle: '商品 API 配置',
                    configured: settingsProvider.isBarcodeConfigured,
                    statusText: settingsProvider.isBarcodeConfigured
                        ? settingsProvider.barcodeApiProvider
                        : null,
                    onTap: () => _showBarcodeSettings(context),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.import_export),
                title: const Text('导入导出'),
                subtitle: const Text('CSV/JSON/ZIP 数据格式'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showImportExportPage(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSettingTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    bool configured = false,
    String? statusText,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: configured
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Colors.grey[300],
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              statusText ?? (configured ? '已配置' : '未配置'),
              style: TextStyle(
                fontSize: 12,
                color: configured
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: onTap,
    );
  }

  Widget _buildAboutSection(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '关于',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.favorite_outline),
            title: const Text('捐赠支持'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showDonationPage(context),
          ),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('使用帮助'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _launchHelpUrl(),
          ),
          ListTile(
            leading: const Icon(Icons.feedback),
            title: const Text('建议反馈'),
            subtitle: const Text('多种反馈方式可选'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showFeedbackPage(context),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于应用'),
            subtitle: Text('版本 ${AppInfo.version}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showAboutAppPage(context),
          ),
        ],
      ),
    );
  }

  void _showCategoryManager(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CategoryManagerPage(),
      ),
    );
  }

  void _showAttributeManager(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AttributeManagerPage(),
      ),
    );
  }

  void _showTagManager(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const TagManagerPage(),
      ),
    );
  }

  void _showSettingsManager(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ReminderSettingsPage(),
      ),
    );
  }

  void _showFeatureComingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature 功能即将推出，敬请期待！'),
      ),
    );
  }

  void _showDonationPage(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const DonationPage(),
      ),
    );
  }

  Future<void> _launchHelpUrl() async {
    const url = 'https://ima.qq.com/wiki/?shareId=1791d940244efe8451e53720d4fa14ce8fddfbbbc1c0df612685231e4a20e960';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    }
  }



  void _showAboutAppPage(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AboutAppPage(),
      ),
    );
  }

  void _showHouseManager(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const HouseManagerPage(),
      ),
    );
  }

  void _showFeedbackPage(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const FeedbackPage(),
      ),
    );
  }

  void _showBarcodeSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const BarcodeSettingsPage(),
      ),
    );
  }

  void _showImportExportPage(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ImportExportPage(),
      ),
    );
  }

  void _showBackupSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const BackupSettingsPage(),
      ),
    );
  }

  void _showAiSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AiSettingsPage(),
      ),
    );
  }
}