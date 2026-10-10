import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

// Both native E2E cohorts use Cargokit's debug configuration. RustBuilder's
// exact-version environment override is applied by the original Python owner.
String configuredNativeToolchain(String contents) {
  final options = loadYaml(contents);
  if (options is! YamlMap) {
    throw const FormatException('Cargokit options must be a map');
  }
  if (!options.containsKey('cargo')) return 'stable';
  final cargo = options['cargo'];
  if (cargo is! YamlMap) {
    throw const FormatException('Cargo options must be a map');
  }
  if (!cargo.containsKey('debug')) return 'stable';
  final debug = cargo['debug'];
  if (debug is! YamlMap) {
    throw const FormatException('Debug cargo options must be a map');
  }
  if (!debug.containsKey('toolchain')) return 'stable';
  final toolchain = debug['toolchain'];
  if (toolchain is! String ||
      !const {'stable', 'beta', 'nightly'}.contains(toolchain)) {
    throw const FormatException('Unknown Cargokit toolchain');
  }
  return toolchain;
}

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln('Usage: cargokit_toolchain.dart <cargokit.yaml>');
    exitCode = 64;
    return;
  }
  try {
    final channel = configuredNativeToolchain(
      File(arguments.single).readAsStringSync(),
    );
    stdout.writeln(jsonEncode({'toolchain': channel}));
  } on Object catch (error) {
    // YAML diagnostics can contain source snippets/private build flags.
    stderr.writeln(
      'Invalid Cargokit toolchain configuration (${error.runtimeType})',
    );
    exitCode = 65;
  }
}
