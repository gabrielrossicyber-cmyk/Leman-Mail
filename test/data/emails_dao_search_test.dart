import 'package:flutter_test/flutter_test.dart';
import 'package:leman_mail/data/database/daos/emails_dao.dart';

void main() {
  group('EmailsDao.buildMatchQuery', () {
    test('termes simples → phrases préfixées', () {
      expect(EmailsDao.buildMatchQuery('facture'), '"facture"*');
      expect(
        EmailsDao.buildMatchQuery('factur digi'),
        '"factur"* "digi"*',
      );
    });

    test('neutralise la syntaxe FTS injectée', () {
      expect(
        EmailsDao.buildMatchQuery('subject:"hack" OR *'),
        '"subject"* "hack"* "OR"*',
      );
      expect(EmailsDao.buildMatchQuery('(a) ^b'), '"a"* "b"*');
    });

    test('entrée vide ou blanche → requête vide', () {
      expect(EmailsDao.buildMatchQuery(''), '');
      expect(EmailsDao.buildMatchQuery('   '), '');
      expect(EmailsDao.buildMatchQuery('"*^()'), '');
    });

    test('conserve les accents et adresses email', () {
      expect(EmailsDao.buildMatchQuery('réunion'), '"réunion"*');
      expect(
        EmailsDao.buildMatchQuery('contact@gabriel-rossi.ch'),
        '"contact@gabriel-rossi.ch"*',
      );
    });
  });
}
