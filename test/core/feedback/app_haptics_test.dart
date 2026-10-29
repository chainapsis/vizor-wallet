import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/feedback/app_haptics.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_copy_feedback.dart';
import 'package:zcash_wallet/src/core/widgets/app_toast.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const nativeChannel = MethodChannel('com.zcash.wallet/haptics');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final feedback = <Object?>[];
  final native = <String>[];
  var clipboardFails = false;
  var nativeHandled = true;

  setUp(() {
    feedback.clear();
    native.clear();
    clipboardFails = false;
    nativeHandled = true;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') feedback.add(call.arguments);
      if (call.method == 'Clipboard.setData' && clipboardFails) {
        throw PlatformException(code: 'clipboard-denied');
      }
      return null;
    });
    messenger.setMockMethodCallHandler(nativeChannel, (call) async {
      native.add(call.method);
      return nativeHandled;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    messenger.setMockMethodCallHandler(nativeChannel, null);
  });

  test('new interaction feedback stays silent in the desktop lane', () async {
    await AppHaptics.selection();
    await AppHaptics.action();
    expect(
      feedback,
      kAppFormFactor == AppFormFactor.mobile
          ? [
              'HapticFeedbackType.selectionClick',
              'HapticFeedbackType.lightImpact',
            ]
          : isEmpty,
    );
  });

  test(
    'access success uses one native confirmation without a second impact',
    () async {
      await AppHaptics.accessGranted();
      expect(
        native,
        kAppFormFactor == AppFormFactor.mobile ? ['success'] : isEmpty,
      );
      expect(feedback, isEmpty);
    },
  );

  test('unhandled native success falls back to one light impact', () async {
    nativeHandled = false;
    await AppHaptics.accessGranted();
    expect(
      feedback,
      kAppFormFactor == AppFormFactor.mobile
          ? ['HapticFeedbackType.lightImpact']
          : isEmpty,
    );
  });

  for (final denied in [false, true]) {
    testWidgets(
      'clipboard ${denied ? 'failure is silent' : 'success confirms once'}',
      (tester) async {
        clipboardFails = denied;
        await tester.pumpWidget(
          MaterialApp(
            home: AppTheme(
              data: AppThemeData.light,
              child: Builder(
                builder: (context) => TextButton(
                  onPressed: () => copyTextWithToast(
                    context,
                    text: 'u1test-address',
                    toastMessage: 'Address copied',
                  ),
                  child: const Text('Copy'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Copy'));
        await tester.pump();
        expect(
          feedback,
          !denied && kAppFormFactor == AppFormFactor.mobile
              ? ['HapticFeedbackType.lightImpact']
              : isEmpty,
        );
        expect(
          find.text('Address copied'),
          denied ? findsNothing : findsOneWidget,
        );
        await tester.pump(AppToast.defaultDuration);
        await tester.pumpAndSettle();
      },
    );
  }
}
