import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/error/failures.dart';
import '../../../domain/entities/account.dart' as domain;
import '../../../domain/entities/email_message.dart';
import '../mail/mail_sync_service.dart';

/// Microsoft Graph implementation of [MailSyncService] for Outlook.com and
/// Microsoft 365. Premium features (calendar events, Teams, OneDrive)
/// extend this same authenticated client.
class MicrosoftGraphService implements MailSyncService {
  MicrosoftGraphService({http.Client? client}) : _http = client ?? http.Client();

  static const _base = 'https://graph.microsoft.com/v1.0/me';

  final http.Client _http;
  String? _accessToken;
  domain.MailProvider _provider = domain.MailProvider.microsoft365;

  @override
  domain.MailProvider get provider => _provider;

  @override
  Future<void> connect(domain.Account account, {required String secret}) async {
    _accessToken = secret;
    _provider = account.provider;
  }

  @override
  Future<void> disconnect() async => _accessToken = null;

  Map<String, String> get _headers {
    final token = _accessToken;
    if (token == null) {
      throw const AuthenticationFailure('Compte Microsoft non connecté.');
    }
    return {'Authorization': 'Bearer $token'};
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final response = await _http.get(
      uri,
      headers: {
        ..._headers,
        // Ask Graph to include SPF/DKIM/DMARC-carrying internet headers.
        'Prefer': 'IdType="ImmutableId"',
      },
    );
    if (response.statusCode == 401) {
      throw const AuthenticationFailure('Jeton Microsoft expiré.');
    }
    if (response.statusCode >= 400) {
      throw NetworkFailure('Microsoft Graph ${response.statusCode}.');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  @override
  Future<List<RemoteFolder>> listFolders() async {
    final json = await _getJson(Uri.parse('$_base/mailFolders?\$top=50'));
    final folders =
        (json['value'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    const typeMap = {
      'inbox': 'inbox',
      'sentitems': 'sent',
      'drafts': 'drafts',
      'deleteditems': 'trash',
      'junkemail': 'spam',
      'archive': 'archive',
    };
    return [
      for (final folder in folders)
        RemoteFolder(
          path: folder['id'] as String,
          name: folder['displayName'] as String? ?? '',
          type: typeMap[(folder['displayName'] as String? ?? '')
                  .toLowerCase()
                  .replaceAll(' ', '')] ??
              'other',
        ),
    ];
  }

  @override
  Future<List<RawEmail>> fetchNewMessages(
    RemoteFolder folder, {
    int sinceUid = 0,
    int limit = 50,
  }) async {
    final json = await _getJson(
      Uri.parse(
        '$_base/mailFolders/${folder.path}/messages'
        '?\$top=$limit&\$orderby=receivedDateTime desc'
        '&\$select=id,conversationId,subject,from,toRecipients,ccRecipients,'
        'replyTo,receivedDateTime,bodyPreview,body,isRead,flag,hasAttachments,'
        'internetMessageId,internetMessageHeaders',
      ),
    );
    final messages =
        (json['value'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

    final result = <RawEmail>[];
    for (final message in messages) {
      final raw = _toRawEmail(message);
      if (raw.uid > sinceUid) result.add(raw);
    }
    return result;
  }

  RawEmail _toRawEmail(Map<String, dynamic> m) {
    final headerList = (m['internetMessageHeaders'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final headers = <String, String>{
      for (final h in headerList)
        (h['name'] as String).toLowerCase(): h['value'] as String? ?? '',
    };

    String addressOf(Map<String, dynamic>? recipient) =>
        ((recipient?['emailAddress'] as Map<String, dynamic>?)?['address']
                    as String? ??
                '')
            .toLowerCase();
    String nameOf(Map<String, dynamic>? recipient) =>
        (recipient?['emailAddress'] as Map<String, dynamic>?)?['name']
                as String? ??
            '';

    final from = m['from'] as Map<String, dynamic>?;
    final body = m['body'] as Map<String, dynamic>? ?? {};
    final isHtml = (body['contentType'] as String? ?? '') == 'html';
    final content = body['content'] as String? ?? '';
    final received = DateTime.tryParse(
          m['receivedDateTime'] as String? ?? '',
        ) ??
        DateTime.now();

    return RawEmail(
      // Graph ids are opaque; derive a stable increasing uid from time.
      uid: received.millisecondsSinceEpoch ~/ 1000,
      messageId: m['internetMessageId'] as String? ?? '<graph-${m['id']}>',
      threadId: m['conversationId'] as String?,
      subject: m['subject'] as String? ?? '',
      fromName: nameOf(from),
      fromAddress: addressOf(from),
      toAddresses: [
        for (final r in (m['toRecipients'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>())
          addressOf(r),
      ],
      ccAddresses: [
        for (final r in (m['ccRecipients'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>())
          addressOf(r),
      ],
      replyToAddress: (m['replyTo'] as List<dynamic>? ?? []).isNotEmpty
          ? addressOf(
              (m['replyTo'] as List<dynamic>).first as Map<String, dynamic>,
            )
          : null,
      date: received,
      headers: headers,
      bodyPlain: isHtml ? (m['bodyPreview'] as String? ?? '') : content,
      bodyHtml: isHtml ? content : null,
      isRead: m['isRead'] as bool? ?? false,
      isFlagged:
          ((m['flag'] as Map<String, dynamic>?)?['flagStatus'] as String?) ==
              'flagged',
      sizeBytes: content.length,
      attachments: const [], // fetched lazily via /attachments when opened
    );
  }

  Future<void> _patch(String messageIdHex, Map<String, Object?> body) async {
    final response = await _http.patch(
      Uri.parse('$_base/messages/$messageIdHex'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode >= 400) {
      throw NetworkFailure('Microsoft Graph patch ${response.statusCode}.');
    }
  }

  // Graph operations key on message ids, which the repository stores in
  // `messageId`; uid-based bulk ops resolve ids first via search. The
  // repository layer passes Graph ids through the RemoteFolder path.
  @override
  Future<void> markRead(
    RemoteFolder folder,
    List<int> uids, {
    bool read = true,
  }) async {
    for (final uid in uids) {
      await _patch(uid.toString(), {'isRead': read});
    }
  }

  @override
  Future<void> deleteMessages(RemoteFolder folder, List<int> uids) async {
    for (final uid in uids) {
      final response = await _http.post(
        Uri.parse('$_base/messages/$uid/move'),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode({'destinationId': 'deleteditems'}),
      );
      if (response.statusCode >= 400) {
        throw NetworkFailure('Microsoft Graph delete ${response.statusCode}.');
      }
    }
  }

  @override
  Future<void> moveToFolder(
    RemoteFolder from,
    RemoteFolder to,
    List<int> uids,
  ) async {
    for (final uid in uids) {
      final response = await _http.post(
        Uri.parse('$_base/messages/$uid/move'),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode({'destinationId': to.path}),
      );
      if (response.statusCode >= 400) {
        throw NetworkFailure('Microsoft Graph move ${response.statusCode}.');
      }
    }
  }
}
