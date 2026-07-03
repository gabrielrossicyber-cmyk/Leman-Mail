import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/entities/inbox_health.dart' as domain;
import '../../domain/repositories/health_repository.dart';
import '../database/app_database.dart';

class HealthRepositoryImpl implements HealthRepository {
  HealthRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<void> saveDailySnapshot(
    domain.InboxHealth health, {
    int? accountId,
  }) {
    final day = DateTime.utc(
      health.computedAt.year,
      health.computedAt.month,
      health.computedAt.day,
    );
    return _db.healthDao.saveSnapshot(
      HealthSnapshotsCompanion.insert(
        accountId: Value(accountId),
        day: day,
        totalScore: health.totalScore,
        securityScore: health.securityScore,
        clutterScore: health.clutterScore,
        privacyScore: health.privacyScore,
        organizationScore: health.organizationScore,
        detailsJson: Value(
          jsonEncode({
            'strengths': health.strengths,
            'improvements': health.improvements,
            'risks': health.risks,
            'recommendations': [
              for (final r in health.recommendations)
                {'message': r.message, 'impact': r.impact},
            ],
          }),
        ),
      ),
    );
  }

  @override
  Future<List<domain.HealthSnapshot>> history(
    HealthPeriod period, {
    int? accountId,
  }) async {
    final since = DateTime.now().toUtc().subtract(period.duration);
    final rows =
        await _db.healthDao.snapshotsSince(since, accountId: accountId);
    return [
      for (final row in rows)
        domain.HealthSnapshot(
          day: row.day,
          totalScore: row.totalScore,
          securityScore: row.securityScore,
          clutterScore: row.clutterScore,
          privacyScore: row.privacyScore,
          organizationScore: row.organizationScore,
        ),
    ];
  }

  @override
  Future<Set<String>> unlockedBadgeIds() => _db.healthDao.unlockedBadgeIds();

  @override
  Future<void> unlockBadges(Set<String> badgeIds) async {
    for (final id in badgeIds) {
      await _db.healthDao.unlockBadge(id);
    }
  }
}
