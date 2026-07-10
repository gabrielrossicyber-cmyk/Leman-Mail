import '../models.dart';
import '../phishing_rule.dart';

/// Social-engineering language heuristics (FR + EN). Each hit is a weak
/// signal; several hits combined with an authentication failure or a
/// lookalike domain push the score into the red zone.
class UrgencyLanguageRule implements PhishingRule {
  const UrgencyLanguageRule();

  @override
  String get id => 'language';

  static final _patterns = <RegExp, String>{
    RegExp(
      r'(compte .{0,20}(suspendu|bloqué|désactivé)|account .{0,20}(suspended|locked|disabled))',
      caseSensitive: false,
    ): 'Menace de suspension de compte',
    RegExp(
      r'(v[ée]rifiez votre (compte|identit[ée])|verify your (account|identity))',
      caseSensitive: false,
    ): 'Demande de vérification d\'identité',
    RegExp(
      r'(mot de passe .{0,15}(expir|réinitialis)|password .{0,15}(expired?|reset))',
      caseSensitive: false,
    ): 'Prétexte de mot de passe expiré',
    RegExp(
      r'(urgent|imm[ée]diatement|immediately|action required|derni[èe]re? (chance|rappel)|final (notice|warning))',
      caseSensitive: false,
    ): 'Langage d\'urgence',
    RegExp(
      r'(dans les (24|48) heures|within (24|48) hours|sous \d+ ?(h|heures|jours))',
      caseSensitive: false,
    ): 'Échéance artificielle',
    RegExp(
      r'(vous avez gagn[ée]|you (have )?won|félicitations.{0,30}(prix|gagn)|congratulations.{0,30}prize)',
      caseSensitive: false,
    ): 'Promesse de gain',
    RegExp(
      r'(confirmez vos (coordonn[ée]es|informations bancaires)|confirm your (billing|payment) (details|information))',
      caseSensitive: false,
    ): 'Demande de coordonnées bancaires',
  };

  @override
  List<PhishingFinding> evaluate(PhishingInput input) {
    final haystack = '${input.subject}\n${input.bodyText}';
    final findings = <PhishingFinding>[];

    for (final entry in _patterns.entries) {
      if (entry.key.hasMatch(haystack)) {
        findings.add(
          PhishingFinding(
            ruleId: id,
            severity: FindingSeverity.low,
            message: '${entry.value} détecté(e) dans le message.',
          ),
        );
      }
    }

    return findings;
  }
}
