import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../database/database.dart';

class TagProvider extends ChangeNotifier {
  final AppDatabase _db;
  List<Tag> _tags = [];

  TagProvider(this._db);

  List<Tag> get tags => _tags;

  Future<void> loadTags(String houseId) async {
    _tags = await (_db.select(_db.tags)
          ..where((t) => t.houseId.equals(houseId))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
    notifyListeners();
  }

  Future<bool> isTagNameExists(String houseId, String name, {String? excludeId}) async {
    final query = _db.select(_db.tags)
      ..where((t) => t.houseId.equals(houseId) & t.name.equals(name));
    final results = await query.get();
    if (excludeId != null) {
      return results.any((t) => t.id != excludeId);
    }
    return results.isNotEmpty;
  }

  Future<void> addTag({
    required String houseId,
    required String name,
  }) async {
    if (await isTagNameExists(houseId, name)) {
      return;
    }

    final id = const Uuid().v4();
    final maxOrder = _tags.isEmpty
        ? 0
        : _tags.map((t) => t.sortOrder).reduce((a, b) => a > b ? a : b);
    await _db.into(_db.tags).insert(TagsCompanion.insert(
      id: id,
      houseId: houseId,
      name: name,
      sortOrder: Value(maxOrder + 1),
      createdAt: DateTime.now(),
    ));
    await loadTags(houseId);
  }

  Future<void> updateTag(Tag tag, String newName) async {
    if (await isTagNameExists(tag.houseId, newName, excludeId: tag.id)) {
      return;
    }
    await (_db.update(_db.tags)..where((t) => t.id.equals(tag.id)))
        .write(TagsCompanion(name: Value(newName)));
    await loadTags(tag.houseId);
  }

  Future<void> deleteTag(Tag tag) async {
    await (_db.delete(_db.tags)..where((t) => t.id.equals(tag.id))).go();
    await loadTags(tag.houseId);
  }

  Future<void> reorderTags(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = _tags.removeAt(oldIndex);
    _tags.insert(newIndex, item);

    for (int i = 0; i < _tags.length; i++) {
      await (_db.update(_db.tags)
            ..where((t) => t.id.equals(_tags[i].id)))
          .write(TagsCompanion(sortOrder: Value(i)));
    }
    notifyListeners();
  }

  List<String> getTagNames() {
    return _tags.map((t) => t.name).toList();
  }
}
