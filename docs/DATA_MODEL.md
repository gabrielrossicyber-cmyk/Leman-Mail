# Leman Mail — Modèle de données détaillé

Base : **SQLite via Drift** (schéma versionné, migrations dans
`lib/data/database/app_database.dart`).

Convention : `id` = clé primaire auto-incrémentée ; timestamps en UTC
(epoch millis) ; les booléens Drift sont stockés en `INTEGER 0/1`.

---

## Diagramme entité-relation

```
accounts 1───n folders 1───n emails 1───n attachments
   │                          │
   │                          └── (colonnes d'analyse embarquées :
   │                               phishing, privacy, newsletter)
   ├── 1───n newsletter_senders
   ├── 1───n health_snapshots (accountId NULL = score global)
   └── 1───n sync_states

blocked_senders (global)      badges (global)
security_recommendations (global)
```

---

## Tables

### `accounts`
Compte mail configuré. **Aucun secret ici** — les tokens OAuth et mots de
passe vivent dans le Secure Storage sous la clé `account_secret_<uuid>`.

| Colonne | Type | Description |
|---|---|---|
| id | INTEGER PK | |
| uuid | TEXT UNIQUE | Référence stable (clé secure storage, logs) |
| email | TEXT | Adresse du compte |
| displayName | TEXT | Nom affiché |
| provider | TEXT enum | `gmail` `outlook` `microsoft365` `yahoo` `infomaniak` `fastmail` `proton` `imap` |
| authMethod | TEXT enum | `oauth2` `password` |
| imapHost / imapPort / imapTls | TEXT/INT/BOOL | Vide si API native |
| smtpHost / smtpPort / smtpTls | TEXT/INT/BOOL | |
| colorValue | INTEGER | Couleur du compte dans l'UI |
| isEnabled | BOOL | Sync active |
| mfaEnabled | BOOL | Déclaré/détecté — alimente le Security Center |
| lastSyncAt | DATETIME NULL | |
| createdAt | DATETIME | |

### `folders`

| Colonne | Type | Description |
|---|---|---|
| id | INTEGER PK | |
| accountId | INTEGER FK→accounts | `ON DELETE CASCADE` |
| path | TEXT | Chemin IMAP / id Gmail label / id Graph folder |
| name | TEXT | Nom affiché |
| type | TEXT enum | `inbox` `sent` `drafts` `trash` `spam` `archive` `other` |
| unreadCount / totalCount | INTEGER | Compteurs dénormalisés |

### `emails`
Un message synchronisé. Le corps est **chiffré AES-256-GCM** au repos.
Les résultats d'analyse sont dénormalisés ici pour des requêtes de
dashboard rapides (index sur `phishingLevel`, `isNewsletter`, `isRead`).

| Colonne | Type | Description |
|---|---|---|
| id | INTEGER PK | |
| accountId | INTEGER FK→accounts | CASCADE |
| folderId | INTEGER FK→folders | CASCADE |
| uid | INTEGER | UID IMAP / hash id API |
| messageId | TEXT | En-tête Message-ID |
| threadId | TEXT NULL | Conversation |
| subject | TEXT | |
| fromName / fromAddress | TEXT | |
| toAddresses / ccAddresses | TEXT | JSON array |
| date | DATETIME | |
| snippet | TEXT | 160 premiers caractères, en clair (liste) |
| bodyEncrypted | BLOB NULL | nonce ‖ ciphertext ‖ tag (AES-256-GCM) |
| bodyIsHtml | BOOL | |
| isRead / isFlagged / isAnswered | BOOL | |
| hasAttachments | BOOL | |
| sizeBytes | INTEGER | Pour Smart Cleanup (espace récupérable) |
| **Authentification** | | |
| spf / dkim / dmarc | TEXT enum | `pass` `fail` `softfail` `none` `unknown` |
| **Anti-phishing** | | |
| phishingScore | INTEGER | 0–100 |
| phishingLevel | TEXT enum | `low` 🟢 `medium` 🟡 `high` 🔴 |
| phishingFindings | TEXT | JSON `[{rule, severity, message}]` |
| **Vie privée** | | |
| trackerCount | INTEGER | Pixels + trackers détectés |
| externalResourceCount | INTEGER | |
| privacyScore | INTEGER | 0–100 (100 = aucun suivi) |
| **Newsletter** | | |
| isNewsletter | BOOL | |
| unsubscribeUrl / unsubscribeMailto | TEXT NULL | Extraits de List-Unsubscribe |
| listUnsubscribePost | BOOL | RFC 8058 (one-click) |
| analyzedAt | DATETIME NULL | Pipeline exécuté |

Index : `(accountId, folderId, uid)` UNIQUE ; `(isRead)` ; `(isNewsletter)` ;
`(phishingLevel)` ; `(fromAddress)` ; `(date DESC)`.

### `attachments`

| Colonne | Type | Description |
|---|---|---|
| id | INTEGER PK | |
| emailId | INTEGER FK→emails | CASCADE |
| fileName / mimeType | TEXT | |
| sizeBytes | INTEGER | |
| isDangerous | BOOL | Extension exécutable / double extension |
| localPath | TEXT NULL | Si téléchargée (répertoire chiffré) |

### `newsletter_senders`
Agrégat par expéditeur pour le Newsletter Cleaner.

| Colonne | Type | Description |
|---|---|---|
| id | INTEGER PK | |
| accountId | INTEGER FK→accounts | CASCADE |
| senderAddress | TEXT | UNIQUE avec accountId |
| senderName | TEXT | « Amazon », « Digitec »… |
| emailCount / unreadCount | INTEGER | |
| totalSizeBytes | INTEGER | |
| lastEmailAt | DATETIME | |
| unsubscribeUrl / unsubscribeMailto | TEXT NULL | Dernier connu |
| supportsOneClick | BOOL | RFC 8058 |
| status | TEXT enum | `active` `unsubscribed` `blocked` `archived` |

### `blocked_senders`

| Colonne | Type | Description |
|---|---|---|
| id | INTEGER PK | |
| pattern | TEXT UNIQUE | Adresse exacte ou `*@domaine.com` |
| reason | TEXT enum | `phishing` `spam` `newsletter` `manual` |
| createdAt | DATETIME | |

### `health_snapshots`
Un point par jour et par compte (+ un global, `accountId NULL`) —
alimente les courbes 7 j / 30 j / 90 j / 12 mois.

| Colonne | Type | Description |
|---|---|---|
| id | INTEGER PK | |
| accountId | INTEGER FK NULL | NULL = score global |
| day | DATETIME | Tronqué à minuit UTC, UNIQUE avec accountId |
| totalScore | INTEGER | 0–100 |
| securityScore / clutterScore / privacyScore / organizationScore | INTEGER | Sous-scores 0–100 |
| detailsJson | TEXT | Forces / améliorations / recommandations sérialisées |

### `security_recommendations`
État des recommandations du Security Center.

| Colonne | Type | Description |
|---|---|---|
| id | INTEGER PK | |
| code | TEXT UNIQUE | ex. `enable_mfa`, `block_suspicious_domain` |
| accountUuid | TEXT NULL | Si liée à un compte |
| points | INTEGER | Valeur (+5, +8…) |
| status | TEXT enum | `open` `completed` `dismissed` |
| completedAt | DATETIME NULL | |

### `badges`

| Colonne | Type | Description |
|---|---|---|
| id | INTEGER PK | |
| badgeId | TEXT UNIQUE | `inbox_clean`, `security_defender`, … |
| unlockedAt | DATETIME | |

### `sync_states`
Curseurs de synchronisation incrémentale.

| Colonne | Type | Description |
|---|---|---|
| id | INTEGER PK | |
| accountId | INTEGER FK | CASCADE |
| folderId | INTEGER FK NULL | NULL pour curseurs de compte (historyId) |
| uidValidity / lastUid | INTEGER NULL | IMAP |
| cursor | TEXT NULL | `historyId` Gmail / `deltaLink` Graph |
| lastSyncAt | DATETIME | |

---

## Entités du domaine

Les entités (`lib/domain/entities/`) sont des classes Dart immuables,
indépendantes de Drift. Les DAOs mappent lignes ↔ entités dans les
implémentations de repositories. Les enums partagés
(`MailProvider`, `AuthResult`, `RiskLevel`, `NewsletterStatus`, …) vivent
dans le domaine et sont sérialisés en TEXT côté base.
