import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../providers/account_providers.dart';
import '../../providers/core_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: ListView(
        children: [
          const _SectionHeader('Comptes'),
          accounts.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => const SizedBox.shrink(),
            data: (list) => Column(
              children: [
                for (final account in list)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Color(account.colorValue),
                      child: Text(
                        account.email.substring(0, 1).toUpperCase(),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    title: Text(account.email),
                    subtitle: Text(account.provider.name),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Supprimer le compte',
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('Supprimer ce compte ?'),
                            content: Text(
                              'Les emails synchronisés de ${account.email} '
                              'seront supprimés de cet appareil.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, false),
                                child: const Text('Annuler'),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, true),
                                child: const Text('Supprimer'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          await ref
                              .read(accountRepositoryProvider)
                              .removeAccount(account);
                        }
                      },
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('Ajouter un compte'),
                  onTap: () => context.push('/add-account'),
                ),
              ],
            ),
          ),
          const Divider(),
          const _SectionHeader('Sécurité'),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: const Text('Verrouillage biométrique'),
            subtitle:
                const Text('Face ID / empreinte à l\'ouverture de l\'app'),
            value: false, // persisted via preferences in a follow-up
            onChanged: (enabled) async {
              if (enabled) {
                final ok = await ref
                    .read(biometricServiceProvider)
                    .authenticate(reason: 'Activer le verrouillage');
                if (!ok && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Biométrie indisponible sur cet appareil.'),
                    ),
                  );
                }
              }
            },
          ),
          const SwitchListTile(
            secondary: Icon(Icons.visibility_off_outlined),
            title: Text('Bloquer les images distantes'),
            subtitle: Text('Protection anti-tracking (recommandé)'),
            value: true,
            onChanged: null, // always-on in the free tier
          ),
          const Divider(),
          const _SectionHeader('Premium'),
          const ListTile(
            leading: Icon(Icons.auto_awesome_outlined),
            title: Text('Leman Mail Premium'),
            subtitle: Text(
              'Résumés IA, recherche naturelle, extraction de tâches, '
              'assistant de boîte de réception — bientôt disponible.',
            ),
          ),
          const Divider(),
          const _SectionHeader('À propos'),
          const ListTile(
            leading: Icon(Icons.shield_outlined),
            title: Text(AppConstants.appName),
            subtitle: Text(
              '${AppConstants.tagline}\n${AppConstants.publisher}',
            ),
            isThreeLine: true,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
