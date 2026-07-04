import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/constants/app_constants.dart';
import '../providers/core_providers.dart';

/// Écran de verrouillage : recouvre toute l'app (au-dessus du navigateur,
/// donc aucune interaction ni lecture possible en dessous) jusqu'à une
/// authentification biométrique réussie. Tente automatiquement Face ID /
/// empreinte à l'affichage, avec un bouton de réessai.
class LockOverlay extends ConsumerStatefulWidget {
  const LockOverlay({super.key});

  @override
  ConsumerState<LockOverlay> createState() => _LockOverlayState();
}

class _LockOverlayState extends ConsumerState<LockOverlay> {
  bool _authenticating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (_authenticating) return;
    setState(() => _authenticating = true);
    try {
      final ok = await ref.read(biometricServiceProvider).authenticate();
      if (ok && mounted) {
        ref.read(appLockedProvider.notifier).state = false;
      }
    } finally {
      if (mounted) setState(() => _authenticating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SvgPicture.asset(
                'assets/branding/logo.svg',
                width: 88,
                height: 88,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              AppConstants.appName,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text('Verrouillé', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _authenticating ? null : _unlock,
              icon: _authenticating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.fingerprint),
              label: const Text('Déverrouiller'),
            ),
          ],
        ),
      ),
    );
  }
}
