package com.nestback.shouna

import android.app.AlarmManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.nestback.shouna/alarm_permission"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openExactAlarmSettings" -> {
                        openExactAlarmSettings()
                        result.success(null)
                    }
                    "canScheduleExactAlarms" -> {
                        val canSchedule = canScheduleExactAlarms()
                        result.success(canSchedule)
                    }
                    "hasPermission" -> {
                        result.success(hasScheduleExactAlarmPermission())
                    }
                    else -> result.notImplemented()
                }
            }
    }
    
    private fun openExactAlarmSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                // 方式一：直接跳转到本应用的闹钟权限页面
                val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                    data = Uri.parse("package:$packageName")
                }
                startActivity(intent)
            } catch (e: Exception) {
                // 方式二：跳转到闹钟与提醒列表页面
                try {
                    val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = Uri.parse("package:$packageName")
                    }
                    startActivity(intent)
                } catch (e2: Exception) {
                    // 方式三：跳转到应用设置
                    val intent = Intent(Settings.ACTION_APPLICATION_SETTINGS)
                    startActivity(intent)
                }
            }
        }
    }
    
    private fun canScheduleExactAlarms(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            return alarmManager.canScheduleExactAlarms()
        }
        return true
    }
    
    private fun hasScheduleExactAlarmPermission(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return checkSelfPermission(android.Manifest.permission.SCHEDULE_EXACT_ALARM) == 
                   android.content.pm.PackageManager.PERMISSION_GRANTED
        }
        return true
    }
}