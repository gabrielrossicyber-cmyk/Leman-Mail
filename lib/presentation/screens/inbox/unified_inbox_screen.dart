import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/account_providers.dart';
import '../../providers/inbox_providers.dart';
import '../../widgets/email_tile.dart';

/// Boîte de réception unifiée : tous les comptes, filtres rapides,
/// compteurs et pull-to-refresh.
class UnifiedInboxScreen extends ConsumerWidget {
  const UnifiedInboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emails = ref.watch(inboxEmailsProvider);
    final accounts = ref.watch(accountsProvider);
    final filter = ref.watch(inboxFilterProvider);
    final selectedAccount = ref.watch(selectedAccountIdProvider);
    final sync = ref.watch(syncControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Boîte unifiée'),
        actions: [
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
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Account selector (unified + one chip per account).
          accounts.when(
            data: (list) => SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: const Text('Tous les comptes'),
                      selected: selectedAccount == null,
                      onSelected: (_) => ref
                          .read(selectedAccountIdProvider.notifier)
                          .state = null,
                    ),
                  ),
                  for (final account in list)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        avatar: CircleAvatar(
                          backgroundColor: Color(account.colorValue),
                        ),
                        label: Text(account.email),
                        selected: selectedAccount == account.id,
                        onSelected: (_) => ref
                            .read(selectedAccountIdProvider.notifier)
                            .state = account.id,
                      ),
                    ),
                ],
              ),
            ),
            loading: () => const SizedBox(height: 48),
            error: (_, __) => const SizedBox(height: 48),
          ),
          // Quick filters.
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final f in InboxFilterUi.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(f.label),
                      selected: filter == f,
                      onSelected: (_) =>
                          ref.read(inboxFilterProvider.notifier).state = f,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: emails.when(
              data: (list) => list.isEmpty
                  ? _EmptyInbox(
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
                          final email = list[index];
                          return EmailTile(
                            email: email,
                            onTap: () => context.push('/email/${email.id}'),
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

class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox({required this.onAddAccount});

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
          const Text('Aucun email — ajoutez un compte pour commencer.'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAddAccount,
            icon: const Icon(Icons.add),
            label: const Text('Ajouter un compte'),
          ),
        ],
      ),
    );
  }
}
