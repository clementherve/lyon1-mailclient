import 'dart:io';

import 'package:lyon1mail/lyon1mail.dart';
import 'package:test/test.dart';
import 'package:dotenv/dotenv.dart' show env, isEveryDefined, load;

void main() {
  late Lyon1Mail _mailClient;

  setUpAll(() {
    load('test/.env');

    String username = Platform.environment['username'] ?? "";
    String password = Platform.environment['password'] ?? "";
    if (isEveryDefined(['username', 'password'])) {
      username = env['username'] ?? "";
      password = env['password'] ?? "";
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
    expect(mails.length, equals(10));
    await _mailClient.logout();
  });

  test('fetch 10 messages without being logged in', () async {
    expect((await _mailClient.fetchMessages(10)).isNone(), equals(true));
  });
}
