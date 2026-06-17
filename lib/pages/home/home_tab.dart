import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:drift/drift.dart' as drift;
import 'dart:io';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/house_provider.dart';
import '../../providers/item_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/space_provider.dart';
import '../../providers/tag_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/attribute_provider.dart';
import '../../database/database.dart';
import '../item/item_detail_page.dart';
import '../notification/notification_page.dart';
import '../stats/total_value_items_page.dart';
import 'expired_items_page.dart';
import 'restock_page.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final TextEditingController _searchController = TextEditingController();
  String _sortBy = 'createdAt';
  String _displayMode = 'default'; // default, expire, price
  String? _lastHouseId;
  int _lastSpaceCount = 0;
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
      } else {
        _selectedItemIds.add(itemId);
      }
    });
  }

  void _selectAll(List<dynamic> items) {
    setState(() {
      _selectedItemIds.addAll(items.map((item) => item.id as String));
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedItemIds.clear();
    });
  }

  @override
  void initState() {
    super.initState();
    _loadDisplayMode();
  }

  Future<void> _loadDisplayMode() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString('home_display_mode');
    if (savedMode != null && mounted) {
      setState(() {
        _displayMode = savedMode;
      });
    }
  }

  Future<void> _saveDisplayMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('home_display_mode', mode);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer6<HouseProvider, ItemProvider, CategoryProvider, SpaceProvider, TagProvider, SettingsProvider>(
      builder: (context, houseProvider, itemProvider, categoryProvider, spaceProvider, tagProvider, settingsProvider, _) {
        final currentHouse = houseProvider.currentHouse;

        if (currentHouse == null) {
          return const Center(child: CircularProgressIndicator());
        }

        // 当家庭变化或空间数据变化时，设置特殊空间ID
        // 必须在 post-frame 回调中执行，避免在 build 期间调用 notifyListeners
        if (_lastHouseId != currentHouse.id || _lastSpaceCount != spaceProvider.spaces.length) {
          print('家庭或空间数据变化，延迟设置特殊空间ID');
          _lastHouseId = currentHouse.id;
          _lastSpaceCount = spaceProvider.spaces.length;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _setSpecialSpaceIds(spaceProvider, itemProvider, currentHouse.id);
              _setSpaceNames(spaceProvider, itemProvider);
            }
          });
        }

        final expiredItems = itemProvider.getExpiredItems(currentHouse.id);
        final expiringItems =
            itemProvider.getExpiringItems(currentHouse.id, settingsProvider.expiringThresholdDays);

        // 过滤掉回收站和垃圾桶空间的物品
        final excludedSpaceTypes = {'recycle', 'trash'};
        final excludedSpaceIds = spaceProvider.spaces
            .where((s) => excludedSpaceTypes.contains(s.type))
            .map((s) => s.id)
            .toSet();
        final filteredExpiredItems = expiredItems.where((item) => !excludedSpaceIds.contains(item.spaceId)).toList();
        final filteredExpiringItems = expiringItems.where((item) => !excludedSpaceIds.contains(item.spaceId)).toList();

        return Scaffold(
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
                      onPressed: () => _selectAll(itemProvider.items),
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
              : null,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (!_isSelectionMode)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(
                          '我的收纳',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        Row(
                          children: <Widget>[
                            _buildNotificationButton(context),
                            const SizedBox(width: 8),
                            _buildHouseSelector(context, houseProvider, currentHouse, itemProvider, categoryProvider, spaceProvider, tagProvider),
                          ],
                        ),
                      ],
                    ),
                  ),
                _buildStatisticsBanner(
                  context, filteredExpiredItems.length, filteredExpiringItems.length, itemProvider.items),
                _buildSearchBar(context, itemProvider),
                const SizedBox(height: 8),
                _buildCategoryFilter(context, categoryProvider, itemProvider),
                const SizedBox(height: 8),
                _buildTagFilter(context, tagProvider, itemProvider),
                _buildSortAndPropertyBar(context, itemProvider),
                Expanded(
                  child: _buildItemList(context, itemProvider, spaceProvider),
                ),
              ],
            ),
          )
        );
      },
    );
  }

  Widget _buildSortAndPropertyBar(BuildContext context, ItemProvider itemProvider) {
    return Container(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '物品列表',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          Row(
            children: [
              _buildModeButton(context, itemProvider),
              _buildSortButton(context, itemProvider),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModeButton(BuildContext context, ItemProvider itemProvider) {
    final modeOptions = {
      'default': '默认模式',
      'expire': '过期模式',
      'price': '价格模式',
    };
    return PopupMenuButton<String>(
      icon: const Icon(Icons.view_module_outlined),
      tooltip: '模式: ${modeOptions[_displayMode] ?? _displayMode}',
      onSelected: (value) {
        setState(() {
          _displayMode = value;
        });
        _saveDisplayMode(value);
      },
      itemBuilder: (context) => modeOptions.entries.map((entry) {
        return PopupMenuItem<String>(
          value: entry.key,
          child: Row(
            children: [
              if (_displayMode == entry.key)
                Icon(Icons.check, size: 18, color: Theme.of(context).colorScheme.primary)
              else
                const SizedBox(width: 18),
              const SizedBox(width: 8),
              Text(entry.value),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSortButton(BuildContext context, ItemProvider itemProvider) {
    final sortOptions = {
      'createdAt': '最近添加',
      'updatedAt': '最近修改',
      'expireDate': '最近过期',
      'price': '最高价格',
    };
    return PopupMenuButton<String>(
      icon: const Icon(Icons.sort),
      tooltip: '排序: ${sortOptions[_sortBy] ?? _sortBy}',
      onSelected: (value) {
        setState(() {
          _sortBy = value;
        });
        itemProvider.setSortBy(value, ascending: value == 'expireDate');
      },
      itemBuilder: (context) => sortOptions.entries.map((entry) {
        return PopupMenuItem<String>(
          value: entry.key,
          child: Row(
            children: [
              if (_sortBy == entry.key)
                Icon(Icons.check, size: 18, color: Theme.of(context).colorScheme.primary)
              else
                const SizedBox(width: 18),
              const SizedBox(width: 8),
              Text(entry.value),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStatisticsBanner(
      BuildContext context, int expiredCount, int expiringCount, List<dynamic> items) {
    if (_displayMode == 'default') {
      return const SizedBox(height: 16);
    }

    if (_displayMode == 'expire') {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: _buildStatCard(
                context,
                '已经过期',
                '$expiredCount件',
                const LinearGradient(
                  colors: [Color(0xFFFF6B6B), Color(0xFFFF8E53)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                Colors.white,
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ExpiredItemsPage(isExpiring: false),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                context,
                '即将过期',
                '$expiringCount件',
                const LinearGradient(
                  colors: [Color(0xFFFFB347), Color(0xFFFF8C00)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                Colors.white,
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ExpiredItemsPage(isExpiring: true),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    }

    // price mode
    final totalPrice = items.fold(0.0, (sum, item) => sum + (item.price ?? 0) * item.quantity);
    return FutureBuilder<double>(
      future: _calculateTotalDailyCost(items),
      builder: (context, snapshot) {
        final dailyCost = snapshot.data ?? 0.0;
        final value1 = '¥${totalPrice >= 10000 ? totalPrice.toInt() : totalPrice.toStringAsFixed(2)}';
        final value2 = dailyCost > 0 ? '¥${dailyCost.toStringAsFixed(2)}' : '¥--';
        final screenWidth = MediaQuery.of(context).size.width;
        final cardWidth = (screenWidth - 32 - 12) / 2 - 32; // padding 16*2 + gap 12 + card padding 16*2
        final fontSize = _calculateUniformFontSize([value1, value2], cardWidth);
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  context,
                  '物品总价',
                  value1,
                  const LinearGradient(
                    colors: [Color(0xFF2196F3), Color(0xFF64B5F6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  Colors.white,
                  () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const TotalValueItemsPage(),
                      ),
                    );
                  },
                  fontSize: fontSize,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  context,
                  '日均成本',
                  value2,
                  const LinearGradient(
                    colors: [Color(0xFF4CAF50), Color(0xFF81C784)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  Colors.white,
                  () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const TotalValueItemsPage(),
                      ),
                    );
                  },
                  fontSize: fontSize,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<double> _calculateTotalDailyCost(List<dynamic> items) async {
    final attributeProvider = context.read<AttributeProvider>();
    final itemProvider = context.read<ItemProvider>();

    if (attributeProvider.attributes.isEmpty) {
      await attributeProvider.loadAttributes();
    }

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

    if (purchaseDateAttr.id.isEmpty) return 0.0;

    double totalDailyCost = 0.0;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    for (final item in items) {
      final itemTotalPrice = (item.price ?? 0) * item.quantity;
      if (itemTotalPrice <= 0) continue;

      final attrs = await itemProvider.getItemAttributes(item.id);
      final dateStr = attrs[purchaseDateAttr.id];
      if (dateStr == null || dateStr.isEmpty) continue;

      try {
        final purchaseDate = DateTime.parse(dateStr);
        final purchaseDay = DateTime(purchaseDate.year, purchaseDate.month, purchaseDate.day);
        final daysOwned = today.difference(purchaseDay).inDays;
        if (daysOwned >= 0) {
          totalDailyCost += itemTotalPrice / (daysOwned == 0 ? 1 : daysOwned);
        }
      } catch (_) {
        continue;
      }
    }

    return totalDailyCost;
  }

  double _calculateUniformFontSize(List<String> values, double maxWidth, {double baseFontSize = 32}) {
    final maxTextWidth = values.map((value) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(fontSize: baseFontSize, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      return textPainter.width;
    }).reduce(math.max);

    if (maxTextWidth <= maxWidth) return baseFontSize;
    return baseFontSize * (maxWidth / maxTextWidth);
  }

  Widget _buildStatCard(BuildContext context, String title, String value,
      LinearGradient gradient, Color textColor, VoidCallback onTap, {double? fontSize}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: textColor,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  color: textColor,
                  fontSize: fontSize ?? 32,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context, ItemProvider itemProvider) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: '搜索名称、分类、位置、标签、备注、品牌等...',
            hintStyle: TextStyle(color: Colors.grey[400]),
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 16, right: 8),
              child: Icon(Icons.search, color: Colors.grey[500]),
            ),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.clear, color: Colors.grey[400]),
                    onPressed: () {
                      _searchController.clear();
                      itemProvider.setSearchQuery('');
                    },
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          ),
          onChanged: (value) {
            itemProvider.setSearchQuery(value);
          },
        ),
      ),
    );
  }

  Widget _buildCategoryFilter(BuildContext context,
      CategoryProvider categoryProvider, ItemProvider itemProvider) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: _buildCategoryChip(
              '全部',
              itemProvider.selectedCategory == null,
              () => itemProvider.setSelectedCategory(null),
              context,
            ),
          ),
          ...categoryProvider.categories.map((category) {
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: _buildCategoryChip(
                category.name,
                itemProvider.selectedCategory == category.name,
                () => itemProvider.setSelectedCategory(
                  itemProvider.selectedCategory == category.name ? null : category.name,
                ),
                context,
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(
      String label, bool selected, VoidCallback onTap, BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Theme.of(context).colorScheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.grey[700],
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildTagFilter(BuildContext context, TagProvider tagProvider,
      ItemProvider itemProvider) {
    if (tagProvider.tags.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: _buildCategoryChip(
              '全部',
              itemProvider.selectedTag == null,
              () => itemProvider.setSelectedTag(null),
              context,
            ),
          ),
          ...tagProvider.tags.map((tag) {
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: _buildCategoryChip(
                tag.name,
                itemProvider.selectedTag == tag.name,
                () => itemProvider.setSelectedTag(
                  itemProvider.selectedTag == tag.name ? null : tag.name,
                ),
                context,
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildItemList(BuildContext context, ItemProvider itemProvider, SpaceProvider spaceProvider) {
    final items = itemProvider.items;

    return ListView.builder(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16, top: 4),
      itemCount: items.isEmpty ? 1 : items.length,
      itemBuilder: (context, index) {
        if (items.isEmpty) {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inventory_2_outlined,
                    size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  '暂无物品',
                  style: TextStyle(color: Colors.grey[600], fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  '点击录入"+"添加物品\n支持滑动和长按操作',
                  style: TextStyle(color: Colors.grey[400], fontSize: 14),
                ),
              ],
            ),
          );
        }
        final item = items[index];
        return _buildItemCard(context, item, itemProvider, spaceProvider);
      },
    );
  }

  String _getItemDisplayMode(dynamic item) {
    if (_displayMode != 'default') return _displayMode;
    if (item.expireDate != null) return 'expire';
    if (item.price != null && item.price! > 0) return 'price';
    return 'expire';
  }

  Widget _buildItemCard(
      BuildContext context, dynamic item, ItemProvider itemProvider, SpaceProvider spaceProvider) {
    final space = spaceProvider.spaces.firstWhere(
      (s) => s.id == item.spaceId,
      orElse: () => Space(id: '', houseId: item.houseId, name: '未知位置', type: 'room', createdAt: DateTime.now(), updatedAt: DateTime.now()),
    );
    final spacePath = _getSpacePath(space, spaceProvider);
    final isExpired = item.expireDate != null && item.expireDate!.isBefore(DateTime.now());
    final isSelected = _selectedItemIds.contains(item.id);
    final itemDisplayMode = _getItemDisplayMode(item);

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
          onTap: () => _toggleItemSelection(item.id),
        ),
      );
    }

    if (itemDisplayMode == 'price') {
      return _buildPriceItemCard(context, item, itemProvider, spaceProvider, isExpired);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Slidable(
        startActionPane: _buildLeftSlideActions(context, item, itemProvider, spaceProvider, isExpired),
        endActionPane: _buildRightSlideActions(context, item, itemProvider, spaceProvider, isExpired),
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
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ItemDetailPage(item: item),
              ),
            );
            // 返回后刷新数据
            if (mounted) {
              final houseProvider = context.read<HouseProvider>();
              final currentHouse = houseProvider.currentHouse;
              if (currentHouse != null) {
                await context.read<ItemProvider>().loadItems(currentHouse.id);
              }
            }
          },
          onLongPress: () {
            _toggleSelectionMode();
            _toggleItemSelection(item.id);
          },
        ),
      ),
    );
  }

  Widget _buildPriceItemCard(BuildContext context, dynamic item, ItemProvider itemProvider,
      SpaceProvider spaceProvider, bool isExpired) {
    final totalPrice = (item.price ?? 0) * item.quantity;
    final attributeProvider = context.read<AttributeProvider>();

    return FutureBuilder<Map<String, dynamic>>(
      future: _getPriceItemCardData(item, attributeProvider, itemProvider),
      builder: (context, snapshot) {
        final data = snapshot.data ?? {};
        final hasPurchaseDate = data['hasPurchaseDate'] == true;
        final hasUsageCount = data['hasUsageCount'] == true;
        final daysOwned = data['daysOwned'] as int? ?? 0;
        final usageCount = data['usageCount'] as int? ?? 0;

        final List<String> subtitleLines = [];
        if (hasPurchaseDate) {
          final dailyCost = daysOwned > 0 ? totalPrice / daysOwned : totalPrice;
          subtitleLines.add('¥${dailyCost.toStringAsFixed(2)} × $daysOwned天');
        }
        if (hasUsageCount) {
          final costPerUse = usageCount > 0 ? totalPrice / usageCount : totalPrice;
          subtitleLines.add('¥${costPerUse.toStringAsFixed(2)} × $usageCount次');
        }
        if (subtitleLines.isEmpty) {
          subtitleLines.add('¥${item.price?.toStringAsFixed(2) ?? "0.00"} × ${item.quantity}件');
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Slidable(
            startActionPane: _buildLeftSlideActions(context, item, itemProvider, spaceProvider, isExpired),
            endActionPane: _buildRightSlideActions(context, item, itemProvider, spaceProvider, isExpired),
            child: InkWell(
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ItemDetailPage(item: item),
                  ),
                );
                if (mounted) {
                  final houseProvider = context.read<HouseProvider>();
                  final currentHouse = houseProvider.currentHouse;
                  if (currentHouse != null) {
                    await context.read<ItemProvider>().loadItems(currentHouse.id);
                  }
                }
              },
              onLongPress: () {
                _toggleSelectionMode();
                _toggleItemSelection(item.id);
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
                          ...subtitleLines.map((line) => Text(
                            line,
                            style: TextStyle(color: Colors.grey[600], fontSize: 13),
                          )),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '¥${totalPrice >= 10000 ? totalPrice.toInt() : totalPrice.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<Map<String, dynamic>> _getPriceItemCardData(dynamic item,
      AttributeProvider attributeProvider, ItemProvider itemProvider) async {
    if (attributeProvider.attributes.isEmpty) {
      await attributeProvider.loadAttributes();
    }

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

    final attrs = await itemProvider.getItemAttributes(item.id);
    final result = <String, dynamic>{};

    if (purchaseDateAttr.id.isNotEmpty && attrs.containsKey(purchaseDateAttr.id)) {
      final dateStr = attrs[purchaseDateAttr.id];
      if (dateStr != null && dateStr.isNotEmpty) {
        try {
          final purchaseDate = DateTime.parse(dateStr);
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final purchaseDay = DateTime(purchaseDate.year, purchaseDate.month, purchaseDate.day);
          final daysOwned = today.difference(purchaseDay).inDays;
          if (daysOwned >= 0) {
            result['hasPurchaseDate'] = true;
            result['daysOwned'] = daysOwned;
          }
        } catch (_) {}
      }
    }

    if (usageCountAttr.id.isNotEmpty && attrs.containsKey(usageCountAttr.id)) {
      final countStr = attrs[usageCountAttr.id];
      if (countStr != null && countStr.isNotEmpty) {
        final count = int.tryParse(countStr);
        if (count != null && count >= 0) {
          result['hasUsageCount'] = true;
          result['usageCount'] = count;
        }
      }
    }

    return result;
  }

  ActionPane? _buildLeftSlideActions(BuildContext context, dynamic item, ItemProvider itemProvider, 
      SpaceProvider spaceProvider, bool isExpired) {
    if (isExpired) {
      return null;
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
              await _decrementQuantityWithoutPop(item, itemProvider);
            }
          },
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
          label: '-1',
          borderRadius: BorderRadius.circular(12),
        ),
        SlidableAction(
          onPressed: (context) async {
            await _incrementQuantityWithoutPop(item, itemProvider);
          },
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          label: '+1',
          borderRadius: BorderRadius.circular(12),
        ),
      ],
    );
  }

  ActionPane _buildRightSlideActions(BuildContext context, dynamic item, ItemProvider itemProvider, 
      SpaceProvider spaceProvider, bool isExpired) {
    if (isExpired) {
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

    // 价格模式下右侧滑动改为使用+1
    if (_displayMode == 'price') {
      return ActionPane(
        motion: const ScrollMotion(),
        children: [
          SlidableAction(
            onPressed: (ctx) async {
              await _handleIncrementUsage(ctx, item);
            },
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            // icon: Icons.add,
            label: '使用+1',
            borderRadius: BorderRadius.circular(12),
          ),
        ],
      );
    }

    return ActionPane(
      motion: const ScrollMotion(),
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
              final houseProvider = context.read<HouseProvider>();
              final currentHouse = houseProvider.currentHouse;
              if (currentHouse != null) {
                await context.read<ItemProvider>().loadItems(currentHouse.id);
              }
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
              final houseProvider = context.read<HouseProvider>();
              final currentHouse = houseProvider.currentHouse;
              if (currentHouse != null) {
                await context.read<ItemProvider>().loadItems(currentHouse.id);
              }
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

  Future<void> _handleIncrementUsage(BuildContext context, dynamic item) async {
    final attributeProvider = context.read<AttributeProvider>();
    final itemProvider = context.read<ItemProvider>();

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

    final attrs = await itemProvider.getItemAttributes(item.id);
    bool hasUsageCount = false;
    if (usageCountAttr.id.isNotEmpty && item.categoryId != null) {
      final db = context.read<AppDatabase>();
      final links = await (db.select(db.categoryAttributes)
            ..where((t) => t.categoryId.equals(item.categoryId!) & t.attributeId.equals(usageCountAttr.id)))
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

  void _navigateToRestockPage(BuildContext context, dynamic item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RestockPage(item: item),
      ),
    );
  }

  Future<void> _decrementQuantityWithoutPop(dynamic item, ItemProvider itemProvider) async {
    final db = Provider.of<AppDatabase>(context, listen: false);
    await (db.update(db.items)..where((t) => t.id.equals(item.id))).write(
      ItemsCompanion(
        quantity: drift.Value(item.quantity - 1),
        modifierId: const drift.Value('user'),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );
    await itemProvider.loadItems(item.houseId);
  }

  Future<void> _incrementQuantityWithoutPop(dynamic item, ItemProvider itemProvider) async {
    final db = Provider.of<AppDatabase>(context, listen: false);
    await (db.update(db.items)..where((t) => t.id.equals(item.id))).write(
      ItemsCompanion(
        quantity: drift.Value(item.quantity + 1),
        modifierId: const drift.Value('user'),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );
    await itemProvider.loadItems(item.houseId);
  }

  Future<void> _moveToRecycleBin(BuildContext context, dynamic item, ItemProvider itemProvider, 
      SpaceProvider spaceProvider, AppDatabase db) async {
    print('开始移动物品到回收站，物品ID: ${item.id}，名称: ${item.name}，houseId: ${item.houseId}');
    
    if (spaceProvider.spaces.isEmpty) {
      print('空间数据为空，尝试重新加载...');
      await spaceProvider.loadSpaces(item.houseId);
    }
    
    print('spaceProvider中的所有空间: ${spaceProvider.spaces.map((s) => '${s.name}(${s.type}, ${s.houseId})').join(', ')}');
    
    final recycleSpace = spaceProvider.getRecycleBinSpace(item.houseId);
    print('找到的回收站空间: ${recycleSpace?.name}，ID: ${recycleSpace?.id}');
    
    if (recycleSpace == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未找到回收站')),
      );
      return;
    }

    print('准备更新物品，原spaceId: ${item.spaceId}，新spaceId: ${recycleSpace.id}');
    
    await (db.update(db.items)..where((t) => t.id.equals(item.id))).write(
      ItemsCompanion(
        spaceId: drift.Value(recycleSpace.id),
        quantity: const drift.Value(1),
        modifierId: const drift.Value('user'),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );
    
    print('物品已更新，重新加载物品...');
    await itemProvider.loadItems(item.houseId);
    
    _setSpecialSpaceIds(spaceProvider, itemProvider, item.houseId);
    
    print('操作完成，当前itemProvider中的特殊空间ID: ${itemProvider.specialSpaceIds}');
    print('显示的物品数量: ${itemProvider.items.length}');
  }



  Future<void> _moveToTrashOrDelete(BuildContext context, dynamic item, ItemProvider itemProvider, 
      SpaceProvider spaceProvider, bool isExpired) async {
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

    await itemProvider.moveItem(item, trashSpace.id);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('物品已移至垃圾桶')),
      );
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

  Widget _buildPropertyValue(BuildContext context, dynamic item) {
    if (item.expireDate == null) {
      return const SizedBox();
    }
    final isWarrantyDate = _isWarrantyExpireDate(item);
    final text = _getExpireText(item.expireDate, isWarrantyDate);
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

  bool _isWarrantyExpireDate(dynamic item) {
    return item.customAttributes == 'warranty';
  }

  String _getExpireText(DateTime? expireDate, bool isWarrantyDate) {
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
    } else if (diff <= 7) {
      return '${diff}天后$suffix';
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

  void _showAddHouseDialog(BuildContext context, HouseProvider houseProvider) {
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
              if (controller.text.isNotEmpty) {
                houseProvider.createHouse(controller.text);
                Navigator.pop(context);
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
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
            leading: Icon(_getSpaceIcon(space.type)),
            title: Text(space.name),
            subtitle: Text(_getSpaceTypeName(space.type)),
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

    final recycleSpace = spaceProvider.getRecycleBinSpace(selectedItems.first.houseId);
    final hasItemsInRecycleBin = selectedItems.any((item) => item.spaceId == recycleSpace?.id);

    String title = '删除物品';
    String message;
    
    if (hasItemsInRecycleBin) {
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
              await _batchDeleteItems(context, itemProvider, spaceProvider, hasItemsInRecycleBin);
            },
            style: FilledButton.styleFrom(
              backgroundColor: hasItemsInRecycleBin ? Colors.red : null,
            ),
            child: Text(hasItemsInRecycleBin ? '彻底删除' : '移至回收站'),
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已移至回收站 ${selectedItems.length} 个物品')),
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
      case 'trash':
        return Icons.delete;
      case 'recycle':
        return Icons.delete_outline;
      default:
        return Icons.folder;
    }
  }

  void _setSpecialSpaceIds(SpaceProvider spaceProvider, ItemProvider itemProvider, String houseId) {
    print('开始设置特殊空间ID，houseId: $houseId');
    final specialSpaceIds = <String>[];
    
    // 获取回收站空间
    final recycleSpace = spaceProvider.getRecycleBinSpace(houseId);
    if (recycleSpace != null) {
      print('找到回收站: ${recycleSpace.name}，ID: ${recycleSpace.id}');
      specialSpaceIds.add(recycleSpace.id);
    } else {
      print('未找到回收站空间');
    }
    
    // 获取垃圾桶空间
    Space? trashSpace;
    for (final space in spaceProvider.spaces) {
      if (space.houseId == houseId && space.type == 'trash') {
        trashSpace = space;
        break;
      }
    }
    if (trashSpace != null) {
      print('找到垃圾桶: ${trashSpace.name}，ID: ${trashSpace.id}');
      specialSpaceIds.add(trashSpace.id);
    } else {
      print('未找到垃圾桶空间');
    }
    
    // 待整理空间不应该被排除，用户应该能在首页看到待整理的物品
    
    print('设置特殊空间ID列表: $specialSpaceIds');
    // 设置到 itemProvider
    itemProvider.setSpecialSpaceIds(specialSpaceIds);
  }
  
  // 设置空间名称缓存用于搜索
  void _setSpaceNames(SpaceProvider spaceProvider, ItemProvider itemProvider) {
    final spaceNames = <String, String>{};
    for (final space in spaceProvider.spaces) {
      spaceNames[space.id] = space.name;
    }
    itemProvider.setSpaceNames(spaceNames);
  }

  Widget _buildActionButton(BuildContext context, IconData icon, VoidCallback onPressed) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, size: 24),
        onPressed: onPressed,
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(),
      ),
    );
  }

  Widget _buildNotificationButton(BuildContext context) {
    final notificationProvider = context.watch<NotificationProvider>();
    final unreadCount = notificationProvider.unreadCount;
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const NotificationPage()),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: Icon(
                unreadCount > 0 ? Icons.notifications : Icons.notifications_none,
                size: 24,
              ),
              onPressed: null,
              padding: const EdgeInsets.all(12),
              constraints: const BoxConstraints(),
            ),
            if (unreadCount > 0)
              Positioned(
                right: 4,
                top: 4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  child: Text(
                    unreadCount > 99 ? '99+' : '$unreadCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHouseSelector(BuildContext context, HouseProvider houseProvider, dynamic currentHouse,
      ItemProvider itemProvider, CategoryProvider categoryProvider, 
      SpaceProvider spaceProvider, TagProvider tagProvider) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: PopupMenuButton<String>(
        icon: const Icon(Icons.home, size: 24),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(),
        itemBuilder: (context) => houseProvider.houses.map((house) {
          return PopupMenuItem<String>(
            value: house.id,
            child: Row(
              children: [
                Icon(
                  Icons.home,
                  size: 18,
                  color: house.id == currentHouse.id
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                const SizedBox(width: 8),
                Text(
                  house.name,
                  style: TextStyle(
                    fontWeight: house.id == currentHouse.id
                        ? FontWeight.bold
                        : null,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
        onSelected: (houseId) async {
          if (houseId != null) {
            final house =
                houseProvider.houses.firstWhere((h) => h.id == houseId);
            houseProvider.switchHouse(house);
            await itemProvider.loadItems(houseId);
            if (!mounted) return;
            await categoryProvider.loadCategories();
            if (!mounted) return;
            await spaceProvider.loadSpaces(houseId);
            if (!mounted) return;
            await tagProvider.loadTags();
            if (!mounted) return;
            
            _setSpecialSpaceIds(spaceProvider, itemProvider, houseId);
          }
        },
      ),
    );
  }
}