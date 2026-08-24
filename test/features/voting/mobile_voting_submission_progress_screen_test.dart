@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/voting/screens/mobile/mobile_voting_submitted_screen.dart';
import 'package:zcash_wallet/src/features/voting/screens/mobile/mobile_voting_submission_progress_screen.dart';
import 'package:zcash_wallet/src/features/voting/screens/voting_status_screen.dart';
import 'package:zcash_wallet/src/providers/voting/voting_state.dart';

void main() {
  test('maps submission phases to the simplified three-step presentation', () {
    expect(
      votingSubmissionProgressStepFor(
        phase: VotingSessionPhase.resolvingPir,
        voteStepComplete: false,
        submissionJobComplete: false,
        submissionJobInFlight: true,
      ),
      VotingSubmissionProgressStep.delegating,
    );
    expect(
      votingSubmissionProgressStepFor(
        phase: VotingSessionPhase.submittingShares,
        voteStepComplete: false,
        submissionJobComplete: false,
        submissionJobInFlight: true,
      ),
      VotingSubmissionProgressStep.castingVotes,
    );
    expect(
      votingSubmissionProgressStepFor(
        phase: VotingSessionPhase.done,
        voteStepComplete: true,
        submissionJobComplete: false,
        submissionJobInFlight: true,
      ),
      VotingSubmissionProgressStep.finalizing,
    );
  });

  testWidgets('renders the simplified three-step casting state', (
    tester,
  ) async {
    await _setMobileViewport(tester);
    await tester.pumpWidget(
      _app(
        const MobileVotingSubmissionProgressScreen(
          activeStep: VotingSubmissionProgressStep.castingVotes,
          activeStepProgress: 0.25,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Don’t leave this window.'), findsOneWidget);
    expect(find.text('Submitting votes...'), findsOneWidget);
    expect(find.text('Delegating voting authority'), findsOneWidget);
    expect(find.text('Casting votes and submitting shares'), findsOneWidget);
    expect(find.text('Finalizing submission'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    final progressSemantics = tester.getSemantics(
      find.bySemanticsLabel('Active voting submission step progress'),
    );
    expect(progressSemantics.value, '25%');
    final progressTransition = tester.widget<TweenAnimationBuilder<double>>(
      find.ancestor(
        of: find.byKey(const ValueKey('mobile_voting_submission_active_step')),
        matching: find.byType(TweenAnimationBuilder<double>),
      ),
    );
    expect(progressTransition.duration, const Duration(milliseconds: 220));
    expect(progressTransition.curve, Curves.easeOutCubic);
    expect(
      find.byKey(
        const ValueKey('mobile_voting_submission_step_delegating_complete'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('mobile_voting_submission_step_castingVotes_active'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('mobile_voting_submission_step_finalizing_pending'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('keeps the active progress ring at a stable size', (
    tester,
  ) async {
    await _setMobileViewport(tester);
    await tester.pumpWidget(
      _app(
        const MobileVotingSubmissionProgressScreen(
          activeStep: VotingSubmissionProgressStep.delegating,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byKey(const ValueKey('mobile_voting_submission_active_step_pulse')),
      findsNothing,
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('mobile_voting_submission_active_step')),
      ),
      const Size.square(20),
    );
  });

  testWidgets('keeps the proof notice visible on a compact mobile height', (
    tester,
  ) async {
    await _setMobileViewport(
      tester,
      size: const Size(375, 667),
      viewPadding: const FakeViewPadding(top: 47, bottom: 34),
    );
    await tester.pumpWidget(
      _app(
        const MobileVotingSubmissionProgressScreen(
          activeStep: VotingSubmissionProgressStep.finalizing,
        ),
      ),
    );

    final notice = find.textContaining('Generating zero-knowledge proofs');
    expect(notice, findsOneWidget);
    expect(tester.getSize(find.byType(Scaffold)), const Size(375, 667));
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -200),
    );
    await tester.pump();
    expect(
      tester
          .getSize(
            find.byKey(
              const ValueKey('mobile_voting_submission_progress_content'),
            ),
          )
          .height,
      740,
    );
    expect(tester.getBottomRight(notice).dy, lessThanOrEqualTo(667));
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders the shared voted success presentation', (tester) async {
    await _setMobileViewport(tester);
    var doneCount = 0;
    await tester.pumpWidget(
      _app(MobileVotingSubmittedScreen(onDone: () => doneCount++)),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Voted'), findsOneWidget);
    expect(
      find.text('Your vote has been submitted and can’t be changed.'),
      findsOneWidget,
    );
    expect(find.text('Go home'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('mobile_voting_submitted_home_button')),
    );
    await tester.tap(
      find.byKey(const ValueKey('mobile_voting_submitted_home_button')),
    );
    expect(doneCount, 1);
  });

  testWidgets('starts the Voted pulse and haptic after route transition', (
    tester,
  ) async {
    await _setMobileViewport(tester);
    const hapticsChannel = MethodChannel('com.zcash.wallet/haptics');
    final haptics = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(hapticsChannel, (call) async {
          haptics.add(call.method);
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(hapticsChannel, null),
    );
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: AppTheme(
          data: AppThemeData.light,
          child: const SizedBox.expand(),
        ),
      ),
    );
    navigatorKey.currentState!.push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) => AppTheme(
          data: AppThemeData.light,
          child: MobileVotingSubmittedScreen(onDone: () {}),
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(
      find.byKey(const ValueKey('mobile_voting_submitted_success_ripple')),
      findsNothing,
    );
    expect(haptics, isEmpty);

    await tester.pump(const Duration(milliseconds: 200));
    expect(
      ModalRoute.of(
        tester.element(find.byType(MobileVotingSubmittedScreen)),
      )?.animation?.status,
      AnimationStatus.completed,
    );
    expect(haptics, ['sendSuccess']);

    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.byKey(const ValueKey('mobile_voting_submitted_success_ripple')),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 700));
    expect(haptics, ['sendSuccess']);
  });

  testWidgets('does not celebrate when Voted is removed during transition', (
    tester,
  ) async {
    await _setMobileViewport(tester);
    const hapticsChannel = MethodChannel('com.zcash.wallet/haptics');
    final haptics = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(hapticsChannel, (call) async {
          haptics.add(call.method);
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(hapticsChannel, null),
    );
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: AppTheme(
          data: AppThemeData.light,
          child: const SizedBox.expand(),
        ),
      ),
    );
    final route = PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) => AppTheme(
        data: AppThemeData.light,
        child: MobileVotingSubmittedScreen(onDone: () {}),
      ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: animation, child: child),
    );
    navigatorKey.currentState!.push(route);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    navigatorKey.currentState!.removeRoute(route);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(MobileVotingSubmittedScreen), findsNothing);
    expect(haptics, isEmpty);
  });

  testWidgets('keeps the Voted action reachable above compact safe areas', (
    tester,
  ) async {
    await _setMobileViewport(tester, size: const Size(375, 667));
    var done = false;
    await tester.pumpWidget(
      _app(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(375, 667),
            padding: EdgeInsets.only(top: 47, bottom: 34),
            viewPadding: EdgeInsets.only(top: 47, bottom: 34),
          ),
          child: MobileVotingSubmittedScreen(onDone: () => done = true),
        ),
      ),
    );

    final button = find.byKey(
      const ValueKey('mobile_voting_submitted_home_button'),
    );
    expect(button, findsOneWidget);
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -80));
    await tester.pump();
    expect(tester.getBottomRight(button).dy, lessThanOrEqualTo(633));
    await tester.tap(button);
    expect(done, isTrue);
  });
}

Widget _app(Widget child) {
  return MaterialApp(
    home: AppTheme(data: AppThemeData.light, child: child),
  );
}

Future<void> _setMobileViewport(
  WidgetTester tester, {
  Size size = const Size(393, 852),
  FakeViewPadding viewPadding = const FakeViewPadding(top: 55),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.viewPadding = viewPadding;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewPadding);
}
