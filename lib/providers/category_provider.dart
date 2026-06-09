import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../database/database.dart' as db;

class CategoryProvider extends ChangeNotifier {
  List<db.Category> _categories = [];
  List<db.Subcategory> _subcategories = [];
  final db.AppDatabase _db;

  CategoryProvider(this._db);

  List<db.Category> get categories => _categories;
  List<db.Subcategory> get subcategories => _subcategories;

  Future<void> loadCategories() async {
    _categories = await (_db.select(_db.categories)
            ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
    await loadAllSubcategories();
    notifyListeners();
  }

  Future<bool> isCategoryNameExists(String name, {String? excludeId}) async {
    final query = _db.select(_db.categories)
      ..where((t) => t.name.equals(name));
    final results = await query.get();
    if (excludeId != null) {
      return results.any((c) => c.id != excludeId);
    }
    return results.isNotEmpty;
  }

  static const List<String> defaultCategoryNames = [
    '食品', '药品', '美妆', '日用品', '数码', '其他'
  ];

  bool isDefaultCategory(String? categoryName) {
    return categoryName != null && defaultCategoryNames.contains(categoryName);
  }

  Future<void> addCategory({
    required String houseId,
    required String name,
    String? icon,
    String? categoryType,
  }) async {
    if (await isCategoryNameExists(name)) {
      return;
    }

    final id = const Uuid().v4();
    final maxOrder = _categories.isEmpty
        ? 0
        : _categories.map((c) => c.sortOrder).reduce((a, b) => a > b ? a : b);
    await _db.into(_db.categories).insert(db.CategoriesCompanion.insert(
          id: id,
          houseId: houseId,
          name: name,
          icon: Value(icon),
          sortOrder: Value(maxOrder + 1),
          createdAt: DateTime.now(),
        ));
    await loadCategories();

    if (categoryType != null) {
      await _createDefaultAttributes(houseId, id, categoryType);
    }
  }

  Future<void> _createDefaultAttributes(
      String houseId, String categoryId, String categoryType) async {
    final attributeConfigs = _getDefaultAttributeConfigs(categoryType);
    for (int i = 0; i < attributeConfigs.length; i++) {
      final config = attributeConfigs[i];
      String? existingAttrId;
      final existingAttrs = await (_db.select(_db.attributes)
            ..where((t) => t.name.equals(config['name']!)))
          .get();
      if (existingAttrs.isNotEmpty) {
        existingAttrId = existingAttrs.first.id;
      }

      String attrId;
      if (existingAttrId != null) {
        attrId = existingAttrId;
      } else {
        attrId = const Uuid().v4();
        await _db.into(_db.attributes).insert(db.AttributesCompanion.insert(
              id: attrId,
              houseId: houseId,
              name: config['name']!,
              type: config['type']!,
              hint: Value(config['hint']),
              options: Value(config['options']),
              required: Value(config['required'] ?? false),
              sortOrder: Value(i),
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ));
      }

      final existingLink = await (_db.select(_db.categoryAttributes)
            ..where((t) => t.categoryId.equals(categoryId) & t.attributeId.equals(attrId)))
          .get();
      if (existingLink.isEmpty) {
        await _db.into(_db.categoryAttributes).insert(
          db.CategoryAttributesCompanion.insert(
            categoryId: categoryId,
            attributeId: attrId,
            sortOrder: Value(i),
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> _getDefaultAttributeConfigs(String categoryType) {
    switch (categoryType) {
      case 'food':
        return [
          {'name': '品牌', 'type': 'text', 'hint': null, 'options': null, 'required': false},
          {'name': '颜色', 'type': 'text', 'hint': null, 'options': null, 'required': false},
          {'name': '储存方式', 'type': 'text', 'hint': null, 'options': null, 'required': false},
          {'name': '生产日期', 'type': 'date', 'hint': null, 'options': null, 'required': false},
          {'name': '保质期', 'type': 'shelf_life', 'hint': null, 'options': '天;月;年', 'required': false},
          {'name': '过期日期', 'type': 'date', 'hint': null, 'options': null, 'required': false},
          {'name': '开封日期', 'type': 'date', 'hint': null, 'options': null, 'required': false},
          {'name': '条形码', 'type': 'text', 'hint': null, 'options': null, 'required': false},
        ];
      case 'medicine':
        return [
          {'name': '品牌', 'type': 'text', 'hint': null, 'options': null, 'required': false},
          {'name': '颜色', 'type': 'text', 'hint': null, 'options': null, 'required': false},
          {'name': '储存方式', 'type': 'text', 'hint': null, 'options': null, 'required': false},
          {'name': '生产日期', 'type': 'date', 'hint': null, 'options': null, 'required': false},
          {'name': '保质期', 'type': 'shelf_life', 'hint': null, 'options': '天;月;年', 'required': false},
          {'name': '过期日期', 'type': 'date', 'hint': null, 'options': null, 'required': false},
          {'name': '开封日期', 'type': 'date', 'hint': null, 'options': null, 'required': false},
          {'name': '条形码', 'type': 'text', 'hint': null, 'options': null, 'required': false},
        ];
      case 'cosmetics':
        return [
          {'name': '品牌', 'type': 'text', 'hint': null, 'options': null, 'required': false},
          {'name': '颜色', 'type': 'text', 'hint': null, 'options': null, 'required': false},
          {'name': '储存方式', 'type': 'text', 'hint': null, 'options': null, 'required': false},
          {'name': '生产日期', 'type': 'date', 'hint': null, 'options': null, 'required': false},
          {'name': '保质期', 'type': 'shelf_life', 'hint': null, 'options': '天;月;年', 'required': false},
          {'name': '过期日期', 'type': 'date', 'hint': null, 'options': null, 'required': false},
          {'name': '开封日期', 'type': 'date', 'hint': null, 'options': null, 'required': false},
          {'name': '条形码', 'type': 'text', 'hint': null, 'options': null, 'required': false},
        ];
      case 'daily':
        return [
          {'name': '品牌', 'type': 'text', 'hint': null, 'options': null, 'required': false},
          {'name': '颜色', 'type': 'text', 'hint': null, 'options': null, 'required': false},
          {'name': '条形码', 'type': 'text', 'hint': null, 'options': null, 'required': false},
        ];
      case 'digital':
        return [
          {'name': '品牌', 'type': 'text', 'hint': null, 'options': null, 'required': false},
          {'name': '颜色', 'type': 'text', 'hint': null, 'options': null, 'required': false},
          {'name': '购买日期', 'type': 'date', 'hint': null, 'options': null, 'required': false},
          {'name': '保修期', 'type': 'warranty', 'hint': null, 'options': '天;月;年', 'required': false},
          {'name': '过保日期', 'type': 'date', 'hint': null, 'options': null, 'required': false},
          {'name': '条形码', 'type': 'text', 'hint': null, 'options': null, 'required': false},
        ];
      case 'other':
        return [
          {'name': '品牌', 'type': 'text', 'hint': null, 'options': null, 'required': false},
          {'name': '颜色', 'type': 'text', 'hint': null, 'options': null, 'required': false},
          {'name': '条形码', 'type': 'text', 'hint': null, 'options': null, 'required': false},
        ];
      default:
        return [];
    }
  }

  Future<void> addCategoryWithType({
    required String houseId,
    required String name,
    required String categoryType,
    String? icon,
  }) async {
    final id = const Uuid().v4();
    final maxOrder = _categories.isEmpty
        ? 0
        : _categories.map((c) => c.sortOrder).reduce((a, b) => a > b ? a : b);
    await _db.into(_db.categories).insert(db.CategoriesCompanion.insert(
          id: id,
          houseId: houseId,
          name: name,
          icon: Value(icon),
          sortOrder: Value(maxOrder + 1),
          createdAt: DateTime.now(),
        ));
    await loadCategories();
    await _createDefaultAttributes(houseId, id, categoryType);
  }

  Future<void> updateCategory(db.Category category, String newName, {String? newIcon}) async {
    if (await isCategoryNameExists(newName, excludeId: category.id)) {
      return;
    }
    await (_db.update(_db.categories)
            ..where((t) => t.id.equals(category.id)))
        .write(db.CategoriesCompanion(
          name: Value(newName),
          icon: newIcon != null ? Value(newIcon) : const Value.absent(),
        ));
    await loadCategories();
  }

  Future<void> updateCategoryIcon(db.Category category, String? newIcon) async {
    await (_db.update(_db.categories)
            ..where((t) => t.id.equals(category.id)))
        .write(db.CategoriesCompanion(icon: Value(newIcon)));
    await loadCategories();
  }

  Future<void> deleteCategory(db.Category category) async {
    // Find the "其他" category
    final otherCategories = await (_db.select(_db.categories)
          ..where((t) => t.name.equals('其他')))
        .get();
    final otherCategory = otherCategories.isNotEmpty ? otherCategories.first : null;

    // Migrate items to "其他" category
    if (otherCategory != null) {
      final items = await (_db.select(_db.items)
            ..where((t) => t.categoryId.equals(category.id)))
          .get();
      for (final item in items) {
        await (_db.update(_db.items)..where((t) => t.id.equals(item.id))).write(
          db.ItemsCompanion(
            category: Value('其他'),
            categoryId: Value(otherCategory.id),
            subcategoryId: const Value(null),
          ),
        );
      }
    }

    // Delete subcategories
    await (_db.delete(_db.subcategories)..where((t) => t.categoryId.equals(category.id))).go();
    // Delete category-attribute associations
    await (_db.delete(_db.categoryAttributes)..where((t) => t.categoryId.equals(category.id))).go();
    // Delete the category
    await (_db.delete(_db.categories)..where((t) => t.id.equals(category.id))).go();
    await loadCategories();
  }

  Future<bool> isCategoryUsedByItems(String categoryId) async {
    final items = await (_db.select(_db.items)
          ..where((t) => t.categoryId.equals(categoryId)))
        .get();
    return items.isNotEmpty;
  }

  Future<void> reorderCategories(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = _categories.removeAt(oldIndex);
    _categories.insert(newIndex, item);

    for (int i = 0; i < _categories.length; i++) {
      await (_db.update(_db.categories)
              ..where((t) => t.id.equals(_categories[i].id)))
          .write(db.CategoriesCompanion(sortOrder: Value(i)));
    }
    notifyListeners();
  }

  Future<void> loadSubcategories(String categoryId) async {
    final newSubcategories = await (_db.select(_db.subcategories)
            ..where((t) => t.categoryId.equals(categoryId))
            ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
    _subcategories = _subcategories
        .where((s) => s.categoryId != categoryId)
        .followedBy(newSubcategories)
        .toList();
    notifyListeners();
  }

  Future<void> loadAllSubcategories() async {
    final categoryIds = _categories.map((c) => c.id).toList();
    if (categoryIds.isEmpty) {
      _subcategories = [];
      notifyListeners();
      return;
    }
    _subcategories = await (_db.select(_db.subcategories)
            ..where((t) => t.categoryId.isIn(categoryIds))
            ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
    notifyListeners();
  }

  List<db.Subcategory> getSubcategoriesForCategory(String categoryId) {
    return _subcategories.where((s) => s.categoryId == categoryId).toList();
  }

  Future<bool> isSubcategoryNameExists(String categoryId, String name, {String? excludeId}) async {
    final query = _db.select(_db.subcategories)
      ..where((t) => t.categoryId.equals(categoryId) & t.name.equals(name));
    final results = await query.get();
    if (excludeId != null) {
      return results.any((s) => s.id != excludeId);
    }
    return results.isNotEmpty;
  }

  Future<void> addSubcategory({
    required String categoryId,
    required String name,
  }) async {
    if (await isSubcategoryNameExists(categoryId, name)) {
      return;
    }

    final existingSubcategories = await (_db.select(_db.subcategories)
            ..where((t) => t.categoryId.equals(categoryId)))
        .get();
    final maxOrder = existingSubcategories.isEmpty
        ? 0
        : existingSubcategories.map((s) => s.sortOrder).reduce((a, b) => a > b ? a : b);

    final id = const Uuid().v4();
    await _db.into(_db.subcategories).insert(db.SubcategoriesCompanion.insert(
          id: id,
          categoryId: categoryId,
          name: name,
          sortOrder: Value(maxOrder + 1),
          createdAt: DateTime.now(),
        ));
    await loadSubcategories(categoryId);
  }

  Future<void> updateSubcategory(db.Subcategory subcategory, String newName) async {
    if (await isSubcategoryNameExists(subcategory.categoryId, newName, excludeId: subcategory.id)) {
      return;
    }
    await (_db.update(_db.subcategories)
            ..where((t) => t.id.equals(subcategory.id)))
        .write(db.SubcategoriesCompanion(name: Value(newName)));
    await loadSubcategories(subcategory.categoryId);
  }

  Future<void> deleteSubcategory(db.Subcategory subcategory) async {
    await (_db.delete(_db.subcategories)..where((t) => t.id.equals(subcategory.id))).go();
    await loadSubcategories(subcategory.categoryId);
  }

  Future<void> reorderSubcategories(int oldIndex, int newIndex, String categoryId) async {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = _subcategories.removeAt(oldIndex);
    _subcategories.insert(newIndex, item);

    for (int i = 0; i < _subcategories.length; i++) {
      await (_db.update(_db.subcategories)
              ..where((t) => t.id.equals(_subcategories[i].id)))
          .write(db.SubcategoriesCompanion(sortOrder: Value(i)));
    }
    notifyListeners();
  }
}
