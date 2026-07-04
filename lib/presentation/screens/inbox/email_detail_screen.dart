import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/email_utils.dart';
import '../../../domain/entities/email_message.dart';
import '../../providers/core_providers.dart';
import '../../providers/inbox_providers.dart';
import '../../widgets/risk_badge.dart';

/// Lecture d'un email : rendu HTML fidèle dans une WebView durcie
/// (JavaScript désactivé, liens ouverts dans le navigateur, contenu
/// distant bloqué par défaut), en-tête compact avec pastille de sécurité —
/// un tap ouvre la fiche d'analyse (score, SPF/DKIM/DMARC, signaux).
class EmailDetailScreen extends ConsumerWidget {
  const EmailDetailScreen({super.key, required this.emailId});

  final int emailId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(emailDetailProvider(emailId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Message'),
        actions: [
          if (detail.valueOrNull?.email case final email?) ...[
            IconButton(
              icon: Icon(
                email.isFlagged ? Icons.star : Icons.star_outline,
                color: email.isFlagged
                    ? Theme.of(context).colorScheme.secondary
                    : null,
              ),
              tooltip:
                  email.isFlagged ? 'Retirer des favoris' : 'Ajouter aux favoris',
              onPressed: () async {
                await ref
                    .read(emailRepositoryProvider)
                    .setFlagged([emailId], flagged: !email.isFlagged);
                ref.invalidate(emailDetailProvider(emailId));
              },
            ),
            IconButton(
              icon: const Icon(Icons.reply_outlined),
              tooltip: 'Répondre',
              onPressed: () => context.push(
                Uri(
                  path: '/compose',
                  queryParameters: {
                    'to': email.fromAddress,
                    'subject': email.subject.startsWith('Re:')
                        ? email.subject
                        : 'Re: ${email.subject}',
                  },
                ).toString(),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.forward_outlined),
              tooltip: 'Transférer',
              onPressed: () => context.push(
                Uri(
                  path: '/compose',
                  queryParameters: {
                    'subject': email.subject.startsWith('Fwd:')
                        ? email.subject
                        : 'Fwd: ${email.subject}',
                    'body': '\n\n---------- Message transféré ----------\n'
                        'De : ${email.fromName} <${email.fromAddress}>\n'
                        'Objet : ${email.subject}\n\n${email.snippet}',
                  },
                ).toString(),
              ),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Supprimer',
            onPressed: () async {
              await ref.read(emailRepositoryProvider).delete([emailId]);
              if (context.mounted) context.pop();
            },
          ),
        ],
      ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Erreur : $error')),
        data: (data) {
          final email = data.email;
          if (email == null) {
            return const Center(child: Text('Email introuvable.'));
          }
          if (!email.isRead) {
            Future.microtask(
              () => ref.read(emailRepositoryProvider).markRead([emailId]),
            );
          }
          return _EmailDetailView(email: email, body: data.body);
        },
      ),
    );
  }
}

class _EmailDetailView extends ConsumerWidget {
  const _EmailDetailView({required this.email, required this.body});

  final EmailMessage email;
  final String? body;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final remoteAllowed = ref.watch(remoteContentAllowedProvider(email.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- Compact header --------------------------------------------------
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                email.subject.isEmpty ? '(sans objet)' : email.subject,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(
                      (email.fromName.isNotEmpty
                              ? email.fromName
                              : email.fromAddress)
                          .substring(0, 1)
                          .toUpperCase(),
                      style: TextStyle(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          email.fromName.isNotEmpty
                              ? email.fromName
                              : email.fromAddress,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${email.fromAddress} · '
                          '${DateFormat('d MMM y, HH:mm', 'fr').format(email.date)}',
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _SecurityDot(email: email),
                ],
              ),
            ],
          ),
        ),
        // --- Warning banners --------------------------------------------------
        if (email.phishingLevel == RiskLevel.high)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _WarningBanner(
              color: AppTheme.riskHigh,
              icon: Icons.gpp_bad_outlined,
              text: 'Signaux forts de phishing détectés. N\'ouvrez aucun '
                  'lien ni pièce jointe.',
              action: TextButton(
                onPressed: () async {
                  final senderDomain = EmailUtils.domainOf(email.fromAddress);
                  await ref.read(emailRepositoryProvider).blockSender(
                        senderDomain != null
                            ? '*@$senderDomain'
                            : email.fromAddress,
                        reason: 'phishing',
                      );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Expéditeur bloqué.')),
                    );
                  }
                },
                child: const Text('Bloquer l\'expéditeur'),
              ),
            ),
          ),
        if ((email.hasTracking || email.externalResourceCount > 0) &&
            !remoteAllowed)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _WarningBanner(
              color: AppTheme.riskMedium,
              icon: Icons.visibility_off_outlined,
              text: email.hasTracking
                  ? 'Cet email tente de suivre votre activité — '
                      '${email.trackerCount} tracker(s) bloqué(s).'
                  : 'Images distantes bloquées pour protéger votre vie privée.',
              action: TextButton(
                onPressed: () => ref
                    .read(remoteContentAllowedProvider(email.id).notifier)
                    .state = true,
                child: const Text('Charger les images'),
              ),
            ),
          ),
        const SizedBox(height: 12),
        const Divider(height: 1),
        // --- Body -------------------------------------------------------------
        Expanded(
          child: body == null || body!.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(email.snippet),
                )
              : email.bodyIsHtml
                  ? _HtmlBody(
                      key: ValueKey('html-${email.id}-$remoteAllowed'),
                      html: body!,
                      allowRemoteContent: remoteAllowed,
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: SelectableText(
                        body!,
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Security dot + analysis sheet
// ---------------------------------------------------------------------------

class _SecurityDot extends StatelessWidget {
  const _SecurityDot({required this.email});

  final EmailMessage email;

  @override
  Widget build(BuildContext context) {
    final color = switch (email.phishingLevel) {
      RiskLevel.low => AppTheme.riskLow,
      RiskLevel.medium => AppTheme.riskMedium,
      RiskLevel.high => AppTheme.riskHigh,
    };
    return Tooltip(
      message: 'Analyse de sécurité',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _showSecuritySheet(context, email),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void _showSecuritySheet(BuildContext context, EmailMessage email) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        maxChildSize: 0.9,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(
              'Analyse de sécurité',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                RiskBadge(level: email.phishingLevel, score: email.phishingScore),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Authentification de l\'expéditeur',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _AuthChip(label: 'SPF', result: email.spf),
                _AuthChip(label: 'DKIM', result: email.dkim),
                _AuthChip(label: 'DMARC', result: email.dmarc),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Vie privée',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              email.trackerCount == 0
                  ? 'Aucun tracker détecté · score de confidentialité '
                      '${email.privacyScore}/100.'
                  : '${email.trackerCount} tracker(s) et '
                      '${email.externalResourceCount} ressource(s) externe(s) '
                      '· score de confidentialité ${email.privacyScore}/100.',
            ),
            if (email.findings.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Signaux détectés',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              for (final finding in email.findings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _severityIcon(finding.severity),
                        size: 18,
                        color: _severityColor(finding.severity),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(finding.message)),
                    ],
                  ),
                ),
            ] else ...[
              const SizedBox(height: 16),
              const Text('Aucun signal suspect — cet email semble sûr. ✅'),
            ],
          ],
        ),
      );
    },
  );
}

IconData _severityIcon(String severity) => switch (severity) {
      'critical' || 'high' => Icons.error_outline,
      'medium' => Icons.warning_amber_outlined,
      'low' => Icons.info_outline,
      _ => Icons.circle_outlined,
    };

Color _severityColor(String severity) => switch (severity) {
      'critical' || 'high' => AppTheme.riskHigh,
      'medium' || 'low' => AppTheme.riskMedium,
      _ => Colors.grey,
    };

class _AuthChip extends StatelessWidget {
  const _AuthChip({required this.label, required this.result});

  final String label;
  final AuthResult result;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (result) {
      AuthResult.pass => (AppTheme.riskLow, Icons.check_circle_outline),
      AuthResult.fail => (AppTheme.riskHigh, Icons.cancel_outlined),
      AuthResult.softfail => (AppTheme.riskMedium, Icons.error_outline),
      AuthResult.none ||
      AuthResult.unknown =>
        (Theme.of(context).colorScheme.outline, Icons.help_outline),
    };
    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text('$label ${result.name}'),
      labelStyle: TextStyle(fontSize: 12, color: color),
      visualDensity: VisualDensity.compact,
    );
  }
}

// ---------------------------------------------------------------------------
// Hardened HTML body
// ---------------------------------------------------------------------------

class _HtmlBody extends StatefulWidget {
  const _HtmlBody({
    super.key,
    required this.html,
    required this.allowRemoteContent,
  });

  final String html;
  final bool allowRemoteContent;

  @override
  State<_HtmlBody> createState() => _HtmlBodyState();
}

class _HtmlBodyState extends State<_HtmlBody> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      // Defense in depth: an email must never execute code.
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            // Taps on links open in the external browser, never inside
            // the mail renderer.
            if (uri != null &&
                (uri.scheme == 'http' || uri.scheme == 'https')) {
              launchUrl(uri, mode: LaunchMode.externalApplication);
              return NavigationDecision.prevent;
            }
            if (uri != null && uri.scheme == 'mailto') {
              launchUrl(uri);
              return NavigationDecision.prevent;
            }
            // Initial loadHtmlString navigation (about:blank / data:).
            return NavigationDecision.navigate;
          },
        ),
      );
    _load();
  }

  void _load() {
    final content = widget.allowRemoteContent
        ? widget.html
        : blockRemoteContent(widget.html);
    _controller.loadHtmlString(_wrap(content));
  }

  /// Viewport + readable defaults for emails designed desktop-first.
  ///
  /// Marketing emails are built on fixed-width tables (600px+); without a
  /// hard clamp they overflow a phone screen and force horizontal
  /// scrolling. The universal `max-width`/`min-width` overrides beat both
  /// inline styles and legacy `width="600"` attributes, and `overflow-x`
  /// removes any residual sideways scroll.
  static String _wrap(String html) => '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=3">
<style>
  html, body {
    margin: 0;
    padding: 0;
    overflow-x: hidden;
  }
  body {
    padding: 12px;
    font-family: -apple-system, Roboto, sans-serif;
    word-wrap: break-word;
    -webkit-text-size-adjust: 100%;
    box-sizing: border-box;
  }
  * {
    max-width: 100% !important;
    min-width: 0 !important;
    box-sizing: border-box;
  }
  table {
    width: auto !important;
    height: auto !important;
  }
  td, th {
    word-break: break-word;
  }
  img {
    max-width: 100% !important;
    height: auto !important;
  }
  pre, code {
    white-space: pre-wrap;
  }
</style>
</head>
<body>$html</body>
</html>''';

  /// Neutralizes every remote reference when content is blocked:
  /// img src/srcset, CSS url(...), background attributes and <link> tags.
  static String blockRemoteContent(String html) => html
      .replaceAllMapped(
        RegExp(
          r'''(\ssrc(?:set)?\s*=\s*["'])(https?:[^"']*)(["'])''',
          caseSensitive: false,
        ),
        (m) => '${m[1]}${m[3]}',
      )
      .replaceAllMapped(
        RegExp(
          r'''(\sbackground\s*=\s*["'])(https?:[^"']*)(["'])''',
          caseSensitive: false,
        ),
        (m) => '${m[1]}${m[3]}',
      )
      .replaceAll(
        RegExp(r'url\s*\(\s*["\x27]?https?:[^)]*\)', caseSensitive: false),
        'none',
      )
      .replaceAll(
        RegExp(r'<link[^>]*>', caseSensitive: false),
        '',
      );

  @override
  Widget build(BuildContext context) =>
      WebViewWidget(controller: _controller);
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({
    required this.color,
    required this.icon,
    required this.text,
    this.action,
  });

  final Color color;
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
          if (action != null) action!,
        ],
      ),
    );
  }
}
