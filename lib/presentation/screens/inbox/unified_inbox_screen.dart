import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/account.dart';
import '../../../domain/entities/email_message.dart';
import '../../providers/account_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/inbox_providers.dart';
import '../../widgets/email_tile.dart';

/// Boîte de réception : filtres rapides en chips en haut, et un volet
/// latéral (drawer) pour la navigation lourde — comptes et dossiers —
/// afin de ne pas surcharger l'écran principal.
class UnifiedInboxScreen extends ConsumerWidget {
  const UnifiedInboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emails = ref.watch(inboxEmailsProvider);
    final threads = ref.watch(threadedInboxProvider);
    final accounts = ref.watch(accountsProvider);
    final filter = ref.watch(inboxFilterProvider);
    final selectedAccountId = ref.watch(selectedAccountIdProvider);
    final folder = ref.watch(selectedFolderProvider);
    final sync = ref.watch(syncControllerProvider);

    // Surface sync results: errors were previously swallowed silently.
    ref.listen(syncControllerProvider, (previous, next) {
      if (next is AsyncError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${next.error}'),
            duration: const Duration(seconds: 8),
            showCloseIcon: true,
          ),
        );
      } else if (previous is AsyncLoading &&
          next is AsyncData<int> &&
          next.value > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${next.value} nouveaux emails.')),
        );
      }
    });

    final accountList = accounts.valueOrNull ?? [];
    final selectedAccount = selectedAccountId == null
        ? null
        : accountList
            .where((a) => a.id == selectedAccountId)
            .firstOrNull;

    final selection = ref.watch(inboxSelectionProvider);
    final selectionMode = selection.isNotEmpty;
    final emailList = emails.valueOrNull ?? [];

    return Scaffold(
      drawer: _MailDrawer(
        accounts: accountList,
        selectedAccountId: selectedAccountId,
        selectedFolder: folder,
      ),
      appBar: selectionMode
          ? _SelectionAppBar(selection: selection, emails: emailList)
          : AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(folder.label),
                  Text(
                    selectedAccount?.email ?? 'Tous les comptes',
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: 'Rechercher',
                  onPressed: () => context.push('/search'),
                ),
                if (sync.isLoading)
                  const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.sync),
                    tooltip: 'Synchroniser',
                    onPressed: () =>
                        ref.read(syncControllerProvider.notifier).syncNow(),
                  ),
              ],
            ),
      body: Column(
        children: [
          // Quick filters — the only horizontal row kept on the main page.
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                for (final f in InboxFilterUi.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(f.label),
                      selected: filter == f,
                      showCheckmark: false,
                      onSelected: (_) =>
                          ref.read(inboxFilterProvider.notifier).state = f,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: threads.when(
              data: (list) => list.isEmpty
                  ? _EmptyState(
                      hasAccounts: accountList.isNotEmpty,
                      onAddAccount: () => context.push('/add-account'),
                    )
                  : RefreshIndicator(
                      onRefresh: () =>
                          ref.read(syncControllerProvider.notifier).syncNow(),
                      child: ListView.separated(
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const Divider(
                          height: 1,
                          indent: 72,
                        ),
                        itemBuilder: (context, index) {
                          final thread = list[index];
                          final isSelected = thread.emailIds
                              .any(selection.contains);

                          // La sélection opère sur le fil entier : tous
                          // ses messages entrent/sortent ensemble.
                          void toggleSelection() {
                            final ids = {...selection};
                            isSelected
                                ? ids.removeAll(thread.emailIds)
                                : ids.addAll(thread.emailIds);
                            ref
                                .read(inboxSelectionProvider.notifier)
                                .state = ids;
                          }

                          final tile = EmailTile(
                            email: thread.latest,
                            threadCount: thread.count,
                            selected: isSelected,
                            selectionMode: selectionMode,
                            onLongPress: toggleSelection,
                            onTap: selectionMode
                                ? toggleSelection
                                : () => context.push(
                                      thread.isThread
                                          ? Uri(
                                              path: '/thread',
                                              queryParameters: {
                                                'id': thread.threadKey,
                                              },
                                            ).toString()
                                          : '/email/${thread.latest.id}',
                                    ),
                          );

                          if (selectionMode) return tile;

                          // Glisser → droite : lu/non lu (réversible, la
                          // tuile reste). Glisser → gauche : suppression.
                          final hasUnread = thread.unreadCount > 0;
                          return Dismissible(
                            key: ValueKey('swipe-${thread.threadKey}'),
                            background: _SwipeBackground(
                              alignment: Alignment.centerLeft,
                              color: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                              icon: hasUnread
                                  ? Icons.mark_email_read_outlined
                                  : Icons.mark_email_unread_outlined,
                              label: hasUnread ? 'Lu' : 'Non lu',
                            ),
                            secondaryBackground: const _SwipeBackground(
                              alignment: Alignment.centerRight,
                              color: AppTheme.riskHigh,
                              icon: Icons.delete_outline,
                              label: 'Supprimer',
                              foreground: Colors.white,
                            ),
                            confirmDismiss: (direction) async {
                              final repo =
                                  ref.read(emailRepositoryProvider);
                              if (direction ==
                                  DismissDirection.startToEnd) {
                                await repo.markRead(
                                  thread.emailIds,
                                  read: hasUnread,
                                );
                                return false; // la tuile reste en place
                              }
                              await repo.delete(thread.emailIds);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      thread.count == 1
                                          ? 'Email supprimé.'
                                          : '${thread.count} emails '
                                              'supprimés.',
                                    ),
                                  ),
                                );
                              }
                              return true;
                            },
                            child: tile,
                          );
                        },
                      ),
                    ),
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('Erreur : $error')),
            ),
          ),
        ],
      ),
    );
  }
}

/// Barre d'actions contextuelle du mode sélection multiple :
/// marquer lu/non lu, favoris, supprimer, tout sélectionner.
class _SelectionAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const _SelectionAppBar({required this.selection, required this.emails});

  final Set<int> selection;
  final List<EmailMessage> emails;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(emailRepositoryProvider);
    final ids = selection.toList();
    final selectedEmails =
        emails.where((e) => selection.contains(e.id)).toList();
    final allFlagged =
        selectedEmails.isNotEmpty && selectedEmails.every((e) => e.isFlagged);

    void clear() =>
        ref.read(inboxSelectionProvider.notifier).state = {};

    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Annuler la sélection',
        onPressed: clear,
      ),
      title: Text('${selection.length} sélectionné(s)'),
      actions: [
        IconButton(
          icon: Icon(allFlagged ? Icons.star : Icons.star_outline),
          tooltip: allFlagged ? 'Retirer des favoris' : 'Ajouter aux favoris',
          onPressed: () async {
            await repo.setFlagged(ids, flagged: !allFlagged);
            clear();
          },
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Supprimer',
          onPressed: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('Supprimer ?'),
                content: Text(
                  'Supprimer ${selection.length} email(s) de cet appareil ?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Annuler'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Supprimer'),
                  ),
                ],
              ),
            );
            if (confirmed == true) {
              await repo.delete(ids);
              clear();
            }
          },
        ),
        PopupMenuButton<String>(
          onSelected: (action) async {
            switch (action) {
              case 'read':
                await repo.markRead(ids);
                clear();
              case 'unread':
                await repo.markRead(ids, read: false);
                clear();
              case 'all':
                ref.read(inboxSelectionProvider.notifier).state =
                    {for (final e in emails) e.id};
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'read',
              child: ListTile(
                leading: Icon(Icons.mark_email_read_outlined),
                title: Text('Marquer comme lu'),
              ),
            ),
            PopupMenuItem(
              value: 'unread',
              child: ListTile(
                leading: Icon(Icons.mark_email_unread_outlined),
                title: Text('Marquer comme non lu'),
              ),
            ),
            PopupMenuItem(
              value: 'all',
              child: ListTile(
                leading: Icon(Icons.select_all),
                title: Text('Tout sélectionner'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Volet latéral : comptes, dossiers, raccourcis. Se ferme après chaque
/// sélection pour revenir immédiatement à la liste.
class _MailDrawer extends ConsumerWidget {
  const _MailDrawer({
    required this.accounts,
    required this.selectedAccountId,
    required this.selectedFolder,
  });

  final List<Account> accounts;
  final int? selectedAccountId;
  final MailFolderUi selectedFolder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    void close() => Navigator.pop(context);

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // --- Brand header -------------------------------------------
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SvgPicture.asset(
                          'assets/branding/logo.svg',
                          width: 36,
                          height: 36,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        AppConstants.appName,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppConstants.tagline,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Divider(),
            // --- Accounts ------------------------------------------------
            _DrawerSectionTitle('Comptes'),
            _DrawerTile(
              leading: const Icon(Icons.all_inbox_outlined),
              label: 'Tous les comptes',
              selected: selectedAccountId == null,
              onTap: () {
                ref.read(selectedAccountIdProvider.notifier).state = null;
                close();
              },
            ),
            for (final account in accounts)
              _DrawerTile(
                leading: CircleAvatar(
                  radius: 10,
                  backgroundColor: Color(account.colorValue),
                  child: Text(
                    account.email.substring(0, 1).toUpperCase(),
                    style: const TextStyle(fontSize: 11, color: Colors.white),
                  ),
                ),
                label: account.email,
                selected: selectedAccountId == account.id,
                onTap: () {
                  ref.read(selectedAccountIdProvider.notifier).state =
                      account.id;
                  close();
                },
              ),
            const Divider(),
            // --- Folders --------------------------------------------------
            _DrawerSectionTitle('Dossiers'),
            for (final folder in MailFolderUi.values)
              _DrawerTile(
                leading: Icon(folder.icon),
                label: folder.label,
                selected: selectedFolder == folder,
                onTap: () {
                  ref.read(selectedFolderProvider.notifier).state = folder;
                  close();
                },
              ),
            _DrawerTile(
              leading: const Icon(Icons.drafts_outlined),
              label: 'Brouillons',
              onTap: () {
                close();
                context.push('/drafts');
              },
            ),
            const Divider(),
            // --- Shortcuts ------------------------------------------------
            _DrawerTile(
              leading: const Icon(Icons.person_add_alt_outlined),
              label: 'Ajouter un compte',
              onTap: () {
                close();
                context.push('/add-account');
              },
            ),
            _DrawerTile(
              leading: const Icon(Icons.settings_outlined),
              label: 'Réglages',
              onTap: () {
                close();
                context.push('/settings');
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerSectionTitle extends StatelessWidget {
  const _DrawerSectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  const _DrawerTile({
    required this.leading,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final Widget leading;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        selected: selected,
        selectedTileColor: theme.colorScheme.primaryContainer,
        leading: leading,
        title: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.alignment,
    required this.color,
    required this.icon,
    required this.label,
    this.foreground,
  });

  final Alignment alignment;
  final Color color;
  final IconData icon;
  final String label;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final fg = foreground ?? Theme.of(context).colorScheme.onPrimaryContainer;
    return Container(
      color: color,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: fg),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: fg, fontSize: 12)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasAccounts, required this.onAddAccount});

  final bool hasAccounts;
  final VoidCallback onAddAccount;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.mark_email_read_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            hasAccounts
                ? 'Aucun email dans ce dossier avec ces filtres.'
                : 'Ajoutez un compte pour commencer.',
          ),
          if (!hasAccounts) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAddAccount,
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un compte'),
            ),
          ],
        ],
      ),
    );
  }
}
