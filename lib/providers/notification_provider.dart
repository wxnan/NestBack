import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../database/database.dart';

class NotificationProvider extends ChangeNotifier {
  final AppDatabase _db;
  List<AppNotification> _notifications = [];

  NotificationProvider(this._db);

  List<AppNotification> get notifications => _notifications;
  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  Future<void> loadNotifications() async {
    _notifications = await (_db.select(_db.appNotifications)
          ..orderBy([
            (t) => OrderingTerm.desc(t.createdAt),
          ]))
        .get();
    notifyListeners();
  }

  Future<void> addNotification({
    required String title,
    required String body,
    String type = 'expire',
    String? itemId,
  }) async {
    final id = const Uuid().v4();
    await _db.into(_db.appNotifications).insert(AppNotificationsCompanion.insert(
          id: id,
          title: title,
          body: body,
          type: Value(type),
          itemId: Value(itemId),
          createdAt: DateTime.now(),
        ));
    await loadNotifications();
  }

  Future<void> markAsRead(String notificationId) async {
    await (_db.update(_db.appNotifications)
          ..where((t) => t.id.equals(notificationId)))
        .write(AppNotificationsCompanion(isRead: Value(true)));
    await loadNotifications();
  }

  Future<void> markAllAsRead() async {
    await (_db.update(_db.appNotifications)
          ..where((t) => t.isRead.equals(false)))
        .write(AppNotificationsCompanion(isRead: Value(true)));
    await loadNotifications();
  }

  Future<void> deleteNotification(String notificationId) async {
    await (_db.delete(_db.appNotifications)
          ..where((t) => t.id.equals(notificationId)))
        .go();
    await loadNotifications();
  }

  Future<void> deleteAllNotifications() async {
    await (_db.delete(_db.appNotifications)).go();
    await loadNotifications();
  }
}
