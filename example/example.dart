import 'package:dartz/dartz.dart';
import 'package:lyon1mail/lyon1mail.dart';

void main() async {
  final Lyon1Mail mailClient = Lyon1Mail("p1234567", "a_valid_password");

  if (!await mailClient.login()) {
    // handle gracefully
  }

  final Option<List<Mail>> emailOpt = await mailClient.fetchMessages(15);
  if (emailOpt.isNone()) {
    // No emails
  }

  for (final Mail mail in emailOpt.toIterable().first) {
    print(
        "${mail.getSender()} sent ${mail.getSubject()} @${mail.getDate().toIso8601String()}");
    print("\tseen: ${mail.isSeen()}");
    print("\t${mail.getBody(excerpt: true, excerptLength: 50)}");
    print("\thasPJ: ${mail.hasAttachments()}");
    mail.getAttachmentsNames().forEach((fname) {
      print("\t\t$fname");
    });
  }

  await mailClient.logout();
}
