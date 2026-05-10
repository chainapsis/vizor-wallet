import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../main.dart' show log;
import '../rust/api/keystone.dart' as rust_keystone;
import '../rust/wallet/keystone.dart' show KeystoneAccountInfo;
import 'qr_scanner.dart';

/// Abstract transport for communicating with Keystone hardware wallet.
/// USB and QR implementations handle the actual data exchange.
abstract class KeystoneTransport {
  String get name;

  /// Get accounts (UFVKs) from the Keystone device. USB implementations may
  /// ignore [context]; QR implementations use it to present the scan screen.
  Future<List<KeystoneAccountInfo>> getAccounts(BuildContext context);

  /// Sign a redacted PCZT. Returns signed PCZT bytes.
  Future<Uint8List> signPczt(BuildContext context, Uint8List redactedPczt);

  /// Returns available transports for the current platform.
  static List<KeystoneTransport> available() {
    final transports = <KeystoneTransport>[];
    // USB: all platforms except iOS
    if (!Platform.isIOS) {
      transports.add(UsbKeystoneTransport());
    }
    // QR: all platforms (camera/webcam)
    transports.add(QrKeystoneTransport());
    return transports;
  }

  /// Select a transport. If only one is available, returns it directly.
  /// If multiple, shows a bottom sheet for user to choose.
  static Future<KeystoneTransport?> select(BuildContext context) async {
    final list = available();
    if (list.isEmpty) return null;
    if (list.length == 1) return list.first;
    return showModalBottomSheet<KeystoneTransport>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Connect Keystone',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            for (final transport in list)
              ListTile(
                leading: Icon(
                  transport is UsbKeystoneTransport ? Icons.usb : Icons.qr_code,
                ),
                title: Text(transport.name),
                onTap: () => Navigator.pop(ctx, transport),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// USB transport — communicates via Rust FFI (nusb + EAPDU protocol).
class UsbKeystoneTransport implements KeystoneTransport {
  @override
  String get name => 'USB';

  @override
  Future<List<KeystoneAccountInfo>> getAccounts(BuildContext context) async {
    // TODO: Implement USB account retrieval
    // For now, USB account import is not yet supported
    throw UnimplementedError(
      'USB account import not yet supported. Use QR code.',
    );
  }

  @override
  Future<Uint8List> signPczt(
    BuildContext context,
    Uint8List redactedPczt,
  ) async {
    log('KeystoneUSB: sending PCZT for signing...');
    final signed = await rust_keystone.keystoneUsbSignPczt(
      pcztBytes: redactedPczt,
    );
    log('KeystoneUSB: received signed PCZT');
    return signed;
  }

  /// Check if a Keystone device is currently connected via USB.
  static Future<bool> isConnected() => rust_keystone.isKeystoneConnected();
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
