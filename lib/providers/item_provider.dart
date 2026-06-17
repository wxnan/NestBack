import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../database/database.dart';

class ItemProvider extends ChangeNotifier {
  final AppDatabase _db;
  List<Item> _items = [];
  List<Item> _filteredItems = [];
  String _searchQuery = '';
  String? _selectedCategory;
  String? _selectedTag;
  String _sortBy = 'createdAt';
  bool _sortAscending = false;
  String? _currentSpaceId; // 当前显示的空间ID
  List<String>? _specialSpaceIds; // 特殊空间ID列表（回收站、垃圾桶等）
  Map<String, Map<String, String>> _itemAttributes = {}; // 物品扩展属性缓存
  Map<String, String> _spaceNames = {}; // 空间名称缓存

  ItemProvider(this._db);

  List<Item> get items => _filteredItems;
  List<Item> get allItems => _items;
  String get searchQuery => _searchQuery;
  String? get selectedCategory => _selectedCategory;
  String? get selectedTag => _selectedTag;
  List<String>? get specialSpaceIds => _specialSpaceIds;

  Future<void> loadItems(String houseId) async {
    _items = await (_db.select(_db.items)
          ..where((t) => t.houseId.equals(houseId)))
        .get();

    // 自动修复旧数据：categoryId 为 null 但 category 有值时，补全 categoryId
    await _fixMissingCategoryIds(houseId);

    // 加载所有物品的扩展属性
    await _loadItemAttributes(houseId);

    _applyFilters();
  }

  /// 修复旧数据中 categoryId 为 null 的情况
  Future<void> _fixMissingCategoryIds(String houseId) async {
    final itemsNeedFix = _items.where((item) =>
        (item.categoryId == null || item.categoryId!.isEmpty) &&
        item.category != null &&
        item.category!.isNotEmpty,
    ).toList();

    if (itemsNeedFix.isEmpty) return;

    // 获取当前家庭的所有分类
    final categories = await (_db.select(_db.categories)
          ..where((t) => t.houseId.equals(houseId)))
        .get();

    final categoryNameToId = <String, String>{};
    for (final cat in categories) {
      categoryNameToId[cat.name] = cat.id;
    }

    for (final item in itemsNeedFix) {
      final categoryName = item.category!;
      final matchedId = categoryNameToId[categoryName];
      if (matchedId != null) {
        await (_db.update(_db.items)..where((t) => t.id.equals(item.id))).write(
          ItemsCompanion(categoryId: Value(matchedId)),
        );
        // 更新内存中的数据
        final index = _items.indexWhere((i) => i.id == item.id);
        if (index >= 0) {
          _items[index] = _items[index].copyWith(categoryId: Value(matchedId));
        }
      }
    }
  }
  
  // 加载物品扩展属性
  Future<void> _loadItemAttributes(String houseId) async {
    final itemIds = _items.map((i) => i.id).toList();
    if (itemIds.isEmpty) {
      _itemAttributes = {};
      return;
    }
    
    final attrs = await (_db.select(_db.itemAttributes)
          ..where((t) => t.itemId.isIn(itemIds)))
        .get();
    
    _itemAttributes = {};
    for (final attr in attrs) {
      _itemAttributes.putIfAbsent(attr.itemId, () => {});
      _itemAttributes[attr.itemId]![attr.attributeId] = attr.value ?? '';
    }
  }
  
  // 设置空间名称缓存（由外部调用）
  void setSpaceNames(Map<String, String> names) {
    _spaceNames = names;
    _applyFilters();
  }

  void _applyFilters() {
    print('开始应用筛选，总物品数: ${_items.length}');
    print('特殊空间ID列表: $_specialSpaceIds');
    
    _filteredItems = _items.where((item) {
      final matchesSearch = _matchesSearchQuery(item);
      final matchesCategory =
          _selectedCategory == null || item.category == _selectedCategory;
      final matchesTag = _selectedTag == null || _hasTag(item.tags, _selectedTag!);
      
      // 空间筛选逻辑
      bool matchesSpace = true;
      if (_currentSpaceId == null) {
        // 首页：排除回收站和垃圾桶的物品
        final isSpecialSpace = _specialSpaceIds != null && _specialSpaceIds!.contains(item.spaceId);
        matchesSpace = !isSpecialSpace;
      } else {
        // 特定空间：只显示该空间的物品
        matchesSpace = item.spaceId == _currentSpaceId;
      }
      
      return matchesSearch && matchesCategory && matchesTag && matchesSpace;
    }).toList();
    
    print('筛选后的物品数: ${_filteredItems.length}');

    _filteredItems.sort((a, b) {
      int result;
      switch (_sortBy) {
        case 'name':
          result = a.name.compareTo(b.name);
          break;
        case 'expireDate':
          final aHasExpireDate = a.expireDate != null;
          final bHasExpireDate = b.expireDate != null;
          
          if (!aHasExpireDate && !bHasExpireDate) {
            result = 0;
          } else if (!aHasExpireDate) {
            result = 1;
          } else if (!bHasExpireDate) {
            result = -1;
          } else {
            result = a.expireDate!.compareTo(b.expireDate!);
          }
          break;
        case 'updatedAt':
          result = a.updatedAt.compareTo(b.updatedAt);
          break;
        case 'price':
          final aPrice = (a.price ?? 0) * a.quantity;
          final bPrice = (b.price ?? 0) * b.quantity;
          result = aPrice.compareTo(bPrice);
          break;
        case 'createdAt':
        default:
          result = a.createdAt.compareTo(b.createdAt);
          break;
      }
      return _sortAscending ? result : -result;
    });

    notifyListeners();
  }

  bool _hasTag(String? tags, String tagName) {
    if (tags == null || tags.isEmpty) return false;
    return tags.contains(tagName);
  }

  /// 多字段搜索匹配
  bool _matchesSearchQuery(Item item) {
    if (_searchQuery.isEmpty) return true;
    
    final query = _searchQuery.toLowerCase();
    
    // 1. 搜索名称
    if (item.name.toLowerCase().contains(query)) return true;
    
    // 2. 搜索分类
    if (item.category != null && item.category!.toLowerCase().contains(query)) return true;
    
    // 3. 搜索标签
    if (item.tags != null && item.tags!.toLowerCase().contains(query)) return true;
    
    // 4. 搜索备注
    if (item.note != null && item.note!.toLowerCase().contains(query)) return true;
    
    // 5. 搜索位置（空间名称）
    final spaceName = _spaceNames[item.spaceId];
    if (spaceName != null && spaceName.toLowerCase().contains(query)) return true;
    
    // 6. 搜索日期（生产日期、过期日期）
    final dateFormat = DateFormat('yyyy-MM-dd');
    if (item.productionDate != null) {
      final dateStr = dateFormat.format(item.productionDate!);
      if (dateStr.contains(query)) return true;
    }
    if (item.expireDate != null) {
      final dateStr = dateFormat.format(item.expireDate!);
      if (dateStr.contains(query)) return true;
    }
    
    // 7. 搜索扩展属性（品牌、厂商、规格、颜色、条形码等）
    final attrs = _itemAttributes[item.id];
    if (attrs != null) {
      for (final value in attrs.values) {
        if (value.toLowerCase().contains(query)) return true;
      }
    }
    
    return false;
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    _applyFilters();
  }

  void setSelectedCategory(String? category) {
    _selectedCategory = category;
    _applyFilters();
  }

  void setSelectedTag(String? tag) {
    _selectedTag = tag;
    _applyFilters();
  }

  void setSortBy(String sortBy, {bool? ascending}) {
    _sortBy = sortBy;
    if (ascending != null) {
      _sortAscending = ascending;
    }
    _applyFilters();
  }

  // 设置当前空间ID
  void setCurrentSpaceId(String? spaceId) {
    _currentSpaceId = spaceId;
    _applyFilters();
  }

  // 设置特殊空间ID列表
  void setSpecialSpaceIds(List<String> spaceIds) {
    _specialSpaceIds = spaceIds;
    _applyFilters();
  }

  Future<String> addItem({
    required String houseId,
    required String spaceId,
    required String name,
    int quantity = 1,
    String? unit,
    DateTime? productionDate,
    int? shelfLife,
    DateTime? expireDate,
    double? price,
    String? category,
    String? categoryId,
    String? subcategoryId,
    List<String>? tags,
    String? imagePath,
    String? note,
    Map<String, String>? customAttributes,
    String? expireDateSource,
  }) async {
    final now = DateTime.now();
    final id = const Uuid().v4();
    
    debugPrint('[addItem] subcategoryId: $subcategoryId, categoryId: $categoryId');
    
    DateTime? finalExpireDate = expireDate;
    
    if (finalExpireDate == null && productionDate != null && shelfLife != null) {
      finalExpireDate = productionDate.add(Duration(days: shelfLife));
    }
    
    await _db.into(_db.items).insert(ItemsCompanion.insert(
      id: id,
      houseId: houseId,
      spaceId: spaceId,
      name: name,
      quantity: Value(quantity),
      unit: Value(unit ?? '件'),
      price: Value(price),
      expireDate: Value(finalExpireDate),
      category: Value(category),
      categoryId: Value(categoryId),
      subcategoryId: Value(subcategoryId),
      tags: Value(tags?.join(',')),
      imagePath: Value(imagePath),
      note: Value(note),
      customAttributes: Value(expireDateSource),
      creatorId: 'user',
      modifierId: 'user',
      createdAt: now,
      updatedAt: now,
    ));
    
    if (customAttributes != null && customAttributes.isNotEmpty) {
      for (var entry in customAttributes.entries) {
        if (entry.value.isNotEmpty) {
          await _db.into(_db.itemAttributes).insert(ItemAttributesCompanion.insert(
            itemId: id,
            attributeId: entry.key,
            value: Value(entry.value),
          ));
        }
      }
    }
    
    await loadItems(houseId);
    return id;
  }

  Future<void> updateItem(Item item, {Map<String, String>? customAttributes, DateTime? expireDate, String? subcategoryId, String? expireDateSource}) async {
    DateTime? finalExpireDate = expireDate ?? item.expireDate;
    
    debugPrint('[updateItem] subcategoryId param: $subcategoryId, item.subcategoryId: ${item.subcategoryId}');
    debugPrint('[updateItem] item.categoryId: ${item.categoryId}');
    
    await (_db.update(_db.items)..where((t) => t.id.equals(item.id))).write(
      ItemsCompanion(
        spaceId: Value(item.spaceId),
        name: Value(item.name),
        quantity: Value(item.quantity),
        unit: Value(item.unit),
        price: Value(item.price),
        expireDate: Value(finalExpireDate),
        category: Value(item.category),
        categoryId: Value(item.categoryId),
        subcategoryId: Value(subcategoryId ?? item.subcategoryId),
        tags: Value(item.tags),
        imagePath: Value(item.imagePath),
        note: Value(item.note),
        customAttributes: Value(expireDateSource ?? item.customAttributes),
        modifierId: Value('user'),
        updatedAt: Value(DateTime.now()),
      ),
    );
    
    if (customAttributes != null) {
      await (_db.delete(_db.itemAttributes)
            ..where((t) => t.itemId.equals(item.id)))
          .go();
      
      for (var entry in customAttributes.entries) {
        if (entry.value.isNotEmpty) {
          await _db.into(_db.itemAttributes).insert(ItemAttributesCompanion.insert(
            itemId: item.id,
            attributeId: entry.key,
            value: Value(entry.value),
          ));
        }
      }
    }
    
    await loadItems(item.houseId);
  }

  Future<Map<String, String>> getItemAttributes(String itemId) async {
    final rows = await (_db.select(_db.itemAttributes)
          ..where((t) => t.itemId.equals(itemId)))
        .get();
    return {for (var row in rows) row.attributeId: row.value ?? ''};
  }

  Future<void> setItemAttributeValue(String itemId, String attributeId, String value) async {
    final existing = await (_db.select(_db.itemAttributes)
          ..where((t) => t.itemId.equals(itemId) & t.attributeId.equals(attributeId)))
        .getSingleOrNull();
    if (existing != null) {
      await (_db.update(_db.itemAttributes)
            ..where((t) => t.itemId.equals(itemId) & t.attributeId.equals(attributeId)))
          .write(ItemAttributesCompanion(value: Value(value)));
    } else {
      await _db.into(_db.itemAttributes).insert(ItemAttributesCompanion.insert(
            itemId: itemId,
            attributeId: attributeId,
            value: Value(value),
          ));
    }
    // 更新缓存
    _itemAttributes.putIfAbsent(itemId, () => {});
    _itemAttributes[itemId]![attributeId] = value;
    notifyListeners();
  }

  Future<int> getLowStockItemsCount(String houseId) async {
    final items = await (_db.select(_db.items)..where((t) => t.houseId.equals(houseId))).get();
    int count = 0;
    for (final item in items) {
      final attrs = await getItemAttributes(item.id);
      final thresholdStr = attrs['_low_stock_threshold'];
      if (thresholdStr != null && thresholdStr.isNotEmpty) {
        final threshold = int.tryParse(thresholdStr);
        if (threshold != null && item.quantity <= threshold) {
          count++;
        }
      }
    }
    return count;
  }

  Future<void> incrementQuantity(Item item) async {
    await (_db.update(_db.items)..where((t) => t.id.equals(item.id))).write(
      ItemsCompanion(
        quantity: Value(item.quantity + 1),
        modifierId: Value('user'),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await loadItems(item.houseId);
  }

  Future<void> decrementQuantity(Item item) async {
    if (item.quantity <= 1) {
      await moveToTrash(item);
    } else {
      await (_db.update(_db.items)..where((t) => t.id.equals(item.id))).write(
        ItemsCompanion(
          quantity: Value(item.quantity - 1),
          modifierId: Value('user'),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
    await loadItems(item.houseId);
  }

  Future<void> moveToTrash(Item item) async {
    final trashSpace = await (_db.select(_db.spaces)
          ..where((t) =>
              t.houseId.equals(item.houseId) & t.type.equals('trash')))
        .getSingleOrNull();

    if (trashSpace != null) {
      await (_db.update(_db.items)..where((t) => t.id.equals(item.id))).write(
        ItemsCompanion(
          spaceId: Value(trashSpace.id),
          quantity: const Value(1),
          modifierId: Value('user'),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await loadItems(item.houseId);
    }
  }

  Future<void> permanentDeleteItem(Item item) async {
    await (_db.delete(_db.itemAttributes)..where((t) => t.itemId.equals(item.id))).go();
    await (_db.delete(_db.items)..where((t) => t.id.equals(item.id))).go();
    await loadItems(item.houseId);
  }

  Future<void> deleteItem(Item item) async {
    final recycleSpace = await (_db.select(_db.spaces)
          ..where((t) =>
              t.houseId.equals(item.houseId) & t.type.equals('recycle')))
        .getSingleOrNull();

    if (recycleSpace != null) {
      await (_db.update(_db.items)..where((t) => t.id.equals(item.id))).write(
        ItemsCompanion(
          spaceId: Value(recycleSpace.id),
          modifierId: Value('user'),
          updatedAt: Value(DateTime.now()),
        ),
      );
    } else {
      await (_db.delete(_db.items)..where((t) => t.id.equals(item.id))).go();
    }
    await loadItems(item.houseId);
  }

  Future<void> restoreItem(Item item, String targetSpaceId) async {
    await (_db.update(_db.items)..where((t) => t.id.equals(item.id))).write(
      ItemsCompanion(
        spaceId: Value(targetSpaceId),
        modifierId: Value('user'),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await loadItems(item.houseId);
  }

  Future<void> moveItem(Item item, String targetSpaceId, {String? targetHouseId}) async {
    await (_db.update(_db.items)..where((t) => t.id.equals(item.id))).write(
      ItemsCompanion(
        houseId: targetHouseId != null ? Value(targetHouseId) : const Value.absent(),
        spaceId: Value(targetSpaceId),
        modifierId: Value('user'),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await loadItems(item.houseId);
    // 如果移动到其他家庭，也加载目标家庭的物品
    if (targetHouseId != null && targetHouseId != item.houseId) {
      await loadItems(targetHouseId);
    }
  }

  /// 获取单个物品的最新信息
  Future<Item?> getItemById(String itemId) async {
    final items = await (_db.select(_db.items)
          ..where((t) => t.id.equals(itemId)))
        .get();
    return items.firstOrNull;
  }

  List<Item> getExpiredItems(String houseId) {
    final now = DateTime.now();
    return _items
        .where((item) =>
            item.houseId == houseId &&
            item.expireDate != null &&
            item.expireDate!.isBefore(now) &&
            item.customAttributes != 'warranty')
        .toList();
  }

  List<Item> getExpiringItems(String houseId, int days) {
    final now = DateTime.now();
    final threshold = now.add(Duration(days: days));
    return _items
        .where((item) =>
            item.houseId == houseId &&
            item.expireDate != null &&
            item.expireDate!.isAfter(now) &&
            item.expireDate!.isBefore(threshold) &&
            item.customAttributes != 'warranty')
        .toList();
  }
}
