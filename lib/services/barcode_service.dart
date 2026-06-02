import 'dart:convert';
import 'package:http/http.dart' as http;

class BarcodeResult {
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

  BarcodeResult({
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

class BarcodeService {
  static Future<BarcodeResult> queryBarcode({
    required String provider,
    required String apiKey,
    required String barcode,
  }) async {
    switch (provider) {
      case 'apizero':
        return _queryApizero(apiKey, barcode);
      case 'apizero-pro':
        return _queryApizeroPro(apiKey, barcode);
      case 'apibyte':
        return _queryApibyte(apiKey, barcode);
      case 'rollapi':
        return _queryRollapi(apiKey, barcode);
      default:
        return _queryApizero(apiKey, barcode);
    }
  }

  static Future<BarcodeResult> _queryApizero(String apiKey, String barcode) async {
    final uri = Uri.https('v1.apizero.cn', '/api/barcode-lookup', {
      'barcode': barcode,
    });
    final headers = <String, String>{};
    if (apiKey.isNotEmpty) {
      headers['Authorization'] = apiKey;
    }
    final response = await http.get(uri, headers: headers);
    final json = jsonDecode(response.body) as Map<String, dynamic>;

    if (json['code'] == 0 && json['data'] != null) {
      final data = json['data'] as Map<String, dynamic>;
      return BarcodeResult(
        barcode: data['barcode'] as String? ?? barcode,
        found: data['found'] as bool? ?? false,
        name: data['name'] as String?,
        brand: data['brand'] as String?,
        manufacturer: data['manufacturer'] as String?,
        spec: data['spec'] as String?,
        price: (data['price'] as num?)?.toDouble(),
        category: data['category'] as String?,
        description: data['description'] as String?,
        imageUrl: data['image'] as String?,
      );
    }

    throw Exception(json['msg'] ?? '请求失败');
  }

  static Future<BarcodeResult> _queryApizeroPro(String apiKey, String barcode) async {
    final uri = Uri.https('v1.apizero.cn', '/api/barcode-gs1', {
      'code': barcode,
    });
    final headers = <String, String>{};
    if (apiKey.isNotEmpty) {
      headers['Authorization'] = apiKey;
    }
    final response = await http.get(uri, headers: headers);
    final json = jsonDecode(response.body) as Map<String, dynamic>;

    if (json['code'] == 0 && json['data'] != null) {
      final data = json['data'] as Map<String, dynamic>;
      final images = data['images'] as List<dynamic>?;
      final firstImage = (images != null && images.isNotEmpty) ? images.first as String : null;
      return BarcodeResult(
        barcode: data['barcode'] as String? ?? barcode,
        found: data['found'] as bool? ?? false,
        name: data['name'] as String?,
        brand: data['brand'] as String?,
        manufacturer: data['manufacturer'] as String?,
        spec: data['specification'] as String?,
        price: double.tryParse(data['price']?.toString() ?? ''),
        category: data['category'] as String?,
        description: data['feature'] as String?,
        imageUrl: firstImage,
      );
    }

    throw Exception(json['msg'] ?? '请求失败');
  }

  static Future<BarcodeResult> _queryApibyte(String apiKey, String barcode) async {
    final uri = Uri.https('apione.apibyte.cn', '/api/barcode', {
      'key': apiKey,
      'barcode': barcode,
    });
    final response = await http.get(uri);
    final json = jsonDecode(response.body) as Map<String, dynamic>;

    if (json['code'] == 200 && json['data'] != null) {
      final data = json['data'] as Map<String, dynamic>;
      return BarcodeResult(
        barcode: data['barcode'] as String? ?? barcode,
        found: data['found'] as bool? ?? false,
        name: data['goods_name'] as String?,
        brand: data['brand'] as String?,
        manufacturer: data['company'] as String?,
        spec: data['specification'] as String?,
        price: double.tryParse(data['price']?.toString() ?? ''),
        category: data['category'] as String?,
        description: data['description'] as String?,
        imageUrl: data['image'] as String?,
      );
    }

    throw Exception(json['msg'] ?? '请求失败');
  }

  static Future<BarcodeResult> _queryRollapi(String apiKey, String barcode) async {
    final parts = apiKey.split(',');
    if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) {
      throw Exception('rollapi 需要 app_id 和 app_secret，格式：app_id,app_secret');
    }
    final appId = parts[0].trim();
    final appSecret = parts[1].trim();

    final uri = Uri.https('www.mxnzp.com', '/api/barcode/goods/details', {
      'barcode': barcode,
      'app_id': appId,
      'app_secret': appSecret,
    });
    final response = await http.get(uri);
    final json = jsonDecode(response.body) as Map<String, dynamic>;

    if (json['code'] == 1 && json['data'] != null) {
      final data = json['data'] as Map<String, dynamic>;
      return BarcodeResult(
        barcode: data['barcode'] as String? ?? barcode,
        found: true,
        name: data['goodsName'] as String?,
        brand: data['brand'] as String?,
        manufacturer: data['supplier'] as String?,
        spec: data['standard'] as String?,
        price: double.tryParse(data['price']?.toString() ?? ''),
        category: null,
        description: null,
        imageUrl: null,
      );
    }

    throw Exception(json['msg'] ?? '请求失败');
  }
}
