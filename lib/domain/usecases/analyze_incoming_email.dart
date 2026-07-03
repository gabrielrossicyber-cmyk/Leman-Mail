import '../../data/services/mail/mail_sync_service.dart';
import '../../features/anti_phishing/models.dart';
import '../../features/anti_phishing/phishing_engine.dart';
import '../../features/newsletter/models.dart';
import '../../features/newsletter/newsletter_detector.dart';
import '../../features/privacy/models.dart';
import '../../features/privacy/tracking_detector.dart';
import '../entities/email_message.dart';

/// Combined result of the full analysis pipeline for one message.
class EmailAnalysisOutcome {
  const EmailAnalysisOutcome({
    required this.spf,
    required this.dkim,
    required this.dmarc,
    required this.phishing,
    required this.privacy,
    required this.newsletter,
  });

  final AuthResult spf;
  final AuthResult dkim;
  final AuthResult dmarc;
  final PhishingVerdict phishing;
  final PrivacyReport privacy;
  final NewsletterDetection newsletter;
}

/// Use case: run every analysis engine over a freshly fetched message.
///
/// Pure orchestration — persistence is the repository's job, which lets
/// this class be exhaustively unit-tested and later reused server-side.
class AnalyzeIncomingEmail {
  const AnalyzeIncomingEmail({
    required this.phishingEngine,
    this.trackingDetector = const TrackingDetector(),
    this.newsletterDetector = const NewsletterDetector(),
  });

  final PhishingEngine phishingEngine;
  final TrackingDetector trackingDetector;
  final NewsletterDetector newsletterDetector;

  EmailAnalysisOutcome call(
    RawEmail email, {
    Set<String> knownSenderAddresses = const {},
    Set<String> userContactDomains = const {},
  }) {
    final auth = parseAuthenticationResults(
      email.headers['authentication-results'],
    );

    final phishing = phishingEngine.analyze(
      PhishingInput(
        fromAddress: email.fromAddress,
        fromName: email.fromName,
        subject: email.subject,
        replyToAddress: email.replyToAddress,
        bodyText: email.bodyPlain ?? '',
        bodyHtml: email.bodyHtml,
        spf: auth.spf,
        dkim: auth.dkim,
        dmarc: auth.dmarc,
        attachments: email.attachments,
        knownSenderAddresses: knownSenderAddresses,
        userContactDomains: userContactDomains,
      ),
    );

    final privacy = trackingDetector.scan(email.bodyHtml);

    final newsletter = newsletterDetector.detect(
      headers: email.headers,
      fromAddress: email.fromAddress,
      subject: email.subject,
      bodyHtml: email.bodyHtml,
    );

    return EmailAnalysisOutcome(
      spf: auth.spf,
      dkim: auth.dkim,
      dmarc: auth.dmarc,
      phishing: phishing,
      privacy: privacy,
      newsletter: newsletter,
    );
  }
}
