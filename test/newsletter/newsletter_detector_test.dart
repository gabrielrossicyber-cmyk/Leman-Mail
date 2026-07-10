import 'package:flutter_test/flutter_test.dart';
import 'package:leman_mail/features/newsletter/newsletter_detector.dart';

void main() {
  const detector = NewsletterDetector();

  group('NewsletterDetector', () {
    test('List-Unsubscribe avec URL et mailto → newsletter avec cibles', () {
      final result = detector.detect(
        headers: {
          'list-unsubscribe':
              '<mailto:unsub@news.amazon.com>, <https://amazon.com/unsub?id=42>',
        },
        fromAddress: 'offres@news.amazon.com',
      );
      expect(result.isNewsletter, isTrue);
      expect(result.unsubscribeMailto, 'mailto:unsub@news.amazon.com');
      expect(result.unsubscribeUrl, 'https://amazon.com/unsub?id=42');
      expect(result.supportsOneClick, isFalse);
    });

    test('RFC 8058 one-click détecté', () {
      final result = detector.detect(
        headers: {
          'list-unsubscribe': '<https://digitec.ch/unsub/abc>',
          'list-unsubscribe-post': 'List-Unsubscribe=One-Click',
        },
        fromAddress: 'newsletter@digitec.ch',
      );
      expect(result.isNewsletter, isTrue);
      expect(result.supportsOneClick, isTrue);
      expect(result.canUnsubscribe, isTrue);
    });

    test('email personnel → pas une newsletter', () {
      final result = detector.detect(
        headers: {'message-id': '<abc@mail.gmail.com>'},
        fromAddress: 'marie.dupont@gmail.com',
        bodyHtml: '<p>Salut, on se voit demain ?</p>',
      );
      expect(result.isNewsletter, isFalse);
      expect(result.canUnsubscribe, isFalse);
    });

    test('un seul signal faible ne suffit pas (no-reply seul)', () {
      final result = detector.detect(
        headers: const {},
        fromAddress: 'noreply@banque.ch',
        bodyHtml: '<p>Votre relevé est disponible.</p>',
      );
      expect(result.isNewsletter, isFalse);
    });

    test('deux signaux faibles suffisent (no-reply + lien désinscription)', () {
      final result = detector.detect(
        headers: const {},
        fromAddress: 'marketing@zalando.ch',
        bodyHtml:
            '<a href="https://zalando.ch/unsubscribe?u=1">Se désabonner</a>',
      );
      expect(result.isNewsletter, isTrue);
      expect(result.unsubscribeUrl, 'https://zalando.ch/unsubscribe?u=1');
    });

    test('Precedence: bulk + List-Id → newsletter', () {
      final result = detector.detect(
        headers: {
          'precedence': 'bulk',
          'list-id': '<news.linkedin.com>',
        },
        fromAddress: 'updates@linkedin.com',
      );
      expect(result.isNewsletter, isTrue);
      expect(result.signals, contains('list-id-header'));
    });
  });
}
