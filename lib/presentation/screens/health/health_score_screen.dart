import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/inbox_health.dart';
import '../../../domain/repositories/health_repository.dart';
import '../../providers/health_providers.dart';
import '../../widgets/score_gauge.dart';

/// Inbox Health Score : jauge, forces / améliorations / risques,
/// recommandations et évolution 7j / 30j / 90j / 12 mois + badges.
class HealthScoreScreen extends ConsumerWidget {
  const HealthScoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(inboxHealthProvider);
    final history = ref.watch(healthHistoryProvider);
    final period = ref.watch(healthPeriodProvider);
    final badges = ref.watch(badgesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Inbox Health Score')),
      body: health.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Erreur : $error')),
        data: (h) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(inboxHealthProvider),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: ScoreGauge(score: h.totalScore, label: h.grade.label),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Votre boîte obtient ${h.totalScore}/100',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _SubScore(label: 'Sécurité', score: h.securityScore),
                  _SubScore(label: 'Encombrement', score: h.clutterScore),
                  _SubScore(label: 'Vie privée', score: h.privacyScore),
                  _SubScore(label: 'Organisation', score: h.organizationScore),
                ],
              ),
              const SizedBox(height: 16),
              if (h.strengths.isNotEmpty)
                _Section(title: '✅ Forces', items: h.strengths),
              if (h.improvements.isNotEmpty)
                _Section(title: '⚠️ À améliorer', items: h.improvements),
              if (h.risks.isNotEmpty)
                _Section(title: '❌ Risques', items: h.risks),
              if (h.recommendations.isNotEmpty)
                _Section(
                  title: '💡 Recommandations',
                  items: [
                    for (final r in h.recommendations)
                      '${r.message} (+${r.impact} pts)',
                  ],
                ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Évolution',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  SegmentedButton<HealthPeriod>(
                    segments: const [
                      ButtonSegment(
                        value: HealthPeriod.week,
                        label: Text('7j'),
                      ),
                      ButtonSegment(
                        value: HealthPeriod.month,
                        label: Text('30j'),
                      ),
                      ButtonSegment(
                        value: HealthPeriod.quarter,
                        label: Text('90j'),
                      ),
                      ButtonSegment(
                        value: HealthPeriod.year,
                        label: Text('12m'),
                      ),
                    ],
                    selected: {period},
                    onSelectionChanged: (selection) => ref
                        .read(healthPeriodProvider.notifier)
                        .state = selection.first,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 180,
                child: history.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (snapshots) => snapshots.length < 2
                      ? const Center(
                          child: Text(
                            'L\'historique apparaîtra après quelques jours '
                            'd\'utilisation.',
                          ),
                        )
                      : LineChart(
                          LineChartData(
                            minY: 0,
                            maxY: 100,
                            titlesData: const FlTitlesData(
                              topTitles: AxisTitles(),
                              rightTitles: AxisTitles(),
                              bottomTitles: AxisTitles(),
                            ),
                            lineBarsData: [
                              LineChartBarData(
                                isCurved: true,
                                color: AppTheme.scoreColor(h.totalScore),
                                barWidth: 3,
                                dotData: const FlDotData(show: false),
                                spots: [
                                  for (final (i, snap)
                                      in snapshots.indexed)
                                    FlSpot(
                                      i.toDouble(),
                                      snap.totalScore.toDouble(),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                '🏆 Badges',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              badges.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (list) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final badge in list)
                      Tooltip(
                        message: badge.description,
                        child: Chip(
                          avatar: Text(badge.emoji),
                          label: Text(badge.title),
                          backgroundColor: badge.isUnlocked
                              ? AppTheme.riskLow.withValues(alpha: 0.15)
                              : null,
                          labelStyle: badge.isUnlocked
                              ? const TextStyle(fontWeight: FontWeight.w700)
                              : TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.outline,
                                ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubScore extends StatelessWidget {
  const _SubScore({required this.label, required this.score});

  final String label;
  final int score;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '$score',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.scoreColor(score),
                ),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $item'),
              ),
          ],
        ),
      ),
    );
  }
}
