import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/house_provider.dart';
import '../providers/item_provider.dart';
import '../providers/space_provider.dart';
import '../providers/category_provider.dart';
import '../providers/attribute_provider.dart';
import '../providers/tag_provider.dart';
import 'home/home_tab.dart';
import 'space/space_tab.dart';
import 'add/add_tab.dart';
import 'stats/stats_tab.dart';
import 'profile/profile_tab.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();

  static Future<void> initializeDataIfNeeded(BuildContext context) async {
    final houseProvider = context.read<HouseProvider>();
    final currentHouse = houseProvider.currentHouse;

    if (currentHouse != null) {
      final itemProvider = context.read<ItemProvider>();
      final spaceProvider = context.read<SpaceProvider>();
      final categoryProvider = context.read<CategoryProvider>();
      final tagProvider = context.read<TagProvider>();

      // 检查数据是否已经加载
      if (spaceProvider.spaces.isEmpty) {
        await spaceProvider.loadSpaces(currentHouse.id);
      }
      if (itemProvider.items.isEmpty) {
        await itemProvider.loadItems(currentHouse.id);
      }
      if (categoryProvider.categories.isEmpty) {
        await categoryProvider.loadCategories();
      }
      if (tagProvider.tags.isEmpty) {
        await tagProvider.loadTags();
      }
    }
  }
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  final List<Widget> _tabs = const [
    HomeTab(),
    SpaceTab(),
    AddTab(),
    StatsTab(),
    ProfileTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _tabs,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: '空间',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline),
            selectedIcon: Icon(Icons.add_circle),
            label: '录入',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: '统计',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
