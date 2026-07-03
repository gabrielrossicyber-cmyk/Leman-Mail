import 'package:flutter_test/flutter_test.dart';
import 'package:leman_mail/domain/entities/email_message.dart';
import 'package:leman_mail/features/anti_phishing/models.dart';
import 'package:leman_mail/features/anti_phishing/phishing_engine.dart';
import 'package:leman_mail/features/anti_phishing/phishing_rule.dart';

void main() {
  final engine = PhishingEngine();

  PhishingInput legitimate({String from = 'newsletter@digitec.ch'}) =>
      PhishingInput(
        fromAddress: from,
        fromName: 'Digitec',
        subject: 'Votre commande a été expédiée',
        bodyText: 'Bonjour, votre commande 4521 est en route.',
        spf: AuthResult.pass,
        dkim: AuthResult.pass,
        dmarc: AuthResult.pass,
      );

  group('PhishingEngine', () {
    test('email légitime authentifié → risque faible', () {
      final verdict = engine.analyze(legitimate());
      expect(verdict.level, RiskLevel.low);
      expect(verdict.score, lessThan(PhishingEngine.mediumThreshold));
    });

    test('échec DMARC → signal critique', () {
      final verdict = engine.analyze(
        PhishingInput(
          fromAddress: 'security@paypal.com',
          fromName: 'PayPal',
          subject: 'Notification',
          spf: AuthResult.fail,
          dkim: AuthResult.fail,
          dmarc: AuthResult.fail,
        ),
      );
      expect(verdict.level, RiskLevel.high);
      expect(
        verdict.findings.any(
          (f) => f.ruleId == 'auth' && f.severity == FindingSeverity.critical,
        ),
        isTrue,
      );
    });

    test('typosquatting paypa1.com détecté par homoglyphes', () {
      final verdict = engine.analyze(
        PhishingInput(
          fromAddress: 'service@paypa1.com',
          fromName: 'PayPal Service',
          subject: 'Vérifiez votre compte',
          bodyText: 'Votre compte est suspendu, vérifiez votre identité.',
          spf: AuthResult.none,
          dkim: AuthResult.none,
          dmarc: AuthResult.none,
        ),
      );
      expect(verdict.level, RiskLevel.high);
      expect(verdict.findings.any((f) => f.ruleId == 'lookalike'), isTrue);
    });

    test('usurpation du nom affiché (PayPal depuis un domaine tiers)', () {
      final verdict = engine.analyze(
        PhishingInput(
          fromAddress: 'billing@random-mail.ru',
          fromName: 'PayPal Billing',
          subject: 'Invoice',
        ),
      );
      expect(
        verdict.findings.any(
          (f) => f.ruleId == 'lookalike' && f.severity == FindingSeverity.high,
        ),
        isTrue,
      );
    });

    test('pièce jointe exécutable → critique', () {
      final verdict = engine.analyze(
        PhishingInput(
          fromAddress: 'contact@entreprise.fr',
          fromName: 'Comptabilité',
          subject: 'Facture',
          attachments: const [
            EmailAttachmentInfo(
              fileName: 'facture.pdf.exe',
              mimeType: 'application/octet-stream',
              sizeBytes: 120000,
            ),
          ],
        ),
      );
      expect(verdict.level, RiskLevel.high);
      expect(verdict.findings.any((f) => f.ruleId == 'attachment'), isTrue);
    });

    test('URL raccourcie + lien IP → findings url', () {
      final verdict = engine.analyze(
        PhishingInput(
          fromAddress: 'info@inconnu.io',
          fromName: 'Info',
          subject: 'Document partagé',
          bodyText:
              'Consultez le document : https://bit.ly/3xYz et '
              'http://192.168.4.12/login',
        ),
      );
      final urlFindings =
          verdict.findings.where((f) => f.ruleId == 'url').toList();
      expect(urlFindings.length, greaterThanOrEqualTo(2));
    });

    test('lien trompeur texte ≠ destination → critique', () {
      final verdict = engine.analyze(
        PhishingInput(
          fromAddress: 'no-reply@service.com',
          fromName: 'Service',
          subject: 'Connexion',
          bodyHtml:
              '<a href="https://evil.example.io/login">https://www.ubs.com</a>',
        ),
      );
      expect(
        verdict.findings.any(
          (f) => f.ruleId == 'url' && f.severity == FindingSeverity.critical,
        ),
        isTrue,
      );
    });

    test('Reply-To vers un autre domaine → signal BEC', () {
      final verdict = engine.analyze(
        PhishingInput(
          fromAddress: 'ceo@entreprise.ch',
          fromName: 'CEO',
          subject: 'Virement urgent',
          replyToAddress: 'ceo-prive@gmail-secure.ru',
        ),
      );
      expect(verdict.findings.any((f) => f.ruleId == 'sender'), isTrue);
    });

    test('langage d\'urgence FR détecté', () {
      final verdict = engine.analyze(
        PhishingInput(
          fromAddress: 'support@service.net',
          fromName: 'Support',
          subject: 'URGENT : votre compte sera suspendu',
          bodyText:
              'Vérifiez votre identité immédiatement, dernière chance '
              'dans les 24 heures.',
        ),
      );
      expect(
        verdict.findings.where((f) => f.ruleId == 'language').length,
        greaterThanOrEqualTo(2),
      );
    });

    test('le score est borné à 100 et les findings triés par sévérité', () {
      final verdict = engine.analyze(
        PhishingInput(
          fromAddress: 'security@paypa1.com',
          fromName: 'PayPal',
          subject: 'URGENT verify your account immediately',
          bodyText: 'Click https://bit.ly/x within 24 hours, account locked.',
          spf: AuthResult.fail,
          dkim: AuthResult.fail,
          dmarc: AuthResult.fail,
          attachments: const [
            EmailAttachmentInfo(
              fileName: 'update.exe',
              mimeType: 'application/x-msdownload',
              sizeBytes: 1,
            ),
          ],
        ),
      );
      expect(verdict.score, 100);
      expect(verdict.level, RiskLevel.high);
      for (var i = 1; i < verdict.findings.length; i++) {
        expect(
          verdict.findings[i - 1].severity.index,
          greaterThanOrEqualTo(verdict.findings[i].severity.index),
        );
      }
    });

    test('moteur extensible : une règle custom est bien exécutée', () {
      final custom = PhishingEngine(rules: [_AlwaysCriticalRule()]);
      final verdict = custom.analyze(legitimate());
      expect(verdict.level, RiskLevel.high);
      expect(verdict.findings.single.ruleId, 'custom');
    });
  });
}

class _AlwaysCriticalRule implements PhishingRule {
  @override
  String get id => 'custom';

  @override
  List<PhishingFinding> evaluate(PhishingInput input) => [
        PhishingFinding(
          ruleId: id,
          severity: FindingSeverity.critical,
          message: 'test',
        ),
      ];
}
