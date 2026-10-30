@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/home/widgets/mobile/shield/mobile_shield_scene.dart';
import 'package:zcash_wallet/src/features/home/widgets/mobile/shield/shield_hardware_motion.dart';
import 'package:zcash_wallet/src/features/home/widgets/mobile/shield/particles/particle_field.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/mobile/mobile_ledger_signing_content.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/mobile/mobile_ledger_sheet_content.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signing_progress.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_app_readiness_service.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/ledger_procedure.dart';

Future<void> _artFrames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 17));
  }
}

ParticleField _field(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((p) => p.painter)
    .whereType<ParticlePainter>()
    .single
    .field;

Widget _content(LedgerSigningStage stage, VoidCallback close) =>
    LedgerInlinePresentation(
      child: MobileLedgerSigningContent(
        title: stage.title,
        message: stage.message,
        status: stage.status,
        active: true,
        failed: false,
        stage: stage,
        readiness: LedgerAppReadinessPhase.ready,
        saving: false,
        finishing: false,
        broadcasting: false,
        declined: false,
        roundNumber: 1,
        roundCount: 1,
        onClose: close,
        onAction: null,
      ),
    );

void main() {
  testWidgets(
    'removing the inline action fades it while blocking input immediately',
    (tester) async {
      final enabled = ValueNotifier(true);
      addTearDown(enabled.dispose);
      var closed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: AppTheme(
            data: AppThemeData.dark,
            child: Center(
              child: SizedBox(
                width: 300,
                height: 480,
                child: ShieldHardwarePresentation(
                  mix: 1,
                  footerOpacity: 1,
                  footerDy: 0,
                  interactive: true,
                  child: ValueListenableBuilder(
                    valueListenable: enabled,
                    builder: (_, value, _) => LedgerInlinePresentation(
                      child: MobileLedgerSheetContent(
                        title: 'Sign transaction',
                        onClose: value ? () => closed++ : null,
                        children: const [],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final before = tester.getRect(find.text('Sign transaction'));
      enabled.value = false;
      await tester.pump();
      expect(
        tester.getRect(find.text('Sign transaction')).center.dy,
        closeTo(before.center.dy, 0.01),
      );
      await tester.tap(find.text('Cancel shielding'), warnIfMissed: false);
      expect(closed, 0);
      await tester.pump(const Duration(milliseconds: 70));
      expect(
        tester
            .widgetList<FadeTransition>(find.byType(FadeTransition))
            .any((fade) => fade.opacity.value > 0 && fade.opacity.value < 1),
        isTrue,
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Cancel shielding'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final inline in [false, true]) {
    for (final scale in [1.0, 2.5]) {
      testWidgets('Ledger status has a trailing loader with no inactive slot '
          '(shield: $inline, text scale: $scale)', (tester) async {
        const boundsKey = ValueKey('status-bounds');
        Future<void> show(String label, {required bool active}) async {
          Widget child = MobileLedgerStatus(label, active: active);
          if (inline) {
            child = ShieldHardwarePresentation(
              mix: 1,
              footerOpacity: 1,
              footerDy: 0,
              interactive: true,
              child: child,
            );
          }
          await tester.pumpWidget(
            MaterialApp(
              home: AppTheme(
                data: AppThemeData.dark,
                child: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Center(
                    child: SizedBox(key: boundsKey, width: 264, child: child),
                  ),
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 250));
        }

        final loader = find.byWidgetPredicate(
          (widget) => widget is AppIcon && widget.name == AppIcons.loader,
        );
        await show('Preparing to sign', active: true);
        final text = tester.getRect(find.text('Preparing to sign'));
        final icon = tester.getRect(loader);
        final bounds = tester.getRect(find.byKey(boundsKey));
        expect(icon.left - text.right, closeTo(8, 0.01));
        expect(icon.center.dy, closeTo(text.center.dy, 0.01));
        expect((text.left + icon.right) / 2, closeTo(bounds.center.dx, 0.01));

        const prompt = 'Follow the prompts on your Ledger';
        await show(prompt, active: false);
        expect(loader, findsNothing);
        final inactiveText = tester.getRect(find.text(prompt));
        final row = tester.getRect(
          find.descendant(
            of: find.byType(MobileLedgerStatus),
            matching: find.byType(Row),
          ),
        );
        expect(row.width, closeTo(inactiveText.width, 0.01));
        expect(inactiveText.center.dx, closeTo(bounds.center.dx, 0.01));
        expect(inactiveText.left, greaterThanOrEqualTo(bounds.left));
        expect(inactiveText.right, lessThanOrEqualTo(bounds.right));

        await show('Checking Bluetooth access…', active: true);
        final wrapped = tester.getRect(find.text('Checking Bluetooth access…'));
        expect(tester.getRect(loader).right, lessThanOrEqualTo(bounds.right));
        expect(wrapped.left, greaterThanOrEqualTo(bounds.left));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets(
    'unknown result omits amount text and particle digits after retargeting',
    (tester) async {
      final known = ValueNotifier(true);
      final phase = ValueNotifier(MobileShieldPhase.working);
      addTearDown(known.dispose);
      addTearDown(phase.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ListenableBuilder(
            listenable: Listenable.merge([known, phase]),
            builder: (_, _) => MobileShieldScene(
              phase: phase.value,
              amount: '14.12',
              resultAmount: '0.0099',
              showResultAmount: known.value,
              title: 'Shielded successfully',
            ),
          ),
        ),
      );
      await _artFrames(tester);
      final original = _field(tester);
      expect(original.geometry.balancePoints, isNotEmpty);
      known.value = false;
      await tester.pump();
      await _artFrames(tester);
      expect(identical(_field(tester), original), isTrue);
      expect(original.geometry.balancePoints, isEmpty);
      phase.value = MobileShieldPhase.succeeded;
      await tester.pump();
      for (var i = 0; i < 360; i++) {
        await tester.pump(const Duration(microseconds: 16667));
      }
      expect(
        find.byKey(const ValueKey('mobile_shield_result_amount')),
        findsNothing,
      );
      expect(find.text('Shielded successfully'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'late result amounts retarget the same live cloud after a long signing wait',
    (tester) async {
      final result = ValueNotifier('—');
      addTearDown(result.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder(
            valueListenable: result,
            builder: (_, value, _) => MobileShieldScene(
              phase: MobileShieldPhase.working,
              amount: '14.12',
              resultAmount: value,
              title: 'Shielding your balance…',
            ),
          ),
        ),
      );
      await _artFrames(tester);
      for (var i = 0; i < 1800; i++) {
        await tester.pump(const Duration(microseconds: 16667));
      }
      final original = _field(tester);
      for (final amount in ['14.1199', '28.2398']) {
        final oldTargets = original.geometry.balancePoints;
        original.captureProjectedParticles = true;
        original.update(31, null);
        final positions = [
          for (final p in original.projectedParticles) p.position,
        ];
        result.value = amount;
        await tester.pump();
        await _artFrames(tester);
        expect(identical(_field(tester), original), isTrue);
        expect(identical(original.geometry.balancePoints, oldTargets), isFalse);
        original.captureProjectedParticles = true;
        original.update(31, null);
        for (var i = 0; i < positions.length; i++) {
          expect(
            (original.projectedParticles[i].position - positions[i]).distance,
            lessThan(120),
            reason: 'particle $i teleported after $amount',
          );
        }
      }
      final late = ParticleField(
        geometry: original.geometry,
        atlas: original.atlas,
        reduceMotion: false,
      )..captureProjectedParticles = true;
      late.update(31, null);
      for (final p in late.projectedParticles) {
        expect(
          p.position.dy,
          inInclusiveRange(-100.0, original.geometry.screen.height + 100),
        );
      }
      late.dispose();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final scale in [1.0, 2.5]) {
    testWidgets('Ledger procedure keeps the footer fixed at scale $scale', (
      tester,
    ) async {
      final stage = ValueNotifier(LedgerSigningStage.preparing);
      addTearDown(stage.dispose);
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: AppTheme(
              data: AppThemeData.dark,
              child: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Center(
                  child: SizedBox(
                    width: 272,
                    height: 480,
                    child: ShieldHardwarePresentation(
                      mix: 1,
                      footerOpacity: 1,
                      footerDy: 0,
                      interactive: true,
                      child: ValueListenableBuilder(
                        valueListenable: stage,
                        builder: (_, value, _) => _content(value, () {}),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final button = find.text('Cancel shielding');
        final rect = tester.getRect(button);
        for (final value in [
          LedgerSigningStage.sending,
          LedgerSigningStage.reviewing,
          LedgerSigningStage.preparing,
        ]) {
          stage.value = value;
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          expect(tester.getRect(button), rect);
          expect(find.text('Sign transaction'), findsOneWidget);
          expect(
            tester
                .widget<LedgerProcedure>(find.byType(LedgerProcedure))
                .currentStep,
            value == LedgerSigningStage.preparing ? 0 : 1,
          );
          await tester.pump(const Duration(milliseconds: 150));
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets(
    'hardware exit gates actions immediately and can reverse without remounting its owner',
    (tester) async {
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      var starts = 0, disposes = 0, closes = 0;
      final child = _Probe(
        onStart: () => starts++,
        onDispose: () => disposes++,
        child: _content(LedgerSigningStage.reviewing, () => closes++),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder(
            valueListenable: visible,
            builder: (_, value, _) => MobileShieldScene(
              animateHardware: true,
              phase: value
                  ? MobileShieldPhase.hardware
                  : MobileShieldPhase.working,
              amount: '14.12',
              title: 'Shield with Ledger',
              focusChild: value ? child : null,
            ),
          ),
        ),
      );
      await _artFrames(tester);
      await tester.pump(const Duration(seconds: 2));
      ShieldHardwarePresentation motion() =>
          tester.widget(find.byType(ShieldHardwarePresentation));
      expect(motion().interactive, isTrue);
      expect(starts, 1);
      visible.value = false;
      await tester.pump();
      expect(motion().interactive, isFalse);
      await tester.tap(find.text('Cancel shielding'), warnIfMissed: false);
      expect(closes, 0);
      await tester.pump(const Duration(milliseconds: 125));
      expect(motion().footerOpacity, inExclusiveRange(0.0, 1.0));
      expect(motion().mix, inExclusiveRange(0.0, 1.0));
      visible.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(motion().interactive, isTrue);
      expect(starts, 1);
      expect(disposes, 0);
      visible.value = false;
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(disposes, 1);
      expect(starts, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('Reduce Motion keeps exits short and removes footer movement', () {
    final motion = ShieldHardwareMotion()..reduceMotion = true;
    motion.configure(true, 0);
    motion.update(0.13);
    expect(motion.mix, 1);
    expect(motion.footerDy, 0);
    motion.configure(false, 0.13);
    motion.update(0.26);
    expect(motion.active, isFalse);
    expect(motion.footer, 0);
  });
}

class _Probe extends StatefulWidget {
  const _Probe({
    required this.child,
    required this.onStart,
    required this.onDispose,
  });
  final Widget child;
  final VoidCallback onStart, onDispose;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.onStart();
  }

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
