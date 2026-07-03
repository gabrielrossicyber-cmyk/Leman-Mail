import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/error/failures.dart';
import '../../../domain/entities/account.dart' as domain;
import '../../../domain/entities/email_message.dart';
import '../mail/mail_sync_service.dart';

/// Gmail REST implementation of [MailSyncService].
///
/// Uses the raw REST endpoints via `http` (lighter than the full
/// `googleapis` client for our narrow needs). Incremental sync relies on
/// `historyId` stored in `sync_states.cursor`; this class exposes the
/// page-based fetch used for both initial and catch-up syncs.
class GmailApiService implements MailSyncService {
  GmailApiService({http.Client? client}) : _http = client ?? http.Client();

  static const _base = 'https://gmail.googleapis.com/gmail/v1/users/me';

  final http.Client _http;
  String? _accessToken;

  @override
  domain.MailProvider get provider => domain.MailProvider.gmail;

  @override
  Future<void> connect(domain.Account account, {required String secret}) async {
    _accessToken = secret; // OAuth access token, refreshed by the caller.
  }

  @override
  Future<void> disconnect() async => _accessToken = null;

  Map<String, String> get _headers {
    final token = _accessToken;
    if (token == null) {
      throw const AuthenticationFailure('Compte Gmail non connecté.');
    }
    return {'Authorization': 'Bearer $token'};
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final response = await _http.get(uri, headers: _headers);
    if (response.statusCode == 401) {
      throw const AuthenticationFailure('Jeton Gmail expiré.');
    }
    if (response.statusCode >= 400) {
      throw NetworkFailure('Gmail API ${response.statusCode}.');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  @override
  Future<List<RemoteFolder>> listFolders() async {
    final json = await _getJson(Uri.parse('$_base/labels'));
    final labels = (json['labels'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    const typeMap = {
      'INBOX': 'inbox',
      'SENT': 'sent',
      'DRAFT': 'drafts',
      'TRASH': 'trash',
      'SPAM': 'spam',
    };
    return [
      for (final label in labels)
        if (label['type'] == 'system' &&
            typeMap.containsKey(label['id'] as String))
          RemoteFolder(
            path: label['id'] as String,
            name: label['name'] as String,
            type: typeMap[label['id'] as String]!,
          ),
    ];
  }

  @override
  Future<List<RawEmail>> fetchNewMessages(
    RemoteFolder folder, {
    int sinceUid = 0,
    int limit = 50,
  }) async {
    final list = await _getJson(
      Uri.parse('$_base/messages').replace(
        queryParameters: {
          'labelIds': folder.path,
          'maxResults': '$limit',
        },
      ),
    );
    final refs = (list['messages'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();

    final emails = <RawEmail>[];
    for (final ref in refs) {
      final id = ref['id'] as String;
      final uid = _uidFromHexId(id);
      if (uid <= sinceUid) continue;
      final full = await _getJson(
        Uri.parse('$_base/messages/$id?format=full'),
      );
      emails.add(_toRawEmail(full, uid));
    }
    return emails;
  }

  /// Gmail ids are hex strings that grow monotonically — usable as UID.
  static int _uidFromHexId(String id) =>
      int.tryParse(id, radix: 16) ?? id.hashCode.abs();

  RawEmail _toRawEmail(Map<String, dynamic> message, int uid) {
    final payload = message['payload'] as Map<String, dynamic>? ?? {};
    final headerList = (payload['headers'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final headers = <String, String>{
      for (final h in headerList)
        (h['name'] as String).toLowerCase(): h['value'] as String? ?? '',
    };

    final (fromName, fromAddress) = _parseAddress(headers['from'] ?? '');
    final labelIds =
        (message['labelIds'] as List<dynamic>? ?? []).cast<String>();

    String? bodyPlain;
    String? bodyHtml;
    final attachments = <EmailAttachmentInfo>[];
    _walkParts(payload, (part) {
      final mime = part['mimeType'] as String? ?? '';
      final filename = part['filename'] as String? ?? '';
      final body = part['body'] as Map<String, dynamic>? ?? {};
      if (filename.isNotEmpty) {
        attachments.add(
          EmailAttachmentInfo(
            fileName: filename,
            mimeType: mime,
            sizeBytes: (body['size'] as num?)?.toInt() ?? 0,
          ),
        );
      } else if (body['data'] != null) {
        final text = utf8.decode(
          base64Url.decode(_padBase64(body['data'] as String)),
          allowMalformed: true,
        );
        if (mime == 'text/plain') bodyPlain ??= text;
        if (mime == 'text/html') bodyHtml ??= text;
      }
    });

    return RawEmail(
      uid: uid,
      messageId: headers['message-id'] ?? '<gmail-${message['id']}>',
      threadId: message['threadId'] as String?,
      subject: headers['subject'] ?? '',
      fromName: fromName,
      fromAddress: fromAddress,
      toAddresses: _splitAddresses(headers['to']),
      ccAddresses: _splitAddresses(headers['cc']),
      replyToAddress: headers['reply-to'] != null
          ? _parseAddress(headers['reply-to']!).$2
          : null,
      date: DateTime.fromMillisecondsSinceEpoch(
        int.tryParse(message['internalDate'] as String? ?? '') ?? 0,
      ),
      headers: headers,
      bodyPlain: bodyPlain ?? (message['snippet'] as String? ?? ''),
      bodyHtml: bodyHtml,
      isRead: !labelIds.contains('UNREAD'),
      isFlagged: labelIds.contains('STARRED'),
      sizeBytes: (message['sizeEstimate'] as num?)?.toInt() ?? 0,
      attachments: attachments,
    );
  }

  static void _walkParts(
    Map<String, dynamic> part,
    void Function(Map<String, dynamic>) visit,
  ) {
    visit(part);
    for (final child
        in (part['parts'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>()) {
      _walkParts(child, visit);
    }
  }

  static String _padBase64(String input) =>
      input.padRight((input.length + 3) & ~3, '=');

  static (String, String) _parseAddress(String raw) {
    final match = RegExp(r'^\s*"?([^"<]*)"?\s*<([^>]+)>').firstMatch(raw);
    if (match != null) {
      return (match.group(1)!.trim(), match.group(2)!.trim().toLowerCase());
    }
    return ('', raw.trim().toLowerCase());
  }

  static List<String> _splitAddresses(String? raw) => raw == null
      ? const []
      : [for (final part in raw.split(',')) _parseAddress(part).$2];

  Future<void> _modifyLabels(
    List<int> uids, {
    List<String> add = const [],
    List<String> remove = const [],
  }) async {
    for (final uid in uids) {
      final id = uid.toRadixString(16);
      final response = await _http.post(
        Uri.parse('$_base/messages/$id/modify'),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode({'addLabelIds': add, 'removeLabelIds': remove}),
      );
      if (response.statusCode >= 400) {
        throw NetworkFailure('Gmail modify ${response.statusCode}.');
      }
    }
  }

  @override
  Future<void> markRead(
    RemoteFolder folder,
    List<int> uids, {
    bool read = true,
  }) =>
      _modifyLabels(
        uids,
        add: read ? const [] : const ['UNREAD'],
        remove: read ? const ['UNREAD'] : const [],
      );

  @override
  Future<void> deleteMessages(RemoteFolder folder, List<int> uids) =>
      _modifyLabels(uids, add: const ['TRASH'], remove: const ['INBOX']);

  @override
  Future<void> moveToFolder(
    RemoteFolder from,
    RemoteFolder to,
    List<int> uids,
  ) =>
      _modifyLabels(uids, add: [to.path], remove: [from.path]);
}
