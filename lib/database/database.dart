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
  int get schemaVersion => 6;

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
      },
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'nestback.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
