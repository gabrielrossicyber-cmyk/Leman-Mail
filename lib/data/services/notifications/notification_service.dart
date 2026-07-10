import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notifications locales à l'écran : nouveaux emails et alertes sécurité.
///
/// Deux canaux distincts pour qu'Android/iOS laissent l'utilisateur
/// régler leur importance séparément :
///  - `new_mail`        : arrivée de nouveaux messages (importance normale)
///  - `security_alerts` : phishing à risque élevé détecté (importance max)
class NotificationService {
  NotificationService([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  static const _newMailChannel = AndroidNotificationDetails(
    'new_mail',
    'Nouveaux emails',
    channelDescription: 'Notification à l\'arrivée de nouveaux emails',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  static const _securityChannel = AndroidNotificationDetails(
    'security_alerts',
    'Alertes sécurité',
    channelDescription:
        'Alerte immédiate quand un email à risque élevé est détecté',
    importance: Importance.max,
    priority: Priority.high,
  );

  Future<void> init({bool requestPermissions = true}) async {
    if (_initialized) return;
    await _plugin.initialize(
      InitializationSettings(
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: requestPermissions,
          requestBadgePermission: requestPermissions,
          requestSoundPermission: requestPermissions,
        ),
      ),
    );
    if (requestPermissions) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
    _initialized = true;
  }

  Future<void> showNewEmails(int count, {String? preview}) => _plugin.show(
        1, // id stable : la notification se remplace au lieu de s'empiler
        count == 1 ? '1 nouvel email' : '$count nouveaux emails',
        preview ?? 'Ouvrez Leman Mail pour les consulter.',
        const NotificationDetails(
          android: _newMailChannel,
          iOS: DarwinNotificationDetails(),
        ),
      );

  Future<void> showThreat(String subject, String fromAddress) => _plugin.show(
        // id dérivé du contenu : chaque menace garde sa notification.
        Object.hash(subject, fromAddress) & 0x7fffffff,
        '🔴 Email à risque élevé détecté',
        '« $subject » — $fromAddress. Ne cliquez sur aucun lien.',
        const NotificationDetails(
          android: _securityChannel,
          iOS: DarwinNotificationDetails(
            interruptionLevel: InterruptionLevel.timeSensitive,
          ),
        ),
      );
}
