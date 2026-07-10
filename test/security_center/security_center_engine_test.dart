import 'package:flutter_test/flutter_test.dart';
import 'package:leman_mail/domain/entities/account.dart';
import 'package:leman_mail/features/health/inbox_health_calculator.dart';
import 'package:leman_mail/features/security_center/security_center_engine.dart';

Account account({
  String uuid = 'a1',
  AuthMethod auth = AuthMethod.oauth2,
  bool mfa = true,
  bool imapTls = true,
  String? imapHost,
}) =>
    Account(
      id: 1,
      uuid: uuid,
      email: '$uuid@example.ch',
      displayName: uuid,
      provider: auth == AuthMethod.oauth2
          ? MailProvider.gmail
          : MailProvider.imap,
      authMethod: auth,
      mfaEnabled: mfa,
      imapTls: imapTls,
      imapHost: imapHost,
    );

InboxStats stats({
  int highRisk = 0,
  int mediumRisk = 0,
  int tracked = 0,
  int total = 100,
}) =>
    InboxStats(
      totalEmails: total,
      unreadCount: 0,
      newsletterCount: 0,
      activeNewsletterSenders: 0,
      ignoredNewsletterSenders: 0,
      oldUnreadCount: 0,
      spfPassCount: total,
      dkimPassCount: total,
      dmarcPassCount: total,
      authEvaluatedCount: total,
      highRiskCount: highRisk,
      mediumRiskCount: mediumRisk,
      suspiciousDomainsBlocked: 0,
      trackedEmailCount: tracked,
      trackerTotal: tracked,
      answeredNeededCount: 0,
      unansweredCount: 0,
    );

void main() {
  const engine = SecurityCenterEngine();

  group('SecurityCenterEngine', () {
    test('posture parfaite → 100 partout, aucune recommandation', () {
      final posture = engine.evaluate(
        accounts: [account()],
        stats: stats(),
        activeNewsletterSenders: 2,
      );
      expect(posture.globalScore, 100);
      expect(posture.phishingScore, 100);
      expect(posture.privacyScore, 100);
      expect(posture.accountScores['a1'], 100);
      expect(posture.recommendations, isEmpty);
    });

    test('compte sans MFA → -30 et recommandation +5 « Activer MFA »', () {
      final posture = engine.evaluate(
        accounts: [account(mfa: false)],
        stats: stats(),
        activeNewsletterSenders: 0,
      );
      expect(posture.accountScores['a1'], 70);
      final mfaRec = posture.recommendations
          .firstWhere((r) => r.code.startsWith('enable_mfa'));
      expect(mfaRec.points, 5);
    });

    test('compte IMAP mot de passe sans TLS → cumul des pénalités', () {
      final posture = engine.evaluate(
        accounts: [
          account(
            auth: AuthMethod.password,
            mfa: false,
            imapTls: false,
            imapHost: 'mail.example.ch',
          ),
        ],
        stats: stats(),
        activeNewsletterSenders: 0,
      );
      expect(posture.accountScores['a1'], 100 - 20 - 30 - 25);
      expect(
        posture.recommendations.map((r) => r.points).toList(),
        containsAll([4, 5, 8]),
      );
    });

    test('menaces actives → score phishing réduit + reco +8 bloquer', () {
      final posture = engine.evaluate(
        accounts: [account()],
        stats: stats(highRisk: 3, mediumRisk: 10),
        activeNewsletterSenders: 0,
      );
      expect(posture.phishingScore, 100 - 30 - 20);
      expect(
        posture.recommendations
            .any((r) => r.code == 'block_suspicious_domains' && r.points == 8),
        isTrue,
      );
    });

    test('trop de newsletters → recommandation d\'hygiène +3', () {
      final posture = engine.evaluate(
        accounts: [account()],
        stats: stats(),
        activeNewsletterSenders: 15,
      );
      expect(
        posture.recommendations
            .any((r) => r.code == 'clean_newsletters' && r.points == 3),
        isTrue,
      );
    });

    test('recommandations triées par points décroissants', () {
      final posture = engine.evaluate(
        accounts: [
          account(
            auth: AuthMethod.password,
            mfa: false,
            imapTls: false,
            imapHost: 'mail.example.ch',
          ),
        ],
        stats: stats(highRisk: 1, tracked: 30),
        activeNewsletterSenders: 20,
      );
      for (var i = 1; i < posture.recommendations.length; i++) {
        expect(
          posture.recommendations[i - 1].points,
          greaterThanOrEqualTo(posture.recommendations[i].points),
        );
      }
    });
  });
}
