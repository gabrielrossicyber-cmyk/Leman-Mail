import '../../../domain/entities/email_message.dart';
import '../models.dart';
import '../phishing_rule.dart';

/// Scores SPF / DKIM / DMARC results parsed from `Authentication-Results`.
///
/// A hard DMARC failure is the strongest single phishing signal we have:
/// the sending domain explicitly told receivers to distrust this message.
class AuthenticationRule implements PhishingRule {
  const AuthenticationRule();

  @override
  String get id => 'auth';

  @override
  List<PhishingFinding> evaluate(PhishingInput input) {
    final findings = <PhishingFinding>[];

    void add(FindingSeverity severity, String message) =>
        findings.add(PhishingFinding(ruleId: id, severity: severity, message: message));

    switch (input.dmarc) {
      case AuthResult.fail:
        add(
          FindingSeverity.critical,
          'Échec DMARC : le domaine expéditeur rejette ce message comme non authentique.',
        );
      case AuthResult.none:
        add(
          FindingSeverity.info,
          'Le domaine expéditeur ne publie pas de politique DMARC.',
        );
      case AuthResult.pass:
      case AuthResult.softfail:
      case AuthResult.unknown:
        break;
    }

    switch (input.spf) {
      case AuthResult.fail:
        add(
          FindingSeverity.high,
          'Échec SPF : le serveur d\'envoi n\'est pas autorisé pour ce domaine.',
        );
      case AuthResult.softfail:
        add(FindingSeverity.low, 'SPF softfail : serveur d\'envoi douteux.');
      case AuthResult.none:
        add(FindingSeverity.info, 'Aucun enregistrement SPF publié.');
      case AuthResult.pass:
      case AuthResult.unknown:
        break;
    }

    if (input.dkim == AuthResult.fail) {
      add(
        FindingSeverity.medium,
        'Échec DKIM : la signature cryptographique du message est invalide.',
      );
    }

    return findings;
  }
}
