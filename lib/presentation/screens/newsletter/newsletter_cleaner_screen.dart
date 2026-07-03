import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../domain/repositories/newsletter_repository.dart';
import '../../../domain/usecases/run_newsletter_cleanup.dart';
import '../../../features/cleanup/smart_cleanup_analyzer.dart';
import '../../providers/newsletter_providers.dart';

/// Newsletter Cleaner : liste des expéditeurs de newsletters avec cases à
/// cocher et bouton « Nettoyer ma boîte ».
class NewsletterCleanerScreen extends ConsumerWidget {
  const NewsletterCleanerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final newsletters = ref.watch(activeNewslettersProvider);
    final selected = ref.watch(selectedNewsletterIdsProvider);
    final cleanup = ref.watch(newsletterCleanupControllerProvider);

    ref.listen(newsletterCleanupControllerProvider, (previous, next) {
      final report = next.valueOrNull;
      if (report == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${report.processed} expéditeur(s) traité(s), '
            '${report.oneClickUnsubscribed} désabonnement(s) automatique(s).',
          ),
        ),
      );
      // Unsubscribe links that need the browser.
      for (final manual in report.manualActionsRequired) {
        if (manual.outcome == UnsubscribeOutcome.openUrl &&
            manual.target != null) {
          launchUrl(
            Uri.parse(manual.target!),
            mode: LaunchMode.externalApplication,
          );
        }
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Newsletter Cleaner')),
      body: newsletters.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Erreur : $error')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Text('Aucune newsletter détectée. Bravo ! 🎉'),
            );
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${list.length} newsletters détectées — '
                        'sélectionnez celles à nettoyer.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: () => ref
                          .read(selectedNewsletterIdsProvider.notifier)
                          .state = {for (final s in list) s.id},
                      child: const Text('Tout cocher'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final sender = list[index];
                    return CheckboxListTile(
                      value: selected.contains(sender.id),
                      onChanged: (checked) {
                        final ids = {...selected};
                        checked == true
                            ? ids.add(sender.id)
                            : ids.remove(sender.id);
                        ref
                            .read(selectedNewsletterIdsProvider.notifier)
                            .state = ids;
                      },
                      title: Text(
                        sender.senderName.isNotEmpty
                            ? sender.senderName
                            : sender.senderAddress,
                      ),
                      subtitle: Text(
                        '${sender.emailCount} emails · '
                        '${SmartCleanupAnalyzer.formatBytes(sender.totalSizeBytes)}'
                        '${sender.supportsOneClick ? ' · désabonnement 1-clic' : ''}',
                      ),
                      secondary: sender.readRatio < 0.2
                          ? Tooltip(
                              message: 'Vous ne lisez presque jamais ces emails',
                              child: Icon(
                                Icons.do_not_disturb_on_outlined,
                                color: Theme.of(context).colorScheme.error,
                              ),
                            )
                          : null,
                    );
                  },
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          icon: cleanup.isLoading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.cleaning_services),
                          label: const Text('Nettoyer ma boîte'),
                          onPressed: selected.isEmpty || cleanup.isLoading
                              ? null
                              : () => _showActionSheet(context, ref),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showActionSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (action, icon, label) in [
              (
                NewsletterCleanupAction.unsubscribe,
                Icons.unsubscribe_outlined,
                'Se désabonner',
              ),
              (
                NewsletterCleanupAction.block,
                Icons.block_outlined,
                'Bloquer',
              ),
              (
                NewsletterCleanupAction.archive,
                Icons.archive_outlined,
                'Archiver',
              ),
              (
                NewsletterCleanupAction.delete,
                Icons.delete_outline,
                'Supprimer les emails',
              ),
            ])
              ListTile(
                leading: Icon(icon),
                title: Text(label),
                onTap: () {
                  Navigator.pop(sheetContext);
                  ref
                      .read(newsletterCleanupControllerProvider.notifier)
                      .run(action);
                },
              ),
          ],
        ),
      ),
    );
  }
}
