import 'package:flutter_test/flutter_test.dart';
import 'package:leman_mail/core/utils/email_utils.dart';

void main() {
  group('EmailUtils', () {
    test('domainOf extrait le domaine en minuscules', () {
      expect(EmailUtils.domainOf('User@Example.COM'), 'example.com');
      expect(EmailUtils.domainOf('invalide'), isNull);
      expect(EmailUtils.domainOf(null), isNull);
    });

    test('registrableDomain gère les sous-domaines et ccTLD composés', () {
      expect(EmailUtils.registrableDomain('mail.paypal.com'), 'paypal.com');
      expect(EmailUtils.registrableDomain('a.b.example.co.uk'), 'example.co.uk');
      expect(EmailUtils.registrableDomain('post.ch'), 'post.ch');
    });

    test('editDistance : distance de Damerau-Levenshtein', () {
      expect(EmailUtils.editDistance('paypal', 'paypal'), 0);
      expect(EmailUtils.editDistance('paypal', 'paypa1'), 1);
      expect(EmailUtils.editDistance('google', 'goolge'), 1); // transposition
      expect(EmailUtils.editDistance('abc', ''), 3);
    });

    test('normalizeHomoglyphs remplace chiffres et cyrilliques', () {
      expect(EmailUtils.normalizeHomoglyphs('payp4l'), 'paypal');
      expect(EmailUtils.normalizeHomoglyphs('g00gle'), 'google');
      expect(EmailUtils.normalizeHomoglyphs('аpple'), 'apple'); // а cyrillique
    });

    test('extractUrls trouve les URLs et nettoie la ponctuation finale', () {
      final urls = EmailUtils.extractUrls(
        'Voir https://example.com/page, puis http://test.io/x.',
      );
      expect(urls.map((u) => u.toString()), [
        'https://example.com/page',
        'http://test.io/x',
      ]);
    });

    test('extractAddresses trouve les emails dans du texte', () {
      expect(
        EmailUtils.extractAddresses('Contact: a@b.ch et c.d+e@f-g.com'),
        ['a@b.ch', 'c.d+e@f-g.com'],
      );
    });
  });
}
