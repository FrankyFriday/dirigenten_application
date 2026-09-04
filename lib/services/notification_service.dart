import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  static const _lastNotifiedVersionKey = 'last_notified_update_version';
  static const _updateChannelId = 'app_updates';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (kIsWeb || _initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    final initialized = await _plugin.initialize(settings: settings);
    if (initialized != true) return;

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _updateChannelId,
        'App-Updates',
        description: 'Benachrichtigungen über neue App-Versionen',
        importance: Importance.max,
      ),
    );
    await androidPlugin?.requestNotificationsPermission();

    _initialized = true;
  }

  Future<void> showUpdateAvailable(String version) async {
    if (!_initialized) return;

    try {
      final preferences = await SharedPreferences.getInstance();
      final lastNotifiedVersion =
          preferences.getString(_lastNotifiedVersionKey);
      if (lastNotifiedVersion == version) return;

      await preferences.setString(_lastNotifiedVersionKey, version);
      await _plugin.show(
        id: 1001,
        title: 'Neues Update verfügbar',
        body: 'Marschpad $version kann jetzt installiert werden.',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _updateChannelId,
            'App-Updates',
            channelDescription:
                'Benachrichtigungen über neue App-Versionen',
            importance: Importance.max,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
          macOS: DarwinNotificationDetails(),
        ),
      );
    } catch (error) {
      debugPrint('Update-Benachrichtigung konnte nicht angezeigt werden: $error');
    }
  }
}

final notificationService = NotificationService();