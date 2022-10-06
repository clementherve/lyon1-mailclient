import 'dart:io';

import 'package:lyon1mail/lyon1mail.dart';
import 'package:test/test.dart';
import 'package:dotenv/dotenv.dart' show env, isEveryDefined, load;

void main() {
  late Lyon1Mail _mailClient;

  Future<void> sendDummyMail() async {
    await _mailClient.login();
    await _mailClient.sendEmail(
      sender: Address(env['email']!, 'nom de test'),
      recipients: [
        Address(env['email']!, 'nom de test 2'),
      ],
      subject: 'test',
      body: 'bodytest',
    );
  }

  late String username;
  late String password;
  late String emailAddress;
  setUpAll(() {
    load('test/.env');

    username = Platform.environment['username'] ?? "";
    password = Platform.environment['password'] ?? "";
    emailAddress = Platform.environment['email'] ?? "";
    if (isEveryDefined(['username', 'password', 'email'])) {
      username = env['username'] ?? "";
      password = env['password'] ?? "";
      emailAddress = env['email'] ?? "";

    }

    if (username.isEmpty || password.isEmpty) {
      fail("username or password were empty. check your envt variables");
    }

    _mailClient = Lyon1Mail(username, password);
  });

  test('login then logout', () async {
    await _mailClient.login();
    await _mailClient.logout();
  });

  test('fetchMessages 10 emails while being logged in', () async {
    await _mailClient.login();
    final List<Mail> mails =
        (await _mailClient.fetchMessages(10)).getOrElse(() => []);
    print(mails);
    expect(mails.length, equals(10));
    await _mailClient.logout();
  });

  test('fetch 10 messages without being logged in', () async {
    expect((await _mailClient.fetchMessages(10)).isNone(), equals(true));
  });

  test('toggle read status of latest email', () async {
    await _mailClient.login();
    final List<Mail> mails =
        (await _mailClient.fetchMessages(10)).getOrElse(() => []);

    final bool isFirstMailSeen = mails.first.isSeen();

    if (isFirstMailSeen) {
      await _mailClient.markAsUnread(mails.first.getSequenceId()!);
    } else {
      await _mailClient.markAsRead(mails.first.getSequenceId()!);
    }

    expect(
        (await _mailClient.fetchMessages(10))
            .getOrElse(() => [])
            .first
            .isSeen(),
        !isFirstMailSeen);

    await _mailClient.logout();
  });

  test('send one email to self', () async {
    await sendDummyMail();

    await _mailClient.login();
    final List<Mail> mailsBeforeDeletion =
        (await _mailClient.fetchMessages(1)).getOrElse(() => []);
    expect(mailsBeforeDeletion.isNotEmpty, true);

    final int latestMessageId = mailsBeforeDeletion.first.getSequenceId()!;
    await _mailClient.delete(latestMessageId);

    final List<Mail> mailsAfterDeletion =
        (await _mailClient.fetchMessages(1)).getOrElse(() => []);
    expect(mailsAfterDeletion.isNotEmpty, true);
    expect(mailsAfterDeletion.first.getSequenceId() != latestMessageId, true);
    await _mailClient.logout();
  });

  test('resolve contact', () async {
    await _mailClient.login();
    print("coucou");
    Address? email = (await _mailClient.resolveContact(username));
    print(email);
    expect(email!.email, emailAddress);
  });

  test('delete latest email', () async {
    await sendDummyMail(); // to make sure we dont delete important mails :)

    await _mailClient.login();
    final List<Mail> mailsBeforeDeletion =
        (await _mailClient.fetchMessages(1)).getOrElse(() => []);
    expect(mailsBeforeDeletion.isNotEmpty, true);

    final int latestMessageId = mailsBeforeDeletion.first.getSequenceId()!;
    await _mailClient.delete(latestMessageId);

    final List<Mail> mailsAfterDeletion =
        (await _mailClient.fetchMessages(1)).getOrElse(() => []);
    expect(mailsAfterDeletion.isNotEmpty, true);
    expect(mailsAfterDeletion.first.getSequenceId() != latestMessageId, true);
    await _mailClient.logout();
  });
}
