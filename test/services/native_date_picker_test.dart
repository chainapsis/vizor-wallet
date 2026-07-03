import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/services/native_date_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(NativeDatePicker.channel, null);
  });

  test('pickDate sends yyyy-MM-dd bounds and decodes the picked day', () async {
    MethodCall? sent;
    messenger.setMockMethodCallHandler(NativeDatePicker.channel, (call) async {
      sent = call;
      return '2024-03-09';
    });

    final picked = await NativeDatePicker.pickDate(
      initialDate: DateTime(2024, 3, 5),
      firstDate: DateTime(2018, 10, 28),
      lastDate: DateTime(2024, 3, 12),
      isDarkTheme: true,
      accentColor: const Color(0xFFE5484D),
    );

    expect(sent!.method, 'pickDate');
    expect(sent!.arguments, {
      'initial': '2024-03-05',
      'min': '2018-10-28',
      'max': '2024-03-12',
      'isDarkTheme': true,
      'accentColorHex': 'e5484d',
    });
    expect(picked, DateTime(2024, 3, 9));
  });

  test('pickDate omits optional args and maps null to a cancel', () async {
    MethodCall? sent;
    messenger.setMockMethodCallHandler(NativeDatePicker.channel, (call) async {
      sent = call;
      return null;
    });

    final picked = await NativeDatePicker.pickDate(
      firstDate: DateTime(2018, 10, 28),
      lastDate: DateTime(2024, 3, 12),
      isDarkTheme: false,
    );

    expect(picked, isNull);
    expect(
      sent!.arguments,
      isNot(anyOf(contains('initial'), contains('accentColorHex'))),
    );
  });

  test(
    'pickMonthYear sends yyyy-MM-dd bounds and decodes the picked month',
    () async {
      MethodCall? sent;
      messenger.setMockMethodCallHandler(NativeDatePicker.channel, (
        call,
      ) async {
        sent = call;
        return '2024-03-01';
      });

      final picked = await NativeDatePicker.pickMonthYear(
        initialDate: DateTime(2024, 2, 20),
        firstDate: DateTime(2018, 10, 28),
        lastDate: DateTime(2024, 3, 12),
        isDarkTheme: true,
        accentColor: const Color(0xFFE5484D),
      );

      expect(sent!.method, 'pickMonthYear');
      expect(sent!.arguments, {
        'initial': '2024-02-20',
        'min': '2018-10-28',
        'max': '2024-03-12',
        'isDarkTheme': true,
        'accentColorHex': 'e5484d',
      });
      expect(picked, DateTime(2024, 3, 1));
    },
  );

  test('pickDate surfaces handler errors for the Flutter-sheet fallback', () {
    messenger.setMockMethodCallHandler(NativeDatePicker.channel, (call) async {
      throw PlatformException(code: 'unavailable');
    });

    expect(
      NativeDatePicker.pickDate(
        firstDate: DateTime(2018, 10, 28),
        lastDate: DateTime(2024, 3, 12),
        isDarkTheme: false,
      ),
      throwsA(isA<PlatformException>()),
    );
  });

  test('cancel invokes the channel', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(NativeDatePicker.channel, (call) async {
      calls.add(call.method);
      return true;
    });

    await NativeDatePicker.cancel();
    expect(calls, ['cancel']);
  });

  test('date codec round-trips and pads single digits', () {
    expect(NativeDatePicker.encodeDate(DateTime(2018, 1, 2)), '2018-01-02');
    expect(NativeDatePicker.decodeDate('2018-01-02'), DateTime(2018, 1, 2));
    expect(
      () => NativeDatePicker.decodeDate('03/09/2024'),
      throwsFormatException,
    );
  });
}
