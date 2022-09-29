import 'dart:math';

import 'package:enough_mail/imap/imap_client.dart';
import 'package:enough_mail/imap/message_sequence.dart';
import 'package:enough_mail/mail_address.dart';
import 'package:enough_mail/message_flags.dart';
import 'package:enough_mail/mime_message.dart';

class Mail {
  final ImapClient _client;
  final MimeMessage _originalMessage;

  Mail(this._client, this._originalMessage);

  String getSubject() {
    return _originalMessage.decodeSubject() ?? "";
  }

  List<String> getCC() {
    const List<String> cc = [];
    for (MailAddress m in _originalMessage.cc ?? []) {
      cc.add(m.email);
    }
    return cc;
  }

  String getSender() {
    return _originalMessage.fromEmail ?? "n/a";
  }

  String getReceiver() {
    return _originalMessage.to.toString() ?? "n/a";
  }

  DateTime getDate() {
    return _originalMessage.decodeDate() ?? DateTime.now();
  }

  bool isSeen() {
    return _originalMessage.hasFlag(MessageFlags.seen);
  }

  bool hasAttachments() {
    return _originalMessage.hasAttachments();
  }

  int? getSequenceId() {
    return _originalMessage.sequenceId;
  }

  List<String> getAttachmentsNames() {
    final List<String> fileNames = [];
    final List<MimePart> parts = _originalMessage.allPartsFlat;
    for (final MimePart mp in parts) {
      if (mp.decodeFileName() != null) {
        fileNames.add(mp.decodeFileName() ?? "");

        // var myFile = File(mp.decodeFileName() ?? "");
        // myFile.writeAsBytes(mp.decodeContentBinary()?.toList() ?? []);
      }
    }
    return fileNames;
  }

  String getBody(
      {removeTrackingImages = false, excerpt = true, excerptLength = 100}) {
    if (excerpt) {
      int length = _originalMessage.decodeTextPlainPart()?.length ?? 0;
      int maxsubstr = min(length, excerptLength);
      return _originalMessage
              .decodeTextPlainPart()
              ?.replaceAll("\n", "")
              .substring(0, maxsubstr) ??
          "";
    } else {
      String? html = _originalMessage.decodeTextHtmlPart();
      if (removeTrackingImages) {
        html?.replaceAll(RegExp(r"img=.*>"), ">");
      }
      return html ?? (_originalMessage.decodeTextPlainPart() ?? "-");
    }
  }

  Future<void> markAsSeen() async {
    final MessageSequence sequence = MessageSequence();
    sequence.addMessage(_originalMessage);
    await _client.markSeen(sequence);
    _originalMessage.isSeen = true;
  }

  Future<void> markAsUnseen() async {
    final MessageSequence sequence = MessageSequence();
    sequence.addMessage(_originalMessage);
    await _client.markUnseen(sequence);
    _originalMessage.isSeen = false;
  }

  Future<void> delete() async {
    final MessageSequence sequence = MessageSequence();
    sequence.addMessage(_originalMessage);
    await _client.markDeleted(sequence);
    _originalMessage.isDeleted = true;
  }
}
