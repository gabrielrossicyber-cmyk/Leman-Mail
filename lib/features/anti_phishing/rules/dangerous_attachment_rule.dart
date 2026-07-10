import '../models.dart';
import '../phishing_rule.dart';

/// Flags executable, script and macro-enabled attachments, plus the
/// classic double-extension trick (`facture.pdf.exe`).
class DangerousAttachmentRule implements PhishingRule {
  const DangerousAttachmentRule();

  @override
  String get id => 'attachment';

  static const executableExtensions = <String>{
    'exe', 'msi', 'bat', 'cmd', 'com', 'scr', 'pif', 'hta', 'cpl',
    'js', 'jse', 'vbs', 'vbe', 'wsf', 'wsh', 'ps1', 'psm1',
    'jar', 'apk', 'app', 'dmg',
    'lnk', 'iso', 'img', 'vhd',
  };

  static const macroExtensions = <String>{'docm', 'xlsm', 'pptm', 'dotm', 'xlam'};

  /// Archives commonly used to smuggle executables past filters.
  static const archiveExtensions = <String>{'zip', 'rar', '7z', 'ace', 'arj'};

  @override
  List<PhishingFinding> evaluate(PhishingInput input) {
    final findings = <PhishingFinding>[];

    for (final attachment in input.attachments) {
      final name = attachment.fileName.toLowerCase().trim();
      final parts = name.split('.');
      if (parts.length < 2) continue;
      final ext = parts.last;

      if (executableExtensions.contains(ext)) {
        findings.add(
          PhishingFinding(
            ruleId: id,
            severity: FindingSeverity.critical,
            message:
                'Pièce jointe exécutable « ${attachment.fileName} » — ne pas ouvrir.',
          ),
        );
        continue;
      }

      // Double extension: document.pdf.exe already caught above; here we
      // catch a *document* extension hiding before a risky one, e.g. shown
      // as "invoice.pdf" but actually "invoice.pdf.zip".
      if (parts.length >= 3) {
        const documentExts = {'pdf', 'doc', 'docx', 'xls', 'xlsx', 'jpg', 'png', 'txt'};
        final maskedAs = parts[parts.length - 2];
        if (documentExts.contains(maskedAs)) {
          findings.add(
            PhishingFinding(
              ruleId: id,
              severity: FindingSeverity.high,
              message:
                  'Double extension suspecte : « ${attachment.fileName} » se fait passer pour un .$maskedAs.',
            ),
          );
          continue;
        }
      }

      if (macroExtensions.contains(ext)) {
        findings.add(
          PhishingFinding(
            ruleId: id,
            severity: FindingSeverity.high,
            message:
                'Document avec macros « ${attachment.fileName} » : vecteur classique de malware.',
          ),
        );
      } else if (archiveExtensions.contains(ext)) {
        findings.add(
          PhishingFinding(
            ruleId: id,
            severity: FindingSeverity.low,
            message:
                'Archive « ${attachment.fileName} » : vérifiez son contenu avant extraction.',
          ),
        );
      }
    }

    return findings;
  }
}
