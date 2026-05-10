import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../main.dart' show log;
import '../rust/api/keystone.dart' as rust_keystone;
import '../rust/wallet/keystone.dart' show KeystoneAccountInfo;
import 'qr_scanner.dart';

/// QR-only transport for communicating with Keystone hardware wallet.
abstract class KeystoneTransport {
  String get name;

  /// Get accounts (UFVKs) from the Keystone device by scanning Keystone QR.
  Future<List<KeystoneAccountInfo>> getAccounts(BuildContext context);

  /// Sign a redacted PCZT through animated QR exchange.
  Future<Uint8List> signPczt(BuildContext context, Uint8List redactedPczt);

  /// Returns the QR transport when camera scanning is supported.
  static List<KeystoneTransport> available() {
    return QrScanner.isAvailable ? [QrKeystoneTransport()] : [];
  }

  /// Select the only supported transport.
  static Future<KeystoneTransport?> select(BuildContext context) async {
    final list = available();
    if (list.isEmpty) return null;
    return list.first;
  }
}

/// QR transport — displays animated QR codes and scans via camera.
class QrKeystoneTransport implements KeystoneTransport {
  @override
  String get name => 'QR Code';

  /// Import accounts by scanning Keystone's ZcashAccounts QR.
  @override
  Future<List<KeystoneAccountInfo>> getAccounts(BuildContext context) async {
    log('KeystoneQR: scanning for ZcashAccounts QR...');
    final result = await QrScanner.scanAnimatedUr(
      context,
      expectedUrType: 'zcash-accounts',
    );
    if (result == null) throw Exception('Scan cancelled');

    // result.data is the CBOR-encoded ZcashAccounts envelope. Unwrap in Rust.
    final accounts = await rust_keystone.decodeAccountsFromCbor(
      cbor: result.data,
    );
    log('KeystoneQR: received ${accounts.length} accounts');
    return accounts;
  }

  @override
  Future<Uint8List> signPczt(
    BuildContext context,
    Uint8List redactedPczt,
  ) async {
    log('KeystoneQR: encoding PCZT for QR display...');

    // 1. Encode PCZT into animated QR parts
    final parts = await rust_keystone.encodePcztUrParts(
      pcztBytes: redactedPczt,
      maxFragmentLen: BigInt.from(
        200,
      ), // ~200 bytes per QR frame for reliable scanning
    );

    // 2. Show animated QR + wait for user to confirm Keystone scanned it
    if (!context.mounted) throw Exception('Context not mounted');
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _SignQrDialog(urParts: parts),
    );
    if (confirmed != true) throw Exception('Signing cancelled');

    // 3. Scan signed PCZT QR from Keystone
    if (!context.mounted) throw Exception('Context not mounted');
    log('KeystoneQR: scanning signed PCZT QR...');

    final result = await QrScanner.scanAnimatedUr(
      context,
      expectedUrType: 'zcash-pczt',
    );
    if (result == null) throw Exception('Scan cancelled');

    // result.data is the CBOR-encoded ZcashPczt envelope ({1: bytes}).
    // Unwrap it to get the raw PCZT bytes.
    final pcztBytes = await rust_keystone.decodePcztFromCbor(cbor: result.data);
    log('KeystoneQR: received signed PCZT (${pcztBytes.length} bytes)');
    return Uint8List.fromList(pcztBytes);
  }
}

/// Dialog that shows animated QR for Keystone to scan, with a "Next" button.
class _SignQrDialog extends StatelessWidget {
  final List<String> urParts;
  const _SignQrDialog({required this.urParts});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Show to Keystone'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Point your Keystone device camera at this QR code.'),
          const SizedBox(height: 16),
          // Lazy import to avoid circular dependency
          _buildQrDisplay(),
          const SizedBox(height: 16),
          const Text(
            'After Keystone finishes scanning, tap Next to scan the signed QR.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Next'),
        ),
      ],
    );
  }

  Widget _buildQrDisplay() {
    return SizedBox(
      width: 300,
      height: 320,
      child: _AnimatedQr(urParts: urParts),
    );
  }
}

class _AnimatedQr extends StatefulWidget {
  final List<String> urParts;
  const _AnimatedQr({required this.urParts});

  @override
  State<_AnimatedQr> createState() => _AnimatedQrState();
}

class _AnimatedQrState extends State<_AnimatedQr> {
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.urParts.length > 1) {
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        setState(() {
          _index = (_index + 1) % widget.urParts.length;
        });
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.urParts.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          color: Colors.white,
          child: QrImageView(
            data: widget.urParts[_index],
            size: 260,
            errorCorrectionLevel: QrErrorCorrectLevel.L,
          ),
        ),
        if (widget.urParts.length > 1)
          Text(
            '${_index + 1}/${widget.urParts.length}',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
      ],
    );
  }
}
