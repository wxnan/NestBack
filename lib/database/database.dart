import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';
import 'package:path/path.dart' as p;

part 'database.g.dart';

class Houses extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Spaces extends Table {
  TextColumn get id => text()();
  TextColumn get houseId => text().references(Houses, #id)();
  TextColumn get name => text()();
  TextColumn get icon => text().nullable()();
  TextColumn get imagePath => text().nullable()();
  TextColumn get parentId => text().nullable()();
  TextColumn get type => text()();
  TextColumn get position => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Items extends Table {
  TextColumn get id => text()();
  TextColumn get houseId => text().references(Houses, #id)();
  TextColumn get spaceId => text().references(Spaces, #id)();
  TextColumn get name => text()();
  IntColumn get quantity => integer().withDefault(const Constant(1))();
  TextColumn get unit => text().withDefault(const Constant('个'))();
  RealColumn get price => real().nullable()();
  DateTimeColumn get productionDate => dateTime().nullable()();
  IntColumn get shelfLife => integer().nullable()();
  DateTimeColumn get expireDate => dateTime().nullable()();
  TextColumn get category => text().nullable()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get subcategoryId => text().nullable()();
  TextColumn get tags => text().nullable()();
  TextColumn get imagePath => text().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get customAttributes => text().nullable()();
  TextColumn get creatorId => text()();
  TextColumn get modifierId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get houseId => text().references(Houses, #id)();
  TextColumn get name => text()();
  TextColumn get icon => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Subcategories extends Table {
  TextColumn get id => text()();
  TextColumn get categoryId => text().references(Categories, #id)();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get houseId => text().references(Houses, #id)();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Attributes extends Table {
  TextColumn get id => text()();
  TextColumn get houseId => text().references(Houses, #id)();
  TextColumn get name => text()();
  TextColumn get type => text()();
  TextColumn get hint => text().nullable()();
  TextColumn get options => text().nullable()();
  BoolColumn get required => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class CategoryAttributes extends Table {
  TextColumn get categoryId => text().references(Categories, #id)();
  TextColumn get attributeId => text().references(Attributes, #id)();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {categoryId, attributeId};
}

class ItemAttributes extends Table {
  TextColumn get itemId => text().references(Items, #id)();
  TextColumn get attributeId => text().references(Attributes, #id)();
  TextColumn get value => text().nullable()();

  @override
  Set<Column> get primaryKey => {itemId, attributeId};
}

class AppNotifications extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get body => text()();
  TextColumn get type => text().withDefault(const Constant('expire'))();
  TextColumn get itemId => text().nullable()();
  BoolColumn get isRead => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
}

@DriftDatabase(tables: [Houses, Spaces, Items, Categories, Subcategories, Tags, Attributes, CategoryAttributes, ItemAttributes, AppNotifications])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from == 1) {
          await m.createTable(attributes);
          await m.createTable(categoryAttributes);
          await m.createTable(itemAttributes);
        }
        if (from < 3) {
          await m.addColumn(tags, tags.sortOrder);
        }
        if (from < 4) {
          await m.createTable(subcategories);
        }
        if (from < 5) {
          await m.addColumn(items, items.subcategoryId);
        }
        if (from < 6) {
          await m.createTable(appNotifications);
        }
        if (from < 7) {
          // v7: 分类、属性、标签改为全局共享，去重已有数据
          await _migrateToGlobalMetadata();
        }
      },
    );
  }

  /// v7 迁移：去重分类、属性、标签数据，使其全局共享
  Future<void> _migrateToGlobalMetadata() async {
    // 1. 去重分类：按名称去重，保留最早创建的
    await customStatement('''
      CREATE TABLE temp_cat_map (old_id TEXT NOT NULL, new_id TEXT NOT NULL);
    ''');
    await customStatement('''
      INSERT INTO temp_cat_map (old_id, new_id)
      SELECT c1.id, c2.id
      FROM categories c1
      JOIN categories c2 ON c1.name = c2.name
      WHERE c2.created_at = (SELECT MIN(c3.created_at) FROM categories c3 WHERE c3.name = c1.name)
      AND c1.id != c2.id;
    ''');

    // 更新 Items.categoryId
    await customStatement('''
      UPDATE items SET category_id = (SELECT new_id FROM temp_cat_map WHERE old_id = items.category_id)
      WHERE category_id IN (SELECT old_id FROM temp_cat_map);
    ''');
    // 更新 Subcategories.categoryId
    await customStatement('''
      UPDATE subcategories SET category_id = (SELECT new_id FROM temp_cat_map WHERE old_id = subcategories.category_id)
      WHERE category_id IN (SELECT old_id FROM temp_cat_map);
    ''');
    // 更新 CategoryAttributes.categoryId
    await customStatement('''
      UPDATE category_attributes SET category_id = (SELECT new_id FROM temp_cat_map WHERE old_id = category_attributes.category_id)
      WHERE category_id IN (SELECT old_id FROM temp_cat_map);
    ''');
    // 删除重复分类
    await customStatement('''
      DELETE FROM categories WHERE id IN (SELECT old_id FROM temp_cat_map);
    ''');
    await customStatement('DROP TABLE temp_cat_map;');

    // 2. 去重二级分类：按 (categoryId, name) 去重
    await customStatement('''
      CREATE TABLE temp_subcat_map (old_id TEXT NOT NULL, new_id TEXT NOT NULL);
    ''');
    await customStatement('''
      INSERT INTO temp_subcat_map (old_id, new_id)
      SELECT s1.id, s2.id
      FROM subcategories s1
      JOIN subcategories s2 ON s1.category_id = s2.category_id AND s1.name = s2.name
      WHERE s2.rowid = (SELECT MIN(s3.rowid) FROM subcategories s3 WHERE s3.category_id = s1.category_id AND s3.name = s1.name)
      AND s1.rowid != s2.rowid;
    ''');
    await customStatement('''
      UPDATE items SET subcategory_id = (SELECT new_id FROM temp_subcat_map WHERE old_id = items.subcategory_id)
      WHERE subcategory_id IN (SELECT old_id FROM temp_subcat_map);
    ''');
    await customStatement('''
      DELETE FROM subcategories WHERE id IN (SELECT old_id FROM temp_subcat_map);
    ''');
    await customStatement('DROP TABLE temp_subcat_map;');

    // 3. 去重属性：按 (name, type) 去重
    await customStatement('''
      CREATE TABLE temp_attr_map (old_id TEXT NOT NULL, new_id TEXT NOT NULL);
    ''');
    await customStatement('''
      INSERT INTO temp_attr_map (old_id, new_id)
      SELECT a1.id, a2.id
      FROM attributes a1
      JOIN attributes a2 ON a1.name = a2.name AND a1.type = a2.type
      WHERE a2.created_at = (SELECT MIN(a3.created_at) FROM attributes a3 WHERE a3.name = a1.name AND a3.type = a1.type)
      AND a1.id != a2.id;
    ''');
    await customStatement('''
      UPDATE category_attributes SET attribute_id = (SELECT new_id FROM temp_attr_map WHERE old_id = category_attributes.attribute_id)
      WHERE attribute_id IN (SELECT old_id FROM temp_attr_map);
    ''');
    await customStatement('''
      UPDATE item_attributes SET attribute_id = (SELECT new_id FROM temp_attr_map WHERE old_id = item_attributes.attribute_id)
      WHERE attribute_id IN (SELECT old_id FROM temp_attr_map);
    ''');
    await customStatement('''
      DELETE FROM attributes WHERE id IN (SELECT old_id FROM temp_attr_map);
    ''');
    await customStatement('DROP TABLE temp_attr_map;');

    // 4. 去重 CategoryAttributes：按 (categoryId, attributeId) 去重
    await customStatement('''
      DELETE FROM category_attributes WHERE rowid NOT IN (
        SELECT MIN(rowid) FROM category_attributes GROUP BY category_id, attribute_id
      );
    ''');

    // 5. 去重标签：按名称去重
    await customStatement('''
      DELETE FROM tags WHERE id NOT IN (
        SELECT id FROM tags t1 WHERE t1.rowid = (
          SELECT MIN(t2.rowid) FROM tags t2 WHERE t2.name = t1.name
        )
      );
    ''');
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'nestback.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
