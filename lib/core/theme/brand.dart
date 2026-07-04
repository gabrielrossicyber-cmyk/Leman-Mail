import 'package:flutter/material.dart';

/// Identité visuelle Leman Cyber Security — source de vérité unique,
/// alignée sur leman-security.gabriel-rossi.ch.
///
/// Charte : éditoriale et élégante — fond crème, encre brun-noir,
/// bordeaux profond et carmin en accents, titres serif, boutons pilule
/// sombres, étiquettes en petites capitales espacées.
abstract final class Brand {
  // --- Palette officielle ----------------------------------------------------

  /// Crème — fond principal des pages (#f5efe7).
  static const cream = Color(0xFFF5EFE7);

  /// Encre — texte principal et boutons pleins (#201914).
  static const ink = Color(0xFF201914);

  /// Taupe — bordures, séparateurs, éléments atténués (#c8bbb1).
  static const taupe = Color(0xFFC8BBB1);

  /// Bordeaux profond — couleur principale de marque (#551112).
  static const bordeaux = Color(0xFF551112);

  /// Carmin — accents, liens, badges (#a5292b).
  static const carmine = Color(0xFFA5292B);

  // --- Rôles -----------------------------------------------------------------

  static const primary = bordeaux;
  static const accent = carmine;

  /// Surface des cartes en mode clair (blanc cassé au-dessus du crème).
  static const cardLight = Color(0xFFFDFAF5);

  /// Fond en mode sombre (encre légèrement réchauffée).
  static const darkSurface = Color(0xFF1B1512);

  /// Cartes en mode sombre.
  static const cardDark = Color(0xFF2A211B);

  /// Dégradé de marque (en-têtes héro).
  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [bordeaux, carmine],
  );

  // --- Sémantique sécurité (proche des badges du site : CRITIQUE/ÉLEVÉ/OK) ---

  static const riskLow = Color(0xFF2E7D32);
  static const riskMedium = Color(0xFFB8860B);
  static const riskHigh = carmine;

  // --- Identité ----------------------------------------------------------------

  static const appName = 'Leman Mail';
  static const companyName = 'Leman Cyber Security';
  static const tagline =
      'Votre boîte mail, sécurisée, maîtrisée et intelligente.';
  static const websiteUrl = 'https://leman-security.gabriel-rossi.ch/';
}
