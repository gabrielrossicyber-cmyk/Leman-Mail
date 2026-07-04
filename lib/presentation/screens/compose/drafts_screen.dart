import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../providers/core_providers.dart';

/// Brouillons locaux : auto-sauvegardés en quittant la composition,
/// repris d'un tap, supprimés à l'envoi.
class DraftsScreen extends ConsumerWidget {
  const DraftsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drafts = ref.watch(draftsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Brouillons')),
      body: drafts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Erreur : $error')),
        data: (list) => list.isEmpty
            ? const Center(child: Text('Aucun brouillon.'))
            : ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 72),
                itemBuilder: (context, index) {
                  final draft = list[index];
                  return ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.drafts_outlined, size: 20),
                    ),
                    title: Text(
                      draft.subject.isEmpty ? '(sans objet)' : draft.subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${draft.toText.isEmpty ? '(sans destinataire)' : 'À : ${draft.toText}'}'
                      '\n${draft.body}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          DateFormat('d MMM, HH:mm', 'fr')
                              .format(draft.updatedAt),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          tooltip: 'Supprimer le brouillon',
                          onPressed: () => ref
                              .read(databaseProvider)
                              .deleteDraftById(draft.id),
                        ),
                      ],
                    ),
                    isThreeLine: true,
                    onTap: () => context.push('/compose?draftId=${draft.id}'),
                  );
                },
              ),
      ),
    );
  }
}
