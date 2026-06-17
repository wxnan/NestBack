import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/settings_provider.dart';
import '../../database/database.dart';
import '../../services/notification_service.dart';
import '../../utils/alarm_settings.dart';

class ReminderSettingsPage extends StatefulWidget {
  const ReminderSettingsPage({super.key});

  @override
  State<ReminderSettingsPage> createState() => _ReminderSettingsPageState();
}

class _ReminderSettingsPageState extends State<ReminderSettingsPage> {
  static const List<int> _warningOffsetOptions = [1, 3, 7, 15, 30];
  static const String _exactAlarmPermissionKey = 'exact_alarm_permission_granted';
  
  bool _notificationPermissionGranted = false;
  bool _exactAlarmPermissionGranted = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final notificationStatus = await Permission.notification.status;
    final prefs = await SharedPreferences.getInstance();
    
    setState(() {
      _notificationPermissionGranted = notificationStatus.isGranted;
      _exactAlarmPermissionGranted = prefs.getBool(_exactAlarmPermissionKey) ?? false;
    });
  }

  String _getOffsetLabel(int offset) {
    return '提前$offset天';
  }

  Future<void> _handleExpireNotificationToggle(bool value, SettingsProvider settingsProvider) async {
    if (value) {
      await _ensurePermissions();
      settingsProvider.toggleExpireNotification(true);
      await _updateReminders();
    } else {
      settingsProvider.toggleExpireNotification(false);
      await _updateReminders();
    }
  }

  Future<void> _ensurePermissions() async {
    if (!_notificationPermissionGranted) {
      final result = await Permission.notification.request();
      if (result.isGranted) {
        setState(() => _notificationPermissionGranted = true);
      }
    }
  }

  Future<void> _requestNotificationPermission() async {
    final status = await Permission.notification.request();
    setState(() {
      _notificationPermissionGranted = status.isGranted;
    });
  }

  Future<void> _requestExactAlarmPermission(bool value) async {
    if (value) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('闹钟与提醒权限'),
          content: const Text(
            '此权限需要手动授权，请按以下步骤操作：\n\n'
            '1. 点击"前往设置"打开权限申请页面\n'
            '2. 将"闹钟与提醒"设置为"允许"\n'
            '3. 返回后点击"已授权"确认',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(context);
                await AlarmSettingsHelper.openAlarmSettings();
              },
              child: const Text('前往设置'),
            ),
          ],
        ),
      );
      
      if (confirmed == null) {
        final userConfirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('确认授权'),
            content: const Text('您是否已在系统设置中开启了"闹钟与提醒"权限？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('还没有'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('已授权'),
              ),
            ],
          ),
        );
        
        if (userConfirmed == true) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool(_exactAlarmPermissionKey, true);
          setState(() => _exactAlarmPermissionGranted = true);
        }
      }
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_exactAlarmPermissionKey, false);
      setState(() => _exactAlarmPermissionGranted = false);
    }
  }

  Future<void> _updateReminders() async {
    final db = Provider.of<AppDatabase>(context, listen: false);
    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    await NotificationService().checkAndScheduleExpireReminders(db, settingsProvider);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('提醒设置'),
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settingsProvider, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Column(
                  children: [
                    ListTile(
                      title: const Text('即将过期阈值'),
                      subtitle: Text('${settingsProvider.expiringThresholdDays} 天内过期视为即将过期'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove),
                            onPressed: () {
                              if (settingsProvider.expiringThresholdDays > 1) {
                                settingsProvider.setExpiringThresholdDays(settingsProvider.expiringThresholdDays - 1);
                              }
                            },
                          ),
                          SizedBox(
                            width: 40,
                            child: Center(
                              child: Text('${settingsProvider.expiringThresholdDays}'),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add),
                            onPressed: () {
                              settingsProvider.setExpiringThresholdDays(settingsProvider.expiringThresholdDays + 1);
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
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
                        '过期提前提醒',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text('选择提醒时间点（可多选）'),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: _warningOffsetOptions.map((offset) {
                          final isSelected = settingsProvider.expireWarningOffsets.contains(offset);
                          return ChoiceChip(
                            label: Text(_getOffsetLabel(offset)),
                            selected: isSelected,
                            onSelected: (selected) {
                              final currentOffsets = List<int>.from(settingsProvider.expireWarningOffsets);
                              if (selected) {
                                if (!currentOffsets.contains(offset)) {
                                  currentOffsets.add(offset);
                                  currentOffsets.sort();
                                }
                              } else {
                                currentOffsets.remove(offset);
                              }
                              settingsProvider.setExpireWarningOffsets(currentOffsets);
                              _updateReminders();
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 16),
                      const Text(
                        '过期提醒时间',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () async {
                          final selectedTime = await showTimePicker(
                            context: context,
                            initialTime: settingsProvider.expireNotificationTime,
                          );
                          if (selectedTime != null) {
                            settingsProvider.setExpireNotificationTime(selectedTime);
                            _updateReminders();
                          }
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${settingsProvider.expireNotificationTime.hour.toString().padLeft(2, '0')}:${settingsProvider.expireNotificationTime.minute.toString().padLeft(2, '0')}',
                              style: const TextStyle(fontSize: 16),
                            ),
                            const Icon(Icons.access_time),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('启用过期提醒'),
                      subtitle: const Text('在设置的提醒时间点通知'),
                      value: settingsProvider.enableExpireNotification,
                      onChanged: (value) {
                        _handleExpireNotificationToggle(value, settingsProvider);
                      },
                    ),
                    const Divider(),
                    SwitchListTile(
                      title: const Text('通知权限'),
                      subtitle: const Text('允许APP发送通知'),
                      value: _notificationPermissionGranted,
                      onChanged: (value) {
                        if (value) {
                          _requestNotificationPermission();
                        } else {
                          openAppSettings();
                        }
                      },
                    ),
                    const Divider(),
                    SwitchListTile(
                      title: const Text('闹钟与提醒权限'),
                      subtitle: const Text('需要手动授权，允许APP在指定时间发送提醒'),
                      value: _exactAlarmPermissionGranted,
                      onChanged: _requestExactAlarmPermission,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
