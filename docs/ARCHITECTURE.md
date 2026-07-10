# Leman Mail — Architecture Globale

> **"Votre boîte mail, sécurisée, maîtrisée et intelligente."**
> Édité par **Leman Cyber Security**.

Ce document couvre : l'architecture globale, les choix techniques, l'arborescence
complète du projet et le modèle de données détaillé (voir aussi `DATA_MODEL.md`).

---

## 1. Vue d'ensemble

Leman Mail est un client mail mobile multi-comptes (Flutter) dont la valeur
différenciante est une **couche d'analyse cybersécurité locale** : chaque email
synchronisé traverse un pipeline d'analyse (anti-phishing, trackers, newsletters)
dont les résultats alimentent le **Inbox Health Score**, le **Security Center**
et la **gamification**.

```
┌─────────────────────────────────────────────────────────────────┐
│                    PRESENTATION (Flutter + Riverpod)            │
│  Screens · Widgets · GoRouter · Providers · Thèmes M3           │
├─────────────────────────────────────────────────────────────────┤
│                          DOMAIN (Dart pur)                      │
│  Entities · Repository interfaces · Use cases                   │
├─────────────────────────────────────────────────────────────────┤
│                    ANALYSIS ENGINES (Dart pur)                  │
│  PhishingEngine · TrackingDetector · NewsletterDetector         │
│  SmartCleanupAnalyzer · InboxHealthCalculator                   │
│  SecurityCenterEngine · BadgeEngine                             │
├─────────────────────────────────────────────────────────────────┤
│                             DATA                                │
│  Drift/SQLite · Repositories impl · IMAP/SMTP (enough_mail)     │
│  Gmail API · Microsoft Graph · OAuth2/OIDC · Secure Storage     │
├─────────────────────────────────────────────────────────────────┤
│                        PLATFORM / SECURITY                      │
│  AES-256-GCM · Keychain/Keystore · Biométrie · Notifications    │
└─────────────────────────────────────────────────────────────────┘
```

### Principes structurants

1. **Clean Architecture** — dépendances orientées vers le domaine.
   `presentation → domain ← data`. Les moteurs d'analyse sont du Dart pur,
   sans dépendance Flutter : testables en isolation, réutilisables côté
   backend SaaS plus tard.
2. **SOLID** — chaque règle anti-phishing est une classe implémentant
   `PhishingRule` (Open/Closed) ; les services mail sont derrière des
   interfaces (`MailSyncService`) avec 3 implémentations (IMAP, Gmail API,
   Microsoft Graph) — Liskov + Dependency Inversion.
3. **Repository Pattern** — le domaine ne connaît ni Drift ni IMAP.
4. **Dependency Injection** — via Riverpod (`Provider` pour les services,
   `NotifierProvider`/`AsyncNotifierProvider` pour l'état).
5. **Offline-first** — SQLite est la source de vérité de l'UI ; la
   synchronisation réseau alimente la base, jamais l'UI directement.
6. **Local-first privacy** — toute l'analyse sécurité s'exécute sur
   l'appareil. Aucun contenu d'email ne quitte le téléphone (hors fonctions
   IA premium explicitement opt-in).

---

## 2. Choix techniques et justifications

| Domaine | Choix | Justification |
|---|---|---|
| UI | Flutter 3.x, Material 3 | Une base de code iOS + Android, theming M3 natif dark/light |
| État & DI | Riverpod 2 (Notifier/AsyncNotifier) | DI compile-safe, testable, pas de codegen obligatoire |
| Navigation | go_router | Deep-links (OAuth redirect, notifications), ShellRoute pour la nav à onglets |
| BDD | Drift (SQLite) | Requêtes typées, migrations versionnées, DAOs, streams réactifs vers l'UI |
| IMAP/SMTP | enough_mail | Client IMAP/SMTP/MIME Dart pur mature (IDLE, extensions) |
| Gmail | Gmail REST API (googleapis) | OAuth2, labels, historique incrémental (`historyId`) |
| Microsoft 365 | Microsoft Graph | Mail + Calendrier + Teams/OneDrive (premium), delta queries |
| OAuth 2.0 / OIDC | flutter_appauth (AppAuth) | PKCE natif, browser custom tabs / ASWebAuthenticationSession |
| Secrets | flutter_secure_storage | Keychain (iOS) / Keystore+EncryptedSharedPreferences (Android) |
| Chiffrement | package `cryptography`, AES-256-GCM | Chiffrement authentifié des corps d'emails et tokens au repos |
| Biométrie | local_auth | Face ID / Touch ID / empreinte, verrouillage d'app |
| Graphiques | fl_chart | Dashboards sécurité et évolution du Health Score |
| Parsing HTML | package `html` | Détection de pixels/trackers dans les corps HTML |
| Tests | flutter_test + mocktail | Unit / widget / intégration, moteurs 100 % couverts |
| CI/CD | GitHub Actions | analyze + codegen + tests + builds AAB/IPA |

### Stratégie de synchronisation

- **IMAP** : `UIDVALIDITY`/`UIDNEXT` par dossier, fetch incrémental par UID,
  IDLE quand l'app est au premier plan, polling + push notifications sinon.
- **Gmail API** : sync initiale par pages, puis `users.history.list` avec le
  dernier `historyId` (delta).
- **Graph** : `delta` queries sur les dossiers (`/mailFolders/{id}/messages/delta`).
- Chaque message entrant traverse le **pipeline d'analyse** avant insertion :
  `parse → authenticate (SPF/DKIM/DMARC via Authentication-Results) →
  phishing rules → tracker scan → newsletter detection → persist`.

### Sécurité applicative (résumé — détails dans `SECURITY.md`)

- Tokens OAuth et mots de passe IMAP : jamais en SQLite. Stockés via
  Keychain/Keystore, chiffrés AES-256-GCM avec une clé maîtresse générée
  sur l'appareil.
- Corps d'emails chiffrés au repos (colonne BLOB chiffrée, clé par appareil).
- Verrouillage biométrique de l'application (opt-in) + timeout.
- Aucune télémétrie par défaut ; réseau limité aux serveurs mail de
  l'utilisateur.
- Certificate pinning optionnel pour Gmail/Graph.

### Monétisation & architecture SaaS

Le code est organisé pour l'ajout d'un backend :
- `domain/` et `features/` (moteurs) sont du Dart pur → portables sur un
  backend Dart (serverpod/shelf) pour les fonctions IA premium.
- Un `EntitlementService` (free/premium) garde les fonctionnalités premium
  derrière une interface — branchable sur RevenueCat / Play Billing /
  StoreKit 2 sans toucher au reste.
- Les fonctions IA premium passent par `AiGateway` (interface) : l'app mobile
  n'embarque aucune clé API ; les appels transitent par le backend Leman.

---

## 3. Arborescence complète du projet

```
Leman-Mail/
├── README.md
├── pubspec.yaml
├── analysis_options.yaml
├── .gitignore
├── .github/
│   └── workflows/
│       ├── ci.yml                     # analyze + codegen + tests
│       └── release.yml                # builds AAB / IPA signés
├── docs/
│   ├── ARCHITECTURE.md                # ce document
│   ├── DATA_MODEL.md                  # modèle de données détaillé
│   ├── SECURITY.md                    # threat model & mesures
│   ├── DEPLOYMENT.md                  # Android / iOS / stores
│   └── ROADMAP.md                     # plan produit 3 ans
├── lib/
│   ├── main.dart                      # bootstrap + ProviderScope
│   ├── app.dart                       # MaterialApp.router, thèmes
│   ├── core/
│   │   ├── constants/app_constants.dart
│   │   ├── error/failures.dart
│   │   ├── theme/app_theme.dart       # Material 3 light/dark
│   │   ├── utils/email_utils.dart     # parsing domaines, en-têtes…
│   │   └── security/
│   │       ├── crypto_service.dart    # AES-256-GCM
│   │       ├── secure_storage_service.dart
│   │       └── biometric_service.dart
│   ├── domain/
│   │   ├── entities/                  # Dart pur, immutable
│   │   │   ├── account.dart
│   │   │   ├── email_message.dart
│   │   │   ├── newsletter_sender.dart
│   │   │   ├── inbox_health.dart
│   │   │   ├── security_recommendation.dart
│   │   │   ├── cleanup_suggestion.dart
│   │   │   └── badge.dart
│   │   ├── repositories/              # interfaces
│   │   │   ├── account_repository.dart
│   │   │   ├── email_repository.dart
│   │   │   ├── newsletter_repository.dart
│   │   │   └── health_repository.dart
│   │   └── usecases/
│   │       ├── analyze_incoming_email.dart   # pipeline d'analyse
│   │       ├── compute_inbox_health.dart
│   │       └── run_newsletter_cleanup.dart
│   ├── data/
│   │   ├── database/
│   │   │   ├── app_database.dart      # tables Drift + migrations
│   │   │   └── daos/
│   │   │       ├── accounts_dao.dart
│   │   │       ├── emails_dao.dart
│   │   │       ├── newsletters_dao.dart
│   │   │       └── health_dao.dart
│   │   ├── repositories/              # implémentations
│   │   │   ├── account_repository_impl.dart
│   │   │   ├── email_repository_impl.dart
│   │   │   ├── newsletter_repository_impl.dart
│   │   │   └── health_repository_impl.dart
│   │   └── services/
│   │       ├── auth/oauth_service.dart          # OAuth2 + OIDC (PKCE)
│   │       ├── mail/
│   │       │   ├── mail_sync_service.dart       # interface commune
│   │       │   ├── imap_service.dart            # enough_mail
│   │       │   ├── smtp_service.dart
│   │       │   └── provider_presets.dart        # Gmail, Outlook, Infomaniak…
│   │       ├── gmail/gmail_api_service.dart
│   │       └── graph/microsoft_graph_service.dart
│   ├── data/sync/
│   │   └── sync_coordinator.dart      # orchestre sync → analyse → persistance
│   ├── features/                      # MOTEURS — Dart pur, testables
│   │   ├── anti_phishing/
│   │   │   ├── phishing_engine.dart   # moteur modulaire
│   │   │   ├── phishing_rule.dart     # contrat de règle
│   │   │   ├── models.dart            # verdict, findings, contexte
│   │   │   └── rules/
│   │   │       ├── authentication_rule.dart     # SPF/DKIM/DMARC
│   │   │       ├── lookalike_domain_rule.dart   # typosquatting
│   │   │       ├── suspicious_url_rule.dart     # raccourcisseurs, IP, punycode
│   │   │       ├── dangerous_attachment_rule.dart
│   │   │       ├── unknown_sender_rule.dart
│   │   │       └── urgency_language_rule.dart
│   │   ├── privacy/
│   │   │   ├── tracking_detector.dart # pixels, trackers, ressources externes
│   │   │   └── models.dart
│   │   ├── newsletter/
│   │   │   ├── newsletter_detector.dart         # List-Unsubscribe, heuristiques
│   │   │   └── models.dart
│   │   ├── cleanup/
│   │   │   └── smart_cleanup_analyzer.dart
│   │   ├── health/
│   │   │   └── inbox_health_calculator.dart     # Inbox Health Score
│   │   ├── security_center/
│   │   │   └── security_center_engine.dart      # Secure-Score-like
│   │   └── gamification/
│   │       └── badge_engine.dart
│   ├── presentation/
│   │   ├── router/app_router.dart
│   │   ├── providers/
│   │   │   ├── core_providers.dart    # DB, services, moteurs (DI)
│   │   │   ├── account_providers.dart
│   │   │   ├── inbox_providers.dart
│   │   │   ├── newsletter_providers.dart
│   │   │   ├── health_providers.dart
│   │   │   └── security_providers.dart
│   │   ├── screens/
│   │   │   ├── onboarding/onboarding_screen.dart
│   │   │   ├── home/home_shell.dart             # nav à onglets
│   │   │   ├── inbox/unified_inbox_screen.dart
│   │   │   ├── inbox/email_detail_screen.dart
│   │   │   ├── compose/compose_screen.dart
│   │   │   ├── newsletter/newsletter_cleaner_screen.dart
│   │   │   ├── cleanup/smart_cleanup_screen.dart
│   │   │   ├── dashboard/security_dashboard_screen.dart
│   │   │   ├── health/health_score_screen.dart
│   │   │   ├── security_center/security_center_screen.dart
│   │   │   ├── accounts/add_account_screen.dart
│   │   │   └── settings/settings_screen.dart
│   │   └── widgets/
│   │       ├── risk_badge.dart
│   │       ├── email_tile.dart
│   │       ├── score_gauge.dart
│   │       └── stat_card.dart
├── test/
│   ├── core/email_utils_test.dart
│   ├── anti_phishing/phishing_engine_test.dart
│   ├── privacy/tracking_detector_test.dart
│   ├── newsletter/newsletter_detector_test.dart
│   ├── cleanup/smart_cleanup_analyzer_test.dart
│   ├── health/inbox_health_calculator_test.dart
│   ├── security_center/security_center_engine_test.dart
│   ├── gamification/badge_engine_test.dart
│   └── widgets/risk_badge_test.dart
├── integration_test/
│   └── app_test.dart
├── android/                           # généré par `flutter create .`
└── ios/                               # généré par `flutter create .`
```

> Les répertoires `android/` et `ios/` sont générés par `flutter create .`
> (voir `DEPLOYMENT.md`). Les fichiers Drift `*.g.dart` sont générés par
> `dart run build_runner build` et ne sont pas versionnés.

---

## 4. Flux de données clés

### Pipeline d'analyse d'un email entrant

```
IMAP/Gmail/Graph ─▶ RawMessage
   │
   ├─ MimeParser ────────────────▶ EmailMessage (entity)
   ├─ AuthenticationResults ─────▶ spf/dkim/dmarc (pass|fail|none)
   ├─ PhishingEngine.analyze() ──▶ score 0-100, niveau 🟢🟡🔴, findings
   ├─ TrackingDetector.scan() ───▶ trackers, pixels, score confidentialité
   ├─ NewsletterDetector ────────▶ isNewsletter, lien de désinscription
   └─ EmailsDao.upsert() ────────▶ SQLite (corps chiffré AES-256-GCM)
                                        │
                     Streams Drift ─────▶ UI (inbox, dashboards) en temps réel
```

### Inbox Health Score

Recalculé après chaque synchronisation et snapshoté quotidiennement dans
`health_snapshots` → graphes d'évolution 7 j / 30 j / 90 j / 12 mois.

### Security Center

Consomme : état MFA des comptes, statistiques d'analyse, newsletters
actives, expéditeurs bloqués → produit un score global + recommandations
actionnables valorisées en points (`+5 Activer MFA`, …).
