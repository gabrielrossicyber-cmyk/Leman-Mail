import 'package:html/parser.dart' as html_parser;

import 'models.dart';

/// Scans an HTML email body for tracking pixels, known tracking services
/// and external resources.
///
/// The renderer blocks remote content by default; this detector explains
/// *why* and feeds the per-email privacy score plus the global dashboards.
class TrackingDetector {
  const TrackingDetector();

  /// Domains of widespread email-tracking / marketing-analytics services.
  static const knownTrackerDomains = <String, String>{
    'list-manage.com': 'Mailchimp',
    'mailchimp.com': 'Mailchimp',
    'sendgrid.net': 'SendGrid',
    'sendgrid.com': 'SendGrid',
    'mailtrack.io': 'Mailtrack',
    'mixmax.com': 'Mixmax',
    'yesware.com': 'Yesware',
    'bananatag.com': 'Bananatag',
    'streak.com': 'Streak',
    'hubspot.com': 'HubSpot',
    'hs-analytics.net': 'HubSpot',
    'mandrillapp.com': 'Mandrill',
    'mailgun.org': 'Mailgun',
    'amazonses.com': 'Amazon SES',
    'klaviyo.com': 'Klaviyo',
    'braze.com': 'Braze',
    'salesforce.com': 'Salesforce Marketing',
    'exacttarget.com': 'Salesforce Marketing',
    'doubleclick.net': 'Google Ads',
    'google-analytics.com': 'Google Analytics',
    'sendinblue.com': 'Brevo',
    'brevo.com': 'Brevo',
    'customer.io': 'Customer.io',
    'mailjet.com': 'Mailjet',
  };

  PrivacyReport scan(String? bodyHtml) {
    if (bodyHtml == null || bodyHtml.isEmpty) {
      return const PrivacyReport(findings: [], privacyScore: 100);
    }

    final findings = <TrackerFinding>[];
    final document = html_parser.parse(bodyHtml);

    for (final img in document.querySelectorAll('img[src]')) {
      final src = img.attributes['src'] ?? '';
      final uri = Uri.tryParse(src);
      if (uri == null || !uri.scheme.startsWith('http')) continue;

      final provider = _providerFor(uri.host);
      final width = _dimension(img.attributes['width'], img.attributes['style'], 'width');
      final height = _dimension(img.attributes['height'], img.attributes['style'], 'height');
      final isHidden = _isHiddenByStyle(img.attributes['style']);
      final isPixel =
          (width != null && width <= 2 && height != null && height <= 2) ||
              isHidden;

      if (isPixel) {
        findings.add(
          TrackerFinding(type: TrackerType.pixel, url: src, provider: provider),
        );
      } else if (provider != null) {
        findings.add(
          TrackerFinding(
            type: TrackerType.knownTracker,
            url: src,
            provider: provider,
          ),
        );
      } else {
        findings.add(TrackerFinding(type: TrackerType.externalImage, url: src));
      }
    }

    // Other remote resources (stylesheets, backgrounds, media).
    for (final el in document.querySelectorAll('[background], link[href], source[src]')) {
      final url = el.attributes['background'] ??
          el.attributes['href'] ??
          el.attributes['src'] ??
          '';
      final uri = Uri.tryParse(url);
      if (uri == null || !uri.scheme.startsWith('http')) continue;
      final provider = _providerFor(uri.host);
      findings.add(
        TrackerFinding(
          type: provider != null
              ? TrackerType.knownTracker
              : TrackerType.externalResource,
          url: url,
          provider: provider,
        ),
      );
    }

    return PrivacyReport(
      findings: findings,
      privacyScore: _score(findings),
    );
  }

  static String? _providerFor(String host) {
    final h = host.toLowerCase();
    for (final entry in knownTrackerDomains.entries) {
      if (h == entry.key || h.endsWith('.${entry.key}')) return entry.value;
    }
    return null;
  }

  static int? _dimension(String? attr, String? style, String cssProp) {
    final fromAttr = int.tryParse((attr ?? '').replaceAll('px', '').trim());
    if (fromAttr != null) return fromAttr;
    if (style == null) return null;
    final m = RegExp('$cssProp\\s*:\\s*(\\d+)px').firstMatch(style);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  static bool _isHiddenByStyle(String? style) {
    if (style == null) return false;
    final s = style.replaceAll(' ', '').toLowerCase();
    return s.contains('display:none') ||
        s.contains('visibility:hidden') ||
        s.contains('opacity:0');
  }

  /// Pixels and identified trackers cost far more than mere external images.
  static int _score(List<TrackerFinding> findings) {
    var penalty = 0;
    for (final f in findings) {
      penalty += switch (f.type) {
        TrackerType.pixel => 30,
        TrackerType.knownTracker => 20,
        TrackerType.externalImage => 5,
        TrackerType.externalResource => 5,
      };
    }
    return (100 - penalty).clamp(0, 100);
  }
}
