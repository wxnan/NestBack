import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import '../item/item_detail_page.dart';
import '../../providers/item_provider.dart';
import '../../providers/attribute_provider.dart';
import '../../providers/house_provider.dart';
import '../../database/database.dart';

class TotalValueItemsPage extends StatefulWidget {
  const TotalValueItemsPage({super.key});

  @override
  State<TotalValueItemsPage> createState() => _TotalValueItemsPageState();
}

class _TotalValueItemsPageState extends State<TotalValueItemsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('物品总价'),
      ),
      body: Consumer2<HouseProvider, ItemProvider>(
        builder: (context, houseProvider, itemProvider, _) {
          final currentHouse = houseProvider.currentHouse;
          if (currentHouse == null) {
            return const Center(child: CircularProgressIndicator());
          }

          final items = itemProvider.items
              .where((item) => item.houseId == currentHouse.id && item.price != null)
              .toList();

          items.sort((a, b) {
            final totalA = (a.price ?? 0) * a.quantity;
            final totalB = (b.price ?? 0) * b.quantity;
            return totalB.compareTo(totalA);
          });

          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.attach_money_outlined, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    '暂无已估值的物品',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return _buildSummaryCard(context, items);
              }
              return _buildItemCard(context, items[index - 1]);
            },
          );
        },
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context, List<Item> items) {
    // 计算所有物品的总价
    double totalPrice = 0;
    for (var item in items) {
      totalPrice += (item.price ?? 0) * item.quantity;
    }

    // 需要异步获取每个物品的购买日期并计算日均成本
    return FutureBuilder<List<DateTime?>>(
      future: Future.wait(items.map((item) => _getPurchaseDate(item.id))),
      builder: (context, snapshot) {
        double totalDailyCost = 0;

        if (snapshot.hasData) {
          final purchaseDates = snapshot.data!;
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);

          for (int i = 0; i < items.length; i++) {
            final item = items[i];
            final purchaseDate = purchaseDates[i];
            if (purchaseDate != null) {
              final purchaseDay = DateTime(
                purchaseDate.year,
                purchaseDate.month,
                purchaseDate.day,
              );
              final daysOwned = today.difference(purchaseDay).inDays;
              if (daysOwned >= 0) {
                final itemTotalPrice = (item.price ?? 0) * item.quantity;
                totalDailyCost += itemTotalPrice / (daysOwned == 0 ? 1 : daysOwned);
              }
            }
          }
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '物品总价',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '¥${totalPrice >= 10000 ? totalPrice.toInt() : totalPrice.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '日均成本',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        totalDailyCost > 0
                            ? '¥${totalDailyCost.toStringAsFixed(2)}'
                            : '--',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildItemCard(BuildContext context, Item item) {
    final totalPrice = (item.price ?? 0) * item.quantity;

    return Slidable(
      key: ValueKey(item.id),
      endActionPane: ActionPane(
        motion: const ScrollMotion(),
        extentRatio: 0.3,
        children: [
          SlidableAction(
            onPressed: (ctx) => _handleIncrementUsage(ctx, item),
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            // icon: Icons.add,
            label: '使用+1',
            borderRadius: BorderRadius.circular(12),
          ),
        ],
      ),
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ItemDetailPage(item: item),
              ),
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _buildItemImage(context, item),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      _buildOwnershipInfo(context, item, totalPrice),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    '¥${totalPrice >= 10000 ? totalPrice.toInt() : totalPrice.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleIncrementUsage(BuildContext context, Item item) async {
    final attributeProvider = context.read<AttributeProvider>();
    final itemProvider = context.read<ItemProvider>();

    // 如果属性列表未加载，先加载
    if (attributeProvider.attributes.isEmpty) {
      await attributeProvider.loadAttributes();
    }

    final usageCountAttr = attributeProvider.attributes.firstWhere(
      (a) => a.name == '使用次数',
      orElse: () => Attribute(
        id: '',
        houseId: '',
        name: '',
        type: '',
        hint: null,
        options: null,
        required: false,
        sortOrder: 0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    // 检查物品是否已有使用次数属性值
    final attrs = await itemProvider.getItemAttributes(item.id);
    bool hasUsageCount = false;
    if (usageCountAttr.id.isNotEmpty && item.categoryId != null) {
      final db = context.read<AppDatabase>();
      final links = await (db.select(db.categoryAttributes)
            ..where((t) => t.categoryId.equals(item.categoryId!))
            ..where((t) => t.attributeId.equals(usageCountAttr.id)))
          .get();
      hasUsageCount = links.isNotEmpty;
    }

    if (!hasUsageCount) {
      if (!context.mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('提示'),
          content: const Text('该物品没有"使用次数"属性，无法记录使用次数。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('确定'),
            ),
          ],
        ),
      );
      return;
    }

    final currentValueStr = attrs[usageCountAttr.id];
    final currentValue = int.tryParse(currentValueStr ?? '') ?? 0;
    final newValue = currentValue + 1;

    await itemProvider.setItemAttributeValue(item.id, usageCountAttr.id, newValue.toString());
  }

  Widget _buildOwnershipInfo(BuildContext context, Item item, double totalPrice) {
    return FutureBuilder<(DateTime?, int?)>(
      future: Future.wait([
        _getPurchaseDate(item.id),
        _getUsageCount(item.id),
      ]).then((results) => (results[0] as DateTime?, results[1] as int?)),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Text(
            '单价 ¥${item.price?.toStringAsFixed(2) ?? "0.00"} × ${item.quantity}',
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          );
        }

        final purchaseDate = snapshot.data!.$1;
        final usageCount = snapshot.data!.$2;

        final children = <Widget>[];

        if (purchaseDate == null && usageCount == null) {
          children.add(
            Text(
              '¥${item.price?.toStringAsFixed(2) ?? "0.00"} × ${item.quantity}件',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          );
        }

        if (purchaseDate != null) {
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final purchaseDay = DateTime(purchaseDate.year, purchaseDate.month, purchaseDate.day);
          final daysOwned = today.difference(purchaseDay).inDays;

          if (daysOwned >= 0) {
            final dailyCost = totalPrice / (daysOwned == 0 ? 1 : daysOwned);
            children.add(
              Text(
                '¥${dailyCost.toStringAsFixed(2)} × $daysOwned天',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            );
          }
        }

        if (usageCount != null && usageCount > 0) {
          final costPerUse = totalPrice / usageCount;
          children.add(
            Text(
              '¥${costPerUse.toStringAsFixed(2)} × $usageCount次',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        );
      },
    );
  }

  Future<DateTime?> _getPurchaseDate(String itemId) async {
    final attributeProvider = context.read<AttributeProvider>();
    final itemProvider = context.read<ItemProvider>();

    final purchaseDateAttr = attributeProvider.attributes.firstWhere(
      (a) => a.name == '购买日期',
      orElse: () => Attribute(
        id: '',
        houseId: '',
        name: '',
        type: '',
        hint: null,
        options: null,
        required: false,
        sortOrder: 0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    if (purchaseDateAttr.id.isEmpty) return null;

    final attrs = await itemProvider.getItemAttributes(itemId);
    final dateStr = attrs[purchaseDateAttr.id];
    if (dateStr == null || dateStr.isEmpty) return null;

    try {
      return DateTime.parse(dateStr);
    } catch (_) {
      return null;
    }
  }

  Future<int?> _getUsageCount(String itemId) async {
    final attributeProvider = context.read<AttributeProvider>();
    final itemProvider = context.read<ItemProvider>();

    final usageCountAttr = attributeProvider.attributes.firstWhere(
      (a) => a.name == '使用次数',
      orElse: () => Attribute(
        id: '',
        houseId: '',
        name: '',
        type: '',
        hint: null,
        options: null,
        required: false,
        sortOrder: 0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    if (usageCountAttr.id.isEmpty) return null;

    final attrs = await itemProvider.getItemAttributes(itemId);
    final countStr = attrs[usageCountAttr.id];
    if (countStr == null || countStr.isEmpty) return null;

    return int.tryParse(countStr);
  }

  Widget _buildItemImage(BuildContext context, Item item) {
    if (item.imagePath != null && item.imagePath!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(item.imagePath!),
          width: 48,
          height: 48,
          fit: BoxFit.cover,
        ),
      );
    }
    return _buildItemIcon(item.category);
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

    final iconData = icons[category] ?? Icons.inventory_2;
    final iconColor = colors[category] ?? Colors.grey;

    return CircleAvatar(
      backgroundColor: iconColor.withOpacity(0.15),
      radius: 24,
      child: Icon(iconData, color: iconColor),
    );
  }
}
