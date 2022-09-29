// ignore_for_file: file_names
import 'package:dartz/dartz.dart';
import 'package:enough_mail/enough_mail.dart';
import 'package:lyon1mail/src/model/address.dart';

import 'model/mail.dart';
import 'config/config.dart';

class Lyon1Mail {
  late ImapClient _client;
  late String _username;
  late String _password;
  late int _nbMessages;
  late String _mailboxName;

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

    final SearchImapResult? unseenSearch =
        !unreadOnly ? null : await _client.searchMessages('UNSEEN');

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

  // TODO: autodiscover own email address
  Future<void> sendEmail({
    required Address sender,
    required List<Address> recipients,
    required String subject,
    required String body,
  }) async {
    await _client.selectInbox();

    final builder = MessageBuilder.prepareMultipartAlternativeMessage()
      ..subject = subject
      ..text = body
      ..from = [MailAddress(sender.name, sender.email)]
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

    final MessageSequence sequence = MessageSequence();
    sequence.add(id);
    _client.markSeen(sequence);
  }

  Future<void> markAsUnread(final int id) async {
    if (!_client.isLoggedIn) {
      return;
    }
    final MessageSequence sequence = MessageSequence();
    sequence.add(id);
    _client.markUnseen(sequence);
  }

  Future<void> logout() async {
    await _client.logout();
  }

  int get nbMessage => _nbMessages;
  String get mailboxName => _mailboxName;
  bool get isAuthenticated => _client.isLoggedIn;
}
