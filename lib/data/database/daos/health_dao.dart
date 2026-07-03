import 'package:drift/drift.dart';

import '../../../domain/entities/security_recommendation.dart'
    show RecommendationStatus;
import '../app_database.dart';

part 'health_dao.g.dart';

@DriftAccessor(tables: [HealthSnapshots, SecurityRecommendations, Badges])
class HealthDao extends DatabaseAccessor<AppDatabase> with _$HealthDaoMixin {
  HealthDao(super.db);

  /// One snapshot per (account, day): re-running the computation the same
  /// day overwrites instead of duplicating. SQLite UNIQUE treats NULLs as
  /// distinct, so global snapshots (accountId NULL) are deduplicated
  /// manually with a delete-then-insert.
  Future<void> saveSnapshot(HealthSnapshotsCompanion snapshot) =>
      transaction(() async {
        final accountId = snapshot.accountId.present
            ? snapshot.accountId.value
            : null;
        final deleteQuery = delete(healthSnapshots)
          ..where((s) => s.day.equals(snapshot.day.value));
        if (accountId == null) {
          deleteQuery.where((s) => s.accountId.isNull());
        } else {
          deleteQuery.where((s) => s.accountId.equals(accountId));
        }
        await deleteQuery.go();
        await into(healthSnapshots).insert(snapshot);
      });

  /// Snapshots for the evolution charts (7d / 30d / 90d / 12m).
  Future<List<HealthSnapshot>> snapshotsSince(
    DateTime since, {
    int? accountId,
  }) {
    final query = select(healthSnapshots)
      ..where((s) => s.day.isBiggerOrEqualValue(since))
      ..orderBy([(s) => OrderingTerm.asc(s.day)]);
    if (accountId == null) {
      query.where((s) => s.accountId.isNull());
    } else {
      query.where((s) => s.accountId.equals(accountId));
    }
    return query.get();
  }

  // ---- Security Center recommendations ------------------------------------

  Future<void> upsertRecommendation(SecurityRecommendationsCompanion rec) =>
      into(securityRecommendations).insertOnConflictUpdate(rec);

  Future<List<SecurityRecommendation>> openRecommendations() =>
      (select(securityRecommendations)
            ..where((r) => r.status.equalsValue(RecommendationStatus.open))
            ..orderBy([(r) => OrderingTerm.desc(r.points)]))
          .get();

  Future<void> setRecommendationStatus(
    String code,
    RecommendationStatus status,
  ) =>
      (update(securityRecommendations)..where((r) => r.code.equals(code)))
          .write(
        SecurityRecommendationsCompanion(
          status: Value(status),
          completedAt: Value(
            status == RecommendationStatus.completed ? DateTime.now() : null,
          ),
        ),
      );

  // ---- Badges --------------------------------------------------------------

  Future<Set<String>> unlockedBadgeIds() async {
    final rows = await select(badges).get();
    return rows.map((b) => b.badgeId).toSet();
  }

  Future<void> unlockBadge(String badgeId) =>
      into(badges).insert(
        BadgesCompanion.insert(badgeId: badgeId),
        mode: InsertMode.insertOrIgnore,
      );
}
