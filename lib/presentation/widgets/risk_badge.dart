import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/email_message.dart';

/// 🟢 / 🟡 / 🔴 phishing risk chip.
class RiskBadge extends StatelessWidget {
  const RiskBadge({super.key, required this.level, this.score, this.compact = false});

  final RiskLevel level;
  final int? score;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (color, label, emoji) = switch (level) {
      RiskLevel.low => (AppTheme.riskLow, 'Faible risque', '🟢'),
      RiskLevel.medium => (AppTheme.riskMedium, 'Risque moyen', '🟡'),
      RiskLevel.high => (AppTheme.riskHigh, 'Risque élevé', '🔴'),
    };

    if (compact) {
      return level == RiskLevel.low
          ? const SizedBox.shrink()
          : Text(emoji, style: const TextStyle(fontSize: 12));
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        score == null ? '$emoji $label' : '$emoji $label · $score/100',
        style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}
