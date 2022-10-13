// ignore_for_file: file_names, depend_on_referenced_packages

import 'package:dartz/dartz.dart';
import 'package:enough_mail/enough_mail.dart' hide Response;
import 'package:http/http.dart' show Response;
import 'package:lyon1mail/src/model/address.dart';
import 'package:lyon1mail/src/model/header_model.dart';
import 'package:lyon1mail/src/model/query_model.dart';
import 'package:requests/requests.dart';

import 'config/config.dart';
import 'model/mail.dart';

class Lyon1Mail {
  late ImapClient _client;
  late String _username;
  late String _password;
  late int _nbMessages;
  late String _mailboxName;
  late Address emailAddress;

  static const String _baseUrl = "https://mail.univ-lyon1.fr/owa/";
  static const String _loginUrl = "${_baseUrl}auth.owa";
  static const String _contactUrl = "${_baseUrl}service.svc?action=FindPeople";
  static const String _logoutUrl = "${_baseUrl}logoff.owa";

  Lyon1Mail(final String username, final String password) {
    _client = ImapClient(isLogEnabled: false);
    _username = username;
    _password = password;
  }

  Future<bool> login() async {
    await _client.connectToServer(
        Lyon1MailConfig.imapHost, Lyon1MailConfig.imapPort,
        isSecure: Lyon1MailConfig.imapSecure);

    await _client.login(_username, _password);

    await Requests.post(
      _loginUrl,
      headers: makeHeader(
        referer:
            'https://mail.univ-lyon1.fr/owa/auth/logon.aspx?replaceCurrent=1&url=https%3a%2f%2fmail.univ-lyon1.fr%2fowa',
        accept:
            'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
        connection: 'keep-alive',
        contentType: 'application/x-www-form-urlencoded',
      ),
      // headers: headers,
      body: {
        "destination":
            _baseUrl.substring(0, _baseUrl.length - 1), // remove trailing slash
        "flags": "4",
        "forcedownlevel": "0",
        "username": _username,
        "password": _password,
        "passwordText": "",
        "isUtf8": "1"
      },
    );
    await Requests.get(
      "https://mail.univ-lyon1.fr/owa/",
    ); //get canary cookies
    emailAddress = (await resolveContact(_username))!;
    return _client.isLoggedIn;
  }

  Future<Option<List<Mail>>> fetchMessages(
    final int end, {
    int? start,
    bool unreadOnly = false,
    bool hasAttachmentOnly = false,
  }) async {
    if (!_client.isLoggedIn) {
      return None();
    }

    final Mailbox mailbox = await _client.selectInbox();

    _mailboxName = mailbox.name;
    _nbMessages = mailbox.messagesExists;

    if (mailbox.messagesExists - end + 1 <= 0) {
      throw "Wrong number of message to fetch";
    }

    if (start != null) {
      if (start < 0 || start > mailbox.messagesExists - end + 1) {
        throw "Wrong number of message to fetch";
      }
    }

    final MessageSequence fetchSequence = MessageSequence();
    fetchSequence.addRange(mailbox.messagesExists - (start ?? 0),
        mailbox.messagesExists - end + 1);

    final SearchImapResult? unseenSearch = !unreadOnly
        ? null
        : await _client.searchMessages(searchCriteria: 'UNSEEN');

    final List<Mail> mails = [];
    final fetchResult = await _client.fetchMessages(
        unseenSearch?.matchingSequence ?? fetchSequence,
        '(FLAGS INTERNALDATE RFC822.SIZE ENVELOPE BODY.PEEK[])');

    for (final MimeMessage email in fetchResult.messages) {
      mails.add(Mail(email));
    }

    return Some(mails.reversed
        .where((mail) => mail.hasAttachments() || !hasAttachmentOnly)
        .toList());
  }

  Future<void> reply({
    Address? sender,
    bool replyAll = false,
    required int originalMessageId,
    required String subject,
    required String body,
  }) async {
    MimeMessage originalMessage = (await _client.fetchMessage(originalMessageId,
            '(FLAGS INTERNALDATE RFC822.SIZE ENVELOPE BODY.PEEK[])'))
        .messages
        .first;
    final builder = MessageBuilder.prepareReplyToMessage(
      originalMessage,
      originalMessage.from!.first,
      replyAll: replyAll,
      quoteOriginalText: true,
      replyToSimplifyReferences: true,
    )..from = [
        MailAddress((sender != null) ? sender.name : emailAddress.name,
            (sender != null) ? sender.email : emailAddress.email)
      ];
    builder.text = body + "\n\n" + (builder.text ?? "");
    await _client.appendMessage(builder.buildMimeMessage());
  }

  Future<void> sendEmail({
    Address? sender,
    required List<Address> recipients,
    required String subject,
    required String body,
  }) async {
    await _client.selectInbox();

    final builder = MessageBuilder.prepareMultipartAlternativeMessage()
      ..subject = subject
      ..text = body
      ..from = [
        MailAddress((sender != null) ? sender.name : emailAddress.name,
            (sender != null) ? sender.email : emailAddress.email)
      ]
      ..to = recipients.map((e) => MailAddress(e.name, e.email)).toList();

    await _client.appendMessage(builder.buildMimeMessage());
  }

  // untested yet
  Future<void> delete(final int id) async {
    if (!_client.isLoggedIn) {
      return;
    }
    final MessageSequence sequence = MessageSequence();
    sequence.add(id);
    _client.markDeleted(sequence);
    _client.expunge();
  }

  Future<void> markAsRead(final int id) async {
    if (!_client.isLoggedIn) {
      return;
    }
    await _client.selectInbox();
    final MessageSequence sequence = MessageSequence();
    sequence.add(id);
    _client.markSeen(sequence);
  }

  Future<void> markAsUnread(final int id) async {
    if (!_client.isLoggedIn) {
      return;
    }
    await _client.selectInbox();
    final MessageSequence sequence = MessageSequence();
    sequence.add(id);
    _client.markUnseen(sequence);
  }

  Future<Address?> resolveContact(String query) async {
    Iterable<Cookie> cookies =
        (await Requests.getStoredCookies(Requests.getHostname(_baseUrl)))
            .values;
    Response response = await Requests.post(
      _contactUrl,
      headers: makeHeader(
        canary: cookies.firstWhere((element) {
          return element.name == "X-OWA-CANARY";
        }).value,
        action: 'FindPeople',
      ),
      body: makeQuerry(query),
      bodyEncoding: RequestBodyEncoding.JSON,
    );
    if (response.json()['Body']['ResponseClass'] == "Success") {
      return Address(
          response.json()['Body']['ResultSet'].first['EmailAddress']
              ['EmailAddress'],
          response.json()['Body']['ResultSet'].first['GivenName'] +
              " " +
              response.json()['Body']['ResultSet'].first['Surname']);
    }
    return null;
  }

  Future<void> logout() async {
    await _client.logout();
    await Requests.get(_logoutUrl, headers: makeHeader());
  }

  int get nbMessage => _nbMessages;

  String get mailboxName => _mailboxName;

  bool get isAuthenticated => _client.isLoggedIn;
}
