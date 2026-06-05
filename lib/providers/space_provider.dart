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

  /// 排序函数：优先按 position 排序，position 为 null 的按 createdAt 排序
  int _sortSpaces(Space a, Space b) {
    // 如果两个都有 position，按 position 排序
    if (a.position != null && b.position != null) {
      return a.position!.compareTo(b.position!);
    }
    // 如果只有一个有 position，有 position 的排前面
    if (a.position != null) return -1;
    if (b.position != null) return 1;
    // 都没有 position，按 createdAt 排序
    return a.createdAt.compareTo(b.createdAt);
  }

  Future<void> loadSpaces(String houseId) async {
    _spaces = await (_db.select(_db.spaces)
          ..where((t) => t.houseId.equals(houseId)))
        .get();
    // 按 position/createdAt 排序
    _spaces.sort(_sortSpaces);

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
    _currentSpaces.sort(_sortSpaces);
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
      _currentSpaces.sort(_sortSpaces);
    } else {
      _currentSpace = _spaces.firstWhere((s) => s.id == parentId);
      _updateBreadcrumb(houseId);
      _currentSpaces = _spaces.where((s) => s.parentId == parentId).toList();
      _currentSpaces.sort(_sortSpaces);
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
  }) async {
    final now = DateTime.now();
    final id = const Uuid().v4();
    
    // 计算新空间的 position：当前层级最大 position + 1
    final siblings = parentId == null
        ? _spaces.where((s) =>
            s.houseId == houseId &&
            s.parentId == null &&
            s.type != 'pending' &&
            s.type != 'trash' &&
            s.type != 'recycle').toList()
        : _spaces.where((s) => s.parentId == parentId).toList();
    
    String? position;
    if (siblings.isEmpty) {
      position = '0';
    } else {
      final maxPosition = siblings
          .map((s) => int.tryParse(s.position ?? '0') ?? 0)
          .reduce((a, b) => a > b ? a : b);
      position = '${maxPosition + 1}';
    }
    
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
  }) async {
    await (_db.update(_db.spaces)..where((t) => t.id.equals(space.id))).write(
      SpacesCompanion(
        name: newName != null ? Value(newName) : const Value.absent(),
        icon: newIcon != null ? Value(newIcon) : const Value.absent(),
        imagePath: newImagePath != null ? Value(newImagePath) : const Value.absent(),
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
    final children = _spaces.where((s) => s.parentId == parentId).toList();
    children.sort(_sortSpaces);
    return children;
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
    
    // 计算新位置的 position
    final siblings = newParentId == null
        ? _spaces.where((s) =>
            s.houseId == space.houseId &&
            s.parentId == null &&
            s.type != 'pending' &&
            s.type != 'trash' &&
            s.type != 'recycle').toList()
        : _spaces.where((s) => s.parentId == newParentId).toList();
    
    final maxPosition = siblings.isEmpty
        ? 0
        : siblings
            .map((s) => int.tryParse(s.position ?? '0') ?? 0)
            .reduce((a, b) => a > b ? a : b);
    
    await (_db.update(_db.spaces)..where((t) => t.id.equals(spaceId))).write(
      SpacesCompanion(
        parentId: Value(newParentId),
        position: Value('${maxPosition + 1}'),
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

  /// 更新空间排序顺序
  Future<void> reorderSpaces(String houseId, String? parentId, int oldIndex, int newIndex) async {
    // 获取当前层级的空间列表
    final currentLevelSpaces = parentId == null
        ? _spaces.where((s) =>
            s.houseId == houseId &&
            s.parentId == null &&
            s.type != 'pending' &&
            s.type != 'trash' &&
            s.type != 'recycle').toList()
        : _spaces.where((s) => s.parentId == parentId).toList();
    
    // 确保按 position 排序，与 UI 显示的顺序一致
    currentLevelSpaces.sort(_sortSpaces);

    if (oldIndex < 0 || oldIndex >= currentLevelSpaces.length ||
        newIndex < 0 || newIndex >= currentLevelSpaces.length) {
      return;
    }

    // 重新排序
    final item = currentLevelSpaces.removeAt(oldIndex);
    currentLevelSpaces.insert(newIndex, item);

    // 更新数据库中的 position 字段
    for (int i = 0; i < currentLevelSpaces.length; i++) {
      final space = currentLevelSpaces[i];
      await (_db.update(_db.spaces)..where((t) => t.id.equals(space.id))).write(
        SpacesCompanion(
          position: Value('$i'),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }

    // 重新加载
    await loadSpaces(houseId);
    if (parentId != null) {
      await loadCurrentLevel(houseId, parentId: parentId);
    }
  }
}
