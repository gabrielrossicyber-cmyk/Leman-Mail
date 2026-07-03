import 'package:drift/drift.dart';

import '../app_database.dart';

part 'accounts_dao.g.dart';

@DriftAccessor(tables: [Accounts, Folders])
class AccountsDao extends DatabaseAccessor<AppDatabase>
    with _$AccountsDaoMixin {
  AccountsDao(super.db);

  Stream<List<Account>> watchAll() =>
      (select(accounts)..orderBy([(a) => OrderingTerm.asc(a.createdAt)]))
          .watch();

  Future<List<Account>> getEnabled() =>
      (select(accounts)..where((a) => a.isEnabled.equals(true))).get();

  Future<Account?> getByUuid(String uuid) =>
      (select(accounts)..where((a) => a.uuid.equals(uuid))).getSingleOrNull();

  Future<int> insertAccount(AccountsCompanion account) =>
      into(accounts).insert(account);

  Future<void> updateLastSync(int accountId, DateTime at) =>
      (update(accounts)..where((a) => a.id.equals(accountId)))
          .write(AccountsCompanion(lastSyncAt: Value(at)));

  Future<void> setMfaEnabled(int accountId, bool enabled) =>
      (update(accounts)..where((a) => a.id.equals(accountId)))
          .write(AccountsCompanion(mfaEnabled: Value(enabled)));

  /// Cascades to folders, emails, attachments, sync states.
  Future<void> deleteAccount(int accountId) =>
      (delete(accounts)..where((a) => a.id.equals(accountId))).go();

  /// Upsert keyed on (accountId, path). Done manually rather than via
  /// `insertOnConflictUpdate` because the returned row id must be reliable
  /// on the update path — emails reference it as a foreign key.
  Future<int> upsertFolder(FoldersCompanion folder) async {
    final existing = await (select(folders)
          ..where(
            (f) =>
                f.accountId.equals(folder.accountId.value) &
                f.path.equals(folder.path.value),
          ))
        .getSingleOrNull();
    if (existing != null) {
      await (update(folders)..where((f) => f.id.equals(existing.id)))
          .write(folder);
      return existing.id;
    }
    return into(folders).insert(folder);
  }

  Future<List<Folder>> foldersOf(int accountId) =>
      (select(folders)..where((f) => f.accountId.equals(accountId))).get();
}
