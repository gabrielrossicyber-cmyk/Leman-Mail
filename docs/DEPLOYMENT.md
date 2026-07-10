# Leman Mail — Déploiement Android & iOS

## Génération des projets natifs

Les répertoires `android/` et `ios/` sont générés localement :

```bash
flutter create . --org com.lemancybersecurity --project-name leman_mail \
  --platforms android,ios
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

Configuration native requise ensuite :

### Android
- `applicationId com.lemancybersecurity.lemanmail`, `minSdk 26`, `targetSdk` courant.
- Signature : keystore de release stocké en secret GitHub (`ANDROID_KEYSTORE_BASE64`,
  `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`).
- `android:allowBackup="false"`, `FLAG_SECURE` sur les écrans mail (anti-capture).
- Redirect scheme AppAuth dans `build.gradle` :
  `manifestPlaceholders = [appAuthRedirectScheme: 'com.lemancybersecurity.lemanmail']`.
- Notifications push : FCM (module optionnel — le mode polling fonctionne sans).

### iOS
- Bundle id `com.lemancybersecurity.lemanmail`, iOS 15+.
- Capabilities : Keychain Sharing (non requis en mono-app), Push Notifications,
  Background fetch (`fetch`, `remote-notification`).
- `NSFaceIDUsageDescription` dans Info.plist.
- **Synchro arrière-plan (workmanager/BGTaskScheduler)** — dans Info.plist :
  ```xml
  <key>BGTaskSchedulerPermittedIdentifiers</key>
  <array>
    <string>com.lemancybersecurity.lemanmail.sync</string>
  </array>
  <key>UIBackgroundModes</key>
  <array>
    <string>fetch</string>
    <string>processing</string>
  </array>
  ```
  et dans `AppDelegate.swift`, enregistrer la tâche au lancement :
  ```swift
  WorkmanagerPlugin.registerBGProcessingTask(
    withIdentifier: "com.lemancybersecurity.lemanmail.sync")
  ```
  iOS déclenche ces fenêtres à sa discrétion (best effort) — les push
  serveur FCM/APNs (backend SaaS, roadmap T3) restent la solution temps
  réel définitive.
- URL scheme de redirection OAuth identique à Android.
- Signature via App Store Connect API key en CI (`fastlane` ou `xcodebuild`).

## Pipelines

- **`ci.yml`** (sur PR et main) : format → analyze → build_runner → tests
  unitaires + widget → couverture.
- **`release.yml`** (sur tag `v*`) : build `appbundle` signé → upload
  Play Console (track internal) ; build IPA → TestFlight.

## Checklist de mise en production

1. Vérification des scopes OAuth en revue Google (restricted scopes Gmail →
   CASA security assessment requis) et Microsoft (publisher verification).
2. Politique de confidentialité publiée (analyse 100 % locale, pas de vente
   de données) — exigée par les deux stores et par l'API Gmail.
3. Export compliance iOS : chiffrement standard (exempt, catégorie 5D992).
4. Tests sur appareils physiques : biométrie, deep links OAuth, IDLE IMAP
   en arrière-plan.
5. Montée progressive : internal → closed testing → production 10 % → 100 %.
