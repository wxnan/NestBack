import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import '../../database/database.dart';
import '../../providers/space_provider.dart';
import '../../providers/house_provider.dart';

class SpaceHierarchyPage extends StatefulWidget {
  const SpaceHierarchyPage({super.key});

  @override
  State<SpaceHierarchyPage> createState() => _SpaceHierarchyPageState();
}

class _SpaceHierarchyPageState extends State<SpaceHierarchyPage> {
  final Map<String, bool> _expandedNodes = {};
  static const int _defaultExpandLevel = 3;
  Space? _draggedSpace;
  Space? _dropTarget;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadExpandedNodes();
    });
  }

  void _loadExpandedNodes() {
    final spaceProvider = Provider.of<SpaceProvider>(context, listen: false);
    final houseProvider = Provider.of<HouseProvider>(context, listen: false);
    final currentHouse = houseProvider.currentHouse;
    
    if (currentHouse != null) {
      final allSpaces = spaceProvider.getAllSpacesExceptSpecial(currentHouse.id);
      _initExpandedNodes(allSpaces, null, 1);
    }
  }

  void _initExpandedNodes(List<Space> spaces, String? parentId, int level) {
    _expandedNodes.clear();
  }

  void _toggleExpand(String spaceId) {
    setState(() {
      _expandedNodes[spaceId] = !(_expandedNodes[spaceId] ?? false);
    });
  }

  bool _isExpanded(String spaceId) {
    return _expandedNodes[spaceId] ?? false;
  }

  Widget _buildTree(BuildContext context, List<Space> spaces, String? parentId, int level) {
    final children = spaces.where((s) => s.parentId == parentId).toList();
    
    if (children.isEmpty) {
      return const SizedBox();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children.map((space) {
        final hasChildren = spaces.any((s) => s.parentId == space.id);
        final isDragged = _draggedSpace?.id == space.id;
        final isDropTarget = _dropTarget?.id == space.id;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSpaceCard(context, space, hasChildren, level, isDragged, isDropTarget),
            if (hasChildren && _isExpanded(space.id))
              Padding(
                padding: EdgeInsets.only(left: 24),
                child: _buildTree(context, spaces, space.id, level + 1),
              ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildSpaceCard(BuildContext context, Space space, bool hasChildren, int level, bool isDragged, bool isDropTarget) {
    final spaceProvider = Provider.of<SpaceProvider>(context, listen: false);
    final childCount = spaceProvider.getChildSpaces(space.id).length;

    return LongPressDraggable<Space>(
      data: space,
      onDragStarted: () {
        setState(() {
          _draggedSpace = space;
        });
      },
      onDragEnd: (details) {
        setState(() {
          _draggedSpace = null;
          _dropTarget = null;
        });
      },
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          width: 200,
          color: Theme.of(context).cardColor,
          child: Row(
            children: [
              Icon(_getSpaceIcon(space.icon, space.type), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  space.name,
                  style: Theme.of(context).textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.5,
        child: _buildSpaceItem(context, space, hasChildren),
      ),
      child: _buildSpaceItem(context, space, hasChildren),
    );
  }

  Widget _buildSpaceItem(BuildContext context, Space space, bool hasChildren) {
    final spaceProvider = Provider.of<SpaceProvider>(context, listen: false);
    final childCount = spaceProvider.getChildSpaces(space.id).length;

    return DragTarget<Space>(
      onAccept: (draggedSpace) {
        if (draggedSpace.id != space.id) {
          _handleDrop(context, draggedSpace, space);
        }
        setState(() {
          _dropTarget = null;
        });
      },
      onLeave: (data) {
        setState(() {
          _dropTarget = null;
        });
      },
      onWillAccept: (data) {
        if (data != null && data.id != space.id) {
          setState(() {
            _dropTarget = space;
          });
          return true;
        }
        return false;
      },
      builder: (context, candidateData, rejectedData) {
        final isDropTarget = _dropTarget?.id == space.id;
        
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: isDropTarget 
              ? BoxDecoration(
                  border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
                  borderRadius: BorderRadius.circular(12),
                )
              : null,
          child: Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: InkWell(
              onTap: () {
                if (hasChildren) {
                  _toggleExpand(space.id);
                }
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: hasChildren
                          ? IconButton(
                              icon: Icon(
                                _isExpanded(space.id) 
                                    ? Icons.expand_more 
                                    : Icons.chevron_right,
                                size: 18,
                              ),
                              onPressed: () => _toggleExpand(space.id),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            )
                          : null,
                    ),
                    _buildSpaceAvatar(context, space),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            space.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            '${_getSpaceTypeLabel(space.type)} · $childCount 个子空间',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
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

  void _handleDrop(BuildContext context, Space draggedSpace, Space targetSpace) async {
    final spaceProvider = Provider.of<SpaceProvider>(context, listen: false);
    await spaceProvider.moveSpace(draggedSpace.id, targetSpace.id);
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
        return Icons.pending;
      case 'trash':
        return Icons.delete;
      case 'recycle':
        return Icons.delete_outline;
      default:
        return Icons.folder;
    }
  }

  String _getSpaceTypeLabel(String type) {
    switch (type) {
      case 'room':
        return '房间';
      case 'container':
        return '容器';
      case 'sub_container':
        return '子容器';
      case 'pending':
        return '特殊';
      case 'trash':
        return '特殊';
      case 'recycle':
        return '特殊';
      default:
        return '空间';
    }
  }

  Widget _buildSpaceAvatar(BuildContext context, Space space) {
    if (space.imagePath != null && space.imagePath!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => _showSpaceImagePreview(context, space.imagePath!),
          child: Image.file(
            File(space.imagePath!),
            width: 32,
            height: 32,
            fit: BoxFit.cover,
          ),
        ),
      );
    }
    return CircleAvatar(
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      radius: 16,
      child: Icon(
        _getSpaceIcon(space.icon, space.type),
        color: Theme.of(context).colorScheme.onPrimaryContainer,
        size: 20,
      ),
    );
  }

  void _showSpaceImagePreview(BuildContext context, String imagePath) {
    showDialog(
      context: context,
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

  @override
  Widget build(BuildContext context) {
    return Consumer2<SpaceProvider, HouseProvider>(
      builder: (context, spaceProvider, houseProvider, _) {
        final currentHouse = houseProvider.currentHouse;
        
        if (currentHouse == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final allSpaces = spaceProvider.getAllSpacesExceptSpecial(currentHouse.id);

        return Scaffold(
          appBar: AppBar(
            title: const Text('空间层级管理'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              children: [
                _buildTree(context, allSpaces, null, 0),
              ],
            ),
          ),
          bottomSheet: Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).scaffoldBackgroundColor,
            child: const Text(
              '长按空间卡片可拖拽移动，子空间和物品将跟随移动',
              style: TextStyle(color: Colors.grey, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        );
      },
    );
  }
}
