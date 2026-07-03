import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leman_mail/domain/entities/email_message.dart';
import 'package:leman_mail/presentation/widgets/risk_badge.dart';

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('RiskBadge', () {
    testWidgets('affiche 🟢 Faible risque avec score', (tester) async {
      await tester.pumpWidget(
        wrap(const RiskBadge(level: RiskLevel.low, score: 5)),
      );
      expect(find.textContaining('Faible risque'), findsOneWidget);
      expect(find.textContaining('5/100'), findsOneWidget);
    });

    testWidgets('affiche 🔴 Risque élevé', (tester) async {
      await tester.pumpWidget(
        wrap(const RiskBadge(level: RiskLevel.high)),
      );
      expect(find.textContaining('Risque élevé'), findsOneWidget);
    });

    testWidgets('mode compact : rien pour risque faible', (tester) async {
      await tester.pumpWidget(
        wrap(const RiskBadge(level: RiskLevel.low, compact: true)),
      );
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('mode compact : pastille pour risque moyen', (tester) async {
      await tester.pumpWidget(
        wrap(const RiskBadge(level: RiskLevel.medium, compact: true)),
      );
      expect(find.text('🟡'), findsOneWidget);
    });
  });
}
