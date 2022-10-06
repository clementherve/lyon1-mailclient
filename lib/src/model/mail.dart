import 'dart:math';

import 'package:enough_mail/mail_address.dart';
import 'package:enough_mail/message_flags.dart';
import 'package:enough_mail/mime_message.dart';

class Mail {
  final MimeMessage _originalMessage;

  Mail(this._originalMessage);

  String getSubject() {
    return _originalMessage.decodeSubject() ?? "";
  }

  List<String> getRecipients() {
    const List<String> recipients = [];
    for (MailAddress m in _originalMessage.cc ?? []) {
      recipients.add(m.email);
    }
    return recipients;
  }

  String getSender() {
    return _originalMessage.fromEmail ?? "n/a";
  }

  String getReceiver() {
    String receiver = "";
    for (MailAddress i in _originalMessage.to!) {
      receiver += i.email + ", ";
    }
    receiver = receiver.substring(0, receiver.length - 2);
    return receiver;
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

  String getBody({
    removeTrackingImages = false,
    excerpt = true,
    excerptLength = 100,
  }) {
    if (excerpt) {
      int length =
          _originalMessage.decodeTextPlainPart()?.replaceAll("\n", "").length ??
              0;
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
}
