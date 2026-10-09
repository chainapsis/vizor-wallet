import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../integration_test/support/verified_zakura_genesis.dart';
import '../../integration_test/support/zakura_lightwalletd_shim.dart';

const _usage =
    'zakura_lwd_shim.dart --listen-port PORT --upstream-port PORT '
    '--genesis-proof PATH --genesis-proof-sha256 SHA256 --fixture-run-id UUID';

Future<void> main(List<String> args) async {
  const required = {
    '--listen-port',
    '--upstream-port',
    '--genesis-proof',
    '--genesis-proof-sha256',
    '--fixture-run-id',
  };
  final options = <String, String>{};
  late final int listenPort;
  late final int upstreamPort;
  try {
    for (var index = 0; index < args.length; index += 2) {
      if (index + 1 >= args.length ||
          !required.contains(args[index]) ||
          options.containsKey(args[index])) {
        throw const FormatException('unknown, duplicate or incomplete option');
      }
      options[args[index]] = args[index + 1];
    }
    if (options.length != required.length) {
      throw const FormatException('all shim options are required');
    }
    int port(String name) {
      final text = options[name]!;
      if (!RegExp(r'^[1-9][0-9]{0,4}$').hasMatch(text)) {
        throw FormatException('invalid $name');
      }
      final value = int.parse(text);
      if (value > 65535) throw FormatException('invalid $name');
      return value;
    }

    listenPort = port('--listen-port');
    upstreamPort = port('--upstream-port');
    if (listenPort == upstreamPort) {
      throw const FormatException('shim must not listen on its raw upstream');
    }
  } on FormatException catch (error) {
    stderr
      ..writeln(error.message)
      ..writeln(_usage);
    exitCode = 64;
    return;
  }
  final genesis = await VerifiedZakuraGenesis.read(
    options['--genesis-proof']!,
    expectedSha256: options['--genesis-proof-sha256']!,
    fixtureRunId: options['--fixture-run-id']!,
    upstreamPort: upstreamPort,
  );
  final shim = ZakuraLightwalletdShim(
    listenPort: listenPort,
    targetPort: upstreamPort,
    genesis: genesis,
    log: stderr.writeln,
  );
  final stopped = Completer<void>();
  final signals = <StreamSubscription<ProcessSignal>>[];
  var availabilitySequence = 0;
  void setAvailable(bool available) {
    if (available) {
      shim.setHealthy();
    } else {
      shim.setDown();
    }
    stdout.writeln(
      jsonEncode({
        'event': 'zakura-lwd-shim-availability',
        'fixture_run_id': genesis.fixtureRunId,
        'pid': pid,
        'available': available,
        'sequence': ++availabilitySequence,
      }),
    );
  }

  void stop(ProcessSignal _) {
    if (!stopped.isCompleted) stopped.complete();
  }

  try {
    signals.add(ProcessSignal.sigint.watch().listen(stop));
    if (!Platform.isWindows) {
      signals.add(ProcessSignal.sigterm.watch().listen(stop));
      signals.add(
        ProcessSignal.sigusr1.watch().listen((_) => setAvailable(false)),
      );
      signals.add(
        ProcessSignal.sigusr2.watch().listen((_) => setAvailable(true)),
      );
    }
    await shim.start();
    if (!stopped.isCompleted) {
      stdout.writeln(
        jsonEncode({
          'event': 'zakura-lwd-shim-listening',
          'fixture_run_id': genesis.fixtureRunId,
          'genesis_hash': genesis.hash,
          'listen_port': listenPort,
          'upstream_port': upstreamPort,
        }),
      );
      await stopped.future;
    }
  } finally {
    for (final signal in signals) {
      await signal.cancel();
    }
    await shim.stop();
  }
}
