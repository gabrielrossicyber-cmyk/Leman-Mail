# Leman Mail

> **"Votre boîte mail, sécurisée, maîtrisée et intelligente."**

Client mail mobile (Flutter, iOS + Android) développé par **Leman Cyber
Security** : multi-comptes, boîte unifiée, moteur anti-phishing local,
protection contre le tracking, nettoyage intelligent des newsletters,
**Inbox Health Score** et **Security Center**.

## Fonctionnalités

**Gratuit** — multi-comptes (Gmail, Outlook/Microsoft 365, Yahoo,
Infomaniak, Fastmail, IMAP générique), boîte unifiée, anti-phishing
(SPF/DKIM/DMARC, typosquatting, URLs et pièces jointes dangereuses),
blocage des trackers, Newsletter Cleaner, Smart Cleanup, dashboard
cybersécurité, Inbox Health Score, gamification, Security Center.

**Premium** — résumés IA, recherche en langage naturel, extraction de
tâches, intégration Microsoft 365 avancée, assistant IA.

## Démarrage

```bash
# Prérequis : Flutter >= 3.22
flutter create . --org com.lemancybersecurity --project-name leman_mail \
  --platforms android,ios          # génère android/ et ios/ (non versionnés)
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # codegen Drift
flutter test                        # tests unitaires + widget
flutter run
```

## Documentation

| Document | Contenu |
|---|---|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Architecture, choix techniques, arborescence |
| [docs/DATA_MODEL.md](docs/DATA_MODEL.md) | Modèle de données SQLite/Drift |
| [docs/SECURITY.md](docs/SECURITY.md) | Threat model, chiffrement, OAuth |
| [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) | Déploiement Android / iOS |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Plan produit 3 ans |

## Architecture (résumé)

Clean Architecture + Riverpod : `presentation → domain ← data`, avec les
moteurs d'analyse (`lib/features/`) en **Dart pur** — sans dépendance
Flutter — entièrement couverts par des tests unitaires.

© Leman Cyber Security
