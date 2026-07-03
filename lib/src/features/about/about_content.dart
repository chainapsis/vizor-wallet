import 'dart:async';

import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/app_localizations.dart';

/// Copy and link targets shared by the desktop and mobile About /
/// legal screens, so the two form factors cannot drift apart.
class AboutParagraph {
  const AboutParagraph({required this.heading, required this.body});

  final String heading;
  final String body;
}

const kVizorGithubUrl = 'https://github.com/chainapsis/vizor-wallet/';
const kVizorWebsiteUrl = 'https://vizor.cash';

List<AboutParagraph> aboutParagraphs(AppLocalizations l10n) => [
  AboutParagraph(
    heading: l10n.aboutKeplrTeamHeading,
    body: l10n.aboutKeplrTeamBody,
  ),
  AboutParagraph(
    heading: l10n.aboutShieldedHeading,
    body: l10n.aboutShieldedBody,
  ),
  AboutParagraph(
    heading: l10n.aboutOpenSourceHeading,
    body: l10n.aboutOpenSourceBody,
  ),
];

List<AboutParagraph> legalParagraphs(AppLocalizations l10n) {
  final placeholder = AboutParagraph(
    heading: l10n.aboutLegalPlaceholderHeading,
    body: l10n.aboutLegalPlaceholderBody,
  );
  return List.filled(6, placeholder);
}

Future<void> launchAboutUrl(String url) async {
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } on Exception {
    // External links are best-effort from these utility pages.
  }
}
