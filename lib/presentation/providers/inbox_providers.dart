import 'package:flutter/material.dart' show IconData, Icons;
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

/// Folder shown in the list — drives the drawer selection.
enum MailFolderUi { inbox, sent, spam, archive }

extension MailFolderUiMeta on MailFolderUi {
  String get label => switch (this) {
        MailFolderUi.inbox => 'Boîte de réception',
        MailFolderUi.sent => 'Envoyés',
        MailFolderUi.spam => 'Spam',
        MailFolderUi.archive => 'Archive',
      };

  IconData get icon => switch (this) {
        MailFolderUi.inbox => Icons.inbox_outlined,
        MailFolderUi.sent => Icons.send_outlined,
        MailFolderUi.spam => Icons.report_gmailerrorred_outlined,
        MailFolderUi.archive => Icons.archive_outlined,
      };
}

final selectedFolderProvider =
    StateProvider<MailFolderUi>((ref) => MailFolderUi.inbox);

final inboxEmailsProvider = StreamProvider<List<EmailMessage>>((ref) {
  final filter = ref.watch(inboxFilterProvider);
  final accountId = ref.watch(selectedAccountIdProvider);
  final folder = ref.watch(selectedFolderProvider);
  return ref.watch(emailRepositoryProvider).watchInbox(
        accountId: accountId,
        folderType: folder.name,
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

/// Multi-selection dans la liste (appui long). Vide = mode normal.
final inboxSelectionProvider = StateProvider<Set<int>>((ref) => {});

/// Résultats de la recherche plein texte locale.
final searchResultsProvider =
    FutureProvider.family<List<EmailMessage>, String>((ref, query) {
  if (query.trim().length < 2) return Future.value(const []);
  return ref.watch(emailRepositoryProvider).search(query);
});
