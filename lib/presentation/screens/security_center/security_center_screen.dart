import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/account_providers.dart';
import '../../providers/security_providers.dart';
import '../../widgets/score_gauge.dart';

/// Security Center : score global façon Secure Score, scores par compte
/// et recommandations valorisées en points.
class SecurityCenterScreen extends ConsumerWidget {
  const SecurityCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posture = ref.watch(securityPostureProvider);
    final accounts = ref.watch(accountsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Security Center')),
      body: posture.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Erreur : $error')),
        data: (p) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(securityPostureProvider),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child:
                    ScoreGauge(score: p.globalScore, label: 'Score global'),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _MiniScore(
                      label: 'Anti-phishing',
                      score: p.phishingScore,
                      icon: Icons.phishing_outlined,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MiniScore(
                      label: 'Confidentialité',
                      score: p.privacyScore,
                      icon: Icons.visibility_off_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Scores par compte',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              accounts.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (list) => Column(
                  children: [
                    for (final account in list)
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Color(account.colorValue),
                          child: Text(
                            account.email.substring(0, 1).toUpperCase(),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text(account.email),
                        subtitle: Text(
                          account.mfaEnabled
                              ? 'MFA actif'
                              : 'MFA non détecté',
                        ),
                        trailing: Text(
                          '${p.accountScores[account.uuid] ?? '—'}/100',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Recommandations',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              if (p.recommendations.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Aucune action requise — votre posture de sécurité '
                      'est excellente. 🎉',
                    ),
                  ),
                )
              else
                for (final rec in p.recommendations)
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            Theme.of(context).colorScheme.primaryContainer,
                        child: Text(
                          '+${rec.points}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                        ),
                      ),
                      title: Text(rec.title),
                      subtitle: Text(rec.description),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniScore extends StatelessWidget {
  const _MiniScore({
    required this.label,
    required this.score,
    required this.icon,
  });

  final String label;
  final int score;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon),
            const SizedBox(height: 8),
            Text(
              '$score/100',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
