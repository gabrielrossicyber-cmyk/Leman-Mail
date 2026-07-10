import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/cleanup_suggestion.dart';
import '../../../features/cleanup/smart_cleanup_analyzer.dart';
import '../../providers/newsletter_providers.dart';

/// Smart Cleanup : suggestions de nettoyage par lot.
class SmartCleanupScreen extends ConsumerWidget {
  const SmartCleanupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestions = ref.watch(cleanupSuggestionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Smart Cleanup')),
      body: suggestions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Erreur : $error')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Text('Rien à nettoyer, votre boîte est saine. ✨'),
            );
          }
          final totalBytes =
              list.fold(0, (sum, s) => sum + s.recoverableBytes);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Vous pouvez récupérer '
                    '${SmartCleanupAnalyzer.formatBytes(totalBytes)} '
                    'et réduire votre bruit numérique.',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              for (final suggestion in list)
                _SuggestionCard(suggestion: suggestion),
            ],
          );
        },
      ),
    );
  }
}

class _SuggestionCard extends ConsumerWidget {
  const _SuggestionCard({required this.suggestion});

  final CleanupSuggestion suggestion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apply = ref.watch(applyCleanupProvider);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              suggestion.title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(suggestion.description),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final action in suggestion.suggestedActions)
                  OutlinedButton.icon(
                    icon: Icon(_iconFor(action), size: 18),
                    label: Text(_labelFor(action)),
                    onPressed: () async {
                      if (action == CleanupAction.delete) {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('Confirmer la suppression'),
                            content: Text(
                              'Supprimer ${suggestion.emailCount} emails ? '
                              'Cette action est irréversible.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, false),
                                child: const Text('Annuler'),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, true),
                                child: const Text('Supprimer'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true) return;
                      }
                      await apply(suggestion, action);
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(CleanupAction action) => switch (action) {
        CleanupAction.delete => Icons.delete_outline,
        CleanupAction.archive => Icons.archive_outlined,
        CleanupAction.unsubscribe => Icons.unsubscribe_outlined,
        CleanupAction.block => Icons.block_outlined,
      };

  static String _labelFor(CleanupAction action) => switch (action) {
        CleanupAction.delete => 'Supprimer',
        CleanupAction.archive => 'Archiver',
        CleanupAction.unsubscribe => 'Se désabonner',
        CleanupAction.block => 'Bloquer',
      };
}
