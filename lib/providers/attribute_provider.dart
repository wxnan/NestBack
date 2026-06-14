import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../database/database.dart';

class AttributeProvider extends ChangeNotifier {
  final AppDatabase _db;
  List<Attribute> _attributes = [];

  AttributeProvider(this._db);

  List<Attribute> get attributes => _attributes;

  Future<void> loadAttributes() async {
    _attributes = await (_db.select(_db.attributes)
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
    notifyListeners();
  }

  Future<bool> isAttributeNameExists(String name, {String? excludeId}) async {
    final query = _db.select(_db.attributes)
      ..where((t) => t.name.equals(name));
    final results = await query.get();
    if (excludeId != null) {
      return results.any((a) => a.id != excludeId);
    }
    return results.isNotEmpty;
  }

  Future<void> addAttribute({
    required String houseId,
    required String name,
    required String type,
    String? hint,
    List<String>? options,
    bool required = false,
  }) async {
    final existingAttrs = await (_db.select(_db.attributes)
          ..where((t) => t.name.equals(name)))
        .get();
    if (existingAttrs.isNotEmpty) {
      return;
    }

    final id = const Uuid().v4();
    final maxOrder = _attributes.isEmpty
        ? 0
        : _attributes.map((a) => a.sortOrder).reduce((a, b) => a > b ? a : b);
    await _db.into(_db.attributes).insert(AttributesCompanion.insert(
          id: id,
          houseId: houseId,
          name: name,
          type: type,
          hint: Value(hint),
          options: Value(options?.join(';')),
          required: Value(required),
          sortOrder: Value(maxOrder + 1),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      mode: InsertMode.insertOrIgnore,
    );
    await loadAttributes();
  }

  Future<void> updateAttribute(Attribute attribute, {
    String? name,
    String? type,
    String? hint,
    List<String>? options,
    bool? required,
  }) async {
    await (_db.update(_db.attributes)
          ..where((t) => t.id.equals(attribute.id)))
        .write(AttributesCompanion(
          name: name != null ? Value(name) : Value.absent(),
          type: type != null ? Value(type) : Value.absent(),
          hint: hint != null ? Value(hint) : Value.absent(),
          options: options != null ? Value(options.join(';')) : Value.absent(),
          required: required != null ? Value(required) : Value.absent(),
          updatedAt: Value(DateTime.now()),
        ));
    await loadAttributes();
  }

  Future<void> deleteAttribute(Attribute attribute) async {
    await (_db.delete(_db.attributes)
          ..where((t) => t.id.equals(attribute.id)))
        .go();
    await (_db.delete(_db.categoryAttributes)
          ..where((t) => t.attributeId.equals(attribute.id)))
        .go();
    await (_db.delete(_db.itemAttributes)
          ..where((t) => t.attributeId.equals(attribute.id)))
        .go();
    await loadAttributes();
  }

  Future<void> updateAttributeOptions(String attributeId, String newOptions) async {
    await (_db.update(_db.attributes)..where((t) => t.id.equals(attributeId))).write(
      AttributesCompanion(
        options: Value(newOptions),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await loadAttributes();
  }

  Future<void> reorderAttributes(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = _attributes.removeAt(oldIndex);
    _attributes.insert(newIndex, item);

    for (int i = 0; i < _attributes.length; i++) {
      await (_db.update(_db.attributes)
            ..where((t) => t.id.equals(_attributes[i].id)))
          .write(AttributesCompanion(sortOrder: Value(i)));
    }
    notifyListeners();
  }

  Future<List<Attribute>> getAttributesForCategory(String categoryId) async {
    final query = _db.select(_db.categoryAttributes).join([
      innerJoin(_db.attributes, _db.categoryAttributes.attributeId.equalsExp(_db.attributes.id)),
    ])..where(_db.categoryAttributes.categoryId.equals(categoryId))
     ..orderBy([OrderingTerm.asc(_db.categoryAttributes.sortOrder)]);

    final rows = await query.get();
    return rows.map((row) => row.readTable(_db.attributes)).toList();
  }

  Future<void> setCategoryAttributes(String categoryId, List<String> attributeIds) async {
    await (_db.delete(_db.categoryAttributes)
          ..where((t) => t.categoryId.equals(categoryId)))
        .go();

    for (int i = 0; i < attributeIds.length; i++) {
      await _db.into(_db.categoryAttributes).insert(CategoryAttributesCompanion.insert(
        categoryId: categoryId,
        attributeId: attributeIds[i],
        sortOrder: Value(i),
      ));
    }
    notifyListeners();
  }

  Future<void> saveItemAttributes(String itemId, Map<String, String?> attributes) async {
    await (_db.delete(_db.itemAttributes)
          ..where((t) => t.itemId.equals(itemId)))
        .go();

    for (var entry in attributes.entries) {
      if (entry.value != null && entry.value!.isNotEmpty) {
        await _db.into(_db.itemAttributes).insert(ItemAttributesCompanion.insert(
          itemId: itemId,
          attributeId: entry.key,
          value: Value(entry.value),
        ));
      }
    }
  }

  Future<Map<String, String>> getItemAttributes(String itemId) async {
    final rows = await (_db.select(_db.itemAttributes)
          ..where((t) => t.itemId.equals(itemId)))
        .get();

    return {for (var row in rows) row.attributeId: row.value ?? ''};
  }

  List<String> getAttributeOptions(Attribute attribute) {
    if (attribute.options == null || attribute.options!.isEmpty) {
      return [];
    }
    return attribute.options!.split(';');
  }
}