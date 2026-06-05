import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  static const String _keyExpiringThresholdDays = 'expiring_threshold_days';
  static const String _keyLowStockThreshold = 'low_stock_threshold';
  static const String _keyExpireWarningOffsets = 'expire_warning_offsets';
  static const String _keyExpireNotificationHour = 'expire_notification_hour';
  static const String _keyExpireNotificationMinute = 'expire_notification_minute';
  static const String _keyEnableExpireNotification = 'enable_expire_notification';
  static const String _keyBarcodeApiProvider = 'barcode_api_provider';
  static const String _keyBarcodeApiKeyApizero = 'barcode_api_key_apizero';
  static const String _keyBarcodeApiKeyApizeroPro = 'barcode_api_key_apizero_pro';
  static const String _keyBarcodeApiKeyApibyte = 'barcode_api_key_apibyte';
  static const String _keyBarcodeApiKeyRollapi = 'barcode_api_key_rollapi';
  static const String _keyWebDavServerUrl = 'webdav_server_url';
  static const String _keyWebDavUsername = 'webdav_username';
  static const String _keyWebDavPassword = 'webdav_password';
  static const String _keyWebDavPath = 'webdav_path';
  static const String _keyWebDavEncryptionKey = 'webdav_encryption_key';

  int _expiringThresholdDays = 30;
  int _lowStockThreshold = 1;
  List<int> _expireWarningOffsets = [0, 7];
  TimeOfDay _expireNotificationTime = const TimeOfDay(hour: 9, minute: 0);
  bool _enableExpireNotification = false;
  String _barcodeApiProvider = 'apizero';
  String _barcodeApiKeyApizero = '';
  String _barcodeApiKeyApizeroPro = '';
  String _barcodeApiKeyApibyte = '';
  String _barcodeApiKeyRollapi = '';
  String _webDavServerUrl = '';
  String _webDavUsername = '';
  String _webDavPassword = '';
  String _webDavPath = '/nestback_backup';
  String _webDavEncryptionKey = '';

  int get expiringThresholdDays => _expiringThresholdDays;
  int get lowStockThreshold => _lowStockThreshold;
  List<int> get expireWarningOffsets => _expireWarningOffsets;
  TimeOfDay get expireNotificationTime => _expireNotificationTime;
  bool get enableExpireNotification => _enableExpireNotification;
  String get barcodeApiProvider => _barcodeApiProvider;
  String get barcodeApiKeyApizero => _barcodeApiKeyApizero;
  String get barcodeApiKeyApizeroPro => _barcodeApiKeyApizeroPro;
  String get barcodeApiKeyApibyte => _barcodeApiKeyApibyte;
  String get barcodeApiKeyRollapi => _barcodeApiKeyRollapi;
  String get webDavServerUrl => _webDavServerUrl;
  String get webDavUsername => _webDavUsername;
  String get webDavPassword => _webDavPassword;
  String get webDavPath => _webDavPath;
  String get webDavEncryptionKey => _webDavEncryptionKey;

  String getBarcodeApiKey(String provider) {
    switch (provider) {
      case 'apizero':
        return _barcodeApiKeyApizero;
      case 'apizero-pro':
        return _barcodeApiKeyApizeroPro;
      case 'apibyte':
        return _barcodeApiKeyApibyte;
      case 'rollapi':
        return _barcodeApiKeyRollapi;
      default:
        return '';
    }
  }

  bool get isBarcodeConfigured {
    final key = getBarcodeApiKey(_barcodeApiProvider);
    return _barcodeApiProvider == 'apizero' ||
        _barcodeApiProvider == 'apizero-pro' ||
        (_barcodeApiProvider == 'apibyte' && key.isNotEmpty) ||
        (_barcodeApiProvider == 'rollapi' && _isRollapiKeyValid(key));
  }

  static bool _isRollapiKeyValid(String key) {
    if (key.isEmpty) return false;
    final parts = key.split(',');
    return parts.length == 2 && parts[0].trim().isNotEmpty && parts[1].trim().isNotEmpty;
  }

  bool get isWebDavConfigured {
    return _webDavServerUrl.isNotEmpty &&
        _webDavUsername.isNotEmpty &&
        _webDavPassword.isNotEmpty;
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    
    _expiringThresholdDays = prefs.getInt(_keyExpiringThresholdDays) ?? 30;
    _lowStockThreshold = prefs.getInt(_keyLowStockThreshold) ?? 1;
    
    final offsetsString = prefs.getString(_keyExpireWarningOffsets);
    if (offsetsString != null) {
      _expireWarningOffsets = offsetsString.split(',').map((s) => int.parse(s)).toList();
    } else {
      _expireWarningOffsets = [0, 7];
    }
    
    final hour = prefs.getInt(_keyExpireNotificationHour) ?? 9;
    final minute = prefs.getInt(_keyExpireNotificationMinute) ?? 0;
    _expireNotificationTime = TimeOfDay(hour: hour, minute: minute);
    
    _enableExpireNotification = prefs.getBool(_keyEnableExpireNotification) ?? false;
    
    _barcodeApiProvider = prefs.getString(_keyBarcodeApiProvider) ?? 'apizero';
    _barcodeApiKeyApizero = prefs.getString(_keyBarcodeApiKeyApizero) ?? '';
    _barcodeApiKeyApizeroPro = prefs.getString(_keyBarcodeApiKeyApizeroPro) ?? '';
    _barcodeApiKeyApibyte = prefs.getString(_keyBarcodeApiKeyApibyte) ?? '';
    _barcodeApiKeyRollapi = prefs.getString(_keyBarcodeApiKeyRollapi) ?? '';
    
    _webDavServerUrl = prefs.getString(_keyWebDavServerUrl) ?? '';
    _webDavUsername = prefs.getString(_keyWebDavUsername) ?? '';
    _webDavPassword = prefs.getString(_keyWebDavPassword) ?? '';
    _webDavPath = prefs.getString(_keyWebDavPath) ?? '/nestback_backup';
    _webDavEncryptionKey = prefs.getString(_keyWebDavEncryptionKey) ?? '';
    
    notifyListeners();
  }

  Future<void> setExpiringThresholdDays(int days) async {
    _expiringThresholdDays = days;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyExpiringThresholdDays, days);
    notifyListeners();
  }

  Future<void> setLowStockThreshold(int threshold) async {
    _lowStockThreshold = threshold;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyLowStockThreshold, threshold);
    notifyListeners();
  }

  Future<void> setExpireWarningOffsets(List<int> offsets) async {
    _expireWarningOffsets = offsets;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyExpireWarningOffsets, offsets.join(','));
    notifyListeners();
  }

  Future<void> setExpireNotificationTime(TimeOfDay time) async {
    _expireNotificationTime = time;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyExpireNotificationHour, time.hour);
    await prefs.setInt(_keyExpireNotificationMinute, time.minute);
    notifyListeners();
  }

  Future<void> toggleExpireNotification(bool enabled) async {
    _enableExpireNotification = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnableExpireNotification, enabled);
    notifyListeners();
  }

  Future<void> setBarcodeApiProvider(String provider) async {
    _barcodeApiProvider = provider;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBarcodeApiProvider, provider);
    notifyListeners();
  }

  Future<void> setBarcodeApiKey(String provider, String key) async {
    final prefs = await SharedPreferences.getInstance();
    switch (provider) {
      case 'apizero':
        _barcodeApiKeyApizero = key;
        await prefs.setString(_keyBarcodeApiKeyApizero, key);
        break;
      case 'apizero-pro':
        _barcodeApiKeyApizeroPro = key;
        await prefs.setString(_keyBarcodeApiKeyApizeroPro, key);
        break;
      case 'apibyte':
        _barcodeApiKeyApibyte = key;
        await prefs.setString(_keyBarcodeApiKeyApibyte, key);
        break;
      case 'rollapi':
        _barcodeApiKeyRollapi = key;
        await prefs.setString(_keyBarcodeApiKeyRollapi, key);
        break;
    }
    notifyListeners();
  }

  Future<void> setWebDavConfig({
    required String serverUrl,
    required String username,
    required String password,
    required String path,
    String? encryptionKey,
  }) async {
    _webDavServerUrl = serverUrl;
    _webDavUsername = username;
    _webDavPassword = password;
    _webDavPath = path;
    _webDavEncryptionKey = encryptionKey ?? '';
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyWebDavServerUrl, serverUrl);
    await prefs.setString(_keyWebDavUsername, username);
    await prefs.setString(_keyWebDavPassword, password);
    await prefs.setString(_keyWebDavPath, path);
    await prefs.setString(_keyWebDavEncryptionKey, encryptionKey ?? '');
    
    notifyListeners();
  }

  Future<void> clearWebDavConfig() async {
    _webDavServerUrl = '';
    _webDavUsername = '';
    _webDavPassword = '';
    _webDavPath = '/nestback_backup';
    _webDavEncryptionKey = '';
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyWebDavServerUrl);
    await prefs.remove(_keyWebDavUsername);
    await prefs.remove(_keyWebDavPassword);
    await prefs.remove(_keyWebDavPath);
    await prefs.remove(_keyWebDavEncryptionKey);
    
    notifyListeners();
  }
}