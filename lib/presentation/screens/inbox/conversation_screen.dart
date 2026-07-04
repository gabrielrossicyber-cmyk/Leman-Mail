import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/core_providers.dart';
import '../../widgets/email_tile.dart';

final _threadProvider = StreamProvider.family
    .autoDispose((ref, String threadId) =>
        ref.watch(emailRepositoryProvider).watchThread(threadId));

/// Fil de conversation : tous les messages du fil, du plus ancien au plus
/// récent ; un tap ouvre la lecture complète du message.
class ConversationScreen extends ConsumerWidget {
  const ConversationScreen({super.key, required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thread = ref.watch(_threadProvider(threadId));

    return Scaffold(
      appBar: AppBar(
        title: thread.whenOrNull(
              data: (messages) => messages.isEmpty
                  ? null
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _normalizeSubject(messages.last.subject),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${messages.length} messages',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
            ) ??
            const Text('Conversation'),
      ),
      body: thread.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Erreur : $error')),
        data: (messages) => messages.isEmpty
            ? const Center(child: Text('Conversation vide.'))
            : ListView.separated(
                itemCount: messages.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 72),
                itemBuilder: (context, index) {
                  final email = messages[index];
                  return EmailTile(
                    email: email,
                    onTap: () => context.push('/email/${email.id}'),
                  );
                },
              ),
      ),
    );
  }

  /// « Re: Re: Fwd: Objet » → « Objet ».
  static String _normalizeSubject(String subject) => subject
      .replaceAll(
        RegExp(r'^((re|fwd|fw|tr)\s*:\s*)+', caseSensitive: false),
        '',
      )
      .trim();
}
