/// On-device ProveKit hashbind prover (see native/hashbind_prover/README.md).
///
/// dart:ffi bridge to `libvizor_hashbind_prover` (native/hashbind_prover),
/// the nightly-Rust cdylib wrapping provekit-ffi at the solver-pinned rev.
/// The b2z/z2b spend-auth scalar `k_a` crosses Dart → native memory inside
/// this process and never touches the network — the production replacement
/// for the regtest HTTP prove helper in zwap_swap_config.dart.
///
/// The proof comes back in provekit's `.np` (postcard) binary format: the
/// encoding the solver's native `ProofEngine` verifies, and the wire
/// discriminator between native (Vizor) and JSON (browser wasm) proofs.
library;

import 'dart:convert' show utf8;
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:ffi/ffi.dart' show calloc;
import 'package:flutter/services.dart' show rootBundle;

/// SHA-256 of assets/zwap/pallas.pkp. Pins the bundled proving key to the
/// byte-identical key the solver verifies against (its
/// assets/provekit/hashbind/pallas.pkp); a mismatched asset fails closed
/// before any proving. Update in lockstep with the solver's key regens
/// (next expected: the proxy WP1 digest byte-order fix).
const String kZwapHashbindPkpSha256 =
    'cca9d3a05faf6749dea4b1aed1c9e041f4196b8357a74008cfd55488f8cee29a';

const String _pkpAssetPath = 'assets/zwap/pallas.pkp';
const String _frameworkName = 'VizorHashbindProver';
const int _statusNotInitialized = 100;

/// Matches `PKBuf` / `VizorHashbindBuf` (native/hashbind_prover/include).
final class _NativeBuf extends ffi.Struct {
  external ffi.Pointer<ffi.Uint8> ptr;

  @ffi.Size()
  external int len;

  @ffi.Size()
  external int cap;
}

typedef _InitC = ffi.Int32 Function(ffi.Pointer<ffi.Uint8>, ffi.Size);
typedef _InitDart = int Function(ffi.Pointer<ffi.Uint8>, int);
typedef _ReadyC = ffi.Int32 Function();
typedef _ProveC = ffi.Int32 Function(
    ffi.Pointer<ffi.Uint8>, ffi.Size, ffi.Pointer<_NativeBuf>);
typedef _ProveDart = int Function(
    ffi.Pointer<ffi.Uint8>, int, ffi.Pointer<_NativeBuf>);
typedef _LastErrorC = ffi.Int32 Function(ffi.Pointer<_NativeBuf>);
typedef _LastErrorDart = int Function(ffi.Pointer<_NativeBuf>);
typedef _FreeBufC = ffi.Void Function(_NativeBuf);
typedef _FreeBufDart = void Function(_NativeBuf);

class _Bindings {
  _Bindings(ffi.DynamicLibrary lib)
      : init = lib.lookupFunction<_InitC, _InitDart>('vizor_hashbind_init'),
        ready = lib.lookupFunction<_ReadyC, int Function()>('vizor_hashbind_ready'),
        prove = lib.lookupFunction<_ProveC, _ProveDart>('vizor_hashbind_prove'),
        lastError = lib.lookupFunction<_LastErrorC, _LastErrorDart>(
            'vizor_hashbind_last_error'),
        freeBuf =
            lib.lookupFunction<_FreeBufC, _FreeBufDart>('vizor_hashbind_free_buf');

  final _InitDart init;
  final int Function() ready;
  final _ProveDart prove;
  final _LastErrorDart lastError;
  final _FreeBufDart freeBuf;
}

/// Opens the prover library in the current isolate. The framework is
/// vendored by the VizorHashbindProver pod on iOS/macOS; Android ships the
/// plain .so once an NDK build lane exists (native/hashbind_prover/README.md).
ffi.DynamicLibrary _openLibrary() {
  final List<String> candidates;
  if (Platform.isIOS) {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    candidates = [
      '$exeDir/Frameworks/$_frameworkName.framework/$_frameworkName',
      '$_frameworkName.framework/$_frameworkName',
    ];
  } else if (Platform.isMacOS) {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    candidates = [
      '$exeDir/../Frameworks/$_frameworkName.framework/$_frameworkName',
      '$_frameworkName.framework/$_frameworkName',
    ];
  } else if (Platform.isAndroid) {
    candidates = ['libvizor_hashbind_prover.so'];
  } else {
    throw StateError(
        'on-device hashbind proving unsupported on ${Platform.operatingSystem}');
  }
  Object? lastError;
  for (final path in candidates) {
    try {
      return ffi.DynamicLibrary.open(path);
    } catch (e) {
      lastError = e;
    }
  }
  throw StateError(
      'zwap hashbind prover library not found (build it with '
      'scripts/build-hashbind-prover.sh, then pod install): $lastError');
}

String _readLastError(_Bindings b) {
  final out = calloc<_NativeBuf>();
  try {
    if (b.lastError(out) != 0 || out.ref.ptr == ffi.nullptr) {
      return '(no native error detail)';
    }
    final msg =
        utf8.decode(out.ref.ptr.asTypedList(out.ref.len), allowMalformed: true);
    b.freeBuf(out.ref);
    return msg;
  } finally {
    calloc.free(out);
  }
}

Uint8List _decodeScalarHex(String kBeHex) {
  if (kBeHex.length != 64 || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(kBeHex)) {
    throw ArgumentError(
        'hashbind scalar must be 64 hex chars (32 bytes BE), got '
        '${kBeHex.length} chars');
  }
  final bytes = Uint8List(32);
  for (var i = 0; i < 32; i++) {
    bytes[i] = int.parse(kBeHex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}

/// Generates hashbind proofs with the in-process ProveKit prover.
///
/// Usage: `ZwapNativeHashbindProver.instance.prove(kBeHex)` — the signature
/// matches `ZwapSwapClient.hashbindProver`. Init (asset load + key-hash
/// check + prover-scheme deserialization) runs once per process and is
/// memoized; proving runs on a worker isolate so the multi-second ProveKit
/// computation never blocks the UI thread.
class ZwapNativeHashbindProver {
  ZwapNativeHashbindProver._();

  static final ZwapNativeHashbindProver instance = ZwapNativeHashbindProver._();

  Future<void>? _init;

  Future<void> _ensureInitialized() {
    final existing = _init;
    if (existing != null) {
      return existing;
    }
    late final Future<void> fut;
    fut = _doInit().then<void>((_) {}, onError: (Object e) {
      // Failed init is not sticky — the next prove() retries from scratch.
      if (identical(_init, fut)) {
        _init = null;
      }
      throw e;
    });
    _init = fut;
    return fut;
  }

  Future<void> _doInit() async {
    final pkp = (await rootBundle.load(_pkpAssetPath)).buffer.asUint8List();
    final digest = sha256.convert(pkp).toString();
    if (digest != kZwapHashbindPkpSha256) {
      throw StateError(
          'bundled $_pkpAssetPath does not match the pinned solver proving '
          'key (got sha256 $digest) — refusing to prove against an unknown '
          'circuit key');
    }
    await Isolate.run(() {
      final b = _Bindings(_openLibrary());
      final buf = calloc<ffi.Uint8>(pkp.length);
      try {
        buf.asTypedList(pkp.length).setAll(0, pkp);
        final rc = b.init(buf, pkp.length);
        if (rc != 0) {
          throw StateError(
              'hashbind prover init failed (status $rc): ${_readLastError(b)}');
        }
      } finally {
        calloc.free(buf);
      }
    });
  }

  /// Proves knowledge of the 32-byte BE spend-auth scalar `kBeHex` and
  /// returns the proof bytes (provekit `.np` format). Matches the
  /// `ZwapSwapClient.hashbindProver` callback signature.
  Future<List<int>> prove(String kBeHex) async {
    final scalar = _decodeScalarHex(kBeHex);
    await _ensureInitialized();
    try {
      return await Isolate.run(() {
        final b = _Bindings(_openLibrary());
        final kPtr = calloc<ffi.Uint8>(32);
        final out = calloc<_NativeBuf>();
        try {
          kPtr.asTypedList(32).setAll(0, scalar);
          final rc = b.prove(kPtr, 32, out);
          if (rc == _statusNotInitialized) {
            throw StateError(
                'hashbind prover lost its initialized state unexpectedly');
          }
          if (rc != 0) {
            throw StateError(
                'hashbind proving failed (status $rc): ${_readLastError(b)}');
          }
          final proof =
              Uint8List.fromList(out.ref.ptr.asTypedList(out.ref.len));
          b.freeBuf(out.ref);
          return proof;
        } finally {
          kPtr.asTypedList(32).fillRange(0, 32, 0); // scrub the scalar copy
          calloc.free(kPtr);
          calloc.free(out);
        }
      });
    } finally {
      scalar.fillRange(0, scalar.length, 0);
    }
  }
}
