// ignore_for_file: file_names
import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:lyon1mail/src/model/address.dart';
import 'package:enough_mail/enough_mail.dart' hide Response;
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';

import 'model/mail.dart';
import 'config/config.dart';

class Lyon1Mail {
  late ImapClient _client;
  late String _username;
  late String _password;
  late int _nbMessages;
  late String _mailboxName;
  Dio _dio = Dio();
  CookieJar _cookieJar = CookieJar();

  static const String _baseUrl = "https://mail.univ-lyon1.fr/owa/";
  static const String _loginUrl = _baseUrl + "auth.owa";
  static const String _contactUrl = _baseUrl + "service.svc?action=FindPeople";

  Lyon1Mail(final String username, final String password) {
    _client = ImapClient(isLogEnabled: false);
    _username = username;
    _password = password;
    _dio.interceptors.add(CookieManager(_cookieJar));
  }

  Future<bool> login() async {
    await _client.connectToServer(
        Lyon1MailConfig.imapHost, Lyon1MailConfig.imapPort,
        isSecure: Lyon1MailConfig.imapSecure);

    await _client.login(_username, _password);

    await _cookieJar.deleteAll();
    var headers = {
      'User-Agent':
          'Mozilla/5.0 (X11; Linux x86_64; rv:105.0) Gecko/20100101 Firefox/105.0',
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
      'Accept-Language': 'fr,fr-FR;q=0.8,en-US;q=0.5,en;q=0.3',
      'Accept-Encoding': 'gzip, deflate, br',
      'Content-Type': 'application/x-www-form-urlencoded',
      'Origin': 'https://mail.univ-lyon1.fr',
      'Connection': 'keep-alive',
      'Referer':
          'https://mail.univ-lyon1.fr/owa/auth/logon.aspx?replaceCurrent=1&url=https%3a%2f%2fmail.univ-lyon1.fr%2fowa',
      'Upgrade-Insecure-Requests': '1',
      'Sec-Fetch-Dest': 'document',
      'Sec-Fetch-Mode': 'navigate',
      'Sec-Fetch-Site': 'same-origin',
      'Sec-Fetch-User': '?1',
    };
    Response reponse = await _dio.post(
      _loginUrl,
      data: {
        "destination":
            _baseUrl.substring(0, _baseUrl.length - 1), // remove trailing slash
        "flags": "4",
        "forcedownlevel": "0",
        "username": _username,
        "password": _password,
        "passwordText": "",
        "isUtf8": "1"
      },
      options: Options(
          validateStatus: ((status) => status == 302),
          contentType: "application/x-www-form-urlencoded"),
    );
    print(await _cookieJar.loadForRequest(Uri.parse(_baseUrl)));
    try {
      reponse = await _dio.get(
        _baseUrl,
      );
      print(reponse.headers);
    } on DioError catch (e) {
      print(e);
    }

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

  Future<String> resolveContact(String query) async {
    String json =
        '{"__type":"FindPeopleJsonRequest:#Exchange","Header":{"__type":"JsonRequestHeaders:#Exchange","RequestServerVersion":"Exchange2013","TimeZoneContext":{"__type":"TimeZoneContext:#Exchange","TimeZoneDefinition":{"__type":"TimeZoneDefinitionType:#Exchange","Id":"Romance Standard Time"}}},"Body":{"__type":"FindPeopleRequest:#Exchange","IndexedPageItemView":{"__type":"IndexedPageView:#Exchange","BasePoint":"Beginning","Offset":0},"QueryString":"$query","AggregationRestriction":{"__type":"RestrictionType:#Exchange","Item":{"__type":"Or:#Exchange","Items":[{"__type":"Exists:#Exchange","Item":{"__type":"PropertyUri:#Exchange","FieldURI":"PersonaEmailAddress"}},{"__type":"IsEqualTo:#Exchange","Item":{"__type":"PropertyUri:#Exchange","FieldURI":"PersonaType"},"FieldURIOrConstant":{"__type":"FieldURIOrConstantType:#Exchange","Item":{"__type":"Constant:#Exchange","Value":"DistributionList"}}}]}},"PersonaShape":{"__type":"PersonaResponseShape:#Exchange","BaseShape":"Default","AdditionalProperties":[{"__type":"PropertyUri:#Exchange","FieldURI":"PersonaAttributions"}]},"ShouldResolveOneOffEmailAddress":true,"SearchPeopleSuggestionIndex":false,"Context":[{"__type":"ContextProperty:#Exchange","Key":"AppName","Value":"OWA"},{"__type":"ContextProperty:#Exchange","Key":"AppScenario","Value":"NewMail.To"},{"__type":"ContextProperty:#Exchange","Key":"ClientSessionId","Value":""}]}}';
    Map<String, String> headers = {
      'User-Agent':
          'Mozilla/5.0 (X11; Linux x86_64; rv:105.0) Gecko/20100101 Firefox/105.0',
      'Accept': '*/*',
      'Action': 'FindPeople',
      'Origin': 'https://mail.univ-lyon1.fr',
      'Accept-Language': 'fr,fr-FR;q=0.8,en-US;q=0.5,en;q=0.3',
      'Accept-Encoding': 'gzip, deflate, br',
      'Content-Type': 'application/json; charset=utf-8',
      'X-Requested-With': 'XMLHttpRequest',
      'X-OWA-ActionName': 'ComposeForms',
      'X-OWA-CANARY': (await _cookieJar.loadForRequest(Uri.parse(_baseUrl)))
          .where((element) => element.name == 'X-OWA-CANARY')
          .first
          .value,
      'Cookie': (await _cookieJar.loadForRequest(Uri.parse(_baseUrl)))
          .map((e) => e.value + "; ")
          .toString()
          .replaceAll("(", "")
          .replaceAll(")", ""),
      // 'X-OWA-CANARY':
      //     'byLRE7qKHUqDTB90N9k5H6AQ-dgGo9oIMFy1JBbKZmT2n17RRMFZaCXKlV2QqWG2G2-vtU8CltE.',
      // 'Cookie':
      //     'X-BackEndCookie=S-1-5-21-1644491937-813497703-1060284298-2231958=u56Lnp2ejJqBm8rHys3HnpvSnsuextLLxsqc0p7Gz8vSnsbOm8aZy8qbzZnMgYHNz83N0s7P0szPq87Ixc7OxcvM; tarteaucitron=!addthis=true; ClientId=F57F75FD17B14CF988F43004C5F0E200; X-OWA-JS-PSD=1; PrivateComputer=true; PBack=0; AppcacheVer=15.2.986.29:fr-frbase; cadata=PGVNxhKvlIuyDUJT5ycn/oUYY1onedFy9oae4uX0GULQK9C72PsKcBVAI7/3kdnD9/5PLQ9I5llJlfWfAFGnue6TUoKLB3jCcDAhXKJd37LazKWA6h2ReN+nhF+4vyLw6BXim9C7Q2rj/YmQogb7wA==; cadataTTL=slivx8OTnlcViQvBSkrCXA==; cadataKey=jVDhG7xkQc573NE6wmGQM9yh4Cerbpa38PgwMqHYWCbrG/RqFc/aDDmtTx+H3yjqvsNzdxm8FaNJEJ3mx8S9JbFbrSTcrt1+Id8Uef7g4hNM0eR51rH2ZYCEG4QKW+gLzZesdhOXf0qn3pK/U6bmB/ZVpVDph3BP5RTvSBYjf4aDDv+Sx/HrBasEistbT+ENBahCXl0MdiYKQXplO5p512xfdf2NPio5wL6AnWmFhwmqYoduYTlb74s4DIbdgxmrPNIPqMKXlbCcxkqSJre7Z0X/EEKZF+Vn4pffgQlcCadBGnJFLSzjCcwwvazVO1qpGKGC9rvb8zlk78pwgBxvKw==; cadataIV=Ssp2mEFrUG8EfIK2q9HtM7ffNug7uzNMgpWkX+W4IjvMDMr0Qm53n9gTmOLb+EfsK2pAsEhR4tFqflpGP5At7B5w8K83m5Dve//myArFUHqe56n382tG9Etd7JEff2CCbiMcp/L/wGTqFoEhGBv05Dsu/31fUCGh4ayeECD7jMoiwa8eBcK/nOTGPQ5bZHXsUvQQxZ7cvwZZunkI4SWkvzveIL2C5ufbF5iXSa1VQUI6ryzQQXDkj2O9L2bXVJeLIRRT12gPCx36AUMxVE0gHp8YSuhQWECl5sGMCI2esIPIvMDar7xXJDckfq7CLcTiI6JjdrEs+7PIYSLxSiZ7og==; cadataSig=yxtTjkCepTxob47xGAmtyPyh2vLH/VOQyosCOY8R44U=; UC=c36563a5422f4778854aca4f3913338b; X-OWA-CANARY=byLRE7qKHUqDTB90N9k5H6AQ-dgGo9oIMFy1JBbKZmT2n17RRMFZaCXKlV2QqWG2G2-vtU8CltE.; offline=0; IsClientAppCacheEnabled=true',
      // 'Cookie': _cookies,
    };

    var url = Uri.parse(_contactUrl);
    var data =
        '{"__type":"FindPeopleJsonRequest:#Exchange","Header":{"__type":"JsonRequestHeaders:#Exchange","RequestServerVersion":"Exchange2013","TimeZoneContext":{"__type":"TimeZoneContext:#Exchange","TimeZoneDefinition":{"__type":"TimeZoneDefinitionType:#Exchange","Id":"Romance Standard Time"}}},"Body":{"__type":"FindPeopleRequest:#Exchange","IndexedPageItemView":{"__type":"IndexedPageView:#Exchange","BasePoint":"Beginning","Offset":0},"QueryString":"' +
            query +
            '","AggregationRestriction":{"__type":"RestrictionType:#Exchange","Item":{"__type":"Or:#Exchange","Items":[{"__type":"Exists:#Exchange","Item":{"__type":"PropertyUri:#Exchange","FieldURI":"PersonaEmailAddress"}},{"__type":"IsEqualTo:#Exchange","Item":{"__type":"PropertyUri:#Exchange","FieldURI":"PersonaType"},"FieldURIOrConstant":{"__type":"FieldURIOrConstantType:#Exchange","Item":{"__type":"Constant:#Exchange","Value":"DistributionList"}}}]}},"PersonaShape":{"__type":"PersonaResponseShape:#Exchange","BaseShape":"Default","AdditionalProperties":[{"__type":"PropertyUri:#Exchange","FieldURI":"PersonaAttributions"}]},"ShouldResolveOneOffEmailAddress":true,"SearchPeopleSuggestionIndex":false,"Context":[{"__type":"ContextProperty:#Exchange","Key":"AppName","Value":"OWA"},{"__type":"ContextProperty:#Exchange","Key":"AppScenario","Value":"NewMail.To"},{"__type":"ContextProperty:#Exchange","Key":"ClientSessionId","Value":""}]}}';
    http.Response response = await http.post(url, headers: headers, body: data);
    print(response.body);
    print(response.statusCode);
    print((await _cookieJar.loadForRequest(Uri.parse(_baseUrl)))
        .map((e) => e.value + "; ")
        .toString());
    print(await _cookieJar.loadForRequest(Uri.parse(_baseUrl)));
    Response response2 = await _dio.post(_contactUrl,
        data: json,
        options: Options(
          headers: headers,
          contentType: "utf8",
          validateStatus: (status) => true,
        ));
    print(response.body);

    return "error";
  }

  int get nbMessage => _nbMessages;
  String get mailboxName => _mailboxName;
  bool get isAuthenticated => _client.isLoggedIn;
}
