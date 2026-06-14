import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../database/database.dart';

class HouseProvider extends ChangeNotifier {
  final AppDatabase _db;
  House? _currentHouse;
  List<House> _houses = [];
  bool _isInitialized = false;
  bool _isLoading = true;

  HouseProvider(this._db);

  bool get isLoading => _isLoading;

  Future<void> init() async {
    _isLoading = true;
    notifyListeners();
    await _loadHouses();
    _isLoading = false;
    notifyListeners();
  }

  House? get currentHouse => _currentHouse;
  List<House> get houses => _houses;
  bool get isInitialized => _isInitialized;

  Future<void> _loadHouses() async {
    _houses = await _db.select(_db.houses).get();
    if (_houses.isEmpty) {
      await _createDefaultHouse();
    } else {
      if (_currentHouse == null && _houses.isNotEmpty) {
        _currentHouse = _houses.firstWhere(
          (h) => h.isDefault,
          orElse: () => _houses.first,
        );
      }
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<void> _createDefaultHouse() async {
    final now = DateTime.now();
    final id = const Uuid().v4();
    await _db.into(_db.houses).insert(HousesCompanion.insert(
      id: id,
      name: '我的家',
      isDefault: const Value(true),
      createdAt: now,
      updatedAt: now,
    ));

    await _db.into(_db.spaces).insert(SpacesCompanion.insert(
      id: const Uuid().v4(),
      houseId: id,
      name: '待整理',
      type: 'pending',
      createdAt: now,
      updatedAt: now,
    ));

    final recycleBinId = const Uuid().v4();
    await _db.into(_db.spaces).insert(SpacesCompanion.insert(
      id: recycleBinId,
      houseId: id,
      name: '回收站',
      type: 'recycle',
      createdAt: now,
      updatedAt: now,
    ));

    await _db.into(_db.spaces).insert(SpacesCompanion.insert(
      id: const Uuid().v4(),
      houseId: id,
      name: '垃圾桶',
      type: 'trash',
      parentId: Value(recycleBinId),
      createdAt: now,
      updatedAt: now,
    ));

    await _createDefaultCategories(id);
    
    _houses = await _db.select(_db.houses).get();
    _currentHouse = _houses.firstWhere(
      (h) => h.isDefault,
      orElse: () => _houses.first,
    );
    _isInitialized = true;
    notifyListeners();
  }

  static const List<Map<String, String?>> _foodAttributes = [
    {'name': '品牌', 'type': 'text', 'hint': '产品品牌名称', 'options': null, 'required': 'false'},
    {'name': '厂商', 'type': 'text', 'hint': '生产厂商或供应商名称', 'options': null, 'required': 'false'},
    {'name': '规格', 'type': 'text', 'hint': '产品规格型号，如500ml、10片装等', 'options': null, 'required': 'false'},
    {'name': '颜色', 'type': 'text', 'hint': '产品颜色', 'options': null, 'required': 'false'},
    {'name': '储存方式', 'type': 'multi_select', 'hint': '选择适宜的储存条件', 'options': '常温;冷藏;冷冻;阴凉;通风;干燥;遮光;密封', 'required': 'false'},
    {'name': '生产日期', 'type': 'date', 'hint': '产品生产的日期', 'options': null, 'required': 'false'},
    {'name': '保质期', 'type': 'duration', 'hint': '产品保质期', 'options': '天;月;年', 'required': 'false'},
    {'name': '过期日期', 'type': 'date', 'hint': '产品过期的日期，可通过生产日期和保质期自动计算', 'options': null, 'required': 'false'},
    {'name': '开封日期', 'type': 'date', 'hint': '产品开封的日期', 'options': null, 'required': 'false'},
    {'name': '条形码', 'type': 'text', 'hint': '产品条形码或二维码', 'options': null, 'required': 'false'},
  ];

  static const Map<String, List<Map<String, String?>>> _categoryAttributeConfigs = {
    '食品': _foodAttributes,
    '药品': _foodAttributes,
    '美妆': _foodAttributes,
    '日用品': [
      {'name': '品牌', 'type': 'text', 'hint': '产品品牌名称', 'options': null, 'required': 'false'},
      {'name': '厂商', 'type': 'text', 'hint': '生产厂商或供应商名称', 'options': null, 'required': 'false'},
      {'name': '规格', 'type': 'text', 'hint': '产品规格型号，如10卷装、500ml等', 'options': null, 'required': 'false'},
      {'name': '颜色', 'type': 'text', 'hint': '产品颜色', 'options': null, 'required': 'false'},
      {'name': '条形码', 'type': 'text', 'hint': '产品条形码或二维码', 'options': null, 'required': 'false'},
    ],
    '数码': [
      {'name': '品牌', 'type': 'text', 'hint': '产品品牌名称', 'options': null, 'required': 'false'},
      {'name': '厂商', 'type': 'text', 'hint': '生产厂商或供应商名称', 'options': null, 'required': 'false'},
      {'name': '规格', 'type': 'text', 'hint': '产品规格型号，如64GB、iPhone 15等', 'options': null, 'required': 'false'},
      {'name': '颜色', 'type': 'text', 'hint': '产品颜色', 'options': null, 'required': 'false'},
      {'name': '购买日期', 'type': 'date', 'hint': '购买产品的日期', 'options': null, 'required': 'false'},
      {'name': '保修期', 'type': 'duration', 'hint': '产品保修期', 'options': '天;月;年', 'required': 'false'},
      {'name': '过保日期', 'type': 'date', 'hint': '保修到期的日期，可通过购买日期和保修期自动计算', 'options': null, 'required': 'false'},
      {'name': '条形码', 'type': 'text', 'hint': '产品条形码或二维码', 'options': null, 'required': 'false'},
    ],
    '其他': [
      {'name': '品牌', 'type': 'text', 'hint': '产品品牌名称', 'options': null, 'required': 'false'},
      {'name': '厂商', 'type': 'text', 'hint': '生产厂商或供应商名称', 'options': null, 'required': 'false'},
      {'name': '规格', 'type': 'text', 'hint': '产品规格型号', 'options': null, 'required': 'false'},
      {'name': '颜色', 'type': 'text', 'hint': '产品颜色', 'options': null, 'required': 'false'},
      {'name': '条形码', 'type': 'text', 'hint': '产品条形码或二维码', 'options': null, 'required': 'false'},
    ],
  };

  Future<void> _createDefaultCategories(String houseId) async {
    final now = DateTime.now();
    final categoryNames = ['食品', '药品', '日用品', '数码', '美妆', '其他'];

    // 全局共享分类/属性，先查数据库已有记录
    final existingCats = await (_db.select(_db.categories)).get();
    final catNameToId = {for (var c in existingCats) c.name: c.id};
    final existingAttrs = await (_db.select(_db.attributes)).get();
    final attrNameToId = {for (var a in existingAttrs) a.name: a.id};

    for (int i = 0; i < categoryNames.length; i++) {
      final categoryName = categoryNames[i];

      // 复用已有分类，避免 UNIQUE 冲突
      String categoryId;
      if (catNameToId.containsKey(categoryName)) {
        categoryId = catNameToId[categoryName]!;
      } else {
        categoryId = const Uuid().v4();
        await _db.into(_db.categories).insert(CategoriesCompanion.insert(
              id: categoryId,
              houseId: houseId,
              name: categoryName,
              sortOrder: Value(i),
              createdAt: now,
            ),
          mode: InsertMode.insertOrIgnore,
        );
        catNameToId[categoryName] = categoryId;
      }

      final attrConfigs = _categoryAttributeConfigs[categoryName];
      if (attrConfigs != null) {
        for (int j = 0; j < attrConfigs.length; j++) {
          final config = attrConfigs[j];
          final attrName = config['name']!;

          // 复用已有属性，避免 UNIQUE 冲突
          String attrId;
          if (attrNameToId.containsKey(attrName)) {
            attrId = attrNameToId[attrName]!;
          } else {
            attrId = const Uuid().v4();
            await _db.into(_db.attributes).insert(AttributesCompanion.insert(
                  id: attrId,
                  houseId: houseId,
                  name: attrName,
                  type: config['type']!,
                  hint: Value(config['hint']),
                  options: Value(config['options']),
                  required: Value(config['required'] == 'true'),
                  sortOrder: Value(attrNameToId.length),
                  createdAt: now,
                  updatedAt: now,
                ),
              mode: InsertMode.insertOrIgnore,
            );
            attrNameToId[attrName] = attrId;
          }

          // 避免重复关联
          final existingLink = await (_db.select(_db.categoryAttributes)
                ..where((t) => t.categoryId.equals(categoryId) & t.attributeId.equals(attrId)))
              .getSingleOrNull();
          if (existingLink == null) {
            await _db.into(_db.categoryAttributes).insert(
              CategoryAttributesCompanion.insert(
                categoryId: categoryId,
                attributeId: attrId,
                sortOrder: Value(j),
              ),
            );
          }
        }
      }
    }
  }

  Future<void> switchHouse(House house) async {
    _currentHouse = house;
    notifyListeners();
  }

  Future<void> updateHouse(String houseId, String newName) async {
    await (_db.update(_db.houses)..where((t) => t.id.equals(houseId))).write(
      HousesCompanion(
        name: Value(newName),
        updatedAt: Value(DateTime.now()),
      ),
    );
    if (_currentHouse?.id == houseId) {
      _currentHouse = await (_db.select(_db.houses)
            ..where((t) => t.id.equals(houseId)))
          .getSingleOrNull();
    }
    await _loadHouses();
  }

  Future<void> createHouse(String name) async {
    final now = DateTime.now();
    final id = const Uuid().v4();
    await _db.into(_db.houses).insert(HousesCompanion.insert(
      id: id,
      name: name,
      createdAt: now,
      updatedAt: now,
    ));

    await _db.into(_db.spaces).insert(SpacesCompanion.insert(
      id: const Uuid().v4(),
      houseId: id,
      name: '待整理',
      type: 'pending',
      createdAt: now,
      updatedAt: now,
    ));

    final recycleBinId = const Uuid().v4();
    await _db.into(_db.spaces).insert(SpacesCompanion.insert(
      id: recycleBinId,
      houseId: id,
      name: '回收站',
      type: 'recycle',
      createdAt: now,
      updatedAt: now,
    ));

    await _db.into(_db.spaces).insert(SpacesCompanion.insert(
      id: const Uuid().v4(),
      houseId: id,
      name: '垃圾桶',
      type: 'trash',
      parentId: Value(recycleBinId),
      createdAt: now,
      updatedAt: now,
    ));

    // 分类、属性、标签是全局共享的，新家庭不再创建默认分类
    await _loadHouses();
  }

  Future<void> deleteHouse(String houseId) async {
    await (_db.delete(_db.items)
          ..where((t) => t.houseId.equals(houseId)))
        .go();
    await (_db.delete(_db.spaces)
          ..where((t) => t.houseId.equals(houseId)))
        .go();
    // 分类、属性、标签是全局共享的，不随家庭删除
    await (_db.delete(_db.houses)
          ..where((t) => t.id.equals(houseId)))
        .go();
    await _loadHouses();
  }
}
