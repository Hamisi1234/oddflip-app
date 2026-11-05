import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class CardNotificationService {
  CardNotificationService._();

  static final _notifications = FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    await _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
        web: WebInitializationSettings(),
      ),
    );

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await requestPermission();
    }
  }

  static Future<void> requestPermission() async {
    if (kIsWeb) {
      await _notifications
          .resolvePlatformSpecificImplementation<
              WebFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      return;
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        await _notifications
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
        return;
      case TargetPlatform.iOS:
        await _notifications
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true);
        return;
      default:
        return;
    }
  }

  static Future<void> showRedCard({
    required String homeTeam,
    required String awayTeam,
    required String player,
    required String team,
    required int minute,
  }) async {
    final id = DateTime.now().microsecondsSinceEpoch % 0x7fffffff;
    await _notifications.show(
      id: id,
      title: 'Red card: $homeTeam vs $awayTeam',
      body: '$player ($team) sent off at $minute′',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'red_card_alerts',
          'Red card alerts',
          channelDescription:
              'Alerts when a red card is reported in a live match.',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentList: true,
          presentSound: true,
        ),
        web: WebNotificationDetails(),
      ),
    );
  }
}
