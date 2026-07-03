import 'package:html/parser.dart' as html_parser;

import '../../../core/utils/email_utils.dart';
import '../models.dart';
import '../phishing_rule.dart';

/// Inspects every link in the message body:
///  - URL shorteners (destination hidden)
///  - raw IP-address hosts
///  - punycode / IDN hosts (homoglyph vector)
///  - credentials embedded in the URL (`https://user@host`)
///  - anchor text showing one domain while the href points to another
///  - plain-HTTP links asking for action
class SuspiciousUrlRule implements PhishingRule {
  const SuspiciousUrlRule();

  @override
  String get id => 'url';

  static const shortenerHosts = <String>{
    'bit.ly',
    'tinyurl.com',
    'goo.gl',
    't.co',
    'ow.ly',
    'is.gd',
    'buff.ly',
    'rebrand.ly',
    'cutt.ly',
    'rb.gy',
    'shorturl.at',
    'tiny.cc',
  };

  static final _ipHost = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');

  @override
  List<PhishingFinding> evaluate(PhishingInput input) {
    final findings = <PhishingFinding>[];
    final reported = <String>{};

    void add(FindingSeverity severity, String message) {
      if (reported.add(message)) {
        findings.add(
          PhishingFinding(ruleId: id, severity: severity, message: message),
        );
      }
    }

    final urls = <Uri>[...EmailUtils.extractUrls(input.bodyText)];

    // Parse HTML for href/text mismatches and collect anchor URLs.
    if (input.bodyHtml != null && input.bodyHtml!.isNotEmpty) {
      final document = html_parser.parse(input.bodyHtml);
      for (final anchor in document.querySelectorAll('a[href]')) {
        final href = Uri.tryParse(anchor.attributes['href'] ?? '');
        if (href == null || !href.hasScheme || href.host.isEmpty) continue;
        urls.add(href);

        final text = anchor.text.trim();
        final textUrls = EmailUtils.extractUrls(text);
        if (textUrls.isNotEmpty) {
          final shownHost =
              EmailUtils.registrableDomain(textUrls.first.host);
          final realHost = EmailUtils.registrableDomain(href.host);
          if (shownHost != realHost) {
            add(
              FindingSeverity.critical,
              'Lien trompeur : le texte affiche « $shownHost » mais pointe vers « $realHost ».',
            );
          }
        }
      }
    }

    for (final url in urls) {
      final host = url.host.toLowerCase();
      if (shortenerHosts.contains(host)) {
        add(
          FindingSeverity.medium,
          'Lien raccourci ($host) : destination réelle masquée.',
        );
      }
      if (_ipHost.hasMatch(host)) {
        add(
          FindingSeverity.high,
          'Lien vers une adresse IP brute ($host) au lieu d\'un nom de domaine.',
        );
      }
      if (host.contains('xn--')) {
        add(
          FindingSeverity.high,
          'Lien vers un domaine internationalisé (punycode) pouvant imiter un site connu.',
        );
      }
      if (url.userInfo.isNotEmpty) {
        add(
          FindingSeverity.high,
          'Lien contenant des identifiants intégrés (technique de masquage d\'URL).',
        );
      }
      if (url.scheme == 'http') {
        add(
          FindingSeverity.low,
          'Lien non chiffré (http) : $host.',
        );
      }
      if (host.split('.').length >= 5) {
        add(
          FindingSeverity.low,
          'Lien avec un empilement inhabituel de sous-domaines ($host).',
        );
      }
    }

    return findings;
  }
}
