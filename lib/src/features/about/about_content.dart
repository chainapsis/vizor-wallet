import 'dart:async';

import 'package:url_launcher/url_launcher.dart';

/// Copy and link targets shared by the desktop and mobile About /
/// legal screens, so the two form factors cannot drift apart.
class AboutParagraph {
  const AboutParagraph({required this.heading, required this.body});

  final String heading;
  final String body;
}

const kVizorGithubUrl = 'https://github.com/chainapsis/vizor-wallet/';
const kVizorWebsiteUrl = 'https://vizor.cash';

const kAboutParagraphs = [
  AboutParagraph(
    heading: 'Built by the Keplr team',
    body:
        'We built Keplr, the wallet used by millions across Cosmos, Ethereum, '
        'and Bitcoin. Vizor is our take on what a Zcash wallet should feel '
        'like.',
  ),
  AboutParagraph(
    heading: 'Designed for shielded Zcash',
    body:
        'Vizor is built around shielded transactions, where the sender, '
        'recipient, and amount stay private. Transparent Zcash works too, but '
        'private is the default.',
  ),
  AboutParagraph(
    heading: 'Open source, self-custodied',
    body:
        "Vizor is Apache licensed. Your keys stay on your device.\n"
        "We don't see your balances or your transactions.",
  ),
];

const _legalPlaceholderParagraph = AboutParagraph(
  heading: 'From the team that brought you Keplr Wallet.',
  body:
      'Unlike Bitcoin or Ethereum, shielded Zcash transactions hide the '
      'sender, recipient, and amount.',
);

const kLegalParagraphs = [
  _legalPlaceholderParagraph,
  _legalPlaceholderParagraph,
  _legalPlaceholderParagraph,
  _legalPlaceholderParagraph,
  _legalPlaceholderParagraph,
  _legalPlaceholderParagraph,
];

Future<void> launchAboutUrl(String url) async {
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } on Exception {
    // External links are best-effort from these utility pages.
  }
}
