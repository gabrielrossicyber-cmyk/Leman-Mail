/// Gamification badge definition + unlock state.
class GamificationBadge {
  const GamificationBadge({
    required this.id,
    required this.emoji,
    required this.title,
    required this.description,
    this.unlockedAt,
  });

  final String id;
  final String emoji;
  final String title;
  final String description;
  final DateTime? unlockedAt;

  bool get isUnlocked => unlockedAt != null;

  GamificationBadge unlock(DateTime at) => GamificationBadge(
        id: id,
        emoji: emoji,
        title: title,
        description: description,
        unlockedAt: at,
      );
}
