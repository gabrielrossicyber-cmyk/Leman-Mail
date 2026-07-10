# Leman Mail — Sécurité applicative

## Threat model (résumé)

| Menace | Mesure |
|---|---|
| Vol de l'appareil | Verrouillage biométrique (Face ID / empreinte), corps d'emails et secrets chiffrés au repos |
| Extraction de la base SQLite | Corps chiffrés AES-256-GCM, clé maîtresse dans Keychain/Keystore (hardware-backed quand disponible) |
| Interception réseau | TLS obligatoire (IMAPS 993 / SMTPS 465 ou STARTTLS), échec = pas de connexion silencieuse en clair |
| Vol de tokens OAuth | Tokens uniquement en secure storage, jamais en base ni en logs ; refresh tokens avec rotation |
| Phishing de l'utilisateur | Moteur anti-phishing local (SPF/DKIM/DMARC, typosquatting, URLs, pièces jointes) |
| Tracking publicitaire | Blocage par défaut des images distantes et pixels de suivi |
| Compromission de la supply chain | Dépendances épinglées, `flutter pub deps` audité en CI, pas de code dynamique |

## Chiffrement au repos

- **Algorithme** : AES-256-GCM (`package:cryptography`), chiffrement
  authentifié — voir `lib/core/security/crypto_service.dart`.
- **Clé maîtresse** : 32 octets générés par CSPRNG au premier lancement,
  stockés via `flutter_secure_storage` :
  - iOS : Keychain, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
  - Android : Keystore (StrongBox si disponible) + EncryptedSharedPreferences
- **Format** : `nonce(12) ‖ ciphertext ‖ tag(16)` par enregistrement,
  nonce unique par message.
- **Chiffré** : corps d'emails, pièces jointes téléchargées, tokens,
  mots de passe IMAP/SMTP.
- **Non chiffré** (nécessaire aux requêtes) : métadonnées — sujet, snippet,
  adresses, scores. Documenté dans la politique de confidentialité.

## Authentification

- **OAuth 2.0 + OIDC avec PKCE** (`flutter_appauth`) pour Gmail, Microsoft
  365/Outlook.com, Yahoo. Scopes minimaux (`gmail.readonly` +
  `gmail.modify` seulement si nettoyage activé ; `Mail.ReadWrite`,
  `offline_access` pour Graph).
- **Mot de passe d'application** pour IMAP générique (Infomaniak, Fastmail,
  Proton via Bridge) — jamais le mot de passe principal si le fournisseur
  propose des app passwords (message d'aide dans l'UI).
- **Verrouillage d'app** : `local_auth`, biométrie ou code appareil,
  timeout configurable (immédiat / 1 min / 5 min).

## Règles de développement

1. Aucun secret dans le code, les logs, les crash reports ou SQLite.
2. Tout nouvel accès réseau passe par un service injecté (mockable, auditable).
3. Toute nouvelle règle d'analyse = classe + tests unitaires dédiés.
4. Revue sécurité obligatoire sur `data/services/` et `core/security/`.
5. `flutter analyze` + tests en CI bloquants sur chaque PR.
