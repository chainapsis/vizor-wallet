import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/voting/widgets/voting_config_error_text.dart';
import 'package:zcash_wallet/src/providers/voting/voting_config_source_provider.dart';
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/wire.dart';
import 'package:zcash_wallet/src/services/voting/voting_config_loader.dart';

import '../../support/test_l10n.dart';

void main() {
  String text(Object error) =>
      votingConfigSourceErrorText(testL10n, error, fallback: 'fallback');

  test('an SDK refusal names the source failure and keeps its reason', () {
    const view = VotingErrorView(
      kind: VotingErrorKindView.invalidInput,
      retryable: false,
      message: 'static config hash does not match the pin',
    );
    expect(
      text(view),
      testL10n.commonErrorWithDetails(
        testL10n.votingConfigLoadFailed,
        'invalidInput: static config hash does not match the pin',
      ),
    );
    expect(text(view), isNot(contains('Instance of')));
  });

  test('a refused URL shows the copy for its problem', () {
    for (final (raw, expected) in [
      ('http://example.com/config.json', testL10n.votingConfigUrlNotHttps),
      ('https://a:b@example.com/c.json', testL10n.votingConfigUrlHasUserInfo),
      ('https://example.com/c.json#x', testL10n.votingConfigUrlHasFragment),
      (
        'https://example.com/c.json?checksum=md5:00',
        testL10n.votingConfigChecksumPrefix,
      ),
      (
        'https://example.com/c.json?checksum=sha256:00',
        testL10n.votingConfigChecksumFormat,
      ),
    ]) {
      expect(
        () => parseStaticVotingConfigSource(raw),
        throwsA(
          isA<StaticVotingConfigSourceMalformed>().having(
            text,
            'text',
            expected,
          ),
        ),
        reason: raw,
      );
    }
  });

  test('a duplicate source and unknown failures use fixed copy', () {
    expect(
      text(
        const DuplicateVotingConfigSource('This source URL is already added.'),
      ),
      testL10n.votingConfigDuplicate,
    );
    expect(text(StateError('disk full')), 'fallback');
  });
}
