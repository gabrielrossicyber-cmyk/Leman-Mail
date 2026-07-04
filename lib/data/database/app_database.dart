import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../domain/entities/account.dart';
import '../../domain/entities/email_message.dart';
import '../../domain/entities/newsletter_sender.dart';
import '../../domain/entities/security_recommendation.dart';
import 'daos/accounts_dao.dart';
import 'daos/emails_dao.dart';
import 'daos/health_dao.dart';
import 'daos/newsletters_dao.dart';

part 'app_database.g.dart';

// ---------------------------------------------------------------------------
// Tables — see docs/DATA_MODEL.md for the full column documentation.
// ---------------------------------------------------------------------------

class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().unique()();
  TextColumn get email => text()();
  TextColumn get displayName => text()();
  TextColumn get provider => textEnum<MailProvider>()();
  TextColumn get authMethod => textEnum<AuthMethod>()();
  TextColumn get imapHost => text().nullable()();
  IntColumn get imapPort => integer().withDefault(const Constant(993))();
  BoolColumn get imapTls => boolean().withDefault(const Constant(true))();
  TextColumn get smtpHost => text().nullable()();
  IntColumn get smtpPort => integer().withDefault(const Constant(465))();
  BoolColumn get smtpTls => boolean().withDefault(const Constant(true))();
  IntColumn get colorValue => integer().withDefault(const Constant(0xFF551112))();
  BoolColumn get isEnabled => boolean().withDefault(const Constant(true))();
  BoolColumn get mfaEnabled => boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastSyncAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class Folders extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get accountId =>
      integer().references(Accounts, #id, onDelete: KeyAction.cascade)();
  TextColumn get path => text()();
  TextColumn get name => text()();
  TextColumn get type => text().withDefault(const Constant('other'))();
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();
  IntColumn get totalCount => integer().withDefault(const Constant(0))();

  @override
  List<Set<Column>> get uniqueKeys => [
        {accountId, path},
      ];
}

class Emails extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get accountId =>
      integer().references(Accounts, #id, onDelete: KeyAction.cascade)();
  IntColumn get folderId =>
      integer().references(Folders, #id, onDelete: KeyAction.cascade)();
  IntColumn get uid => integer()();
  TextColumn get messageId => text()();
  TextColumn get threadId => text().nullable()();
  TextColumn get subject => text().withDefault(const Constant(''))();
  TextColumn get fromName => text().withDefault(const Constant(''))();
  TextColumn get fromAddress => text()();
  TextColumn get toAddresses => text().withDefault(const Constant('[]'))();
  TextColumn get ccAddresses => text().withDefault(const Constant('[]'))();
  DateTimeColumn get date => dateTime()();
  TextColumn get snippet => text().withDefault(const Constant(''))();

  /// AES-256-GCM record: nonce || ciphertext || mac (see CryptoService).
  BlobColumn get bodyEncrypted => blob().nullable()();
  BoolColumn get bodyIsHtml => boolean().withDefault(const Constant(false))();
  BoolColumn get isRead => boolean().withDefault(const Constant(false))();
  BoolColumn get isFlagged => boolean().withDefault(const Constant(false))();
  BoolColumn get isAnswered => boolean().withDefault(const Constant(false))();
  BoolColumn get hasAttachments => boolean().withDefault(const Constant(false))();
  IntColumn get sizeBytes => integer().withDefault(const Constant(0))();

  // Authentication results.
  TextColumn get spf => textEnum<AuthResult>().withDefault(const Constant('unknown'))();
  TextColumn get dkim => textEnum<AuthResult>().withDefault(const Constant('unknown'))();
  TextColumn get dmarc => textEnum<AuthResult>().withDefault(const Constant('unknown'))();

  // Anti-phishing verdict (denormalized for dashboard queries).
  IntColumn get phishingScore => integer().withDefault(const Constant(0))();
  TextColumn get phishingLevel =>
      textEnum<RiskLevel>().withDefault(const Constant('low'))();
  TextColumn get phishingFindings => text().withDefault(const Constant('[]'))();

  // Privacy scan.
  IntColumn get trackerCount => integer().withDefault(const Constant(0))();
  IntColumn get externalResourceCount => integer().withDefault(const Constant(0))();
  IntColumn get privacyScore => integer().withDefault(const Constant(100))();

  // Newsletter detection.
  BoolColumn get isNewsletter => boolean().withDefault(const Constant(false))();
  TextColumn get unsubscribeUrl => text().nullable()();
  TextColumn get unsubscribeMailto => text().nullable()();
  BoolColumn get listUnsubscribePost =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get analyzedAt => dateTime().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {accountId, folderId, uid},
      ];
}

class Attachments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get emailId =>
      integer().references(Emails, #id, onDelete: KeyAction.cascade)();
  TextColumn get fileName => text()();
  TextColumn get mimeType => text()();
  IntColumn get sizeBytes => integer().withDefault(const Constant(0))();
  BoolColumn get isDangerous => boolean().withDefault(const Constant(false))();
  TextColumn get localPath => text().nullable()();
}

class NewsletterSenders extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get accountId =>
      integer().references(Accounts, #id, onDelete: KeyAction.cascade)();
  TextColumn get senderAddress => text()();
  TextColumn get senderName => text().withDefault(const Constant(''))();
  IntColumn get emailCount => integer().withDefault(const Constant(0))();
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();
  IntColumn get totalSizeBytes => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastEmailAt => dateTime()();
  TextColumn get unsubscribeUrl => text().nullable()();
  TextColumn get unsubscribeMailto => text().nullable()();
  BoolColumn get supportsOneClick =>
      boolean().withDefault(const Constant(false))();
  TextColumn get status =>
      textEnum<NewsletterStatus>().withDefault(const Constant('active'))();

  @override
  List<Set<Column>> get uniqueKeys => [
        {accountId, senderAddress},
      ];
}

class BlockedSenders extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Exact address or `*@domain.tld`.
  TextColumn get pattern => text().unique()();
  TextColumn get reason => text().withDefault(const Constant('manual'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class HealthSnapshots extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Null = global (all accounts combined).
  IntColumn get accountId => integer()
      .nullable()
      .references(Accounts, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get day => dateTime()();
  IntColumn get totalScore => integer()();
  IntColumn get securityScore => integer()();
  IntColumn get clutterScore => integer()();
  IntColumn get privacyScore => integer()();
  IntColumn get organizationScore => integer()();
  TextColumn get detailsJson => text().withDefault(const Constant('{}'))();

  @override
  List<Set<Column>> get uniqueKeys => [
        {accountId, day},
      ];
}

class SecurityRecommendations extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get code => text().unique()();
  TextColumn get accountUuid => text().nullable()();
  IntColumn get points => integer()();
  TextColumn get status =>
      textEnum<RecommendationStatus>().withDefault(const Constant('open'))();
  DateTimeColumn get completedAt => dateTime().nullable()();
}

class Badges extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get badgeId => text().unique()();
  DateTimeColumn get unlockedAt => dateTime().withDefault(currentDateAndTime)();
}

class SyncStates extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get accountId =>
      integer().references(Accounts, #id, onDelete: KeyAction.cascade)();
  IntColumn get folderId => integer()
      .nullable()
      .references(Folders, #id, onDelete: KeyAction.cascade)();
  IntColumn get uidValidity => integer().nullable()();
  IntColumn get lastUid => integer().nullable()();

  /// Gmail `historyId` or Microsoft Graph `deltaLink`.
  TextColumn get cursor => text().nullable()();
  DateTimeColumn get lastSyncAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
        {accountId, folderId},
      ];
}

// ---------------------------------------------------------------------------
// Database
// ---------------------------------------------------------------------------

@DriftDatabase(
  tables: [
    Accounts,
    Folders,
    Emails,
    Attachments,
    NewsletterSenders,
    BlockedSenders,
    HealthSnapshots,
    SecurityRecommendations,
    Badges,
    SyncStates,
  ],
  daos: [AccountsDao, EmailsDao, NewslettersDao, HealthDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// For tests: `AppDatabase.forTesting(NativeDatabase.memory())`.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await customStatement(
            'CREATE INDEX idx_emails_date ON emails (date DESC)',
          );
          await customStatement(
            'CREATE INDEX idx_emails_from ON emails (from_address)',
          );
          await customStatement(
            'CREATE INDEX idx_emails_flags ON emails (is_read, is_newsletter, phishing_level)',
          );
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  static QueryExecutor _openConnection() =>
      driftDatabase(name: 'leman_mail');
}
