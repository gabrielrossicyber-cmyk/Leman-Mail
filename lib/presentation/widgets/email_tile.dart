import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/email_message.dart';
import 'risk_badge.dart';

/// One row of the unified inbox, with multi-selection support:
/// long-press enters selection mode, the avatar becomes a check mark.
class EmailTile extends StatelessWidget {
  const EmailTile({
    super.key,
    required this.email,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.selectionMode = false,
  });

  final EmailMessage email;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool selectionMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weight = email.isRead ? FontWeight.normal : FontWeight.w700;

    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      selected: selected,
      selectedTileColor: theme.colorScheme.primaryContainer,
      leading: selectionMode
          ? CircleAvatar(
              backgroundColor: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.surfaceContainerHighest,
              child: Icon(
                selected ? Icons.check : Icons.circle_outlined,
                color: selected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.outline,
                size: 20,
              ),
            )
          : CircleAvatar(
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                (email.fromName.isNotEmpty ? email.fromName : email.fromAddress)
                    .substring(0, 1)
                    .toUpperCase(),
                style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
              ),
            ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              email.fromName.isNotEmpty ? email.fromName : email.fromAddress,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: weight),
            ),
          ),
          if (email.isFlagged)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                Icons.star,
                size: 15,
                color: theme.colorScheme.secondary,
              ),
            ),
          RiskBadge(level: email.phishingLevel, compact: true),
          const SizedBox(width: 6),
          Text(
            _formatDate(email.date),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            email.subject.isEmpty ? '(sans objet)' : email.subject,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: weight),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  email.snippet,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              if (email.hasAttachments)
                const Icon(Icons.attach_file, size: 14),
              if (email.isNewsletter)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.campaign_outlined, size: 14),
                ),
              if (email.hasTracking)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.visibility_off_outlined, size: 14),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      return DateFormat.Hm().format(date);
    }
    return DateFormat('d MMM', 'fr').format(date);
  }
}
