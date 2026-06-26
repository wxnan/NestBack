import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'dart:io';
import '../../providers/house_provider.dart';
import '../../providers/item_provider.dart';
import '../../providers/space_provider.dart';
import '../../providers/settings_provider.dart';
import '../../database/database.dart';
import '../item/item_detail_page.dart';
import 'restock_page.dart';

class ExpiredItemsPage extends StatefulWidget {
  final bool isExpiring;

  const ExpiredItemsPage({super.key, this.isExpiring = false});

  @override
  State<ExpiredItemsPage> createState() => _ExpiredItemsPageState();
}

class _ExpiredItemsPageState extends State<ExpiredItemsPage> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await Future.delayed(const Duration(milliseconds: 100));
    setState(() {
      _isLoading = false;
    });
  }

  String _getSpacePath(Space space, SpaceProvider spaceProvider) {
    List<String> path = [space.name];
    String? parentId = space.parentId;

    while (parentId != null) {
      final parent = spaceProvider.spaces.firstWhere(
        (s) => s.id == parentId,
        orElse: () => Space(id: '', houseId: '', name: '', type: 'room', createdAt: DateTime.now(), updatedAt: DateTime.now()),
      );
      if (parent.name.isEmpty) break;
      path.insert(0, parent.name);
      parentId = parent.parentId;
    }

    return path.join(' - ');
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
    return _buildItemIcon(context, item.category);
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

  Widget _buildItemIcon(BuildContext context, String? category) {
    final icons = {
      '食品': Icons.local_dining,
      '药品': Icons.medication,
      '日用品': Icons.cleaning_services,
      '数码': Icons.devices,
      '美妆': Icons.spa,
    };

    final iconData = icons[category] ?? Icons.inventory_2;
    final colors = {
      '食品': Colors.amber,
      '药品': Colors.green,
      '日用品': Colors.blue,
      '数码': Colors.purple,
      '美妆': Colors.pink,
    };
    final iconColor = colors[category] ?? Colors.grey;

    return CircleAvatar(
      backgroundColor: iconColor.withOpacity(0.15),
      child: Icon(
        iconData,
        color: iconColor,
      ),
    );
  }

  Widget _buildPropertyValue(BuildContext context, dynamic item) {
    if (item.expireDate == null) {
      return const SizedBox();
    }
    final isWarrantyDate = item.customAttributes == 'warranty';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expireDay = DateTime(item.expireDate!.year, item.expireDate!.month, item.expireDate!.day);
    final diff = expireDay.difference(today).inDays;
    String text;
    Color color;

    final suffix = isWarrantyDate ? '过保' : '过期';
    if (diff < 0) {
      text = '已$suffix ${-diff} 天';
      color = Colors.red;
    } else if (diff == 0) {
      text = '今天$suffix';
      color = Colors.orange;
    } else if (diff <= 7) {
      text = '$diff 天后$suffix';
      color = Colors.orange;
    } else {
      text = '$diff 天后$suffix';
      color = Colors.grey;
    }

    return Text(
      text,
      style: TextStyle(color: color, fontSize: 12),
    );
  }

  ActionPane _buildEndSlideActions(BuildContext context, dynamic item, ItemProvider itemProvider, SpaceProvider spaceProvider) {
    return ActionPane(
      motion: const ScrollMotion(),
      extentRatio: 0.55,
      children: [
        SlidableAction(
          onPressed: (context) => _navigateToRestockPage(context, item),
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          icon: Icons.refresh,
          label: '补货',
          borderRadius: BorderRadius.circular(12),
        ),
        SlidableAction(
          onPressed: (context) => _moveToTrash(context, item, itemProvider, spaceProvider),
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
          icon: Icons.delete,
          label: '扔掉',
          borderRadius: BorderRadius.circular(12),
        ),
      ],
    );
  }

  Future<void> _moveToTrash(BuildContext context, dynamic item, ItemProvider itemProvider, SpaceProvider spaceProvider) async {
    final trashSpace = spaceProvider.spaces.firstWhere(
      (s) => s.houseId == item.houseId && s.type == 'trash',
      orElse: () => Space(id: '', houseId: item.houseId, name: '垃圾桶', type: 'trash', createdAt: DateTime.now(), updatedAt: DateTime.now()),
    );

    if (trashSpace.id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未找到垃圾桶空间')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('扔掉物品'),
        content: const Text('确定将物品移至垃圾桶吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await itemProvider.moveItem(item, trashSpace.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('物品已移至垃圾桶')),
        );
      }
    }
  }

  void _navigateToRestockPage(BuildContext context, dynamic item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RestockPage(item: item),
      ),
    );
  }

  Future<void> _moveToSpace(BuildContext context, dynamic item, ItemProvider itemProvider, SpaceProvider spaceProvider) async {
    await spaceProvider.loadSpaces(item.houseId);
    final spaces = spaceProvider.spaces
        .where((s) => s.type != 'trash')
        .toList();

    if (!mounted) return;

    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => ListView.builder(
        itemCount: spaces.length,
        itemBuilder: (context, index) {
          final space = spaces[index];
          return ListTile(
            leading: Icon(_getSpaceIcon(space.type)),
            title: Text(space.name),
            subtitle: Text(_getSpaceTypeName(space.type)),
            onTap: () => Navigator.pop(context, space.id),
          );
        },
      ),
    );

    if (result != null) {
      await itemProvider.moveItem(item, result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('物品已移动')),
        );
      }
    }
  }

  String _getSpaceTypeName(String type) {
    switch (type) {
      case 'room':
        return '房间';
      case 'container':
        return '容器';
      case 'sub_container':
        return '子容器';
      case 'pending':
        return '待整理';
      default:
        return type;
    }
  }

  IconData _getSpaceIcon(String type) {
    switch (type) {
      case 'room':
        return Icons.meeting_room;
      case 'container':
        return Icons.inventory_2;
      case 'sub_container':
        return Icons.luggage;
      case 'pending':
        return Icons.pending;
      default:
        return Icons.folder;
    }
  }

  void _showDeleteDialog(BuildContext context, dynamic item, ItemProvider itemProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除物品'),
        content: const Text('确定要删除这个物品吗？此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              await itemProvider.deleteItem(item);
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('物品已删除')),
                );
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  Widget _buildItemCard(BuildContext context, dynamic item, ItemProvider itemProvider, SpaceProvider spaceProvider) {
    final space = spaceProvider.spaces.firstWhere(
      (s) => s.id == item.spaceId,
      orElse: () => Space(id: '', houseId: item.houseId, name: '未知位置', type: 'room', createdAt: DateTime.now(), updatedAt: DateTime.now()),
    );
    final spacePath = _getSpacePath(space, spaceProvider);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Slidable(
        endActionPane: _buildEndSlideActions(context, item, itemProvider, spaceProvider),
        child: ListTile(
          leading: _buildItemImage(context, item),
          title: Text(item.name),
          subtitle: Row(
            children: [
              Flexible(
                child: Text(
                  spacePath,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '×${item.quantity}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.secondary,
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          trailing: _buildPropertyValue(context, item),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ItemDetailPage(item: item),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isExpiring ? '即将过期' : '已经过期';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Consumer4<ItemProvider, SpaceProvider, HouseProvider, SettingsProvider>(
              builder: (context, itemProvider, spaceProvider, houseProvider, settingsProvider, _) {
                final currentHouse = houseProvider.currentHouse;
                if (currentHouse == null) {
                  return const Center(child: Text('请先选择一个家庭'));
                }

                List<dynamic> items;
                if (widget.isExpiring) {
                  items = itemProvider.getExpiringItems(currentHouse.id, settingsProvider.expiringThresholdDays);
                } else {
                  items = itemProvider.getExpiredItems(currentHouse.id);
                }

                // 过滤掉回收站和垃圾桶空间的物品
                final excludedSpaceTypes = {'recycle', 'trash'};
                final excludedSpaceIds = spaceProvider.spaces
                    .where((s) => excludedSpaceTypes.contains(s.type))
                    .map((s) => s.id)
                    .toSet();
                items = items.where((item) => !excludedSpaceIds.contains(item.spaceId)).toList();

                final now = DateTime.now();
                final today = DateTime(now.year, now.month, now.day);

                // 已经过期页面按过期天数从多到少排序
                if (!widget.isExpiring) {
                  items.sort((a, b) {
                    final aExpireDay = DateTime(a.expireDate!.year, a.expireDate!.month, a.expireDate!.day);
                    final bExpireDay = DateTime(b.expireDate!.year, b.expireDate!.month, b.expireDate!.day);
                    final aDays = today.difference(aExpireDay).inDays;
                    final bDays = today.difference(bExpireDay).inDays;
                    return bDays.compareTo(aDays);
                  });
                } else {
                  // 即将过期页面按距离过期天数从小到大排序
                  items.sort((a, b) {
                    final aExpireDay = DateTime(a.expireDate!.year, a.expireDate!.month, a.expireDate!.day);
                    final bExpireDay = DateTime(b.expireDate!.year, b.expireDate!.month, b.expireDate!.day);
                    final aDays = aExpireDay.difference(today).inDays;
                    final bDays = bExpireDay.difference(today).inDays;
                    return aDays.compareTo(bDays);
                  });
                }

                if (items.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          widget.isExpiring ? Icons.check_circle : Icons.check_circle,
                          size: 64,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          widget.isExpiring ? '暂无即将过期的物品' : '暂无已过期的物品',
                          style: TextStyle(color: Colors.grey[500]),
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
}