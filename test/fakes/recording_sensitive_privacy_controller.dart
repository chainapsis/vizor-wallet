import 'package:zcash_wallet/src/core/privacy/sensitive_privacy_overlay.dart';

class RecordingSensitivePrivacyController
    extends SensitivePrivacyOverlayController {
  int begins = 0;
  int ends = 0;

  @override
  void beginAuthPrompt() {
    begins++;
    super.beginAuthPrompt();
  }

  @override
  void endAuthPrompt() {
    ends++;
    super.endAuthPrompt();
  }
}
