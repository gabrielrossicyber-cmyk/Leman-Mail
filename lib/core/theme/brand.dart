import 'package:flutter/material.dart';

/// Identité visuelle Leman Cyber Security — source de vérité unique.
///
/// Toute la charte de l'application (thème, en-têtes, jauges, onboarding)
/// se dérive de ce fichier : pour aligner l'app sur le site
/// leman-security.gabriel-rossi.ch, seules ces valeurs changent.
///
/// ⚠️ Les valeurs ci-dessous sont provisoires (bleu Léman) en attendant
/// les codes couleur officiels du site.
abstract final class Brand {
  // --- Couleurs ------------------------------------------------------------

  /// Couleur principale (boutons, éléments actifs, liens).
  static const primary = Color(0xFF0B5394);

  /// Couleur d'accent secondaire (highlights, dégradés).
  static const accent = Color(0xFF2E7D32);

  /// Fond des surfaces sombres (drawer header, splash) si le site est
  /// à dominante sombre.
  static const darkSurface = Color(0xFF0E1621);

  /// Dégradé de marque utilisé pour les en-têtes héro.
  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, accent],
  );

  // --- Sémantique sécurité (indépendante de la marque) ----------------------

  static const riskLow = Color(0xFF2E7D32);
  static const riskMedium = Color(0xFFF9A825);
  static const riskHigh = Color(0xFFC62828);

  // --- Identité -------------------------------------------------------------

  static const appName = 'Leman Mail';
  static const companyName = 'Leman Cyber Security';
  static const tagline =
      'Votre boîte mail, sécurisée, maîtrisée et intelligente.';
  static const websiteUrl = 'https://leman-security.gabriel-rossi.ch/';

  /// Police d'affichage si la charte en impose une (null = système).
  /// Renseigner ici le nom d'une police ajoutée dans pubspec (fonts:).
  static const String? displayFontFamily = null;
}
