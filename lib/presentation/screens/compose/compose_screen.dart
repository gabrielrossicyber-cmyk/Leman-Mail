import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/services/mail/smtp_service.dart';
import '../../providers/account_providers.dart';
import '../../providers/core_providers.dart';

/// Rédaction d'un email (envoi SMTP ; Gmail/Graph envoient via leur API
/// dans une itération suivante).
class ComposeScreen extends ConsumerStatefulWidget {
  const ComposeScreen({super.key});

  @override
  ConsumerState<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends ConsumerState<ComposeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _to = TextEditingController();
  final _subject = TextEditingController();
  final _body = TextEditingController();
  int? _accountId;
  bool _sending = false;

  @override
  void dispose() {
    _to.dispose();
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    final accounts = ref.read(accountsProvider).valueOrNull ?? [];
    if (accounts.isEmpty) return;
    final account = accounts.firstWhere(
      (a) => a.id == _accountId,
      orElse: () => accounts.first,
    );

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
        to: _to.text.split(',').map((a) => a.trim()).toList(),
        subject: _subject.text,
        textBody: _body.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Email envoyé.')));
        context.pop();
      }
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Échec de l\'envoi : $error')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider).valueOrNull ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nouveau message'),
        actions: [
          IconButton(
            icon: _sending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_outlined),
            onPressed: _sending ? null : _send,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (accounts.length > 1)
              DropdownButtonFormField<int>(
                initialValue: _accountId ?? accounts.first.id,
                decoration: const InputDecoration(labelText: 'De'),
                items: [
                  for (final account in accounts)
                    DropdownMenuItem(
                      value: account.id,
                      child: Text(account.email),
                    ),
                ],
                onChanged: (value) => setState(() => _accountId = value),
              ),
            TextFormField(
              controller: _to,
              decoration: const InputDecoration(labelText: 'À'),
              keyboardType: TextInputType.emailAddress,
              validator: (value) => value != null && value.contains('@')
                  ? null
                  : 'Destinataire invalide',
            ),
            TextFormField(
              controller: _subject,
              decoration: const InputDecoration(labelText: 'Objet'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _body,
              decoration: const InputDecoration(
                hintText: 'Votre message…',
                border: OutlineInputBorder(),
              ),
              maxLines: 14,
            ),
          ],
        ),
      ),
    );
  }
}
