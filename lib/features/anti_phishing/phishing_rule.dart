import 'models.dart';

/// Contract for one modular detection rule (Open/Closed principle: add a
/// rule = add a class + tests, the engine itself never changes).
///
/// Rules must be pure: no I/O, no shared state — they receive everything
/// they need in [PhishingInput].
abstract class PhishingRule {
  /// Stable identifier persisted with findings (`auth`, `lookalike`, ...).
  String get id;

  List<PhishingFinding> evaluate(PhishingInput input);
}
