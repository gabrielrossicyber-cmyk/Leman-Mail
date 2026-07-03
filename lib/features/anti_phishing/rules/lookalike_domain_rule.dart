import '../../../core/utils/email_utils.dart';
import '../models.dart';
import '../phishing_rule.dart';

/// Detects typosquatting / lookalike sender domains and display-name
/// spoofing against a protected-brand list plus the user's own contact
/// domains.
///
/// Examples caught:
///  - `security@paypa1.com`  (homoglyph of paypal.com)
///  - `it-support@rnicrosoft.com` (rn → m)
///  - From: `"PayPal" <billing@random-host.ru>` (brand in display name only)
class LookalikeDomainRule implements PhishingRule {
  const LookalikeDomainRule({this.extraProtectedDomains = const {}});

  /// Additional domains to protect (fed from the user's frequent contacts).
  final Set<String> extraProtectedDomains;

  @override
  String get id => 'lookalike';

  /// High-value brands most commonly impersonated. Extend freely — the
  /// engine cost is O(brands × 1 edit-distance) per email.
  static const protectedDomains = <String>{
    'paypal.com',
    'google.com',
    'gmail.com',
    'microsoft.com',
    'outlook.com',
    'office.com',
    'apple.com',
    'icloud.com',
    'amazon.com',
    'netflix.com',
    'facebook.com',
    'instagram.com',
    'linkedin.com',
    'whatsapp.com',
    'dhl.com',
    'ups.com',
    'fedex.com',
    'laposte.fr',
    'post.ch',
    'ubs.com',
    'credit-suisse.com',
    'postfinance.ch',
    'raiffeisen.ch',
    'swisscom.ch',
    'infomaniak.com',
    'digitec.ch',
    'galaxus.ch',
    'migros.ch',
    'booking.com',
    'zalando.ch',
    'twint.ch',
  };

  @override
  List<PhishingFinding> evaluate(PhishingInput input) {
    final findings = <PhishingFinding>[];
    final domain = EmailUtils.domainOf(input.fromAddress);
    if (domain == null) {
      return [
        PhishingFinding(
          ruleId: id,
          severity: FindingSeverity.medium,
          message: 'Adresse expéditeur malformée.',
        ),
      ];
    }

    final senderRegistrable = EmailUtils.registrableDomain(domain);
    final normalizedSender =
        EmailUtils.normalizeHomoglyphs(senderRegistrable);
    final allProtected = {...protectedDomains, ...extraProtectedDomains};

    for (final brand in allProtected) {
      if (senderRegistrable == brand) return findings; // legitimate sender

      final brandLabel = brand.split('.').first;
      final senderLabel = senderRegistrable.split('.').first;

      // 1. Homoglyph match: normalization makes them identical.
      if (normalizedSender != senderRegistrable &&
          EmailUtils.normalizeHomoglyphs(brand) == normalizedSender) {
        findings.add(
          PhishingFinding(
            ruleId: id,
            severity: FindingSeverity.critical,
            message:
                'Le domaine « $senderRegistrable » imite « $brand » par substitution de caractères.',
          ),
        );
        return findings;
      }

      // 2. Typosquatting: distance 1 on the registrable label.
      if (senderLabel.length >= 4 &&
          EmailUtils.editDistance(senderLabel, brandLabel) == 1) {
        findings.add(
          PhishingFinding(
            ruleId: id,
            severity: FindingSeverity.high,
            message:
                'Le domaine « $senderRegistrable » ressemble fortement à « $brand » (typosquatting probable).',
          ),
        );
        return findings;
      }

      // 3. Brand as subdomain of an unrelated domain: paypal.com.evil.io
      if (domain != brand &&
          senderRegistrable != brand &&
          domain.split('.').contains(brandLabel) &&
          senderLabel != brandLabel) {
        findings.add(
          PhishingFinding(
            ruleId: id,
            severity: FindingSeverity.high,
            message:
                'Le domaine « $domain » utilise « $brandLabel » comme sous-domaine trompeur.',
          ),
        );
        return findings;
      }
    }

    // 4. Display-name spoofing: brand name shown, unrelated domain used.
    final displayName = input.fromName.toLowerCase();
    for (final brand in allProtected) {
      final brandLabel = brand.split('.').first;
      if (brandLabel.length >= 4 &&
          displayName.contains(brandLabel) &&
          !senderRegistrable.contains(brandLabel)) {
        findings.add(
          PhishingFinding(
            ruleId: id,
            severity: FindingSeverity.high,
            message:
                'Le nom affiché mentionne « $brandLabel » mais l\'adresse réelle est « ${input.fromAddress} ».',
          ),
        );
        break;
      }
    }

    return findings;
  }
}
