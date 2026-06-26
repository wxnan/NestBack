import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart';

class ImportExportService {
  final AppDatabase _db;
  static const _version = '1.0';
  static const _appName = 'nestback';

  ImportExportService(this._db);

  Future<String> exportToJson(String houseId) async {
    final house = await (_db.select(_db.houses)
          ..where((t) => t.id.equals(houseId)))
        .getSingleOrNull();
    if (house == null) throw Exception('家庭不存在');

    final spaces = await (_db.select(_db.spaces)
          ..where((t) => t.houseId.equals(houseId)))
        .get();
    final items = await (_db.select(_db.items)
          ..where((t) => t.houseId.equals(houseId)))
        .get();
    final categories = await (_db.select(_db.categories)
          ..where((t) => t.houseId.equals(houseId)))
        .get();
    final tags = await (_db.select(_db.tags)
          ..where((t) => t.houseId.equals(houseId)))
        .get();
    final attributes = await (_db.select(_db.attributes)
          ..where((t) => t.houseId.equals(houseId)))
        .get();

    final subcategoryIds = categories.map((c) => c.id).toList();
    final subcategories = await (_db.select(_db.subcategories)
          ..where((t) => t.categoryId.isIn(subcategoryIds)))
        .get();

    final categoryAttrs = await (_db.select(_db.categoryAttributes)).get();
    final filteredCategoryAttrs = categoryAttrs
        .where((ca) => categories.any((c) => c.id == ca.categoryId))
        .toList();

    final itemIds = items.map((i) => i.id).toList();
    final itemAttrs = itemIds.isEmpty
        ? <ItemAttribute>[]
        : await (_db.select(_db.itemAttributes)
              ..where((t) => t.itemId.isIn(itemIds)))
            .get();

    final data = {
      'meta': {
        'version': _version,
        'app': _appName,
        'exportedAt': DateTime.now().toIso8601String(),
        'type': 'json',
      },
      'house': _houseToMap(house),
      'spaces': spaces.map(_spaceToMap).toList(),
      'items': items.map(_itemToMap).toList(),
      'categories': categories.map(_categoryToMap).toList(),
      'subcategories': subcategories.map(_subcategoryToMap).toList(),
      'tags': tags.map(_tagToMap).toList(),
      'attributes': attributes.map(_attributeToMap).toList(),
      'categoryAttributes': filteredCategoryAttrs.map(_categoryAttributeToMap).toList(),
      'itemAttributes': itemAttrs.map(_itemAttributeToMap).toList(),
    };

    final dir = await getTemporaryDirectory();
    final timestamp = _formatTimestamp(DateTime.now());
    final file = File(p.join(dir.path, 'nestback_export_$timestamp.json'));
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    return file.path;
  }

  Future<ImportResult> importFromJson(String filePath, String targetHouseId) async {
    final file = File(filePath);
    if (!await file.exists()) throw Exception('文件不存在');

    final content = await file.readAsString();
    final data = jsonDecode(content) as Map<String, dynamic>;

    final meta = data['meta'] as Map<String, dynamic>?;
    if (meta == null || meta['app'] != _appName) {
      throw Exception('无效的归巢导出文件');
    }

    return await _db.transaction(() async {
      final idMapping = <String, String>{};
      final now = DateTime.now();

      await _importSpaces(data, targetHouseId, idMapping, now);

      await _importCategories(data, targetHouseId, idMapping, now);

      await _importSubcategories(data, idMapping, now);

      await _importTags(data, targetHouseId, idMapping, now);

      await _importAttributes(data, targetHouseId, idMapping, now);

      await _importCategoryAttributes(data, idMapping);

      final importResult = await _importItems(data, targetHouseId, idMapping, now);

      return ImportResult(
        success: true,
        houseId: targetHouseId,
        houseName: '',
        itemCount: importResult.itemCount,
        spaceCount: importResult.spaceCount,
        message: '成功导入 ${importResult.itemCount} 个物品',
        idMapping: idMapping,
      );
    });
  }

  Future<void> _importSpaces(Map<String, dynamic> data, String houseId,
      Map<String, String> idMapping, DateTime now) async {
    final existingSpaces = await (_db.select(_db.spaces)
          ..where((t) => t.houseId.equals(houseId)))
        .get();
    final processedNames = <String, String>{};
    for (var s in existingSpaces) {
      processedNames[s.name] = s.id;
    }

    final spacesData = (data['spaces'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

    for (final s in spacesData) {
      final oldId = s['id'] as String;
      final name = s['name'] as String;
      final parentId = s['parentId'] as String?;

      if (processedNames.containsKey(name)) {
        idMapping[oldId] = processedNames[name]!;
        continue;
      }

      final newId = const Uuid().v4();
      idMapping[oldId] = newId;
      processedNames[name] = newId;

      String? mappedParentId;
      if (parentId != null) {
        mappedParentId = idMapping[parentId];
      }

      await _db.into(_db.spaces).insert(SpacesCompanion.insert(
        id: newId,
        houseId: houseId,
        name: name,
        icon: Value(s['icon'] as String?),
        imagePath: Value(s['imagePath'] as String?),
        parentId: Value(mappedParentId),
        type: s['type'] as String,
        position: Value(s['position'] as String?),
        defaultCategoryId: Value(s['defaultCategoryId'] as String?),
        createdAt: _parseDateTime(s['createdAt']) ?? now,
        updatedAt: now,
      ));
    }
  }

  Future<void> _importCategories(Map<String, dynamic> data, String houseId,
      Map<String, String> idMapping, DateTime now) async {
    // 全局共享分类，不加 houseId 过滤
    final existingCategories = await (_db.select(_db.categories)).get();
    final processedNames = <String, String>{};
    for (var c in existingCategories) {
      processedNames[c.name] = c.id;
    }

    final categoriesData = (data['categories'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

    for (final c in categoriesData) {
      final oldId = c['id'] as String;
      final name = c['name'] as String;

      if (processedNames.containsKey(name)) {
        idMapping[oldId] = processedNames[name]!;
        continue;
      }

      final newId = const Uuid().v4();
      idMapping[oldId] = newId;
      processedNames[name] = newId;

      await _db.into(_db.categories).insert(CategoriesCompanion.insert(
        id: newId,
        houseId: houseId,
        name: name,
        icon: Value(c['icon'] as String?),
        sortOrder: Value(c['sortOrder'] as int? ?? 0),
        createdAt: _parseDateTime(c['createdAt']) ?? now,
      ),
        mode: InsertMode.insertOrIgnore,
      );
    }
  }

  Future<void> _importSubcategories(Map<String, dynamic> data, 
      Map<String, String> idMapping, DateTime now) async {
    final subcategoriesData = (data['subcategories'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    
    for (final sc in subcategoriesData) {
      final oldId = sc['id'] as String;
      final oldCategoryId = sc['categoryId'] as String;
      final name = sc['name'] as String;

      final newCategoryId = idMapping[oldCategoryId];
      if (newCategoryId == null) continue;

      final existingSubcategories = await (_db.select(_db.subcategories)
            ..where((t) => t.categoryId.equals(newCategoryId) & t.name.equals(name)))
          .get();
      
      if (existingSubcategories.isNotEmpty) {
        idMapping[oldId] = existingSubcategories.first.id;
        continue;
      }

      final newId = const Uuid().v4();
      idMapping[oldId] = newId;

      await _db.into(_db.subcategories).insert(SubcategoriesCompanion.insert(
        id: newId,
        categoryId: newCategoryId,
        name: name,
        sortOrder: Value(sc['sortOrder'] as int? ?? 0),
        createdAt: _parseDateTime(sc['createdAt']) ?? now,
      ),
        mode: InsertMode.insertOrIgnore,
      );
    }
  }

  Future<void> _importTags(Map<String, dynamic> data, String houseId,
      Map<String, String> idMapping, DateTime now) async {
    // 全局共享标签，不加 houseId 过滤
    final existingTags = await (_db.select(_db.tags)).get();
    final processedNames = <String, String>{};
    for (var t in existingTags) {
      processedNames[t.name] = t.id;
    }

    final tagsData = (data['tags'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

    for (final t in tagsData) {
      final oldId = t['id'] as String;
      final name = t['name'] as String;

      if (processedNames.containsKey(name)) {
        idMapping[oldId] = processedNames[name]!;
        continue;
      }

      final newId = const Uuid().v4();
      idMapping[oldId] = newId;
      processedNames[name] = newId;

      await _db.into(_db.tags).insert(TagsCompanion.insert(
        id: newId,
        houseId: houseId,
        name: name,
        sortOrder: Value(t['sortOrder'] as int? ?? 0),
        createdAt: _parseDateTime(t['createdAt']) ?? now,
      ),
        mode: InsertMode.insertOrIgnore,
      );
    }
  }

  Future<void> _importAttributes(Map<String, dynamic> data, String houseId,
      Map<String, String> idMapping, DateTime now) async {
    // 全局共享属性，不加 houseId 过滤
    final existingAttributes = await (_db.select(_db.attributes)).get();
    final processedNames = <String, String>{};
    for (var a in existingAttributes) {
      processedNames[a.name] = a.id;
    }

    final attributesData = (data['attributes'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

    for (final a in attributesData) {
      final oldId = a['id'] as String;
      final name = a['name'] as String;

      if (processedNames.containsKey(name)) {
        idMapping[oldId] = processedNames[name]!;
        continue;
      }

      final newId = const Uuid().v4();
      idMapping[oldId] = newId;
      processedNames[name] = newId;

      await _db.into(_db.attributes).insert(AttributesCompanion.insert(
        id: newId,
        houseId: houseId,
        name: name,
        type: a['type'] as String,
        hint: Value(a['hint'] as String?),
        options: Value(a['options'] as String?),
        required: Value(a['required'] as bool? ?? false),
        sortOrder: Value(a['sortOrder'] as int? ?? 0),
        createdAt: _parseDateTime(a['createdAt']) ?? now,
        updatedAt: now,
      ),
        mode: InsertMode.insertOrIgnore,
      );
    }
  }

  Future<void> _importCategoryAttributes(Map<String, dynamic> data, Map<String, String> idMapping) async {
    final categoryAttrsData = (data['categoryAttributes'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    
    for (final ca in categoryAttrsData) {
      final oldCategoryId = ca['categoryId'] as String;
      final oldAttributeId = ca['attributeId'] as String;
      final newCategoryId = idMapping[oldCategoryId];
      final newAttributeId = idMapping[oldAttributeId];

      if (newCategoryId == null || newAttributeId == null) continue;

      final existingLink = await (_db.select(_db.categoryAttributes)
            ..where((t) => t.categoryId.equals(newCategoryId) & t.attributeId.equals(newAttributeId)))
          .get();
      
      if (existingLink.isNotEmpty) continue;

      await _db.into(_db.categoryAttributes).insert(CategoryAttributesCompanion.insert(
        categoryId: newCategoryId,
        attributeId: newAttributeId,
        sortOrder: Value(ca['sortOrder'] as int? ?? 0),
      ));
    }
  }

  Future<({int itemCount, int spaceCount})> _importItems(Map<String, dynamic> data, 
      String houseId, Map<String, String> idMapping, DateTime now) async {
    final itemsData = (data['items'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    
    final pendingSpace = await (_db.select(_db.spaces)
          ..where((t) => t.houseId.equals(houseId) & t.type.equals('pending')))
        .getSingleOrNull();
    final pendingSpaceId = pendingSpace?.id ?? '';

    int itemCount = 0;
    int spaceCount = 0;

    for (final i in itemsData) {
      final oldId = i['id'] as String;
      final name = i['name'] as String;
      final oldSpaceId = i['spaceId'] as String?;
      final oldCategoryId = i['categoryId'] as String?;
      final oldSubcategoryId = i['subcategoryId'] as String?;

      final mappedSpaceId = oldSpaceId != null ? idMapping[oldSpaceId] ?? pendingSpaceId : pendingSpaceId;
      final mappedCategoryId = oldCategoryId != null ? idMapping[oldCategoryId] : null;
      final mappedSubcategoryId = oldSubcategoryId != null ? idMapping[oldSubcategoryId] : null;

      // 使用导出文件中的原物品 ID 作为新记录 ID，并以 insertOrReplace 写入。
      // 这样同名但不同 ID 的物品（如复制出来的物品）都会被保留；
      // 重复导入同一份备份时也不会产生重复记录，而是覆盖更新。
      final newItemId = oldId;
      await _db.into(_db.items).insert(
        ItemsCompanion.insert(
          id: newItemId,
          houseId: houseId,
          spaceId: mappedSpaceId,
          name: name,
          quantity: Value(i['quantity'] as int? ?? 1),
          unit: Value(i['unit'] as String? ?? '件'),
          price: Value(i['price'] as double?),
          productionDate: Value(_parseDateTime(i['productionDate'])),
          shelfLife: Value(i['shelfLife'] as int?),
          expireDate: Value(_parseDateTime(i['expireDate'])),
          category: Value(i['category'] as String?),
          categoryId: Value(mappedCategoryId),
          subcategoryId: Value(mappedSubcategoryId),
          tags: Value(i['tags'] as String?),
          imagePath: Value(i['imagePath'] as String?),
          note: Value(i['note'] as String?),
          customAttributes: Value(i['customAttributes'] as String?),
          creatorId: i['creatorId'] as String? ?? 'user',
          modifierId: i['modifierId'] as String? ?? 'user',
          createdAt: _parseDateTime(i['createdAt']) ?? now,
          updatedAt: now,
        ),
        mode: InsertMode.insertOrReplace,
      );
      itemCount++;

      idMapping[oldId] = newItemId;
    }

    final itemAttrsData = (data['itemAttributes'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    for (final ia in itemAttrsData) {
      final oldItemId = ia['itemId'] as String;
      final oldAttributeId = ia['attributeId'] as String;
      final newItemId = idMapping[oldItemId];
      if (newItemId == null) continue;

      // 统一解析 attributeId（内部属性保持原样，自定义属性映射到新ID）
      final String resolvedAttributeId;
      if (oldAttributeId.startsWith('_')) {
        resolvedAttributeId = oldAttributeId;
      } else {
        final mapped = idMapping[oldAttributeId];
        if (mapped == null) continue;
        resolvedAttributeId = mapped;
      }

      final existingItemAttr = await (_db.select(_db.itemAttributes)
            ..where((t) => t.itemId.equals(newItemId) & t.attributeId.equals(resolvedAttributeId)))
          .get();

      if (existingItemAttr.isNotEmpty) {
        await (_db.update(_db.itemAttributes)
              ..where((t) => t.itemId.equals(newItemId) & t.attributeId.equals(resolvedAttributeId)))
            .write(ItemAttributesCompanion(
              value: Value(ia['value'] as String?),
            ));
        continue;
      }

      await _db.into(_db.itemAttributes).insert(ItemAttributesCompanion.insert(
        itemId: newItemId,
        attributeId: resolvedAttributeId,
        value: Value(ia['value'] as String?),
      ));
    }

    return (itemCount: itemCount, spaceCount: spaceCount);
  }

  Future<String> exportToCsv(String houseId) async {
    final house = await (_db.select(_db.houses)
          ..where((t) => t.id.equals(houseId)))
        .getSingleOrNull();
    if (house == null) throw Exception('家庭不存在');

    final items = await (_db.select(_db.items)
          ..where((t) => t.houseId.equals(houseId)))
        .get();
    final spaces = await (_db.select(_db.spaces)
          ..where((t) => t.houseId.equals(houseId)))
        .get();
    final categories = await (_db.select(_db.categories)
          ..where((t) => t.houseId.equals(houseId)))
        .get();
    final attributes = await (_db.select(_db.attributes)
          ..where((t) => t.houseId.equals(houseId)))
        .get();

    final subcategoryIds = categories.map((c) => c.id).toList();
    final subcategories = subcategoryIds.isEmpty
        ? <Subcategory>[]
        : await (_db.select(_db.subcategories)
              ..where((t) => t.categoryId.isIn(subcategoryIds)))
            .get();

    final itemIds = items.map((i) => i.id).toList();
    final itemAttrs = itemIds.isEmpty
        ? <ItemAttribute>[]
        : await (_db.select(_db.itemAttributes)
              ..where((t) => t.itemId.isIn(itemIds)))
            .get();

    final spaceMap = {for (var s in spaces) s.id: s};
    final categoryMap = {for (var c in categories) c.id: c};
    final subcategoryMap = {for (var sc in subcategories) sc.id: sc};
    final attrMap = {for (var a in attributes) a.id: a};

    final itemAttrValues = <String, Map<String, String>>{};
    final lowStockThresholds = <String, String>{};
    for (final ia in itemAttrs) {
      if (ia.attributeId == '_low_stock_threshold' && ia.value != null && ia.value!.isNotEmpty) {
        lowStockThresholds[ia.itemId] = ia.value!;
        continue;
      }
      final attrName = attrMap[ia.attributeId]?.name;
      if (attrName != null && ia.value != null && ia.value!.isNotEmpty) {
        itemAttrValues.putIfAbsent(ia.itemId, () => {});
        itemAttrValues[ia.itemId]![attrName] = ia.value!;
      }
    }

    String getSpacePath(String? spaceId) {
      if (spaceId == null) return '';
      final space = spaceMap[spaceId];
      if (space == null) return '';
      final parts = <String>[];
      Space? current = space;
      while (current != null) {
        parts.insert(0, current.name);
        if (current.parentId != null) {
          current = spaceMap[current.parentId];
        } else {
          current = null;
        }
      }
      return parts.join(' > ');
    }

    final sortedAttrs = attributes.toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final attrNames = sortedAttrs.map((a) => a.name).toList();

    final systemHeaderNames = {'备注', '创建时间', '更新时间'};
    final csvAttrNames = attrNames.where((name) => !systemHeaderNames.contains(name)).toList();

    final baseHeaders = [
      '名称', '数量', '单位', '单价', '总价', '分类', '二级分类', '位置', '标签', '最低库存阈值',
    ];
    final extendedHeaders = csvAttrNames;
    final systemHeaders = ['备注', '创建时间', '更新时间'];
    final allHeaders = [...baseHeaders, ...extendedHeaders, ...systemHeaders];

    final rows = <List<String>>[];
    rows.add(allHeaders);

    for (final item in items) {
      final categoryName = item.category ?? (item.categoryId != null ? categoryMap[item.categoryId]?.name ?? '' : '');
      final subcategoryName = item.subcategoryId != null ? subcategoryMap[item.subcategoryId]?.name ?? '' : '';
      final attrs = itemAttrValues[item.id] ?? {};
      final isWarranty = item.customAttributes == 'warranty';

      final baseRow = [
        item.name,
        item.quantity.toString(),
        item.unit,
        item.price?.toStringAsFixed(2) ?? '',
        item.price != null ? (item.price! * item.quantity).toStringAsFixed(2) : '',
        categoryName,
        subcategoryName,
        getSpacePath(item.spaceId),
        item.tags ?? '',
        lowStockThresholds[item.id] ?? '',
      ];

      final extendedRow = <String>[];
      for (final dbName in csvAttrNames) {
        if (dbName == '过期日期') {
          if (isWarranty) {
            extendedRow.add(attrs['过期日期'] ?? '');
          } else {
            extendedRow.add(_formatDate(item.expireDate));
          }
        } else if (dbName == '过保日期') {
          if (isWarranty) {
            extendedRow.add(_formatDate(item.expireDate));
          } else {
            extendedRow.add(attrs['过保日期'] ?? '');
          }
        } else if (dbName == '生产日期') {
          extendedRow.add(attrs['生产日期'] ?? _formatDate(item.productionDate));
        } else if (dbName == '保质期') {
          extendedRow.add(attrs['保质期'] ?? (item.shelfLife?.toString() ?? ''));
        } else {
          extendedRow.add(attrs[dbName] ?? '');
        }
      }

      final systemRow = [
        item.note ?? '',
        _formatDateTime(item.createdAt),
        _formatDateTime(item.updatedAt),
      ];

      rows.add([...baseRow, ...extendedRow, ...systemRow]);
    }

    final csvString = const ListToCsvConverter().convert(rows);
    final dir = await getTemporaryDirectory();
    final timestamp = _formatTimestamp(DateTime.now());
    final file = File(p.join(dir.path, 'nestback_export_$timestamp.csv'));

    final bom = utf8.encode('\ufeff');
    final csvBytes = utf8.encode(csvString);
    await file.writeAsBytes([...bom, ...csvBytes]);
    return file.path;
  }

  Future<ImportResult> importFromCsv(String filePath, String houseId) async {
    final file = File(filePath);
    if (!await file.exists()) throw Exception('文件不存在');

    var bytes = await file.readAsBytes();
    var content = utf8.decode(bytes);
    if (content.startsWith('\ufeff')) {
      content = content.substring(1);
    }

    final rows = const CsvToListConverter().convert(content);
    if (rows.isEmpty) throw Exception('CSV文件为空');

    final header = rows.first.map((e) => e.toString()).toList();
    final nameIdx = _findIndex(header, '名称');
    final quantityIdx = _findIndex(header, '数量');
    final unitIdx = _findIndex(header, '单位');
    final priceIdx = _findIndex(header, '单价');
    final categoryIdx = _findIndex(header, '分类');
    final subcategoryIdx = _findIndex(header, '二级分类');
    final spaceIdx = _findIndex(header, '位置');
    final tagsIdx = _findIndex(header, '标签');
    final lowStockIdx = _findIndex(header, '最低库存阈值') != -1
        ? _findIndex(header, '最低库存阈值')
        : _findIndex(header, '最低库存提醒');
    final noteIdx = _findIndex(header, '备注');

    if (nameIdx == -1) throw Exception('CSV缺少"名称"列');

    return await _db.transaction(() async {
      final spaces = await (_db.select(_db.spaces)
            ..where((t) => t.houseId.equals(houseId)))
          .get();
      final pendingSpace = spaces.firstWhere(
        (s) => s.type == 'pending',
        orElse: () => spaces.first,
      );

      // 全局共享分类，不加 houseId 过滤
      final categories = await (_db.select(_db.categories)).get();
      final categoryNameMap = {for (var c in categories) c.name: c};

      final existingSubcategories = await (_db.select(_db.subcategories)).get();
      final subcategoryNameMap = <String, Map<String, Subcategory>>{};
      for (final sc in existingSubcategories) {
        subcategoryNameMap.putIfAbsent(sc.categoryId, () => {});
        subcategoryNameMap[sc.categoryId]![sc.name] = sc;
      }

      // 全局共享属性，不加 houseId 过滤
      final existingAttributes = await (_db.select(_db.attributes)).get();
      final attrNameToId = {for (var a in existingAttributes) a.name: a.id};

      final baseHeaderNames = {
        '名称', '数量', '单位', '单价', '总价', '分类', '二级分类', '位置', '标签', '最低库存阈值',
        '备注', '创建时间', '更新时间',
      };

      final extendedAttrNames = <String>[];
      for (final h in header) {
        final trimmed = h.trim();
        if (!baseHeaderNames.contains(trimmed) && trimmed.isNotEmpty) {
          extendedAttrNames.add(trimmed);
        }
      }

      int itemCount = 0;
      final now = DateTime.now();

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        final name = _getCellValue(row, nameIdx).trim();
        if (name.isEmpty) continue;

        final quantityStr = _getCellValue(row, quantityIdx);
        final quantity = int.tryParse(quantityStr) ?? 1;
        final unit = _getCellValue(row, unitIdx);
        final priceStr = _getCellValue(row, priceIdx);
        final price = double.tryParse(priceStr);
        final categoryName = _getCellValue(row, categoryIdx).trim();
        final spacePath = _getCellValue(row, spaceIdx);
        final tagsStr = _getCellValue(row, tagsIdx);
        final note = _getCellValue(row, noteIdx);

        String spaceId = pendingSpace.id;
        if (spacePath.isNotEmpty) {
          final pathParts = spacePath.split('>').map((e) => e.trim()).toList();
          String? parentId;
          for (final partName in pathParts) {
            final existingSpace = spaces.firstWhere(
              (s) => s.name == partName && s.houseId == houseId && s.parentId == parentId,
              orElse: () => spaces.firstWhere((s) => false, orElse: () => pendingSpace),
            );
            if (existingSpace.name == partName) {
              spaceId = existingSpace.id;
              parentId = existingSpace.id;
            } else {
              final newSpaceId = const Uuid().v4();
              await _db.into(_db.spaces).insert(SpacesCompanion.insert(
                id: newSpaceId,
                houseId: houseId,
                name: partName,
                parentId: Value(parentId),
                type: parentId == null ? 'room' : 'container',
                createdAt: now,
                updatedAt: now,
              ));
              // 将新创建的空间加入列表，防止同一次导入中重复创建
              final newSpace = await (_db.select(_db.spaces)
                    ..where((t) => t.id.equals(newSpaceId)))
                  .getSingle();
              spaces.add(newSpace);
              spaceId = newSpaceId;
              parentId = newSpaceId;
            }
          }
        }

        String? categoryId;
        if (categoryName.isNotEmpty) {
          final existingCategory = categoryNameMap[categoryName];
          if (existingCategory != null) {
            categoryId = existingCategory.id;
          } else {
            categoryId = const Uuid().v4();
            await _db.into(_db.categories).insert(CategoriesCompanion.insert(
              id: categoryId,
              houseId: houseId,
              name: categoryName,
              createdAt: now,
            ),
              mode: InsertMode.insertOrIgnore,
            );
            categoryNameMap[categoryName] = await (_db.select(_db.categories)
                  ..where((t) => t.id.equals(categoryId!)))
                .getSingle();
          }
        }

        final subcategoryName = _getCellValue(row, subcategoryIdx).trim();
        String? subcategoryId;
        if (subcategoryName.isNotEmpty && categoryId != null) {
          final catSubcats = subcategoryNameMap[categoryId] ?? {};
          final existingSubcat = catSubcats[subcategoryName];
          if (existingSubcat != null) {
            subcategoryId = existingSubcat.id;
          } else {
            subcategoryId = const Uuid().v4();
            await _db.into(_db.subcategories).insert(SubcategoriesCompanion.insert(
              id: subcategoryId,
              categoryId: categoryId,
              name: subcategoryName,
              createdAt: now,
            ),
              mode: InsertMode.insertOrIgnore,
            );
            subcategoryNameMap.putIfAbsent(categoryId, () => {});
            subcategoryNameMap[categoryId]![subcategoryName] = Subcategory(
              id: subcategoryId,
              categoryId: categoryId,
              name: subcategoryName,
              sortOrder: 0,
              createdAt: now,
            );
          }
        }

        final lowStockValue = _getCellValue(row, lowStockIdx);
        final lowStockThreshold = int.tryParse(lowStockValue);

        final extendedValues = <String, String>{};
        for (final attrName in extendedAttrNames) {
          final idx = _findIndex(header, attrName);
          final val = _getCellValue(row, idx);
          if (val.isNotEmpty) {
            extendedValues[attrName] = val;
          }
        }

        final expireDateStr = extendedValues['过期日期'] ?? '';
        final warrantyExpireDateStr = extendedValues['过保日期'] ?? '';
        final productionDateStr = extendedValues['生产日期'] ?? '';
        final shelfLifeStr = extendedValues['保质期'] ?? '';

        DateTime? expireDate = _parseFlexibleDate(expireDateStr);
        DateTime? warrantyExpireDate = _parseFlexibleDate(warrantyExpireDateStr);
        DateTime? productionDate = _parseFlexibleDate(productionDateStr);
        int? shelfLife = int.tryParse(shelfLifeStr);

        String? expireDateSource;
        DateTime? finalExpireDate;

        if (expireDate != null) {
          finalExpireDate = expireDate;
          expireDateSource = 'expire';
        } else if (warrantyExpireDate != null) {
          finalExpireDate = warrantyExpireDate;
          expireDateSource = 'warranty';
        }

        if (finalExpireDate == null && productionDate != null && shelfLife != null) {
          finalExpireDate = productionDate.add(Duration(days: shelfLife));
          expireDateSource = 'expire';
        }

        // CSV 导入不再按名称去重：同名物品应当作为独立条目导入，
        // 避免复制出来的同名物品被覆盖合并。
        final id = const Uuid().v4();
        await _db.into(_db.items).insert(ItemsCompanion.insert(
          id: id,
          houseId: houseId,
          spaceId: spaceId,
          name: name,
          quantity: Value(quantity),
          unit: Value(unit.isEmpty ? '件' : unit),
          price: Value(price),
          productionDate: Value(productionDate),
          shelfLife: Value(shelfLife),
          expireDate: Value(finalExpireDate),
          category: Value(categoryName.isNotEmpty ? categoryName : null),
          categoryId: Value(categoryId),
          subcategoryId: Value(subcategoryId),
          tags: Value(tagsStr.isNotEmpty ? tagsStr : null),
          note: Value(note.isNotEmpty ? note : null),
          customAttributes: Value(expireDateSource),
          creatorId: 'user',
          modifierId: 'user',
          createdAt: now,
          updatedAt: now,
        ));
        itemCount++;

        // 新物品没有旧属性，无需清空，直接写入本次属性即可。

        final categoryAttrLinked = <String>{};

        for (final entry in extendedValues.entries) {
          final csvAttrName = entry.key;
          final attrValue = entry.value;

          if (csvAttrName == '过期日期' || csvAttrName == '过保日期') continue;

          var attrId = attrNameToId[csvAttrName];
          if (attrId == null) {
            attrId = const Uuid().v4();
            await _db.into(_db.attributes).insert(AttributesCompanion.insert(
              id: attrId,
              houseId: houseId,
              name: csvAttrName,
              type: _inferAttributeType(csvAttrName),
              createdAt: now,
              updatedAt: now,
            ),
              mode: InsertMode.insertOrIgnore,
            );
            attrNameToId[csvAttrName] = attrId;
          }
          final resolvedAttrId = attrId;

          await _db.into(_db.itemAttributes).insert(ItemAttributesCompanion.insert(
            itemId: id,
            attributeId: resolvedAttrId,
            value: Value(attrValue),
          ));

          if (categoryId != null) {
            final catId = categoryId;
            if (!categoryAttrLinked.contains(resolvedAttrId)) {
              final existingLink = await (_db.select(_db.categoryAttributes)
                    ..where((t) => t.categoryId.equals(catId) & t.attributeId.equals(resolvedAttrId)))
                  .get();
              if (existingLink.isEmpty) {
                await _db.into(_db.categoryAttributes).insert(CategoryAttributesCompanion.insert(
                  categoryId: catId,
                  attributeId: resolvedAttrId,
                ));
              }
              categoryAttrLinked.add(resolvedAttrId);
            }
          }
        }

        if (lowStockThreshold != null && lowStockThreshold >= 0) {
          await _db.into(_db.itemAttributes).insert(ItemAttributesCompanion.insert(
            itemId: id,
            attributeId: '_low_stock_threshold',
            value: Value(lowStockThreshold.toString()),
          ));
        }
      }

      return ImportResult(
        success: true,
        houseId: houseId,
        houseName: '',
        itemCount: itemCount,
        spaceCount: 0,
        message: '成功导入 $itemCount 个物品',
      );
    });
  }

  Future<String> exportToZip(String houseId) async {
    final jsonPath = await exportToJson(houseId);

    final items = await (_db.select(_db.items)
          ..where((t) => t.houseId.equals(houseId)))
        .get();

    final archive = Archive();
    final jsonFile = File(jsonPath);
    final jsonBytes = await jsonFile.readAsBytes();
    archive.addFile(ArchiveFile('nestback_data.json', jsonBytes.length, jsonBytes));

    for (final item in items) {
      if (item.imagePath != null && item.imagePath!.isNotEmpty) {
        final imgFile = File(item.imagePath!);
        if (await imgFile.exists()) {
          final imgBytes = await imgFile.readAsBytes();
          final ext = p.extension(item.imagePath!);
          archive.addFile(ArchiveFile(
            'images/${item.id}$ext',
            imgBytes.length,
            imgBytes,
          ));
        }
      }
    }

    final spaces = await (_db.select(_db.spaces)
          ..where((t) => t.houseId.equals(houseId)))
        .get();
    for (final space in spaces) {
      if (space.imagePath != null && space.imagePath!.isNotEmpty) {
        final imgFile = File(space.imagePath!);
        if (await imgFile.exists()) {
          final imgBytes = await imgFile.readAsBytes();
          final ext = p.extension(space.imagePath!);
          archive.addFile(ArchiveFile(
            'images/space_${space.id}$ext',
            imgBytes.length,
            imgBytes,
          ));
        }
      }
    }

    final zipBytes = ZipEncoder().encode(archive);

    final dir = await getTemporaryDirectory();
    final timestamp = _formatTimestamp(DateTime.now());
    final zipPath = p.join(dir.path, 'nestback_export_$timestamp.zip');
    await File(zipPath).writeAsBytes(zipBytes);
    return zipPath;
  }

  Future<ImportResult> importFromZip(String filePath, String houseId) async {
    final file = File(filePath);
    if (!await file.exists()) throw Exception('文件不存在');

    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    ArchiveFile? jsonArchiveFile;
    for (final f in archive) {
      if (f.name == 'nestback_data.json') {
        jsonArchiveFile = f;
        break;
      }
    }

    if (jsonArchiveFile == null) throw Exception('ZIP中未找到数据文件');

    final dir = await getTemporaryDirectory();
    final jsonPath = p.join(dir.path, 'nestback_import_temp.json');
    await File(jsonPath).writeAsBytes(jsonArchiveFile.content as List<int>);

    final imageMap = <String, String>{};
    final appDir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory(p.join(appDir.path, 'imported_images'));
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    for (final f in archive) {
      if (f.name.startsWith('images/') && !f.isFile) continue;
      if (f.name.startsWith('images/') && f.isFile) {
        final fileName = p.basename(f.name);
        final localPath = p.join(imagesDir.path, fileName);
        await File(localPath).writeAsBytes(f.content as List<int>);
        final idPart = fileName.replaceAll(RegExp(r'\.(png|jpg|jpeg|webp)$'), '');
        if (fileName.startsWith('space_')) {
          imageMap['space_${idPart.replaceFirst('space_', '')}'] = localPath;
        } else {
          imageMap[idPart] = localPath;
        }
      }
    }

    final result = await importFromJson(jsonPath, houseId);

    if (imageMap.isNotEmpty) {
      final remappedImages = <String, String>{};
      for (final entry in imageMap.entries) {
        final oldKey = entry.key;
        final localPath = entry.value;
        if (oldKey.startsWith('space_')) {
          final oldSpaceId = oldKey.replaceFirst('space_', '');
          final newSpaceId = result.idMapping[oldSpaceId];
          if (newSpaceId != null) {
            remappedImages['space_$newSpaceId'] = localPath;
          } else {
            remappedImages[oldKey] = localPath;
          }
        } else {
          final newItemId = result.idMapping[oldKey];
          if (newItemId != null) {
            remappedImages[newItemId] = localPath;
          } else {
            remappedImages[oldKey] = localPath;
          }
        }
      }

      final items = await (_db.select(_db.items)
            ..where((t) => t.houseId.equals(result.houseId)))
          .get();
      for (final item in items) {
        final localPath = remappedImages[item.id];
        if (localPath != null) {
          await (_db.update(_db.items)..where((t) => t.id.equals(item.id))).write(
            ItemsCompanion(imagePath: Value(localPath)),
          );
        }
      }

      final spaces = await (_db.select(_db.spaces)
            ..where((t) => t.houseId.equals(result.houseId)))
          .get();
      for (final space in spaces) {
        final localPath = remappedImages['space_${space.id}'];
        if (localPath != null) {
          await (_db.update(_db.spaces)..where((t) => t.id.equals(space.id))).write(
            SpacesCompanion(imagePath: Value(localPath)),
          );
        }
      }
    }

    try {
      await File(jsonPath).delete();
    } catch (_) {}

    return result;
  }

  int _findIndex(List<String> header, String name) {
    for (int i = 0; i < header.length; i++) {
      if (header[i].trim() == name) return i;
    }
    return -1;
  }

  String _getCellValue(List<dynamic> row, int index) {
    if (index == -1 || index >= row.length) return '';
    return row[index]?.toString() ?? '';
  }

  Map<String, dynamic> _houseToMap(House h) => {
        'id': h.id,
        'name': h.name,
        'isDefault': h.isDefault,
        'createdAt': h.createdAt.toIso8601String(),
        'updatedAt': h.updatedAt.toIso8601String(),
      };

  Map<String, dynamic> _spaceToMap(Space s) => {
        'id': s.id,
        'houseId': s.houseId,
        'name': s.name,
        'icon': s.icon,
        'imagePath': s.imagePath,
        'parentId': s.parentId,
        'type': s.type,
        'position': s.position,
        'defaultCategoryId': s.defaultCategoryId,
        'createdAt': s.createdAt.toIso8601String(),
        'updatedAt': s.updatedAt.toIso8601String(),
      };

  Map<String, dynamic> _itemToMap(Item i) => {
        'id': i.id,
        'houseId': i.houseId,
        'spaceId': i.spaceId,
        'name': i.name,
        'quantity': i.quantity,
        'unit': i.unit,
        'price': i.price,
        'productionDate': i.productionDate?.toIso8601String(),
        'shelfLife': i.shelfLife,
        'expireDate': i.expireDate?.toIso8601String(),
        'category': i.category,
        'categoryId': i.categoryId,
        'subcategoryId': i.subcategoryId,
        'tags': i.tags,
        'imagePath': i.imagePath,
        'note': i.note,
        'customAttributes': i.customAttributes,
        'creatorId': i.creatorId,
        'modifierId': i.modifierId,
        'createdAt': i.createdAt.toIso8601String(),
        'updatedAt': i.updatedAt.toIso8601String(),
      };

  Map<String, dynamic> _categoryToMap(Category c) => {
        'id': c.id,
        'houseId': c.houseId,
        'name': c.name,
        'icon': c.icon,
        'sortOrder': c.sortOrder,
        'createdAt': c.createdAt.toIso8601String(),
      };

  Map<String, dynamic> _subcategoryToMap(Subcategory sc) => {
        'id': sc.id,
        'categoryId': sc.categoryId,
        'name': sc.name,
        'sortOrder': sc.sortOrder,
        'createdAt': sc.createdAt.toIso8601String(),
      };

  Map<String, dynamic> _tagToMap(Tag t) => {
        'id': t.id,
        'houseId': t.houseId,
        'name': t.name,
        'sortOrder': t.sortOrder,
        'createdAt': t.createdAt.toIso8601String(),
      };

  Map<String, dynamic> _attributeToMap(Attribute a) => {
        'id': a.id,
        'houseId': a.houseId,
        'name': a.name,
        'type': a.type,
        'hint': a.hint,
        'options': a.options,
        'required': a.required,
        'sortOrder': a.sortOrder,
        'createdAt': a.createdAt.toIso8601String(),
        'updatedAt': a.updatedAt.toIso8601String(),
      };

  Map<String, dynamic> _categoryAttributeToMap(CategoryAttribute ca) => {
        'categoryId': ca.categoryId,
        'attributeId': ca.attributeId,
        'sortOrder': ca.sortOrder,
      };

  Map<String, dynamic> _itemAttributeToMap(ItemAttribute ia) => {
        'itemId': ia.itemId,
        'attributeId': ia.attributeId,
        'value': ia.value,
      };

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  DateTime? _parseFlexibleDate(String value) {
    if (value.isEmpty) return null;
    final d = DateTime.tryParse(value);
    if (d != null) return d;
    final parts = value.split(RegExp(r'[/\-年月日]'));
    if (parts.length >= 3) {
      final year = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final day = int.tryParse(parts[2]);
      if (year != null && month != null && day != null) {
        return DateTime(year, month, day);
      }
    }
    return null;
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return '';
    return dt.toIso8601String();
  }

  String _formatTimestamp(DateTime dt) {
    return '${dt.year}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}_${dt.hour.toString().padLeft(2, '0')}${dt.minute.toString().padLeft(2, '0')}${dt.second.toString().padLeft(2, '0')}';
  }

  String _inferAttributeType(String name) {
    final dateNames = {'生产日期', '过期日期', '开封日期', '购买日期', '过保日期'};
    final durationNames = {'保质期', '保修期'};
    final multiSelectNames = {'储存方式'};
    final linkNames = {'链接', '网址', '购买链接', '官网', '参考链接', 'URL'};
    if (dateNames.contains(name)) return 'date';
    if (durationNames.contains(name)) return 'duration';
    if (multiSelectNames.contains(name)) return 'multi_select';
    if (linkNames.contains(name)) return 'link';
    return 'text';
  }
}

class ImportResult {
  final bool success;
  final String houseId;
  final String houseName;
  final int itemCount;
  final int spaceCount;
  final String message;
  final Map<String, String> idMapping;

  ImportResult({
    required this.success,
    required this.houseId,
    required this.houseName,
    required this.itemCount,
    required this.spaceCount,
    required this.message,
    this.idMapping = const {},
  });
}