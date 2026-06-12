import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:drift/drift.dart' as drift;
import 'dart:io';
import '../../database/database.dart';
import '../../providers/house_provider.dart';
import '../../providers/space_provider.dart';
import '../../providers/item_provider.dart';
import 'space_hierarchy_page.dart';
import 'space_edit_page.dart';
import '../item/item_detail_page.dart';
import '../home/restock_page.dart';
import '../../main.dart';

class SpaceTab extends StatefulWidget {
  const SpaceTab({super.key});

  @override
  State<SpaceTab> createState() => _SpaceTabState();
}

class _SpaceTabState extends State<SpaceTab> {
  bool _isSelectionMode = false;
  final Set<String> _selectedItemIds = {};
  bool _isReordering = false;

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
      } else {
        _selectedItemIds.add(itemId);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedItemIds.clear();
    });
  }

  void _selectAll(List<Item> items) {
    setState(() {
      _selectedItemIds.addAll(items.map((item) => item.id));
    });
  }

  Future<void> _batchMoveItems(BuildContext context, ItemProvider itemProvider, SpaceProvider spaceProvider) async {
    final allItems = itemProvider.allItems;
    final selectedItems = allItems.where((item) => _selectedItemIds.contains(item.id)).toList();
    if (selectedItems.isEmpty) return;

    await spaceProvider.loadSpaces(selectedItems.first.houseId);
    final spaces = spaceProvider.spaces.where((s) => s.type != 'trash' && s.type != 'recycle').toList();

    if (!mounted) return;

    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => ListView.builder(
        itemCount: spaces.length,
        itemBuilder: (context, index) {
          final space = spaces[index];
          return ListTile(
            leading: Icon(_getSpaceIcon(space.icon, space.type)),
            title: Text(space.name),
            subtitle: Text(space.type),
            onTap: () => Navigator.pop(context, space.id),
          );
        },
      ),
    );

    if (result != null) {
      for (final item in selectedItems) {
        await itemProvider.moveItem(item, result);
      }
      _clearSelection();
      _toggleSelectionMode();
      // 刷新数据以即时更新空间物品数量
      await _refreshData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已移动 ${selectedItems.length} 个物品')),
        );
      }
    }
  }

  void _showBatchDeleteDialog(BuildContext context, ItemProvider itemProvider, SpaceProvider spaceProvider) {
    final allItems = itemProvider.allItems;
    final selectedItems = allItems.where((item) => _selectedItemIds.contains(item.id)).toList();
    if (selectedItems.isEmpty) return;

    // 检查选中的物品是否在回收站或垃圾桶中
    final hasItemsInSpecialSpace = selectedItems.any((item) {
      final space = spaceProvider.spaces.firstWhereOrNull((s) => s.id == item.spaceId);
      return space != null && (space.type == 'recycle' || space.type == 'trash');
    });

    String title = '删除物品';
    String message;
    
    if (hasItemsInSpecialSpace) {
      title = '彻底删除';
      message = '确定要彻底删除选中的 ${selectedItems.length} 个物品吗？此操作无法撤销。';
    } else {
      message = '确定将选中的 ${selectedItems.length} 个物品移至回收站吗？';
    }

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
            onPressed: () async {
              Navigator.pop(context);
              await _batchDeleteItems(context, itemProvider, spaceProvider, hasItemsInSpecialSpace);
            },
            style: FilledButton.styleFrom(
              backgroundColor: hasItemsInSpecialSpace ? Colors.red : null,
            ),
            child: Text(hasItemsInSpecialSpace ? '彻底删除' : '移至回收站'),
          ),
        ],
      ),
    );
  }

  Future<void> _batchDeleteItems(BuildContext context, ItemProvider itemProvider, SpaceProvider spaceProvider, bool permanentDelete) async {
    final allItems = itemProvider.allItems;
    final selectedItems = allItems.where((item) => _selectedItemIds.contains(item.id)).toList();
    if (selectedItems.isEmpty) return;

    if (permanentDelete) {
      for (final item in selectedItems) {
        await itemProvider.permanentDeleteItem(item);
      }
      _clearSelection();
      _toggleSelectionMode();
      // 刷新数据以即时更新空间物品数量
      await _refreshData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已彻底删除 ${selectedItems.length} 个物品')),
        );
      }
    } else {
      final recycleSpace = spaceProvider.getRecycleBinSpace(selectedItems.first.houseId);
      if (recycleSpace == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未找到回收站')),
          );
        }
        return;
      }

      for (final item in selectedItems) {
        await itemProvider.moveItem(item, recycleSpace.id);
      }
      _clearSelection();
      _toggleSelectionMode();
      // 刷新数据以即时更新空间物品数量
      await _refreshData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已移至回收站 ${selectedItems.length} 个物品')),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    final houseProvider = context.read<HouseProvider>();
    final currentHouse = houseProvider.currentHouse;
    if (currentHouse != null) {
      await context.read<SpaceProvider>().loadSpaces(currentHouse.id);
      await context.read<SpaceProvider>().loadCurrentLevel(currentHouse.id);
    }
  }

  Future<void> _refreshData() async {
    final houseProvider = context.read<HouseProvider>();
    final currentHouse = houseProvider.currentHouse;
    if (currentHouse != null) {
      final spaceProvider = context.read<SpaceProvider>();
      // 保存当前空间状态（loadSpaces 会重置 currentSpace）
      final currentSpaceId = spaceProvider.currentSpace?.id;
      
      // 刷新物品数据
      await context.read<ItemProvider>().loadItems(currentHouse.id);
      // 刷新空间数据（这会重置 currentSpace）
      await spaceProvider.loadSpaces(currentHouse.id);
      // 恢复到之前的空间层级
      await spaceProvider.loadCurrentLevel(
        currentHouse.id,
        parentId: currentSpaceId,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer3<HouseProvider, SpaceProvider, ItemProvider>(
      builder: (context, houseProvider, spaceProvider, itemProvider, _) {
        final currentHouse = houseProvider.currentHouse;

        if (currentHouse == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final breadcrumb = spaceProvider.breadcrumb;
        final currentSpaces = spaceProvider.currentSpaces;
        final allItems = itemProvider.allItems;
        final currentSpace = spaceProvider.currentSpace;

        return PopScope(
          canPop: breadcrumb.isEmpty,
          onPopInvoked: (bool didPop) {
            if (!didPop && breadcrumb.isNotEmpty) {
              if (currentSpace?.parentId != null) {
                spaceProvider.loadCurrentLevel(
                  currentHouse.id,
                  parentId: currentSpace?.parentId,
                );
              } else {
                spaceProvider.loadCurrentLevel(currentHouse.id);
              }
            }
          },
          child: Scaffold(
            appBar: _isSelectionMode
                ? AppBar(
                    leading: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _toggleSelectionMode,
                    ),
                    title: Text('已选择 ${_selectedItemIds.length} 个物品'),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.select_all),
                        onPressed: () => _selectAll(allItems),
                        tooltip: '全选',
                      ),
                      IconButton(
                        icon: const Icon(Icons.drive_file_move),
                        onPressed: _selectedItemIds.isEmpty ? null : () => _batchMoveItems(context, itemProvider, spaceProvider),
                        tooltip: '移动',
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: _selectedItemIds.isEmpty ? null : () => _showBatchDeleteDialog(context, itemProvider, spaceProvider),
                        tooltip: '删除',
                      ),
                    ],
                  )
                : AppBar(
                    title: const Text('空间管理'),
                    leading: breadcrumb.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.arrow_back),
                            onPressed: () async {
                              if (currentSpace?.parentId != null) {
                                await spaceProvider.loadCurrentLevel(
                                  currentHouse.id,
                                  parentId: currentSpace?.parentId,
                                );
                              } else {
                                await spaceProvider.loadCurrentLevel(currentHouse.id);
                              }
                            },
                          )
                        : null,
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.list),
                        onPressed: () => _showSpaceHierarchy(context, spaceProvider, currentHouse.id),
                        tooltip: '空间层级管理',
                      ),
                    ],
                  ),
            body: Column(
              children: [
                _buildBreadcrumb(context, breadcrumb, currentHouse.name),
                Expanded(
                  child: _buildSpaceList(
                      context, spaceProvider, currentHouse.id, allItems),
                ),
              ],
            ),
            floatingActionButton: FloatingActionButton(
              onPressed: () => _showAddSpaceDialog(context, spaceProvider, currentHouse.id, currentSpace?.id),
              child: const Icon(Icons.add),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBreadcrumb(BuildContext context, List<dynamic> breadcrumb, String houseName) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            InkWell(
              onTap: () async {
                final houseProvider = context.read<HouseProvider>();
                final spaceProvider = context.read<SpaceProvider>();
                final currentHouse = houseProvider.currentHouse;
                if (currentHouse != null) {
                  await spaceProvider.loadCurrentLevel(currentHouse.id);
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.home, size: 16, color: Theme.of(context).colorScheme.primary),
                    SizedBox(width: 4),
                    Text(
                      houseName,
                      style: TextStyle(color: Theme.of(context).colorScheme.primary),
                    ),
                  ],
                ),
              ),
            ),
            ...breadcrumb.asMap().entries.map((entry) {
              final space = entry.value;
              return Row(
                children: [
                  const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                  InkWell(
                    onTap: () async {
                      final spaceProvider = context.read<SpaceProvider>();
                      final houseProvider = context.read<HouseProvider>();
                      final currentHouse = houseProvider.currentHouse;
                      if (currentHouse != null) {
                        await spaceProvider.loadCurrentLevel(
                          currentHouse.id,
                          parentId: space.id,
                        );
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      child: Text(space.name),
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildSpaceList(BuildContext context, SpaceProvider spaceProvider,
      String houseId, List<Item> allItems) {
    final currentSpaces = spaceProvider.currentSpaces;
    final pendingSpace = spaceProvider.getPendingSpace(houseId);
    final recycleBinSpace = spaceProvider.getRecycleBinSpace(houseId);
    final currentSpace = spaceProvider.currentSpace;

    final List<Widget> topItems = [];

    // 先添加特殊空间卡片（顶层，固定位置）
    if (spaceProvider.currentSpace == null && pendingSpace != null) {
      final pendingDirectCount = spaceProvider.getItemsInSpace(allItems, pendingSpace.id).length;
      final pendingChildCount = spaceProvider.getChildSpaces(pendingSpace.id).length;
      final pendingTotalCount = pendingDirectCount + _getChildItemsCount(spaceProvider, allItems, pendingSpace.id);
      topItems.add(_buildSpecialSpaceCard(
        context,
        pendingSpace,
        Icons.pending_actions,
        '待整理',
        Colors.orange,
        pendingDirectCount,
        pendingChildCount,
        pendingTotalCount,
      ));
    }

    if (spaceProvider.currentSpace == null && recycleBinSpace != null) {
      final recycleDirectCount = spaceProvider.getItemsInSpace(allItems, recycleBinSpace.id).length;
      final recycleChildCount = spaceProvider.getChildSpaces(recycleBinSpace.id).length;
      final recycleTotalCount = recycleDirectCount + _getChildItemsCount(spaceProvider, allItems, recycleBinSpace.id);
      topItems.add(_buildSpecialSpaceCard(
        context,
        recycleBinSpace,
        Icons.delete_outline,
        '回收站',
        Colors.red,
        recycleDirectCount,
        recycleChildCount,
        recycleTotalCount,
      ));
    }

    // 添加物品卡片（当前空间中的物品）
    final List<Widget> itemCards = [];
    if (currentSpace != null) {
      final currentSpaceItems = spaceProvider.getItemsInSpace(allItems, currentSpace.id);
      if (currentSpaceItems.isNotEmpty) {
        itemCards.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '物品 (${currentSpaceItems.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        );
        itemCards.addAll(currentSpaceItems.map((item) => _buildItemCard(context, item, currentSpace.type)));
      }
    }

    // 如果没有子空间，显示简单列表
    if (currentSpaces.isEmpty) {
      final allItems = topItems + itemCards;
      if (allItems.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.folder_open, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                '暂无空间',
                style: TextStyle(color: Colors.grey[600], fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                '点击右下角"+"添加空间',
                style: TextStyle(color: Colors.grey[400], fontSize: 14),
              ),
            ],
          ),
        );
      }
      return ListView(
        padding: const EdgeInsets.all(16),
        children: allItems,
      );
    }

    // 有子空间时，使用 ReorderableListView 支持拖拽排序
    return CustomScrollView(
      slivers: [
        // 特殊空间卡片（固定位置，不可拖拽）
        if (topItems.isNotEmpty)
          SliverList(
            delegate: SliverChildListDelegate(topItems),
          ),
        // 可拖拽排序的子空间卡片
        SliverReorderableList(
          itemBuilder: (context, index) {
            final space = currentSpaces[index];
            return ReorderableDelayedDragStartListener(
              key: ValueKey(space.id),
              index: index,
              child: _buildReorderableSpaceCard(
                context,
                space,
                spaceProvider,
                houseId,
              ),
            );
          },
          itemCount: currentSpaces.length,
          onReorder: (oldIndex, newIndex) async {
            await spaceProvider.reorderSpaces(
              houseId,
              currentSpace?.id,
              oldIndex,
              newIndex,
            );
          },
        ),
        // 物品卡片（固定位置，不可拖拽）
        if (itemCards.isNotEmpty)
          SliverList(
            delegate: SliverChildListDelegate(itemCards),
          ),
        // 底部提示
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 80),
            child: Text(
              '长按空间卡片可拖拽排序',
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReorderableSpaceCard(BuildContext context, dynamic space,
      SpaceProvider spaceProvider, String houseId) {
    final allItems = context.read<ItemProvider>().allItems;
    final childCount = spaceProvider.getChildSpaces(space.id).length;
    final directCount = spaceProvider.getItemsInSpace(allItems, space.id).length;
    final totalCount = directCount + _getChildItemsCount(spaceProvider, allItems, space.id);
    final itemCountText = childCount > 0 && totalCount != directCount
        ? '$directCount ($totalCount) 个物品'
        : '$directCount 个物品';

    return Slidable(
      key: ValueKey(space.id),
      endActionPane: ActionPane(
        motion: const ScrollMotion(),
        extentRatio: 0.5,
        children: [
          SlidableAction(
            onPressed: (context) => _editSpace(context, spaceProvider, space),
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            icon: Icons.edit,
            label: '编辑',
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12),
              bottomLeft: Radius.circular(12),
              topRight: Radius.circular(12),
              bottomRight: Radius.circular(12),
            ),
            flex: 1,
          ),
          SlidableAction(
            onPressed: (context) => _deleteSpace(context, spaceProvider, space),
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            icon: Icons.delete,
            label: '删除',
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(12),
              bottomRight: Radius.circular(12),
              topLeft: Radius.circular(12),
              bottomLeft: Radius.circular(12),
            ),
            flex: 1,
          ),
        ],
      ),
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          onTap: () => _navigateToSpace(context, space),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _buildSpaceAvatar(context, space),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        space.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        childCount > 0
                            ? '$childCount 个子空间 · $itemCountText'
                            : itemCountText,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                // 拖拽手柄图标
                ReorderableDragStartListener(
                  index: spaceProvider.currentSpaces.indexOf(space),
                  child: Icon(
                    Icons.drag_handle,
                    color: Colors.grey[400],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSpecialSpaceCard(BuildContext context, dynamic space,
      IconData icon, String title, Color color, int directItemCount, int childCount, int totalCount) {
    final itemCountText = childCount > 0 && totalCount != directItemCount
        ? '$directItemCount ($totalCount) 个物品'
        : '$directItemCount 个物品';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: color.withOpacity(0.15),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _navigateToSpace(context, space),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withOpacity(0.2),
                radius: 20,
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      childCount > 0
                          ? '$childCount 个子空间 · $itemCountText'
                          : itemCountText,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSpaceCard(BuildContext context, dynamic space,
      SpaceProvider spaceProvider, String houseId) {
    final allItems = context.read<ItemProvider>().allItems;
    final childCount = spaceProvider.getChildSpaces(space.id).length;
    final directCount = spaceProvider.getItemsInSpace(allItems, space.id).length;
    final totalCount = directCount + _getChildItemsCount(spaceProvider, allItems, space.id);
    final itemCountText = childCount > 0 && totalCount != directCount
        ? '$directCount ($totalCount) 个物品'
        : '$directCount 个物品';
    final isSpecial = spaceProvider.isSpecialSpace(space);

    if (isSpecial) {
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          onTap: () => _navigateToSpace(context, space),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _buildSpaceAvatar(context, space),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        space.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        childCount > 0
                            ? '$childCount 个子空间 · $itemCountText'
                            : itemCountText,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.grey),
              ],
            ),
          ),
        ),
      );
    }

    return Slidable(
      endActionPane: ActionPane(
        motion: const ScrollMotion(),
        extentRatio: 0.5,
        children: [
          SlidableAction(
            onPressed: (context) => _editSpace(context, spaceProvider, space),
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            icon: Icons.edit,
            label: '编辑',
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12),
              bottomLeft: Radius.circular(12),
              topRight: Radius.circular(12),
              bottomRight: Radius.circular(12),
            ),
            flex: 1,
          ),
          SlidableAction(
            onPressed: (context) => _deleteSpace(context, spaceProvider, space),
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            icon: Icons.delete,
            label: '删除',
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(12),
              bottomRight: Radius.circular(12),
              topLeft: Radius.circular(12),
              bottomLeft: Radius.circular(12),
            ),
            flex: 1,
          ),
        ],
      ),
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          onTap: () => _navigateToSpace(context, space),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _buildSpaceAvatar(context, space),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        space.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        childCount > 0
                            ? '$childCount 个子空间 · $itemCountText'
                            : itemCountText,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.grey),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _getSpaceIcon(String? iconName, String type) {
    if (iconName != null) {
      switch (iconName) {
        case '文件夹':
          return Icons.folder;
        case '房间':
          return Icons.meeting_room;
        case '容器':
          return Icons.inventory_2;
        case '箱子':
          return Icons.luggage;
        case '书架':
          return Icons.book;
        case '抽屉':
          return Icons.view_agenda;
        case '柜子':
          return Icons.store;
        case '盒子':
          return Icons.inbox;
        case '沙发':
          return Icons.weekend;
        case '床':
          return Icons.bed;
        case '餐具':
          return Icons.restaurant;
        case '马桶':
          return Icons.wc;
      }
    }
    switch (type) {
      case 'room':
        return Icons.meeting_room;
      case 'container':
        return Icons.inventory_2;
      case 'sub_container':
        return Icons.luggage;
      case 'pending':
        return Icons.pending_actions;
      case 'trash':
        return Icons.delete;
      case 'recycle':
        return Icons.delete_outline;
      default:
        return Icons.folder;
    }
  }

  Widget _buildSpaceAvatar(BuildContext context, dynamic space) {
    if (space.imagePath != null && space.imagePath!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: () => _showSpaceImagePreview(space.imagePath!),
          child: Image.file(
            File(space.imagePath!),
            width: 40,
            height: 40,
            fit: BoxFit.cover,
          ),
        ),
      );
    }
    return CircleAvatar(
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      radius: 20,
      child: Icon(
        _getSpaceIcon(space.icon, space.type),
        color: Theme.of(context).colorScheme.onPrimaryContainer,
        size: 24,
      ),
    );
  }

  Widget _buildItemCard(BuildContext context, Item item, [String? spaceType]) {
    final isSelected = _selectedItemIds.contains(item.id);
    final isExpired = item.expireDate != null && item.expireDate!.isBefore(DateTime.now());
    final isSpecialSpace = spaceType == 'recycle' || spaceType == 'trash';

    if (_isSelectionMode) {
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 0,
        color: isSelected ? Theme.of(context).colorScheme.primaryContainer : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          onTap: () => _toggleItemSelection(item.id),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Checkbox(
                  value: isSelected,
                  onChanged: (value) => _toggleItemSelection(item.id),
                ),
                const SizedBox(width: 16),
                _buildItemImage(context, item),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${item.quantity} 个 · ${item.category ?? '未分类'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                _buildExpireStatus(item),
              ],
            ),
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Slidable(
        endActionPane: isSpecialSpace
            ? _buildSpecialSpaceItemSlideActions(context, item)
            : _buildRightSlideActions(context, item),
        child: InkWell(
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ItemDetailPage(item: item),
              ),
            );
            // 返回后刷新数据
            if (mounted) {
              await _refreshData();
            }
          },
          onLongPress: () {
            _toggleSelectionMode();
            _toggleItemSelection(item.id);
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _buildItemImage(context, item),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${item.quantity} 个 · ${item.category ?? '未分类'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                _buildExpireStatus(item),
              ],
            ),
          ),
        ),
      ),
    );
  }

  ActionPane _buildLeftSlideActions(BuildContext context, Item item, bool isExpired) {
    if (isExpired) {
      return ActionPane(
        motion: const ScrollMotion(),
        extentRatio: 0.25,
        children: [
          SlidableAction(
            onPressed: (context) {
              _showConfirmDialog(context, '扔掉物品',
                  '确定将物品移至垃圾桶吗？', () async {
                await _moveItemToTrash(context, item);
              });
            },
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
      extentRatio: 0.5,
      children: [
        SlidableAction(
          onPressed: (ctx) async {
            if (item.quantity <= 1) {
              final db = Provider.of<AppDatabase>(ctx, listen: false);
              _showConfirmDialog(ctx, '移至回收站',
                  '确定将物品移至回收站吗？', () async {
                await _moveToRecycleBin(ctx, item, db);
              });
            } else {
              await _decrementQuantity(item);
            }
          },
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
          label: '-1',
          borderRadius: BorderRadius.circular(12),
        ),
        SlidableAction(
          onPressed: (context) async {
            await _incrementQuantity(item);
          },
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          label: '+1',
          borderRadius: BorderRadius.circular(12),
        ),
      ],
    );
  }

  ActionPane _buildRightSlideActions(BuildContext context, Item item) {
    return ActionPane(
      motion: const ScrollMotion(),
      extentRatio: 0.5,
      children: [
        SlidableAction(
          onPressed: (context) async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ItemDetailPage(item: item, isCopy: true),
              ),
            );
            // 返回后刷新数据
            if (mounted) {
              await _refreshData();
            }
          },
          backgroundColor: Colors.purple,
          foregroundColor: Colors.white,
          icon: Icons.copy,
          label: '复制',
          borderRadius: BorderRadius.circular(12),
        ),
        SlidableAction(
          onPressed: (context) async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ItemDetailPage(item: item, isSplit: true),
              ),
            );
            // 返回后刷新数据
            if (mounted) {
              await _refreshData();
            }
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

  ActionPane _buildSpecialSpaceItemSlideActions(BuildContext context, Item item) {
    return ActionPane(
      motion: const ScrollMotion(),
      extentRatio: 0.55,
      children: [
        SlidableAction(
          onPressed: (context) async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => RestockPage(item: item),
              ),
            );
            // 返回后刷新数据
            if (mounted) {
              await _refreshData();
            }
          },
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          icon: Icons.refresh,
          label: '补货',
          borderRadius: BorderRadius.circular(12),
        ),
        SlidableAction(
          onPressed: (context) async {
            final itemProvider = Provider.of<ItemProvider>(context, listen: false);
            await itemProvider.permanentDeleteItem(item);
            // 删除后刷新数据
            if (mounted) {
              await _refreshData();
            }
          },
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
          icon: Icons.delete_forever,
          label: '删除',
          borderRadius: BorderRadius.circular(12),
        ),
      ],
    );
  }

  void _showConfirmDialog(BuildContext context, String title, String message, Future<void> Function() onConfirm) {
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
            onPressed: () async {
              Navigator.pop(context);
              await onConfirm();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _incrementQuantity(Item item) async {
    final db = Provider.of<AppDatabase>(context, listen: false);
    await (db.update(db.items)..where((t) => t.id.equals(item.id))).write(
      ItemsCompanion(
        quantity: drift.Value(item.quantity + 1),
        modifierId: const drift.Value('user'),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );
    await context.read<ItemProvider>().loadItems(item.houseId);
    // 刷新数据以即时更新空间物品数量
    await _refreshData();
  }

  Future<void> _decrementQuantity(Item item) async {
    final db = Provider.of<AppDatabase>(context, listen: false);
    await (db.update(db.items)..where((t) => t.id.equals(item.id))).write(
      ItemsCompanion(
        quantity: drift.Value(item.quantity - 1),
        modifierId: const drift.Value('user'),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );
    await context.read<ItemProvider>().loadItems(item.houseId);
    // 刷新数据以即时更新空间物品数量
    await _refreshData();
  }

  Future<void> _moveToRecycleBin(BuildContext context, Item item, AppDatabase db) async {
    final spaceProvider = context.read<SpaceProvider>();
    final itemProvider = context.read<ItemProvider>();
    
    final recycleSpace = spaceProvider.getRecycleBinSpace(item.houseId);
    if (recycleSpace == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未找到回收站')),
      );
      return;
    }

    await (db.update(db.items)..where((t) => t.id.equals(item.id))).write(
      ItemsCompanion(
        spaceId: drift.Value(recycleSpace.id),
        quantity: const drift.Value(1),
        modifierId: const drift.Value('user'),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );
    await itemProvider.loadItems(item.houseId);
    // 刷新数据以即时更新空间物品数量
    await _refreshData();
  }

  Future<void> _moveItemToTrash(BuildContext context, Item item) async {
    final spaceProvider = context.read<SpaceProvider>();
    final itemProvider = context.read<ItemProvider>();
    final db = Provider.of<AppDatabase>(context, listen: false);
    
    final trashSpace = spaceProvider.getTrashSpace(item.houseId);
    if (trashSpace == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未找到垃圾桶')),
      );
      return;
    }

    await (db.update(db.items)..where((t) => t.id.equals(item.id))).write(
      ItemsCompanion(
        spaceId: drift.Value(trashSpace.id),
        quantity: const drift.Value(1),
        modifierId: const drift.Value('user'),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );
    await itemProvider.loadItems(item.houseId);
    // 刷新数据以即时更新空间物品数量
    await _refreshData();
  }

  Widget _buildItemImage(BuildContext context, Item item) {
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
    return CircleAvatar(
      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
      radius: 20,
      child: Icon(
        Icons.inventory,
        color: Theme.of(context).colorScheme.onSecondaryContainer,
        size: 24,
      ),
    );
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

  Widget _buildExpireStatus(dynamic item) {
    if (item.expireDate == null) {
      return const SizedBox();
    }

    final isWarrantyDate = item.customAttributes == 'warranty';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expireDay = DateTime(item.expireDate!.year, item.expireDate!.month, item.expireDate!.day);
    final difference = expireDay.difference(today).inDays;

    Color textColor;
    String text;

    final suffix = isWarrantyDate ? '过保' : '过期';
    if (difference < 0) {
      textColor = Colors.red;
      text = '已$suffix';
    } else if (difference == 0) {
      textColor = Colors.red;
      text = '今日$suffix';
    } else if (difference <= 7) {
      textColor = Colors.orange;
      text = '$difference天后$suffix';
    } else {
      textColor = Colors.grey;
      text = '$difference天后$suffix';
    }

    return Text(
      text,
      style: TextStyle(
        color: textColor,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Future<void> _navigateToSpace(BuildContext context, dynamic space) async {
    final houseProvider = context.read<HouseProvider>();
    final spaceProvider = context.read<SpaceProvider>();
    final currentHouse = houseProvider.currentHouse;

    if (currentHouse != null) {
      await spaceProvider.loadCurrentLevel(currentHouse.id, parentId: space.id);
    }
  }

  void _showSpaceItems(BuildContext context, dynamic space) async {
    final itemProvider = context.read<ItemProvider>();
    final spaceProvider = context.read<SpaceProvider>();
    final items = spaceProvider.getItemsInSpace(itemProvider.allItems, space.id);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      space.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text(
                        '暂无物品',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return ListTile(
                          title: Text(item.name),
                          subtitle: Text('x${item.quantity}'),
                          trailing: space.type == 'trash'
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.restore),
                                      onPressed: () async {
                                        final spaceProvider =
                                            context.read<SpaceProvider>();
                                        final pendingSpace =
                                            spaceProvider.getPendingSpace(
                                                item.houseId);
                                        if (pendingSpace != null) {
                                          await itemProvider.restoreItem(
                                              item, pendingSpace.id);
                                          Navigator.pop(context);
                                        }
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_forever,
                                          color: Colors.red),
                                      onPressed: () async {
                                        await itemProvider.deleteItem(item);
                                        Navigator.pop(context);
                                      },
                                    ),
                                  ],
                                )
                              : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
    
    // 弹窗关闭后刷新数据
    if (mounted) {
      await _refreshData();
    }
  }

  void _showAddSpaceDialog(BuildContext context, SpaceProvider spaceProvider,
      String houseId, String? parentId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SpaceEditPage(
          isAdd: true,
          houseId: houseId,
          parentId: parentId,
        ),
      ),
    );
    // 返回后刷新数据
    if (mounted) {
      await _refreshData();
    }
  }

  void _editSpace(
      BuildContext context, SpaceProvider spaceProvider, dynamic space) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SpaceEditPage(
          isAdd: false,
          space: space,
        ),
      ),
    );
    // 返回后刷新数据
    if (mounted) {
      await _refreshData();
    }
  }

  void _deleteSpace(
      BuildContext context, SpaceProvider spaceProvider, dynamic space) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除空间'),
        content: Text('确定要删除"${space.name}"吗？该空间下的所有物品也会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              await spaceProvider.deleteSpace(space);
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _showSpaceHierarchy(BuildContext context, SpaceProvider spaceProvider, String houseId) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SpaceHierarchyPage()),
    );
  }

  void _showSpaceImagePreview(String imagePath) {
    showDialog(
      context: navigatorKey.currentContext!,
      builder: (context) => GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Dialog(
          backgroundColor: Colors.black,
          insetPadding: EdgeInsets.zero,
          child: Center(
            child: InteractiveViewer(
              child: Image.file(File(imagePath)),
            ),
          ),
        ),
      ),
    );
  }

  int _getChildItemsCount(SpaceProvider spaceProvider, List<Item> allItems, String parentSpaceId) {
    int count = 0;
    final childSpaces = spaceProvider.getChildSpaces(parentSpaceId);
    for (final child in childSpaces) {
      count += spaceProvider.getItemsInSpace(allItems, child.id).length;
      count += _getChildItemsCount(spaceProvider, allItems, child.id);
    }
    return count;
  }
}
