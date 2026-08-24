import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/private_state_sync_config.dart';

void main() {
  test('normalizes a production HTTPS base URL', () {
    expect(
      parsePrivateStateBaseUri(
        ' https://functions.vizor.cash/api/private-state/v1/ ',
        allowInsecureHttp: false,
      ).toString(),
      'https://functions.vizor.cash/api/private-state/v1',
    );
  });

  test('requires an explicit opt-in for development HTTP', () {
    expect(
      () => parsePrivateStateBaseUri(
        'http://127.0.0.1:3000/api/private-state/v1',
        allowInsecureHttp: false,
      ),
      throwsStateError,
    );
    expect(
      parsePrivateStateBaseUri(
        'http://10.0.2.2:3000/api/private-state/v1',
        allowInsecureHttp: true,
      ).host,
      '10.0.2.2',
    );
  });

  test('rejects credentials, query parameters, and fragments', () {
    for (final value in [
      'https://user@example.com/v1',
      'https://example.com/v1?wallet=1',
      'https://example.com/v1#state',
    ]) {
      expect(
        () => parsePrivateStateBaseUri(value, allowInsecureHttp: false),
        throwsStateError,
      );
    }
  });
}
