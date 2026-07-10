enum TrackerType { pixel, knownTracker, externalImage, externalResource }

class TrackerFinding {
  const TrackerFinding({
    required this.type,
    required this.url,
    this.provider,
  });

  final TrackerType type;
  final String url;

  /// Human-readable tracking provider when identified ("Mailchimp", ...).
  final String? provider;
}

/// Privacy scan result for one email.
class PrivacyReport {
  const PrivacyReport({
    required this.findings,
    required this.privacyScore,
  });

  final List<TrackerFinding> findings;

  /// 100 = no tracking at all, 0 = heavily tracked.
  final int privacyScore;

  int get trackerCount => findings
      .where(
        (f) => f.type == TrackerType.pixel || f.type == TrackerType.knownTracker,
      )
      .length;

  int get externalResourceCount => findings
      .where(
        (f) =>
            f.type == TrackerType.externalImage ||
            f.type == TrackerType.externalResource,
      )
      .length;

  bool get isTracking => trackerCount > 0;

  /// UI banner: « Cet email tente de suivre votre activité. »
  bool get shouldWarnUser => isTracking;
}
