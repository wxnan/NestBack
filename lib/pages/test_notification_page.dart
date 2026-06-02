import 'package:flutter/material.dart';
import '../services/notification_service.dart';

class TestNotificationPage extends StatelessWidget {
  const TestNotificationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('测试通知功能'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '测试工具',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () async {
              await NotificationService().testNotification();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已发送测试通知')),
              );
            },
            child: const Text('发送即时测试通知'),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () async {
              await NotificationService().testScheduledNotification();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已安排5秒后的定时通知')),
              );
            },
            child: const Text('发送5秒后定时测试通知'),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () async {
              await NotificationService().cancelAllNotifications();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已取消所有通知')),
              );
            },
            child: const Text('取消所有通知'),
          ),
          const SizedBox(height: 24),
          const Text(
            '排查步骤',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('1. 确保已授予通知权限'),
          const Text('2. 确保已授予精确闹钟权限'),
          const Text('3. 检查AndroidManifest.xml中的权限配置'),
          const Text('4. 查看Logcat日志，搜索 [NotificationService]'),
          const SizedBox(height: 24),
          const Text(
            '日志说明',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('- [NotificationService] Timezone initialized: 时区初始化'),
          const Text('- [NotificationService] Notification service initialized: 服务初始化'),
          const Text('- [NotificationService] Scheduling notification: 开始调度'),
          const Text('- [NotificationService] Notification scheduled successfully: 调度成功'),
        ],
      ),
    );
  }
}
