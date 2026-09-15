import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:zcash_wallet/widgetbook/support/wb_state.dart';

import 'wb_gallery_harness.dart';

enum _FourStates { idle, quoting, quoted, failed }

enum _FiveStates { idle, quoting, quoted, failed, notEnoughZec }

String _fourLabel(_FourStates value) => switch (value) {
  _FourStates.idle => 'Idle',
  _FourStates.quoting => 'Quoting',
  _FourStates.quoted => 'Quoted',
  _FourStates.failed => 'Failed',
};

String _fiveLabel(_FiveStates value) => switch (value) {
  _FiveStates.idle => 'Idle',
  _FiveStates.quoting => 'Quoting',
  _FiveStates.quoted => 'Quoted',
  _FiveStates.failed => 'Failed',
  _FiveStates.notEnoughZec => 'Not enough ZEC',
};

void main() {
  testWidgets('every option count renders a dropdown knob', (tester) async {
    final state = await pumpUseCase(tester, (context) {
      wbStateKnob<_FourStates>(
        context,
        label: 'Quote',
        options: _FourStates.values,
        labelBuilder: _fourLabel,
      );
      wbStateKnob<_FiveStates>(
        context,
        label: 'Status',
        options: _FiveStates.values,
        labelBuilder: _fiveLabel,
      );
      return const SizedBox.shrink();
    });

    expect(state.knobs['Quote']!.fields.single.type, FieldType.objectDropdown);
    expect(state.knobs['Status']!.fields.single.type, FieldType.objectDropdown);
  });

  testWidgets('state knob falls back to initial, then to the query group', (
    tester,
  ) async {
    _FourStates? captured;

    Widget build(BuildContext context) {
      captured = wbStateKnob<_FourStates>(
        context,
        label: 'Quote',
        options: _FourStates.values,
        initial: _FourStates.quoted,
        labelBuilder: _fourLabel,
      );
      return const SizedBox.shrink();
    }

    await pumpUseCase(tester, build);
    expect(captured, _FourStates.quoted);

    await pumpUseCase(tester, build, knobs: {'Quote': 'Failed'});
    expect(captured, _FourStates.failed);
  });

  testWidgets('the option label is what the query group encodes', (
    tester,
  ) async {
    _FiveStates? captured;

    await pumpUseCase(tester, (context) {
      captured = wbStateKnob<_FiveStates>(
        context,
        label: 'Status',
        options: _FiveStates.values,
        labelBuilder: _fiveLabel,
      );
      return const SizedBox.shrink();
    }, knobs: {'Status': 'Not enough ZEC'});

    expect(captured, _FiveStates.notEnoughZec);
  });

  testWidgets('wbBoolKnob registers a boolean field with its initial value', (
    tester,
  ) async {
    bool? captured;

    final state = await pumpUseCase(tester, (context) {
      captured = wbBoolKnob(context, label: 'Hardware wallet', initial: true);
      return const SizedBox.shrink();
    });

    expect(captured, isTrue);
    expect(
      state.knobs['Hardware wallet']!.fields.single.type,
      FieldType.boolean,
    );
  });

  test('the opt-in generic label builder sentence-cases camelCase names', () {
    expect(wbEnumLabel(_FourStates.idle), 'Idle');
    // Why `labelBuilder` is required: the generic builder has no product
    // vocabulary, so an acronym comes out lowercased.
    expect(wbEnumLabel(_FiveStates.notEnoughZec), 'Not enough zec');
    expect(wbSentenceCaseFromCamel('awaitingSignature'), 'Awaiting signature');
    expect(wbSentenceCaseFromCamel('step2Ready'), 'Step2 ready');
    expect(wbSentenceCaseFromCamel(''), '');
  });
}
