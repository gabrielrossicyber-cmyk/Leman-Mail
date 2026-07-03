import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/email_message.dart';
import 'core_providers.dart';

/// Quick filters of the unified inbox.
enum InboxFilterUi { all, unread, attachments, favorites, priority, suspicious }

extension InboxFilterUiLabel on InboxFilterUi {
  String get label => switch (this) {
        InboxFilterUi.all => 'Tous',
        InboxFilterUi.unread => 'Non lus',
        InboxFilterUi.attachments => 'Pièces jointes',
        InboxFilterUi.favorites => 'Favoris',
        InboxFilterUi.priority => 'Prioritaires',
        InboxFilterUi.suspicious => 'Suspects',
      };
}

final inboxFilterProvider =
    StateProvider<InboxFilterUi>((ref) => InboxFilterUi.all);

/// null = unified inbox (all accounts).
final selectedAccountIdProvider = StateProvider<int?>((ref) => null);

final inboxEmailsProvider = StreamProvider<List<EmailMessage>>((ref) {
  final filter = ref.watch(inboxFilterProvider);
  final accountId = ref.watch(selectedAccountIdProvider);
  return ref.watch(emailRepositoryProvider).watchInbox(
        accountId: accountId,
        filter: filter.name,
        limit: 200,
      );
});

final emailDetailProvider =
    FutureProvider.family<({EmailMessage? email, String? body}), int>(
        (ref, emailId) async {
  final repo = ref.watch(emailRepositoryProvider);
  final email = await repo.byId(emailId);
  final body = email == null ? null : await repo.loadBody(emailId);
  return (email: email, body: body);
});

/// Per-email remote-content policy: blocked by default, the user can
/// load images manually for one message.
final remoteContentAllowedProvider =
    StateProvider.family<bool, int>((ref, emailId) => false);
