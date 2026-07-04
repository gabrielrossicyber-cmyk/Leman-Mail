/// Contrat des notifications push distantes (FCM / APNs).
///
/// Les vraies push exigent le backend SaaS Leman (roadmap T3) : un serveur
/// qui surveille les boîtes — webhooks Microsoft Graph (`/subscriptions`),
/// Gmail `users.watch` + Cloud Pub/Sub, ou pool IMAP IDLE côté serveur —
/// puis relaie vers FCM/APNs. L'application, elle, n'a qu'à s'enregistrer
/// et réagir : c'est ce contrat.
///
/// En attendant, [NoopPushService] est injecté et l'app couvre le besoin
/// avec l'IDLE au premier plan + la synchronisation périodique en
/// arrière-plan (voir `background_sync.dart`).
abstract interface class PushService {
  /// Enregistre l'appareil (jeton FCM/APNs) auprès du backend.
  Future<void> register();

  /// Révoque l'enregistrement (déconnexion, suppression de compte).
  Future<void> unregister();

  /// Flux des réveils push reçus ; chaque événement déclenche une synchro.
  Stream<void> get wakeUps;
}

class NoopPushService implements PushService {
  const NoopPushService();

  @override
  Future<void> register() async {}

  @override
  Future<void> unregister() async {}

  @override
  Stream<void> get wakeUps => const Stream.empty();
}
