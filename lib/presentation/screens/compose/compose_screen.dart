import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/services/mail/smtp_service.dart';
import '../../../domain/entities/account.dart';
import '../../../features/cleanup/smart_cleanup_analyzer.dart';
import '../../providers/account_providers.dart';
import '../../providers/core_providers.dart';

/// Rédaction d'un email : compte expéditeur, destinataires multiples,
/// Cc/Cci repliables, pièces jointes. Envoi via SMTP (comptes IMAP).
class ComposeScreen extends ConsumerStatefulWidget {
  const ComposeScreen({
    super.key,
    this.initialTo,
    this.initialSubject,
    this.initialBody,
  });

  final String? initialTo;
  final String? initialSubject;
  final String? initialBody;

  @override
  ConsumerState<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends ConsumerState<ComposeScreen> {
  static const _maxAttachmentBytes = 20 * 1024 * 1024; // 20 Mo au total

  final _formKey = GlobalKey<FormState>();
  late final _to = TextEditingController(text: widget.initialTo ?? '');
  final _cc = TextEditingController();
  final _bcc = TextEditingController();
  late final _subject =
      TextEditingController(text: widget.initialSubject ?? '');
  late final _body = TextEditingController(text: widget.initialBody ?? '');

  int? _accountId;
  bool _showCcBcc = false;
  bool _sending = false;
  final List<PlatformFile> _attachments = [];

  static final _addressRegex =
      RegExp(r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$');

  @override
  void dispose() {
    _to.dispose();
    _cc.dispose();
    _bcc.dispose();
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  /// « a@b.ch, c@d.ch ; e@f.ch » → liste normalisée.
  static List<String> _splitAddresses(String raw) => raw
      .split(RegExp(r'[,;]'))
      .map((a) => a.trim())
      .where((a) => a.isNotEmpty)
      .toList();

  static String? _validateAddresses(String? value, {bool required = false}) {
    final addresses = _splitAddresses(value ?? '');
    if (addresses.isEmpty) {
      return required ? 'Au moins un destinataire requis' : null;
    }
    for (final address in addresses) {
      if (!_addressRegex.hasMatch(address)) {
        return 'Adresse invalide : $address';
      }
    }
    return null;
  }

  int get _attachmentsTotalBytes =>
      _attachments.fold(0, (sum, f) => sum + f.size);

  Future<void> _pickAttachments() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true, // bytes en mémoire, requis pour l'envoi
    );
    if (result == null) return;

    setState(() {
      for (final file in result.files) {
        if (file.bytes == null) continue;
        if (_attachmentsTotalBytes + file.size > _maxAttachmentBytes) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Limite de 20 Mo de pièces jointes atteinte.'),
            ),
          );
          break;
        }
        _attachments.add(file);
      }
    });
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    final accounts = ref.read(accountsProvider).valueOrNull ?? [];
    if (accounts.isEmpty) return;
    final account = accounts.firstWhere(
      (a) => a.id == _accountId,
      orElse: () => accounts.first,
    );

    if (account.smtpHost == null || account.smtpHost!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'L\'envoi pour ${account.provider.name} passe par son API native '
            '(bientôt disponible) — utilisez un compte IMAP pour envoyer.',
          ),
        ),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      final credentials = await ref
          .read(accountRepositoryProvider)
          .credentialsOf(account.uuid);
      final secret = credentials?.password ?? credentials?.accessToken;
      if (secret == null) {
        throw Exception('Identifiants introuvables pour ${account.email}');
      }
      await const SmtpService().send(
        account: account,
        secret: secret,
        to: _splitAddresses(_to.text),
        cc: _splitAddresses(_cc.text),
        bcc: _splitAddresses(_bcc.text),
        subject: _subject.text,
        textBody: _body.text,
        attachments: [
          for (final file in _attachments)
            if (file.bytes != null)
              OutgoingAttachment(fileName: file.name, bytes: file.bytes!),
        ],
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Email envoyé. ✉️')));
        context.pop();
      }
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Échec de l\'envoi : $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accounts = ref.watch(accountsProvider).valueOrNull ?? [];
    final selectedAccount = accounts.isEmpty
        ? null
        : accounts.firstWhere(
            (a) => a.id == _accountId,
            orElse: () => accounts.first,
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nouveau message'),
        actions: [
          IconButton(
            icon: const Icon(Icons.attach_file),
            tooltip: 'Ajouter une pièce jointe',
            onPressed: _sending ? null : _pickAttachments,
          ),
          IconButton(
            icon: _sending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_outlined),
            tooltip: 'Envoyer',
            onPressed: _sending ? null : _send,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  // --- De ------------------------------------------------
                  if (selectedAccount != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          Text('De', style: theme.textTheme.bodySmall),
                          const SizedBox(width: 12),
                          Expanded(
                            child: accounts.length > 1
                                ? DropdownButton<int>(
                                    value: selectedAccount.id,
                                    isExpanded: true,
                                    underline: const SizedBox.shrink(),
                                    items: [
                                      for (final account in accounts)
                                        DropdownMenuItem(
                                          value: account.id,
                                          child: Row(
                                            children: [
                                              CircleAvatar(
                                                radius: 6,
                                                backgroundColor:
                                                    Color(account.colorValue),
                                              ),
                                              const SizedBox(width: 8),
                                              Flexible(
                                                child: Text(
                                                  account.email,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                    onChanged: (value) =>
                                        setState(() => _accountId = value),
                                  )
                                : Text(
                                    selectedAccount.email,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                          ),
                        ],
                      ),
                    ),
                  const Divider(height: 8),
                  // --- À, avec bouton Cc/Cci -----------------------------
                  TextFormField(
                    controller: _to,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: 'À',
                      hintText: 'adresse@exemple.ch, autre@exemple.ch',
                      border: InputBorder.none,
                      suffixIcon: TextButton(
                        onPressed: () =>
                            setState(() => _showCcBcc = !_showCcBcc),
                        child: Text(_showCcBcc ? 'Masquer' : 'Cc/Cci'),
                      ),
                    ),
                    validator: (v) => _validateAddresses(v, required: true),
                  ),
                  if (_showCcBcc) ...[
                    const Divider(height: 1),
                    TextFormField(
                      controller: _cc,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Cc',
                        border: InputBorder.none,
                      ),
                      validator: _validateAddresses,
                    ),
                    const Divider(height: 1),
                    TextFormField(
                      controller: _bcc,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Cci',
                        helperText:
                            'Destinataires invisibles les uns des autres',
                        border: InputBorder.none,
                      ),
                      validator: _validateAddresses,
                    ),
                  ],
                  const Divider(height: 1),
                  // --- Objet ---------------------------------------------
                  TextFormField(
                    controller: _subject,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Objet',
                      border: InputBorder.none,
                    ),
                  ),
                  const Divider(height: 1),
                  // --- Pièces jointes ------------------------------------
                  if (_attachments.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final (index, file)
                              in _attachments.indexed)
                            InputChip(
                              avatar: const Icon(Icons.description_outlined,
                                  size: 18),
                              label: Text(
                                '${file.name} · '
                                '${SmartCleanupAnalyzer.formatBytes(file.size)}',
                                overflow: TextOverflow.ellipsis,
                              ),
                              onDeleted: () => setState(
                                () => _attachments.removeAt(index),
                              ),
                            ),
                        ],
                      ),
                    ),
                  // --- Corps ---------------------------------------------
                  TextFormField(
                    controller: _body,
                    textCapitalization: TextCapitalization.sentences,
                    keyboardType: TextInputType.multiline,
                    minLines: 10,
                    maxLines: null,
                    decoration: const InputDecoration(
                      hintText: 'Votre message…',
                      border: InputBorder.none,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
