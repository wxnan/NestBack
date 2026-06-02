import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import 'package:drift/drift.dart' as drift;
import '../item/item_detail_page.dart';
import '../../providers/item_provider.dart';
import '../../providers/space_provider.dart';
import '../../providers/house_provider.dart';
import '../../database/database.dart';

class PendingValueItemsPage extends StatefulWidget {
  const PendingValueItemsPage({super.key});

  @override
  State<PendingValueItemsPage> createState() => _PendingValueItemsPageState();
}

class _PendingValueItemsPageState extends State<PendingValueItemsPage> {
  bool _isSelectionMode = false;
  final Set<String> _selectedItemIds = {};

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedItemIds.clear();
      }
    });
  }

  void _toggleItemSelection(String itemId) {
    setState(() {
      if (_selectedItemIds.contains(itemId)) {
        _selectedItemIds.remove(itemId);
        if (_selectedItemIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedItemIds.add(itemId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isSelectionMode ? '已选择 ${_selectedItemIds.length} 个物品' : '等待估值'),
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _toggleSelectionMode,
              )
            : null,
        actions: _isSelectionMode
            ? [
                PopupMenuButton<String>(
                  onSelected: (value) => _handleMenuAction(context, value),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, color: Colors.red),
                          SizedBox(width: 8),
                          Text('删除'),
                        ],
                      ),
                    ),
                  ],
                ),
              ]
            : null,
      ),
      body: Consumer3<HouseProvider, ItemProvider, SpaceProvider>(
        builder: (context, houseProvider, itemProvider, spaceProvider, _) {
          final currentHouse = houseProvider.currentHouse;
          if (currentHouse == null) {
            return const Center(child: CircularProgressIndicator());
          }

          final items = itemProvider.items
              .where((item) => item.houseId == currentHouse.id && item.price == null)
              .toList();

          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.attach_money_outlined, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    '暂无等待估值的物品',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              return _buildItemCard(context, items[index], itemProvider, spaceProvider);
            },
          );
        },
      ),
    );
  }

  Widget _buildItemCard(BuildContext context, Item item, ItemProvider itemProvider, SpaceProvider spaceProvider) {
    final space = spaceProvider.spaces.firstWhere(
      (s) => s.id == item.spaceId,
      orElse: () => Space(id: '', houseId: '', name: '未知', type: '', parentId: null, icon: null, createdAt: DateTime.now(), updatedAt: DateTime.now()),
    );
    final isExpired = item.expireDate != null && item.expireDate!.isBefore(DateTime.now());
    final isSelected = _selectedItemIds.contains(item.id);

    if (_isSelectionMode) {
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        color: isSelected ? Theme.of(context).colorScheme.primaryContainer : null,
        child: ListTile(
          leading: Checkbox(
            value: isSelected,
            onChanged: (value) => _toggleItemSelection(item.id),
          ),
          title: Text(item.name),
          subtitle: Text(
            '${space.name} ×${item.quantity}',
            style: const TextStyle(fontSize: 12),
          ),
          trailing: _buildExpireText(item),
          onTap: () => _toggleItemSelection(item.id),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Slidable(
        startActionPane: _buildLeftSlideActions(context, item, itemProvider, spaceProvider, isExpired),
        endActionPane: _buildRightSlideActions(context, item, itemProvider, spaceProvider, isExpired),
        child: ListTile(
          leading: _buildItemImage(context, item),
          title: Text(item.name),
          subtitle: Text(
            '${space.name} ×${item.quantity}',
            style: const TextStyle(fontSize: 12),
          ),
          trailing: _buildExpireText(item),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ItemDetailPage(item: item),
              ),
            );
          },
          onLongPress: () {
            _toggleSelectionMode();
            _toggleItemSelection(item.id);
          },
        ),
      ),
    );
  }

  ActionPane _buildLeftSlideActions(BuildContext context, Item item, ItemProvider itemProvider,
      SpaceProvider spaceProvider, bool isExpired) {
    if (isExpired) {
      return ActionPane(
        motion: const ScrollMotion(),
        extentRatio: 0.25,
        children: [
          SlidableAction(
            onPressed: (context) => _showConfirmDialog(context, '扔掉物品',
                '确定将物品移至垃圾桶吗？', () async {
              await _moveToTrashOrDelete(context, item, itemProvider, spaceProvider, true);
            }),
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            icon: Icons.delete,
            label: '扔掉',
            borderRadius: BorderRadius.circular(12),
          ),
        ],
      );
    }
    return ActionPane(
      motion: const ScrollMotion(),
      extentRatio: 0.4,
      children: [
        SlidableAction(
          onPressed: (ctx) async {
            if (item.quantity <= 1) {
              final db = Provider.of<AppDatabase>(ctx, listen: false);
              _showConfirmDialog(ctx, '移至回收站',
                  '确定将物品移至回收站吗？', () async {
                await _moveToRecycleBin(ctx, item, itemProvider, spaceProvider, db);
              });
            } else {
              await _decrementQuantityWithoutPop(ctx, item, itemProvider);
            }
          },
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
          label: '-1',
          borderRadius: BorderRadius.circular(12),
        ),
        SlidableAction(
          onPressed: (context) async {
            await _incrementQuantityWithoutPop(context, item, itemProvider);
          },
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          label: '+1',
          borderRadius: BorderRadius.circular(12),
        ),
      ],
    );
  }

  ActionPane _buildRightSlideActions(BuildContext context, Item item, ItemProvider itemProvider,
      SpaceProvider spaceProvider, bool isExpired) {
    if (isExpired) {
      return ActionPane(
        motion: const ScrollMotion(),
        children: [
          SlidableAction(
            onPressed: (context) => _showConfirmDialog(context, '扔掉物品',
                '确定将物品移至垃圾桶吗？', () async {
              await _moveToTrashOrDelete(context, item, itemProvider, spaceProvider, true);
            }),
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            icon: Icons.delete,
            label: '扔掉',
            borderRadius: BorderRadius.circular(12),
          ),
        ],
      );
    }
    return ActionPane(
      motion: const ScrollMotion(),
      children: [
        SlidableAction(
          onPressed: (context) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ItemDetailPage(item: item, isCopy: true),
              ),
            );
          },
          backgroundColor: Colors.purple,
          foregroundColor: Colors.white,
          icon: Icons.copy,
          label: '复制',
          borderRadius: BorderRadius.circular(12),
        ),
        SlidableAction(
          onPressed: (context) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ItemDetailPage(item: item, isSplit: true),
              ),
            );
          },
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          icon: Icons.cut,
          label: '拆分',
          borderRadius: BorderRadius.circular(12),
        ),
      ],
    );
  }

  void _handleMenuAction(BuildContext context, String action) async {
    if (action == 'delete') {
      final itemProvider = Provider.of<ItemProvider>(context, listen: false);
      final spaceProvider = Provider.of<SpaceProvider>(context, listen: false);
      final selectedItems = itemProvider.items.where((item) => _selectedItemIds.contains(item.id)).toList();
      
      final isFromRecycleOrTrash = selectedItems.every((item) {
        final space = spaceProvider.spaces.firstWhere(
          (s) => s.id == item.spaceId,
          orElse: () => Space(id: '', houseId: '', name: '', type: '', parentId: null, icon: null, createdAt: DateTime.now(), updatedAt: DateTime.now()),
        );
        return space.type == 'recycle' || space.type == 'trash';
      });

      if (isFromRecycleOrTrash) {
        _showConfirmDialog(context, '彻底删除',
            '确定彻底删除选中的 ${_selectedItemIds.length} 个物品吗？此操作不可恢复。', () async {
          for (final item in selectedItems) {
            await itemProvider.permanentDeleteItem(item);
          }
          _toggleSelectionMode();
        });
      } else {
        _showConfirmDialog(context, '移至回收站',
            '确定将选中的 ${_selectedItemIds.length} 个物品移至回收站吗？', () async {
          for (final item in selectedItems) {
            await itemProvider.deleteItem(item);
          }
          _toggleSelectionMode();
        });
      }
    }
  }

  Future<void> _decrementQuantityWithoutPop(BuildContext ctx, Item item, ItemProvider itemProvider) async {
    final db = Provider.of<AppDatabase>(ctx, listen: false);
    await (db.update(db.items)..where((t) => t.id.equals(item.id))).write(
      ItemsCompanion(
        quantity: drift.Value(item.quantity - 1),
        modifierId: const drift.Value('user'),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );
    await itemProvider.loadItems(item.houseId);
  }

  Future<void> _incrementQuantityWithoutPop(BuildContext ctx, Item item, ItemProvider itemProvider) async {
    final db = Provider.of<AppDatabase>(ctx, listen: false);
    await (db.update(db.items)..where((t) => t.id.equals(item.id))).write(
      ItemsCompanion(
        quantity: drift.Value(item.quantity + 1),
        modifierId: const drift.Value('user'),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );
    await itemProvider.loadItems(item.houseId);
  }

  Future<void> _moveToTrashOrDelete(BuildContext ctx, Item item, ItemProvider itemProvider, SpaceProvider spaceProvider, bool forceDelete) async {
    final space = spaceProvider.spaces.firstWhere(
      (s) => s.id == item.spaceId,
      orElse: () => Space(id: '', houseId: '', name: '', type: '', parentId: null, icon: null, createdAt: DateTime.now(), updatedAt: DateTime.now()),
    );

    if (forceDelete || space.type == 'recycle' || space.type == 'trash') {
      await itemProvider.permanentDeleteItem(item);
    } else {
      await itemProvider.moveToTrash(item);
    }
  }

  Future<void> _moveToRecycleBin(BuildContext ctx, Item item, ItemProvider itemProvider, SpaceProvider spaceProvider, AppDatabase db) async {
    final recycleSpace = await (db.select(db.spaces)
          ..where((t) => t.houseId.equals(item.houseId) & t.type.equals('recycle')))
        .getSingleOrNull();

    if (recycleSpace != null) {
      await (db.update(db.items)..where((t) => t.id.equals(item.id))).write(
        ItemsCompanion(
          spaceId: drift.Value(recycleSpace.id),
          modifierId: const drift.Value('user'),
          updatedAt: drift.Value(DateTime.now()),
        ),
      );
      await itemProvider.loadItems(item.houseId);
    }
  }

  void _showConfirmDialog(BuildContext context, String title, String message, VoidCallback onConfirm) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              onConfirm();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Widget _buildExpireText(dynamic item) {
    if (item.expireDate == null) return const SizedBox();
    final text = _getExpireText(item.expireDate, item.customAttributes == 'warranty');
    final color = _getExpireColor(item.expireDate);
    return Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  String _getExpireText(DateTime? expireDate, [bool isWarrantyDate = false]) {
    if (expireDate == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expireDay = DateTime(expireDate.year, expireDate.month, expireDate.day);
    final diff = expireDay.difference(today).inDays;

    final suffix = isWarrantyDate ? '过保' : '过期';
    if (diff < 0) {
      return '已$suffix';
    } else if (diff == 0) {
      return '今日$suffix';
    } else {
      return '${diff}天后$suffix';
    }
  }

  Color _getExpireColor(DateTime? expireDate) {
    if (expireDate == null) return Colors.grey;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expireDay = DateTime(expireDate.year, expireDate.month, expireDate.day);
    final diff = expireDay.difference(today).inDays;

    if (diff < 0) {
      return Colors.red;
    } else if (diff == 0) {
      return Colors.red;
    } else if (diff <= 7) {
      return Colors.orange;
    } else if (diff <= 30) {
      return Colors.amber;
    } else {
      return Colors.green;
    }
  }

  Widget _buildItemImage(BuildContext context, dynamic item) {
    if (item.imagePath != null && item.imagePath!.isNotEmpty) {
      return GestureDetector(
        onTap: () => _showImagePreview(context, item.imagePath!),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(item.imagePath!),
            width: 40,
            height: 40,
            fit: BoxFit.cover,
          ),
        ),
      );
    }
    return _buildItemIcon(item.category);
  }

  void _showImagePreview(BuildContext context, String imagePath) {
    showDialog(
      context: context,
      barrierColor: Colors.black,
      builder: (context) => GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.black,
          child: Center(
            child: InteractiveViewer(
              child: Image.file(
                File(imagePath),
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItemIcon(String? category) {
    final icons = {
      '食品': Icons.local_dining,
      '药品': Icons.medication,
      '日用品': Icons.cleaning_services,
      '数码': Icons.devices,
      '美妆': Icons.spa,
    };
    final colors = {
      '食品': Colors.amber,
      '药品': Colors.green,
      '日用品': Colors.blue,
      '数码': Colors.purple,
      '美妆': Colors.pink,
    };

    final iconData = icons[category] ?? Icons.category;
    final iconColor = colors[category] ?? Colors.grey;

    return CircleAvatar(
      backgroundColor: iconColor.withOpacity(0.15),
      child: Icon(iconData, color: iconColor),
    );
  }
}
