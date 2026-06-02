import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/services.dart';

class AlarmSettingsHelper {
  static Future<void> openAlarmSettings() async {
    final intent = AndroidIntent(
      action: 'android.settings.REQUEST_SCHEDULE_EXACT_ALARM',
      data: 'package:com.nestback.shouna',
    );
    try {
      await intent.launch();
    } on PlatformException catch (e) {
      print('Failed to open alarm settings: ${e.message}');
    }
  }
}