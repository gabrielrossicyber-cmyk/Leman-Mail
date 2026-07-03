import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../providers/security_providers.dart';
import '../../widgets/stat_card.dart';

/// Dashboard cybersécurité : tuiles de statistiques + répartition
/// SPF/DKIM/DMARC.
class SecurityDashboardScreen extends ConsumerWidget {
  const SecurityDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(dashboardStatsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard sécurité'),
        actions: [
          IconButton(
            icon: const Icon(Icons.cleaning_services_outlined),
            tooltip: 'Smart Cleanup',
            onPressed: () => context.push('/cleanup'),
          ),
        ],
      ),
      body: stats.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Erreur : $error')),
        data: (s) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(dashboardStatsProvider),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.5,
                children: [
                  StatCard(
                    value: '${s.totalEmails}',
                    label: 'Emails analysés',
                    icon: Icons.mark_email_read_outlined,
                  ),
                  StatCard(
                    value: '${s.highRiskCount}',
                    label: 'Menaces détectées',
                    icon: Icons.gpp_bad_outlined,
                    color: AppTheme.riskHigh,
                  ),
                  StatCard(
                    value: '${s.mediumRiskCount}',
                    label: 'Emails suspects',
                    icon: Icons.warning_amber_outlined,
                    color: AppTheme.riskMedium,
                  ),
                  StatCard(
                    value: '${s.suspiciousDomainsBlocked}',
                    label: 'Domaines suspects bloqués',
                    icon: Icons.block_outlined,
                  ),
                  StatCard(
                    value: '${s.trackedEmailCount}',
                    label: 'Emails avec trackers',
                    icon: Icons.visibility_off_outlined,
                  ),
                  StatCard(
                    value: '${s.trackerTotal}',
                    label: 'Trackers bloqués',
                    icon: Icons.shield_outlined,
                    color: AppTheme.riskLow,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Authentification des emails reçus',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    height: 220,
                    child: s.authEvaluatedCount == 0
                        ? const Center(
                            child: Text('Pas encore de données.'),
                          )
                        : BarChart(
                            BarChartData(
                              maxY: 100,
                              barTouchData: BarTouchData(enabled: false),
                              titlesData: FlTitlesData(
                                topTitles: const AxisTitles(),
                                rightTitles: const AxisTitles(),
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    getTitlesWidget: (value, meta) => Text(
                                      switch (value.toInt()) {
                                        0 => 'SPF',
                                        1 => 'DKIM',
                                        _ => 'DMARC',
                                      },
                                    ),
                                  ),
                                ),
                              ),
                              barGroups: [
                                for (final (i, pass) in [
                                  s.spfPassCount,
                                  s.dkimPassCount,
                                  s.dmarcPassCount,
                                ].indexed)
                                  BarChartGroupData(
                                    x: i,
                                    barRods: [
                                      BarChartRodData(
                                        toY: pass *
                                            100 /
                                            s.authEvaluatedCount,
                                        width: 32,
                                        borderRadius:
                                            BorderRadius.circular(6),
                                        color: AppTheme.scoreColor(
                                          (pass *
                                                  100 /
                                                  s.authEvaluatedCount)
                                              .round(),
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Pourcentage d\'emails passant chaque contrôle '
                'd\'authentification.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
