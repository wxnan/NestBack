import 'dart:io';
import 'package:flutter/material.dart';
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
            itemCount: items.length,
            itemBuilder: (context, index) {
              return _buildItemCard(context, items[index]);
            },
          );
        },
      ),
    );
  }

  Widget _buildItemCard(BuildContext context, Item item) {
    final totalPrice = (item.price ?? 0) * item.quantity;

    return Card(
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
    );
  }

  Widget _buildOwnershipInfo(BuildContext context, Item item, double totalPrice) {
    return FutureBuilder<DateTime?>(
      future: _getPurchaseDate(item.id),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          return Text(
            '单价 ¥${item.price?.toStringAsFixed(2) ?? "0.00"} × ${item.quantity}',
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          );
        }

        final purchaseDate = snapshot.data!;
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final purchaseDay = DateTime(purchaseDate.year, purchaseDate.month, purchaseDate.day);
        final daysOwned = today.difference(purchaseDay).inDays;

        String daysText;
        if (daysOwned < 0) {
          daysText = '尚未拥有';
        } else if (daysOwned == 0) {
          daysText = '今日购入';
        } else {
          daysText = '已拥有$daysOwned天';
        }

        String dailyCostText;
        if (daysOwned > 0) {
          final dailyCost = totalPrice / daysOwned;
          dailyCostText = '日均 ¥${dailyCost.toStringAsFixed(2)}';
        } else {
          dailyCostText = '日均 --';
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.schedule, size: 14, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    daysText,
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Icon(Icons.trending_down, size: 14, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    dailyCostText,
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
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
