import '../../../core/utils/email_utils.dart';
import '../models.dart';
import '../phishing_rule.dart';

/// Trust-context signals:
///  - first contact from an unknown sender (weak signal on its own,
///    but it amplifies other findings),
///  - Reply-To pointing to a different domain than From — the classic
///    BEC / invoice-fraud setup.
class UnknownSenderRule implements PhishingRule {
  const UnknownSenderRule();

  @override
  String get id => 'sender';

  @override
  List<PhishingFinding> evaluate(PhishingInput input) {
    final findings = <PhishingFinding>[];
    final from = input.fromAddress.toLowerCase();

    if (input.knownSenderAddresses.isNotEmpty &&
        !input.knownSenderAddresses.contains(from)) {
      findings.add(
        PhishingFinding(
          ruleId: id,
          severity: FindingSeverity.info,
          message: 'Premier message de cet expéditeur.',
        ),
      );
    }

    final replyTo = input.replyToAddress;
    if (replyTo != null && replyTo.isNotEmpty) {
      final fromDomain = EmailUtils.domainOf(from);
      final replyDomain = EmailUtils.domainOf(replyTo);
      if (fromDomain != null &&
          replyDomain != null &&
          EmailUtils.registrableDomain(fromDomain) !=
              EmailUtils.registrableDomain(replyDomain)) {
        findings.add(
          PhishingFinding(
            ruleId: id,
            severity: FindingSeverity.medium,
            message:
                'L\'adresse de réponse ($replyTo) diffère de l\'expéditeur ($from).',
          ),
        );
      }
    }

    return findings;
  }
}
