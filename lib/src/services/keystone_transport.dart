import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../main.dart' show log;
import '../rust/api/keystone.dart' as rust_keystone;

/// Abstract transport for communicating with Keystone hardware wallet.
/// USB and QR implementations handle the actual data exchange.
abstract class KeystoneTransport {
  String get name;

  /// Get accounts (UFVKs) from the Keystone device.
  Future<List<rust_keystone.KeystoneAccountInfo>> getAccounts();

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
  Future<List<rust_keystone.KeystoneAccountInfo>> getAccounts() async {
    // TODO: Implement USB account retrieval
    // For now, USB account import is not yet supported
    throw UnimplementedError('USB account import not yet supported. Use QR code.');
  }

  @override
  Future<Uint8List> signPczt(BuildContext context, Uint8List redactedPczt) async {
    log('KeystoneUSB: sending PCZT for signing...');
    final signed = await rust_keystone.keystoneUsbSignPczt(pcztBytes: redactedPczt);
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

  @override
  Future<List<rust_keystone.KeystoneAccountInfo>> getAccounts() async {
    // TODO: Open camera, scan animated QR from Keystone device,
    // decode UR string, call rust_keystone.decodeAccountsUr()
    throw UnimplementedError('QR account import not yet implemented.');
  }

  @override
  Future<Uint8List> signPczt(BuildContext context, Uint8List redactedPczt) async {
    // TODO:
    // 1. Encode PCZT to UR: rust_keystone.encodePcztToUr(pcztBytes: redactedPczt)
    // 2. Display animated QR on screen for Keystone to scan
    // 3. Open camera to scan signed PCZT QR from Keystone
    // 4. Decode UR: rust_keystone.decodeUrToPczt(urString: scannedUr)
    throw UnimplementedError('QR signing not yet implemented.');
  }
}
