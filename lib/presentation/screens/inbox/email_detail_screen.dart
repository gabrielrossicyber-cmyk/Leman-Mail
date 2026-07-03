import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/email_utils.dart';
import '../../../domain/entities/email_message.dart';
import '../../providers/core_providers.dart';
import '../../providers/inbox_providers.dart';
import '../../widgets/risk_badge.dart';

/// Lecture d'un email : verdict sécurité, bannière anti-tracking,
/// authentification SPF/DKIM/DMARC, corps déchiffré à la demande.
class EmailDetailScreen extends ConsumerWidget {
  const EmailDetailScreen({super.key, required this.emailId});

  final int emailId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(emailDetailProvider(emailId));
    final remoteAllowed = ref.watch(remoteContentAllowedProvider(emailId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Message'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Supprimer',
            onPressed: () async {
              await ref.read(emailRepositoryProvider).delete([emailId]);
              if (context.mounted) context.pop();
            },
          ),
        ],
      ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Erreur : $error')),
        data: (data) {
          final email = data.email;
          if (email == null) {
            return const Center(child: Text('Email introuvable.'));
          }
          // Mark as read on open.
          if (!email.isRead) {
            Future.microtask(
              () => ref.read(emailRepositoryProvider).markRead([emailId]),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                email.subject.isEmpty ? '(sans objet)' : email.subject,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${email.fromName} <${email.fromAddress}>',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  Text(
                    DateFormat('d MMM y, HH:mm', 'fr').format(email.date),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // --- Security verdict --------------------------------------
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  RiskBadge(
                    level: email.phishingLevel,
                    score: email.phishingScore,
                  ),
                  _AuthChip(label: 'SPF', result: email.spf),
                  _AuthChip(label: 'DKIM', result: email.dkim),
                  _AuthChip(label: 'DMARC', result: email.dmarc),
                ],
              ),
              if (email.phishingLevel == RiskLevel.high) ...[
                const SizedBox(height: 12),
                _WarningBanner(
                  color: AppTheme.riskHigh,
                  icon: Icons.gpp_bad_outlined,
                  text:
                      'Cet email présente des signaux forts de phishing. '
                      'N\'ouvrez aucun lien ni pièce jointe.',
                  action: TextButton(
                    onPressed: () async {
                      final domain =
                          EmailUtils.domainOf(email.fromAddress);
                      await ref.read(emailRepositoryProvider).blockSender(
                            domain != null
                                ? '*@$domain'
                                : email.fromAddress,
                            reason: 'phishing',
                          );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Expéditeur bloqué.'),
                          ),
                        );
                      }
                    },
                    child: const Text('Bloquer l\'expéditeur'),
                  ),
                ),
              ],
              if (email.hasTracking && !remoteAllowed) ...[
                const SizedBox(height: 12),
                _WarningBanner(
                  color: AppTheme.riskMedium,
                  icon: Icons.visibility_off_outlined,
                  text:
                      'Cet email tente de suivre votre activité. '
                      '${email.trackerCount} tracker(s) bloqué(s).',
                  action: TextButton(
                    onPressed: () => ref
                        .read(
                          remoteContentAllowedProvider(emailId).notifier,
                        )
                        .state = true,
                    child: const Text('Charger quand même'),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              // --- Body ----------------------------------------------------
              // The HTML body is rendered as sanitized text in this version;
              // a hardened WebView (JS off, remote content gated by
              // remoteAllowed) is the natural upgrade path.
              SelectableText(
                data.body == null
                    ? email.snippet
                    : _stripHtml(data.body!),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          );
        },
      ),
    );
  }

  static String _stripHtml(String source) => source
      .replaceAll(RegExp(r'<(style|script)[^>]*>.*?</\1>',
          dotAll: true, caseSensitive: false), '')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n')
      .replaceAll(RegExp('<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .trim();
}

class _AuthChip extends StatelessWidget {
  const _AuthChip({required this.label, required this.result});

  final String label;
  final AuthResult result;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (result) {
      AuthResult.pass => (AppTheme.riskLow, Icons.check_circle_outline),
      AuthResult.fail => (AppTheme.riskHigh, Icons.cancel_outlined),
      AuthResult.softfail => (AppTheme.riskMedium, Icons.error_outline),
      AuthResult.none ||
      AuthResult.unknown =>
        (Theme.of(context).colorScheme.outline, Icons.help_outline),
    };
    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text('$label ${result.name}'),
      labelStyle: TextStyle(fontSize: 12, color: color),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({
    required this.color,
    required this.icon,
    required this.text,
    this.action,
  });

  final Color color;
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(text)),
            ],
          ),
          if (action != null)
            Align(alignment: Alignment.centerRight, child: action),
        ],
      ),
    );
  }
}
