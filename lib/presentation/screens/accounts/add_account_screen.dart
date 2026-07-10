import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/services/mail/provider_presets.dart';
import '../../../domain/entities/account.dart';
import '../../providers/account_providers.dart';

/// Ajout de compte : choix du fournisseur, puis OAuth ou IMAP.
class AddAccountScreen extends ConsumerStatefulWidget {
  const AddAccountScreen({super.key});

  @override
  ConsumerState<AddAccountScreen> createState() => _AddAccountScreenState();
}

class _AddAccountScreenState extends ConsumerState<AddAccountScreen> {
  ProviderPreset? _preset;
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _imapHost = TextEditingController();
  final _smtpHost = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _imapHost.dispose();
    _smtpHost.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(addAccountControllerProvider);

    ref.listen(addAccountControllerProvider, (previous, next) {
      if (previous is AsyncLoading && next is AsyncData) {
        context.go('/');
      }
      if (next is AsyncError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Échec : ${next.error}')),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Ajouter un compte')),
      body: _preset == null ? _providerList() : _configForm(state),
    );
  }

  Widget _providerList() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final preset in providerPresets)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: Icon(
                preset.usesNativeApi
                    ? Icons.cloud_outlined
                    : Icons.dns_outlined,
              ),
              title: Text(preset.label),
              subtitle: Text(
                preset.authMethod == AuthMethod.oauth2
                    ? 'Connexion sécurisée OAuth 2.0'
                    : 'IMAP / SMTP avec mot de passe d\'application',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => setState(() => _preset = preset),
            ),
          ),
      ],
    );
  }

  Widget _configForm(AsyncValue<void> state) {
    final preset = _preset!;
    final isOAuth = preset.authMethod == AuthMethod.oauth2;
    final isCustomImap = preset.provider == MailProvider.imap;

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            preset.label,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (preset.helpText != null) ...[
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline),
                    const SizedBox(width: 8),
                    Expanded(child: Text(preset.helpText!)),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Adresse email',
              border: OutlineInputBorder(),
            ),
            validator: (value) =>
                value != null && value.contains('@') ? null : 'Email invalide',
          ),
          if (!isOAuth) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Mot de passe d\'application',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  value != null && value.isNotEmpty ? null : 'Requis',
            ),
          ],
          if (isCustomImap) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _imapHost,
              decoration: const InputDecoration(
                labelText: 'Serveur IMAP (ex. imap.mondomaine.ch)',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  value != null && value.isNotEmpty ? null : 'Requis',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _smtpHost,
              decoration: const InputDecoration(
                labelText: 'Serveur SMTP (ex. smtp.mondomaine.ch)',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  value != null && value.isNotEmpty ? null : 'Requis',
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: state.isLoading
                ? null
                : () {
                    if (!_formKey.currentState!.validate()) return;
                    final controller =
                        ref.read(addAccountControllerProvider.notifier);
                    if (isOAuth) {
                      controller.addOAuthAccount(preset, _email.text.trim());
                    } else {
                      controller.addImapAccount(
                        preset: preset,
                        email: _email.text.trim(),
                        password: _password.text,
                        imapHost: isCustomImap ? _imapHost.text.trim() : null,
                        smtpHost: isCustomImap ? _smtpHost.text.trim() : null,
                      );
                    }
                  },
            child: state.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    isOAuth
                        ? 'Se connecter avec ${preset.label}'
                        : 'Ajouter le compte',
                  ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() => _preset = null),
            child: const Text('Choisir un autre fournisseur'),
          ),
        ],
      ),
    );
  }
}
