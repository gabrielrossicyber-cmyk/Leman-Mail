import 'dart:async';

import 'package:enough_mail/enough_mail.dart';

import '../../../domain/entities/account.dart' as domain;
import '../../../domain/repositories/account_repository.dart';

/// IMAP IDLE (RFC 2177) : garde une connexion ouverte sur INBOX pour chaque
/// compte IMAP et déclenche [onNewMail] dès que le serveur signale un
/// nouveau message — synchronisation instantanée tant que l'app est au
/// premier plan.
///
/// Cycle de vie : démarré au lancement et à chaque retour au premier plan,
/// arrêté à la mise en arrière-plan (iOS/Android coupent les sockets des
/// apps en arrière-plan ; c'est la synchro périodique WorkManager qui prend
/// le relais — voir `background_sync.dart`).
class ImapIdleService {
  ImapIdleService({required this.onNewMail});

  /// Callback synchro, débouncé : plusieurs événements rapprochés ne
  /// déclenchent qu'une synchronisation.
  final Future<void> Function() onNewMail;

  final List<ImapClient> _clients = [];
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _debounce;
  bool _running = false;

  Future<void> start(
    List<domain.Account> accounts,
    Future<AccountCredentials?> Function(String uuid) credentialsOf,
  ) async {
    if (_running) await stop();
    _running = true;

    for (final account in accounts) {
      // IDLE ne concerne que les comptes IMAP à mot de passe : Gmail et
      // Microsoft passent par leurs API (et, à terme, les push serveur).
      if (account.authMethod != domain.AuthMethod.password ||
          account.imapHost == null) {
        continue;
      }
      final credentials = await credentialsOf(account.uuid);
      final password = credentials?.password;
      if (password == null) continue;

      try {
        final client = ImapClient(isLogEnabled: false);
        await client.connectToServer(
          account.imapHost!,
          account.imapPort,
          isSecure: account.imapTls,
        );
        await client.login(account.email, password);
        await client.selectInbox();

        final subscription = client.eventBus.on<ImapEvent>().listen((event) {
          if (event.eventType == ImapEventType.exists ||
              event.eventType == ImapEventType.recent) {
            _scheduleSync();
          }
        });

        await client.idleStart();
        _clients.add(client);
        _subscriptions.add(subscription);
      } on Exception {
        // Best effort : un compte injoignable n'empêche pas les autres
        // d'écouter ; la synchro manuelle/périodique reste disponible.
      }
    }
  }

  void _scheduleSync() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () {
      unawaited(onNewMail());
    });
  }

  Future<void> stop() async {
    _running = false;
    _debounce?.cancel();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    for (final client in _clients) {
      try {
        if (client.isConnected) {
          await client.idleDone();
          await client.logout();
        }
      } on Exception {
        // Socket déjà fermé par l'OS : rien à faire.
      }
    }
    _clients.clear();
  }
}
