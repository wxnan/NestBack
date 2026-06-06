import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../database/database.dart';
import '../../providers/house_provider.dart';
import '../../providers/item_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/space_provider.dart';
import '../../providers/tag_provider.dart';

class HouseManagerPage extends StatelessWidget {
  const HouseManagerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('家庭管理'),
      ),
      body: Consumer<HouseProvider>(
        builder: (context, houseProvider, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildCurrentHouseSection(context, houseProvider),
              const SizedBox(height: 24),
              _buildHouseListSection(context, houseProvider),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateHouseDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('创建家庭'),
      ),
    );
  }

  Widget _buildCurrentHouseSection(BuildContext context, HouseProvider houseProvider) {
    final currentHouse = houseProvider.currentHouse;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            '当前家庭',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: currentHouse == null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.home_outlined, size: 48, color: Colors.grey[400]),
                        const SizedBox(height: 12),
                        Text(
                          '请选择或创建一个家庭',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                )
              : InkWell(
                  onTap: () => _showSwitchHouseDialog(context, houseProvider),
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.home,
                            size: 32,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                currentHouse.name,
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '点击切换家庭',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.grey[600],
                                    ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.swap_horiz,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildHouseListSection(BuildContext context, HouseProvider houseProvider) {
    final houses = houseProvider.houses;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            '家庭列表',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        if (houses.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.inbox, size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 12),
                    Text(
                      '暂无家庭，点击下方按钮创建',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          ...houses.map((house) => _buildHouseCard(context, houseProvider, house)),
      ],
    );
  }

  Widget _buildHouseCard(BuildContext context, HouseProvider houseProvider, House house) {
    final isCurrent = house.id == houseProvider.currentHouse?.id;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isCurrent
            ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isCurrent
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isCurrent ? Icons.home : Icons.home_outlined,
                color: isCurrent
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey[600],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    house.name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                  if (isCurrent) ...[
                    const SizedBox(height: 2),
                    Text(
                      '当前家庭',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              onPressed: () => _showEditHouseDialog(context, houseProvider, house),
              icon: Icon(Icons.edit_outlined, size: 20, color: Colors.grey[600]),
              tooltip: '编辑',
            ),
            IconButton(
              onPressed: isCurrent
                  ? null
                  : () => _showDeleteConfirmDialog(context, houseProvider, house),
              icon: Icon(
                Icons.delete_outline,
                size: 20,
                color: isCurrent ? Colors.grey[300] : Colors.red[400],
              ),
              tooltip: isCurrent ? '无法删除当前家庭' : '删除',
            ),
          ],
        ),
      ),
    );
  }

  void _showSwitchHouseDialog(BuildContext context, HouseProvider houseProvider) {
    final houses = houseProvider.houses;
    if (houses.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前只有一个家庭，无法切换')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择当前家庭'),
        children: houses.map((house) {
          final isCurrent = house.id == houseProvider.currentHouse?.id;
          return SimpleDialogOption(
            onPressed: () async {
              houseProvider.switchHouse(house);
              Navigator.pop(context);
              await context.read<ItemProvider>().loadItems(house.id);
              if (!context.mounted) return;
              await context.read<CategoryProvider>().loadCategories();
              if (!context.mounted) return;
              await context.read<SpaceProvider>().loadSpaces(house.id);
              if (!context.mounted) return;
              await context.read<TagProvider>().loadTags();
              if (!context.mounted) return;
              _setSpecialSpaceIds(context, house.id);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('已切换到"${house.name}"')),
              );
            },
            child: Row(
              children: [
                Icon(
                  isCurrent ? Icons.check_circle : Icons.circle_outlined,
                  color: isCurrent ? Theme.of(context).colorScheme.primary : Colors.grey,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(
                  house.name,
                  style: TextStyle(
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                if (isCurrent) ...[
                  const SizedBox(width: 8),
                  Text(
                    '(当前)',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  void _showEditHouseDialog(BuildContext context, HouseProvider houseProvider, House house) {
    final controller = TextEditingController(text: house.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑家庭名称'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '家庭名称',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != house.name) {
                houseProvider.updateHouse(house.id, newName);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已更名为"$newName"')),
                );
              } else {
                Navigator.pop(context);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmDialog(BuildContext context, HouseProvider houseProvider, House house) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除家庭'),
        content: Text(
          '确定要删除"${house.name}"吗？\n\n'
          '该操作将删除该家庭下的所有空间和物品数据，且不可恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              houseProvider.deleteHouse(house.id);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('已删除"${house.name}"')),
              );
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _showCreateHouseDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('创建新家庭'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '家庭名称',
            hintText: '例如：我的家',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                context.read<HouseProvider>().createHouse(name);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已创建"$name"')),
                );
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  void _setSpecialSpaceIds(BuildContext context, String houseId) {
    final spaceProvider = context.read<SpaceProvider>();
    final itemProvider = context.read<ItemProvider>();
    final specialSpaceIds = <String>[];

    final recycleSpace = spaceProvider.getRecycleBinSpace(houseId);
    if (recycleSpace != null) {
      specialSpaceIds.add(recycleSpace.id);
    }

    for (final space in spaceProvider.spaces) {
      if (space.houseId == houseId && space.type == 'trash') {
        specialSpaceIds.add(space.id);
        break;
      }
    }

    itemProvider.setSpecialSpaceIds(specialSpaceIds);
  }
}
