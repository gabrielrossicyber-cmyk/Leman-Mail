import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/security/secure_storage_service.dart';
import '../../domain/entities/account.dart' as domain;
import '../../domain/repositories/account_repository.dart';
import '../database/app_database.dart';

class AccountRepositoryImpl implements AccountRepository {
  AccountRepositoryImpl(this._db, this._secureStorage);

  final AppDatabase _db;
  final SecureStorageService _secureStorage;

  @override
  Stream<List<domain.Account>> watchAccounts() =>
      _db.accountsDao.watchAll().map((rows) => rows.map(_toEntity).toList());

  @override
  Future<List<domain.Account>> enabledAccounts() async =>
      (await _db.accountsDao.getEnabled()).map(_toEntity).toList();

  @override
  Future<domain.Account> addAccount({
    required domain.Account draft,
    required AccountCredentials credentials,
  }) async {
    final uuid = draft.uuid.isEmpty ? const Uuid().v4() : draft.uuid;

    await _secureStorage.writeAccountSecret(
      uuid,
      jsonEncode({
        'password': credentials.password,
        'accessToken': credentials.accessToken,
        'refreshToken': credentials.refreshToken,
        'tokenExpiry': credentials.tokenExpiry?.toIso8601String(),
      }),
    );

    final id = await _db.accountsDao.insertAccount(
      AccountsCompanion.insert(
        uuid: uuid,
        email: draft.email,
        displayName: draft.displayName,
        provider: draft.provider,
        authMethod: draft.authMethod,
        imapHost: Value(draft.imapHost),
        imapPort: Value(draft.imapPort),
        imapTls: Value(draft.imapTls),
        smtpHost: Value(draft.smtpHost),
        smtpPort: Value(draft.smtpPort),
        smtpTls: Value(draft.smtpTls),
        colorValue: Value(draft.colorValue),
        mfaEnabled: Value(draft.mfaEnabled || draft.usesOAuth),
      ),
    );

    return domain.Account(
      id: id,
      uuid: uuid,
      email: draft.email,
      displayName: draft.displayName,
      provider: draft.provider,
      authMethod: draft.authMethod,
      imapHost: draft.imapHost,
      imapPort: draft.imapPort,
      imapTls: draft.imapTls,
      smtpHost: draft.smtpHost,
      smtpPort: draft.smtpPort,
      smtpTls: draft.smtpTls,
      colorValue: draft.colorValue,
      mfaEnabled: draft.mfaEnabled || draft.usesOAuth,
    );
  }

  @override
  Future<AccountCredentials?> credentialsOf(String accountUuid) async {
    final raw = await _secureStorage.readAccountSecret(accountUuid);
    if (raw == null) return null;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return AccountCredentials(
      password: json['password'] as String?,
      accessToken: json['accessToken'] as String?,
      refreshToken: json['refreshToken'] as String?,
      tokenExpiry: json['tokenExpiry'] != null
          ? DateTime.tryParse(json['tokenExpiry'] as String)
          : null,
    );
  }

  @override
  Future<void> updateCredentials(
    String accountUuid,
    AccountCredentials credentials,
  ) =>
      _secureStorage.writeAccountSecret(
        accountUuid,
        jsonEncode({
          'password': credentials.password,
          'accessToken': credentials.accessToken,
          'refreshToken': credentials.refreshToken,
          'tokenExpiry': credentials.tokenExpiry?.toIso8601String(),
        }),
      );

  @override
  Future<void> removeAccount(domain.Account account) async {
    await _secureStorage.deleteAccountSecret(account.uuid);
    await _db.accountsDao.deleteAccount(account.id);
  }

  @override
  Future<void> setMfaEnabled(domain.Account account, bool enabled) =>
      _db.accountsDao.setMfaEnabled(account.id, enabled);

  static domain.Account _toEntity(Account row) => domain.Account(
        id: row.id,
        uuid: row.uuid,
        email: row.email,
        displayName: row.displayName,
        provider: row.provider,
        authMethod: row.authMethod,
        imapHost: row.imapHost,
        imapPort: row.imapPort,
        imapTls: row.imapTls,
        smtpHost: row.smtpHost,
        smtpPort: row.smtpPort,
        smtpTls: row.smtpTls,
        colorValue: row.colorValue,
        isEnabled: row.isEnabled,
        mfaEnabled: row.mfaEnabled,
        lastSyncAt: row.lastSyncAt,
      );
}
