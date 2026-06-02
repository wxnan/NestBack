import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../providers/house_provider.dart';
import '../../providers/item_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/space_provider.dart';
import '../../providers/settings_provider.dart';
import '../home/expired_items_page.dart';
import './pending_value_items_page.dart';
import './low_stock_items_page.dart';
import './total_value_items_page.dart';

class StatsTab extends StatefulWidget {
  const StatsTab({super.key});

  @override
  State<StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<StatsTab> {
  String _selectedDimension = 'category';

  @override
  Widget build(BuildContext context) {
    return Consumer5<HouseProvider, ItemProvider, CategoryProvider, SpaceProvider, SettingsProvider>(
      builder: (context, houseProvider, itemProvider, categoryProvider, spaceProvider, settingsProvider, _) {
        final currentHouse = houseProvider.currentHouse;

        if (currentHouse == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final items = itemProvider.items;
        
        // 获取过期和即将过期物品
        final expiredItems = itemProvider.getExpiredItems(currentHouse.id);
        final expiringItems = itemProvider.getExpiringItems(currentHouse.id, settingsProvider.expiringThresholdDays);
        
        // 过滤掉回收站和垃圾桶空间的物品
        final excludedSpaceTypes = {'recycle', 'trash'};
        final excludedSpaceIds = spaceProvider.spaces
            .where((s) => excludedSpaceTypes.contains(s.type))
            .map((s) => s.id)
            .toSet();
        
        final filteredExpiredItems = expiredItems.where((item) => !excludedSpaceIds.contains(item.spaceId)).toList();
        final filteredExpiringItems = expiringItems.where((item) => !excludedSpaceIds.contains(item.spaceId)).toList();
        
        final expiredCount = filteredExpiredItems.length;
        final expiringCount = filteredExpiringItems.length;

        final totalItems = items.length;
        final totalValue = items.fold<double>(
            0, (sum, item) => sum + (item.price ?? 0) * item.quantity);
        final pendingValueItems =
            items.where((item) => item.price == null).length;
        
        return FutureBuilder<int>(
          future: itemProvider.getLowStockItemsCount(currentHouse.id, settingsProvider.lowStockThreshold),
          initialData: 0,
          builder: (context, snapshot) {
            final lowStockItems = snapshot.data ?? 0;
            
            return Scaffold(
              appBar: AppBar(
                title: const Text('统计'),
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildOverviewCards(
                        context, totalItems, totalValue, expiredCount, expiringCount),
                    const SizedBox(height: 16),
                    _buildSecondaryIndicators(
                        context, pendingValueItems, lowStockItems),
                    const SizedBox(height: 24),
                    _buildDimensionSelector(context),
                    const SizedBox(height: 16),
                    _buildPieChart(context, items, spaceProvider, currentHouse.name),
                    const SizedBox(height: 16),
                    _buildCategoryList(context, items, spaceProvider, currentHouse.name),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildOverviewCards(BuildContext context, int totalItems,
      double totalValue, int expiredCount, int expiringCount) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                context,
                '物品总数',
                '${totalItems}件',
                Icons.inventory_2,
                Colors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const TotalValueItemsPage(),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: _buildStatCard(
                  context,
                  '物品总价',
                  '¥${totalValue >= 10000 ? totalValue.toInt() : totalValue.toStringAsFixed(2)}',
                  Icons.attach_money,
                  Colors.green,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ExpiredItemsPage(isExpiring: false),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: _buildStatCard(
                  context,
                  '已经过期',
                  '${expiredCount}件',
                  Icons.warning,
                  Colors.red,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ExpiredItemsPage(isExpiring: true),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: _buildStatCard(
                  context,
                  '即将过期',
                  '${expiringCount}件',
                  Icons.schedule,
                  Colors.orange,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(BuildContext context, String title, String value,
      IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecondaryIndicators(
      BuildContext context, int pendingValueItems, int lowStockItems) {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const PendingValueItemsPage(),
                ),
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '等待估值',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${pendingValueItems}件',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const LowStockItemsPage(),
                ),
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '低库存提醒',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${lowStockItems}件',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: lowStockItems > 0 ? Colors.orange : Colors.grey,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDimensionSelector(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildDimensionChip('按分类', 'category'),
          const SizedBox(width: 8),
          _buildDimensionChip('按房间', 'space'),
          const SizedBox(width: 8),
          _buildDimensionChip('按标签', 'tag'),
        ],
      ),
    );
  }

  Widget _buildDimensionChip(String label, String value) {
    final isSelected = _selectedDimension == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _selectedDimension = value;
          });
        }
      },
    );
  }

  Widget _buildPieChart(BuildContext context, List<dynamic> items, SpaceProvider spaceProvider, String houseName) {
    if (items.isEmpty) {
      return Card(
        child: Container(
          height: 300,
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.pie_chart_outline, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  '暂无数据',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final categoryData = _groupByDimension(items, _selectedDimension, spaceProvider, houseName);

    if (categoryData.isEmpty) {
      return Card(
        child: Container(
          height: 300,
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Text(
              '该维度暂无分类数据',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
        ),
      );
    }

    final colors = _getColors(categoryData.length);
    final total = categoryData.values.fold<int>(0, (sum, count) => sum + count);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SizedBox(
              height: 250,
              child: PieChart(
                PieChartData(
                  sections: categoryData.entries.toList().asMap().entries.map((entry) {
                    final index = entry.key;
                    final count = entry.value.value;
                    final percentage = (count / total * 100).toStringAsFixed(1);

                    return PieChartSectionData(
                      color: colors[index],
                      value: count.toDouble(),
                      title: '$percentage%',
                      radius: 80,
                      titleStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    );
                  }).toList(),
                  sectionsSpace: 2,
                  centerSpaceRadius: 40,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: categoryData.entries.toList().asMap().entries.map((entry) {
                final index = entry.key;
                final category = entry.value.key;
                final count = entry.value.value;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: colors[index],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        '$category ($count)',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryList(BuildContext context, List<dynamic> items, SpaceProvider spaceProvider, String houseName) {
    final categoryData = _groupByDimension(items, _selectedDimension, spaceProvider, houseName);
    final sortedCategories = categoryData.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (sortedCategories.isEmpty) {
      return const SizedBox();
    }

    final colors = _getColors(sortedCategories.length);
    final total = items.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '分类详情',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            ...sortedCategories.asMap().entries.map((entry) {
              final index = entry.key;
              final category = entry.value.key;
              final count = entry.value.value;
              final percentage = count / total;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: colors[index],
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  category,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text('$count 个 (${(percentage * 100).toStringAsFixed(1)}%)'),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: percentage,
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation<Color>(colors[index]),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Map<String, int> _groupByDimension(List<dynamic> items, String dimension, SpaceProvider spaceProvider, String houseName) {
    final Map<String, int> result = {};

    for (final item in items) {
      String key;
      switch (dimension) {
        case 'category':
          key = item.category ?? '未分类';
          break;
        case 'space':
          final space = spaceProvider.spaces.firstWhere(
            (s) => s.id == item.spaceId,
            orElse: () => throw Exception('Space not found'),
          );
          key = _getTopLevelSpaceName(space, spaceProvider, houseName);
          break;
        case 'tag':
          key = item.tags?.split(',').first ?? '无标签';
          if (key.isEmpty) key = '无标签';
          break;
        default:
          key = '其他';
      }

      result[key] = (result[key] ?? 0) + 1;
    }

    result.removeWhere((key, value) => key == '未分类' || key == '无标签');
    if (result.isEmpty) {
      result['未分类'] = items.length;
    }

    return result;
  }

  String _getTopLevelSpaceName(dynamic space, SpaceProvider spaceProvider, String houseName) {
    var currentSpace = space;
    
    while (currentSpace.parentId != null) {
      try {
        currentSpace = spaceProvider.spaces.firstWhere(
          (s) => s.id == currentSpace.parentId,
        );
      } catch (_) {
        break;
      }
    }
    
    return currentSpace.name;
  }

  List<Color> _getColors(int count) {
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.red,
      Colors.teal,
      Colors.pink,
      Colors.indigo,
      Colors.amber,
      Colors.cyan,
    ];

    return List.generate(count, (index) => colors[index % colors.length]);
  }
}
