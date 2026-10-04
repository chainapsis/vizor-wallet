import 'dart:convert';
import 'dart:io';

import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';

/// Encodes one or more externally funded v4 gift links from JSON or CSV.
Future<void> main(List<String> arguments) async {
  try {
    final options = _Options.parse(arguments);
    final input = options.inputPath == null
        ? await stdin.transform(utf8.decoder).join()
        : await File(options.inputPath!).readAsString();
    final records = options.format == 'csv'
        ? _parseCsv(input)
        : _parseJson(input);
    final output = records.map(_encodeRecord).join('\n');
    if (options.outputPath == null) {
      stdout.writeln(output);
    } else {
      await File(options.outputPath!).writeAsString('$output\n');
    }
  } on _UsageException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(_Options.usage);
    exitCode = 64;
  } on Object {
    stderr.writeln(
      'Could not encode gift links. Check the field names, types, and limits.',
    );
    exitCode = 65;
  }
}

String _encodeRecord(Map<String, Object?> record) {
  final locatorText = _requiredString(record, 'locatorKind');
  final locator = switch (locatorText) {
    'birthday' => PaymentLinkLocatorKind.birthday,
    'fundingHeight' => PaymentLinkLocatorKind.fundingHeight,
    'fundingTxid' => PaymentLinkLocatorKind.fundingTxid,
    _ => throw FormatException('Unknown locatorKind "$locatorText".'),
  };
  final artworkId = _optionalText(record['artworkId'], 'artworkId');
  final message = _optionalText(record['message'], 'message');
  final fiatText = _optionalNumberText(record['fiatUsd'], 'fiatUsd');
  final amountText = _requiredString(record, 'amountZatoshi');
  if (!RegExp(r'^[1-9][0-9]*$').hasMatch(amountText)) {
    throw const FormatException('amountZatoshi must be a positive integer.');
  }
  return VizorPaymentLink.encodeV4FromEntropy(
    entropy: _decodeHex(_requiredString(record, 'entropyHex'), 16),
    amountZatoshi: BigInt.parse(amountText),
    locatorKind: locator,
    birthdayHeight: _optionalInt(record['birthdayHeight']),
    fundingHeight: _optionalInt(record['fundingHeight']),
    fundingTxid: _optionalText(record['fundingTxid'], 'fundingTxid'),
    presentation: artworkId == null && message == null && fiatText == null
        ? null
        : PaymentLinkPresentation(
            artworkId: artworkId,
            message: message,
            fiatSnapshot: fiatText == null
                ? null
                : PaymentLinkFiatSnapshot(amount: double.parse(fiatText)),
          ),
  ).toString();
}

List<Map<String, Object?>> _parseJson(String input) {
  final decoded = jsonDecode(input);
  final values = decoded is List ? decoded : [decoded];
  return values.map((value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException(
        'JSON input must be an object or object array.',
      );
    }
    return Map<String, Object?>.from(value);
  }).toList();
}

List<Map<String, Object?>> _parseCsv(String input) {
  final rows = _csvRows(input);
  if (rows.isEmpty) return [];
  final headers = rows.first;
  return rows.skip(1).where((row) => row.any((value) => value.isNotEmpty)).map((
    row,
  ) {
    if (row.length != headers.length) {
      throw const FormatException('CSV row has the wrong number of columns.');
    }
    return <String, Object?>{
      for (var index = 0; index < headers.length; index++)
        headers[index]: row[index],
    };
  }).toList();
}

List<List<String>> _csvRows(String input) {
  final rows = <List<String>>[];
  var row = <String>[];
  var field = StringBuffer();
  var quoted = false;
  for (var index = 0; index < input.length; index++) {
    final char = input[index];
    if (char == '"') {
      if (quoted && index + 1 < input.length && input[index + 1] == '"') {
        field.write('"');
        index++;
      } else {
        quoted = !quoted;
      }
    } else if (char == ',' && !quoted) {
      row.add(field.toString());
      field = StringBuffer();
    } else if ((char == '\n' || char == '\r') && !quoted) {
      if (char == '\r' &&
          index + 1 < input.length &&
          input[index + 1] == '\n') {
        index++;
      }
      row.add(field.toString());
      field = StringBuffer();
      rows.add(row);
      row = <String>[];
    } else {
      field.write(char);
    }
  }
  if (quoted) {
    throw const FormatException('CSV contains an unterminated quote.');
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  return rows;
}

String _requiredString(Map<String, Object?> record, String key) {
  final value = _optionalText(record[key], key);
  if (value == null) throw FormatException('Missing required field "$key".');
  return value;
}

String? _optionalText(Object? value, String field) {
  if (value == null) return null;
  if (value is! String) throw FormatException('$field must be a string.');
  final text = value.trim();
  return text.isEmpty ? null : text;
}

String? _optionalNumberText(Object? value, String field) {
  if (value == null) return null;
  if (value is! num && value is! String) {
    throw FormatException('$field must be a number.');
  }
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

int? _optionalInt(Object? value) {
  final text = _optionalNumberText(value, 'height');
  return text == null ? null : int.parse(text);
}

List<int> _decodeHex(String value, int expectedBytes) {
  if (!RegExp('^[0-9a-fA-F]{${expectedBytes * 2}}\$').hasMatch(value)) {
    throw FormatException(
      'entropyHex must contain ${expectedBytes * 2} hex characters.',
    );
  }
  return List<int>.generate(
    expectedBytes,
    (index) => int.parse(value.substring(index * 2, index * 2 + 2), radix: 16),
  );
}

final class _Options {
  const _Options({required this.format, this.inputPath, this.outputPath});

  final String format;
  final String? inputPath;
  final String? outputPath;

  static const usage = '''Usage: dart run tool/gift_link_v4.dart [options]
  --format json|csv   Input format (default: json)
  --input PATH        Read from a file instead of stdin
  --output PATH       Write URLs to a file instead of stdout''';

  static _Options parse(List<String> arguments) {
    var format = 'json';
    String? inputPath;
    String? outputPath;
    for (var index = 0; index < arguments.length; index++) {
      final option = arguments[index];
      if (option == '--help' || option == '-h') throw const _UsageException('');
      if (index + 1 >= arguments.length) {
        throw _UsageException('Missing value for $option.');
      }
      final value = arguments[++index];
      switch (option) {
        case '--format':
          format = value;
        case '--input':
          inputPath = value;
        case '--output':
          outputPath = value;
        default:
          throw _UsageException('Unknown option: $option');
      }
    }
    if (format != 'json' && format != 'csv') {
      throw const _UsageException('--format must be json or csv.');
    }
    return _Options(
      format: format,
      inputPath: inputPath,
      outputPath: outputPath,
    );
  }
}

final class _UsageException implements Exception {
  const _UsageException(this.message);
  final String message;
}
