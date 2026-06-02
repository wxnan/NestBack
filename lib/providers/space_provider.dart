import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../database/database.dart';

class SpaceProvider extends ChangeNotifier {
  final AppDatabase _db;
  List<Space> _spaces = [];
  List<Space> _currentSpaces = [];
  Space? _currentSpace;
  List<Space> _breadcrumb = [];

  SpaceProvider(this._db);

  List<Space> get spaces => _spaces;
  List<Space> get currentSpaces => _currentSpaces;
  Space? get currentSpace => _currentSpace;
  List<Space> get breadcrumb => _breadcrumb;

  Future<void> loadSpaces(String houseId) async {
    _spaces = await (_db.select(_db.spaces)
          ..where((t) => t.houseId.equals(houseId)))
        .get();
    _currentSpace = null;
    _breadcrumb = [];
    _currentSpaces = _spaces
        .where((s) =>
            s.houseId == houseId &&
            s.parentId == null &&
            s.type != 'pending' &&
            s.type != 'trash' &&
            s.type != 'recycle')
        .toList();
    notifyListeners();
  }

  Future<void> loadCurrentLevel(String houseId, {String? parentId}) async {
    if (parentId == null) {
      _currentSpace = null;
      _breadcrumb = [];
      _currentSpaces = _spaces
          .where((s) =>
              s.houseId == houseId &&
              s.parentId == null &&
              s.type != 'pending' &&
              s.type != 'trash' &&
              s.type != 'recycle')
          .toList();
    } else {
      _currentSpace = _spaces.firstWhere((s) => s.id == parentId);
      _updateBreadcrumb(houseId);
      _currentSpaces = _spaces.where((s) => s.parentId == parentId).toList();
    }
    notifyListeners();
  }

  void _updateBreadcrumb(String houseId) {
    _breadcrumb = [];
    Space? space = _currentSpace;
    while (space != null) {
      _breadcrumb.insert(0, space);
      if (space.parentId != null) {
        space = _spaces.firstWhere(
          (s) => s.id == space!.parentId,
          orElse: () => space!,
        );
      } else {
        space = null;
      }
    }
  }

  Future<void> addSpace({
    required String houseId,
    required String name,
    String? parentId,
    String? icon,
    String? imagePath,
    String? position,
  }) async {
    final now = DateTime.now();
    final id = const Uuid().v4();
    await _db.into(_db.spaces).insert(SpacesCompanion.insert(
      id: id,
      houseId: houseId,
      name: name,
      icon: Value(icon),
      imagePath: Value(imagePath),
      parentId: Value(parentId),
      type: parentId == null ? 'room' : 'container',
      position: Value(position),
      createdAt: now,
      updatedAt: now,
    ));
    await loadSpaces(houseId);
    await loadCurrentLevel(houseId, parentId: parentId);
  }

  Future<void> updateSpace(Space space, {
    String? newName,
    String? newIcon,
    String? newImagePath,
    String? newPosition,
  }) async {
    await (_db.update(_db.spaces)..where((t) => t.id.equals(space.id))).write(
      SpacesCompanion(
        name: newName != null ? Value(newName) : const Value.absent(),
        icon: newIcon != null ? Value(newIcon) : const Value.absent(),
        imagePath: newImagePath != null ? Value(newImagePath) : const Value.absent(),
        position: newPosition != null ? Value(newPosition) : const Value.absent(),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await loadSpaces(space.houseId);
    await loadCurrentLevel(space.houseId, parentId: space.parentId);
  }

  Future<void> deleteSpace(Space space) async {
    final childSpaces = _spaces.where((s) => s.parentId == space.id).toList();
    for (final child in childSpaces) {
      await deleteSpace(child);
    }

    await (_db.delete(_db.items)..where((t) => t.spaceId.equals(space.id)))
        .go();
    await (_db.delete(_db.spaces)..where((t) => t.id.equals(space.id))).go();
    await loadSpaces(space.houseId);
    await loadCurrentLevel(space.houseId, parentId: space.parentId);
  }

  List<Space> getChildSpaces(String parentId) {
    return _spaces.where((s) => s.parentId == parentId).toList();
  }

  List<Item> getItemsInSpace(List<Item> allItems, String spaceId) {
    return allItems.where((item) => item.spaceId == spaceId).toList();
  }

  Space? getPendingSpace(String houseId) {
    try {
      return _spaces.firstWhere(
        (s) => s.houseId == houseId && s.type == 'pending',
      );
    } catch (e) {
      return null;
    }
  }

  Space? getTrashSpace(String houseId) {
    try {
      return _spaces.firstWhere(
        (s) => s.houseId == houseId && s.type == 'trash',
      );
    } catch (e) {
      return null;
    }
  }

  Space? getRecycleBinSpace(String houseId) {
    try {
      return _spaces.firstWhere(
        (s) => s.houseId == houseId && s.type == 'recycle',
      );
    } catch (e) {
      return null;
    }
  }

  bool isSpecialSpace(dynamic space) {
    final type = space.type as String?;
    return type == 'pending' || type == 'trash' || type == 'recycle';
  }

  Future<void> moveSpace(String spaceId, String? newParentId) async {
    final space = _spaces.firstWhere((s) => s.id == spaceId);
    await (_db.update(_db.spaces)..where((t) => t.id.equals(spaceId))).write(
      SpacesCompanion(
        parentId: Value(newParentId),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await loadSpaces(space.houseId);
    await loadCurrentLevel(space.houseId, parentId: space.parentId);
  }

  List<Space> getAllSpacesExceptSpecial(String houseId) {
    return _spaces.where((s) => 
      s.houseId == houseId && 
      s.type != 'pending' && 
      s.type != 'trash' &&
      s.type != 'recycle'
    ).toList();
  }

  String getSpacePath(Space space, {bool includeSelf = false}) {
    List<String> path = [];
    Space? current = includeSelf ? space : _spaces.firstWhere(
      (s) => s.id == space.parentId,
      orElse: () => space,
    );
    
    while (current != null && (includeSelf || current.id != space.id)) {
      path.insert(0, current.name);
      if (current.parentId != null) {
        current = _spaces.firstWhere(
          (s) => s.id == current!.parentId,
          orElse: () => current!,
        );
      } else {
        current = null;
      }
    }
    
    return path.join(' - ');
  }

  Space? getSpaceById(String? spaceId) {
    if (spaceId == null) return null;
    try {
      return _spaces.firstWhere((s) => s.id == spaceId);
    } catch (e) {
      return null;
    }
  }
}
