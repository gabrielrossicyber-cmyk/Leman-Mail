import 'package:flutter_test/flutter_test.dart';
import 'package:leman_mail/features/privacy/models.dart';
import 'package:leman_mail/features/privacy/tracking_detector.dart';

void main() {
  const detector = TrackingDetector();

  group('TrackingDetector', () {
    test('email sans HTML → score 100, aucun tracker', () {
      final report = detector.scan(null);
      expect(report.privacyScore, 100);
      expect(report.isTracking, isFalse);
      expect(report.shouldWarnUser, isFalse);
    });

    test('pixel invisible 1x1 détecté', () {
      final report = detector.scan(
        '<html><body>Hello'
        '<img src="https://track.example.com/open.gif" width="1" height="1">'
        '</body></html>',
      );
      expect(report.trackerCount, 1);
      expect(report.findings.single.type, TrackerType.pixel);
      expect(report.privacyScore, lessThan(100));
      expect(report.shouldWarnUser, isTrue);
    });

    test('pixel caché par style CSS détecté', () {
      final report = detector.scan(
        '<img src="https://cdn.example.io/p.png" '
        'style="display:none; width:50px">',
      );
      expect(report.findings.single.type, TrackerType.pixel);
    });

    test('tracker connu identifié avec son fournisseur', () {
      final report = detector.scan(
        '<img src="https://open.list-manage.com/track/abc.png" '
        'width="200" height="60">',
      );
      expect(report.findings.single.type, TrackerType.knownTracker);
      expect(report.findings.single.provider, 'Mailchimp');
    });

    test('sous-domaine d\'un tracker connu identifié', () {
      final report = detector.scan(
        '<img src="https://email.klaviyo.com/img/x.png" width="300" height="80">',
      );
      expect(report.findings.single.provider, 'Klaviyo');
    });

    test('image externe simple = pénalité légère', () {
      final report = detector.scan(
        '<img src="https://images.shop.ch/banner.jpg" width="600" height="200">',
      );
      expect(report.findings.single.type, TrackerType.externalImage);
      expect(report.trackerCount, 0);
      expect(report.privacyScore, 95);
    });

    test('email très tracké → score plancher 0', () {
      final pixels = List.generate(
        6,
        (i) => '<img src="https://t$i.mailtrack.io/p.gif" width="1" height="1">',
      ).join();
      final report = detector.scan('<html>$pixels</html>');
      expect(report.privacyScore, 0);
      expect(report.trackerCount, 6);
    });

    test('les images embarquées (cid:/data:) ne sont pas comptées', () {
      final report = detector.scan(
        '<img src="cid:logo@mail"><img src="data:image/png;base64,AAA=">',
      );
      expect(report.findings, isEmpty);
      expect(report.privacyScore, 100);
    });
  });
}
