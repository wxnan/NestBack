import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';
import '../../providers/item_provider.dart';
import '../../providers/attribute_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/house_provider.dart';
import '../../providers/space_provider.dart';
import '../../database/database.dart';

class RestockPage extends StatefulWidget {
  final Item item;

  const RestockPage({super.key, required this.item});

  @override
  State<RestockPage> createState() => _RestockPageState();
}

class _RestockPageState extends State<RestockPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _priceController = TextEditingController();
  final _totalPriceController = TextEditingController();
  final _productionDateController = TextEditingController();
  final _expireDateController = TextEditingController();
  final _shelfLifeValueController = TextEditingController();
  String _shelfLifeUnit = '天';
  String? _selectedSpaceId;

  bool _hasError = false;
  String _errorMessage = '';
  bool _isCalculating = false;
  Map<String, String> _originalCustomAttributes = {};

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.item.name;

    if (widget.item.price != null) {
      _priceController.text = widget.item.price!.toString();
      _calculateTotalPrice();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final itemProvider = context.read<ItemProvider>();
      final attrs = await itemProvider.getItemAttributes(widget.item.id);
      if (mounted) {
        setState(() {
          _originalCustomAttributes = attrs;
        });
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    _totalPriceController.dispose();
    _productionDateController.dispose();
    _expireDateController.dispose();
    _shelfLifeValueController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _selectDate(TextEditingController controller, {bool isProduction = false}) async {
    DateTime initialDate = DateTime.now();
    if (controller.text.isNotEmpty) {
      try {
        initialDate = DateTime.parse(controller.text);
      } catch (_) {
        initialDate = DateTime.now();
      }
    }

    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );

    if (date != null) {
      setState(() {
        controller.text = _formatDate(date);
        if (isProduction && _shelfLifeValueController.text.isNotEmpty) {
          _calculateExpireDateFromProduction();
        } else if (!isProduction && _shelfLifeValueController.text.isNotEmpty && _productionDateController.text.isEmpty) {
          _calculateProductionDateFromExpire();
        }
      });
    }
  }

  void _calculateExpireDateFromProduction() {
    if (_productionDateController.text.isEmpty || _shelfLifeValueController.text.isEmpty) {
      return;
    }

    try {
      final productionDate = DateTime.parse(_productionDateController.text);
      final shelfLife = int.parse(_shelfLifeValueController.text);

      DateTime expireDate;
      switch (_shelfLifeUnit) {
        case '天':
          expireDate = productionDate.add(Duration(days: shelfLife));
          break;
        case '月':
          expireDate = productionDate.add(Duration(days: shelfLife * 30));
          break;
        case '年':
          expireDate = productionDate.add(Duration(days: shelfLife * 365));
          break;
        default:
          expireDate = productionDate.add(Duration(days: shelfLife));
      }

      setState(() {
        _expireDateController.text = _formatDate(expireDate);
      });
    } catch (_) {
      // 解析失败
    }
  }

  void _calculateProductionDateFromExpire() {
    if (_expireDateController.text.isEmpty || _shelfLifeValueController.text.isEmpty) {
      return;
    }

    try {
      final expireDate = DateTime.parse(_expireDateController.text);
      final shelfLife = int.parse(_shelfLifeValueController.text);

      DateTime productionDate;
      switch (_shelfLifeUnit) {
        case '天':
          productionDate = expireDate.subtract(Duration(days: shelfLife));
          break;
        case '月':
          productionDate = expireDate.subtract(Duration(days: shelfLife * 30));
          break;
        case '年':
          productionDate = expireDate.subtract(Duration(days: shelfLife * 365));
          break;
        default:
          productionDate = expireDate.subtract(Duration(days: shelfLife));
      }

      setState(() {
        _productionDateController.text = _formatDate(productionDate);
      });
    } catch (_) {
      // 解析失败
    }
  }

  void _calculateTotalPrice() {
    if (_isCalculating) return;
    _isCalculating = true;

    try {
      final price = double.tryParse(_priceController.text);
      final quantity = int.tryParse(_quantityController.text) ?? 1;
      if (price != null) {
        _totalPriceController.text = (price * quantity).toStringAsFixed(2);
      } else {
        _totalPriceController.clear();
      }
    } finally {
      _isCalculating = false;
    }
  }

  void _calculatePriceFromTotal() {
    if (_isCalculating) return;
    _isCalculating = true;

    try {
      final total = double.tryParse(_totalPriceController.text);
      final quantity = int.tryParse(_quantityController.text) ?? 1;
      if (total != null && quantity > 0) {
        _priceController.text = (total / quantity).toStringAsFixed(2);
      } else {
        _priceController.clear();
      }
    } finally {
      _isCalculating = false;
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final newExpireDateStr = _expireDateController.text;
    if (newExpireDateStr.isEmpty) {
      setState(() {
        _hasError = true;
        _errorMessage = '请选择新过期日期';
      });
      return;
    }

    if (widget.item.expireDate != null) {
      final oldExpireDateStr = _formatDate(widget.item.expireDate!);
      if (newExpireDateStr == oldExpireDateStr) {
        setState(() {
          _hasError = true;
          _errorMessage = '过期日期必须与原物品不同';
        });
        return;
      }
    }

    setState(() {
      _hasError = false;
      _errorMessage = '';
    });

    final itemProvider = context.read<ItemProvider>();
    final houseProvider = context.read<HouseProvider>();

    DateTime? expireDate;
    if (newExpireDateStr.isNotEmpty) {
      try {
        expireDate = DateTime.parse(newExpireDateStr);
      } catch (_) {
        // 解析失败
      }
    }

    double? price;
    if (_priceController.text.isNotEmpty) {
      price = double.tryParse(_priceController.text);
    }

    // 获取目标位置，如果用户没有选择则使用原物品的位置
    final targetSpaceId = _selectedSpaceId ?? widget.item.spaceId;

    // 创建新物品，保留原物品的大部分信息，只更新过期日期相关字段
    await itemProvider.addItem(
      houseId: widget.item.houseId,
      spaceId: targetSpaceId,
      name: _nameController.text.trim(),
      quantity: int.tryParse(_quantityController.text) ?? 1,
      unit: widget.item.unit ?? '件',
      price: price,
      category: widget.item.category,
      categoryId: widget.item.categoryId,
      tags: widget.item.tags != null ? widget.item.tags!.split(',').where((t) => t.isNotEmpty).toList() : null,
      imagePath: widget.item.imagePath,
      note: widget.item.note,
      expireDate: expireDate,
      customAttributes: _buildCustomAttributes(),
      expireDateSource: expireDate != null ? 'expire' : null,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('补货成功，已添加新物品')),
      );
      Navigator.pop(context);
    }
  }

  Map<String, String>? _buildCustomAttributes() {
    final attributes = Map<String, String>.from(_originalCustomAttributes);

    attributes.remove('_low_stock_reminder');
    attributes.remove('_low_stock_threshold');

    if (_productionDateController.text.isNotEmpty) {
      final attributeProvider = context.read<AttributeProvider>();
      final categoryProvider = context.read<CategoryProvider>();
      final houseProvider = context.read<HouseProvider>();

      if (houseProvider.currentHouse != null) {
        final category = categoryProvider.categories.firstWhere(
          (c) => c.name == widget.item.category,
          orElse: () => Category(id: '', houseId: houseProvider.currentHouse!.id, name: '其他', icon: null, sortOrder: 0, createdAt: DateTime.now()),
        );

        final productionDateAttr = attributeProvider.attributes.firstWhere(
          (a) => a.name == '生产日期',
          orElse: () => Attribute(id: '', houseId: '', name: '', type: '', hint: null, options: null, required: false, sortOrder: 0, createdAt: DateTime.now(), updatedAt: DateTime.now()),
        );

        if (productionDateAttr.id.isNotEmpty) {
          attributes[productionDateAttr.id] = _productionDateController.text;
        }

        if (_shelfLifeValueController.text.isNotEmpty) {
          final shelfLifeAttr = attributeProvider.attributes.firstWhere(
            (a) => a.name == '保质期',
            orElse: () => Attribute(id: '', houseId: '', name: '', type: '', hint: null, options: null, required: false, sortOrder: 0, createdAt: DateTime.now(), updatedAt: DateTime.now()),
          );

          if (shelfLifeAttr.id.isNotEmpty) {
            attributes[shelfLifeAttr.id] = '${_shelfLifeValueController.text}|$_shelfLifeUnit';
          }
        }
      }
    }

    return attributes.isNotEmpty ? attributes : null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('补货'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 原物品信息提示
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '原物品信息',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text('物品名称：${widget.item.name}'),
                    if (widget.item.expireDate != null)
                      Text('原过期日期：${_formatDate(widget.item.expireDate!)}'),
                    if (widget.item.price != null)
                      Text('原单价：¥ ${widget.item.price}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 补货表单
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '补货信息',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: '物品名称 *',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        prefixIcon: const Icon(Icons.label),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return '请输入物品名称';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    // 数量
                    TextFormField(
                      controller: _quantityController,
                      decoration: InputDecoration(
                        labelText: '补货数量 *',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        prefixIcon: const Icon(Icons.numbers),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return '请输入补货数量';
                        }
                        final qty = int.tryParse(value);
                        if (qty == null || qty <= 0) {
                          return '请输入有效的数量';
                        }
                        return null;
                      },
                      onChanged: (value) {
                        _calculateTotalPrice();
                      },
                    ),
                    const SizedBox(height: 16),
                    // 位置
                    Consumer<SpaceProvider>(
                      builder: (context, spaceProvider, child) {
                        final spaces = spaceProvider.spaces
                            .where((s) => s.houseId == widget.item.houseId && 
                                s.type != 'recycle' && 
                                s.type != 'trash')
                            .toList();
                        
                        String? effectiveSpaceId = _selectedSpaceId;
                        if (effectiveSpaceId == null) {
                          // 检查原物品是否位于回收站或垃圾桶
                          final originalSpace = spaceProvider.spaces.firstWhereOrNull(
                            (s) => s.id == widget.item.spaceId
                          );
                          final isSpecialSpace = originalSpace != null && 
                              (originalSpace.type == 'recycle' || originalSpace.type == 'trash');
                          
                          if (isSpecialSpace) {
                            // 原物品在回收站或垃圾桶，默认选择待整理空间
                            final pendingSpace = spaceProvider.spaces.firstWhereOrNull(
                              (s) => s.houseId == widget.item.houseId && s.type == 'pending'
                            );
                            if (pendingSpace != null) {
                              effectiveSpaceId = pendingSpace.id;
                            } else {
                              effectiveSpaceId = spaces.firstOrNull?.id;
                            }
                          } else {
                            // 原物品在普通空间，使用原位置
                            final originalSpaceIsValid = spaces.any((s) => s.id == widget.item.spaceId);
                            effectiveSpaceId = originalSpaceIsValid ? widget.item.spaceId : spaces.firstOrNull?.id;
                          }
                        } else if (!spaces.any((s) => s.id == effectiveSpaceId)) {
                          effectiveSpaceId = spaces.firstOrNull?.id;
                        }
                        
                        if (spaces.isEmpty) {
                          return const Text('暂无可用位置');
                        }
                        
                        return DropdownButtonFormField<String>(
                          value: effectiveSpaceId,
                          decoration: InputDecoration(
                            labelText: '存放位置',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            prefixIcon: const Icon(Icons.location_on),
                          ),
                          items: spaces.map((space) => DropdownMenuItem<String>(
                            value: space.id,
                            child: Text(space.name),
                          )).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedSpaceId = value;
                            });
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    // 单价
                    TextFormField(
                      controller: _priceController,
                      decoration: InputDecoration(
                        labelText: '单价',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        prefixIcon: const Icon(Icons.attach_money),
                        prefixText: '¥ ',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (value) => _calculateTotalPrice(),
                    ),
                    const SizedBox(height: 16),
                    // 总价
                    TextFormField(
                      controller: _totalPriceController,
                      decoration: InputDecoration(
                        labelText: '总价',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        prefixIcon: const Icon(Icons.money),
                        prefixText: '¥ ',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (value) => _calculatePriceFromTotal(),
                    ),
                    const SizedBox(height: 16),
                    // 生产日期
                    InkWell(
                      onTap: () => _selectDate(_productionDateController, isProduction: true),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: '生产日期',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _productionDateController.text.isNotEmpty
                                  ? _productionDateController.text
                                  : '请选择',
                              style: TextStyle(
                                color: _productionDateController.text.isNotEmpty
                                    ? null
                                    : Colors.grey,
                              ),
                            ),
                            const Icon(Icons.calendar_today),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 保质期
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _shelfLifeValueController,
                            decoration: InputDecoration(
                              labelText: '保质期',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (value) {
                              _calculateExpireDateFromProduction();
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 1,
                          child: DropdownButtonFormField<String>(
                            value: _shelfLifeUnit,
                            decoration: InputDecoration(
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            items: ['天', '月', '年']
                                .map((unit) => DropdownMenuItem<String>(
                                      value: unit,
                                      child: Text(unit),
                                    ))
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _shelfLifeUnit = value;
                                  _calculateExpireDateFromProduction();
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // 过期日期（必须与原物品不同）
                    InkWell(
                      onTap: () => _selectDate(_expireDateController),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: '新过期日期 *',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          errorText: _hasError ? _errorMessage : null,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _expireDateController.text.isNotEmpty
                                  ? _expireDateController.text
                                  : '请选择',
                              style: TextStyle(
                                color: _expireDateController.text.isNotEmpty
                                    ? null
                                    : Colors.grey,
                              ),
                            ),
                            const Icon(Icons.calendar_today),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 100),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _submitForm,
            icon: const Icon(Icons.add),
            label: const Text('确认补货'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ),
    );
  }
}