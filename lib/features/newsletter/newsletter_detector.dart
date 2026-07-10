import 'models.dart';

/// Classifies newsletters / marketing emails and extracts unsubscribe
/// targets.
///
/// Primary signal: the `List-Unsubscribe` header (RFC 2369) and
/// `List-Unsubscribe-Post` (RFC 8058, one-click). Fallback heuristics:
/// `Precedence: bulk`, ESP `X-` headers, sender patterns (no-reply@…,
/// newsletter@…) and unsubscribe wording in the body.
class NewsletterDetector {
  const NewsletterDetector();

  static final _mailtoRegex = RegExp(r'<(mailto:[^>]+)>', caseSensitive: false);
  static final _httpRegex = RegExp(r'<(https?://[^>]+)>', caseSensitive: false);

  static final _bulkSenderPatterns = RegExp(
    r'^(newsletter|news|noreply|no-reply|nepasrepondre|marketing|promo|offers?|info|hello|contact|notifications?)@',
    caseSensitive: false,
  );

  static final _bodyUnsubscribeRegex = RegExp(
    r'''href=["']([^"']+)["'][^>]*>[^<]{0,60}(se\s+d[ée]sabonner|d[ée]sinscri|unsubscribe|opt[ -]?out|g[ée]rer (mes|vos) pr[ée]f[ée]rences)''',
    caseSensitive: false,
  );

  /// [headers] keys are expected lowercase (`list-unsubscribe`, ...).
  NewsletterDetection detect({
    required Map<String, String> headers,
    required String fromAddress,
    String subject = '',
    String? bodyHtml,
  }) {
    final signals = <String>[];
    String? unsubscribeUrl;
    String? unsubscribeMailto;
    var oneClick = false;

    final listUnsubscribe = headers['list-unsubscribe'];
    if (listUnsubscribe != null && listUnsubscribe.trim().isNotEmpty) {
      signals.add('list-unsubscribe-header');
      final mailto = _mailtoRegex.firstMatch(listUnsubscribe);
      final http = _httpRegex.firstMatch(listUnsubscribe);
      unsubscribeMailto = mailto?.group(1);
      unsubscribeUrl = http?.group(1);
      oneClick = (headers['list-unsubscribe-post'] ?? '')
          .toLowerCase()
          .contains('one-click');
      if (oneClick) signals.add('rfc8058-one-click');
    }

    if (headers.containsKey('list-id')) signals.add('list-id-header');
    if ((headers['precedence'] ?? '').toLowerCase() case 'bulk' || 'list') {
      signals.add('precedence-bulk');
    }
    for (final espHeader in const [
      'x-mailchimp-campaign',
      'x-mailgun-tag',
      'x-ses-configuration-set',
      'x-campaign',
      'x-mailer-campaign',
      'x-sib-id',
    ]) {
      if (headers.containsKey(espHeader)) {
        signals.add('esp-header:$espHeader');
        break;
      }
    }

    if (_bulkSenderPatterns.hasMatch(fromAddress.trim())) {
      signals.add('bulk-sender-address');
    }

    if (bodyHtml != null && unsubscribeUrl == null) {
      final m = _bodyUnsubscribeRegex.firstMatch(bodyHtml);
      if (m != null) {
        signals.add('body-unsubscribe-link');
        unsubscribeUrl = m.group(1);
      }
    }

    // Decision: a List-Unsubscribe / List-Id header is conclusive on its
    // own; otherwise require two independent weak signals to avoid
    // misclassifying personal mail from a no-reply-like address.
    final conclusive = signals.contains('list-unsubscribe-header') ||
        signals.contains('list-id-header');
    final isNewsletter = conclusive || signals.length >= 2;

    if (!isNewsletter) return NewsletterDetection.none;

    return NewsletterDetection(
      isNewsletter: true,
      unsubscribeUrl: unsubscribeUrl,
      unsubscribeMailto: unsubscribeMailto,
      supportsOneClick: oneClick,
      signals: signals,
    );
  }
}
