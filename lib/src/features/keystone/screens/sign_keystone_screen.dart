import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../main.dart' show log;
import '../../../services/keystone_transport.dart';

/// Screen that handles Keystone signing flow.
/// For USB: shows a waiting indicator while the device signs.
/// For QR: shows animated QR + camera scan (TODO).
class SignKeystoneScreen extends StatefulWidget {
  final Uint8List redactedPczt;
  final void Function(Uint8List signedPczt) onSigned;
  final VoidCallback onCancel;

  const SignKeystoneScreen({
    super.key,
    required this.redactedPczt,
    required this.onSigned,
    required this.onCancel,
  });

  @override
  State<SignKeystoneScreen> createState() => _SignKeystoneScreenState();
}

class _SignKeystoneScreenState extends State<SignKeystoneScreen> {
  bool _isSigning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _startSigning());
  }

  Future<void> _startSigning() async {
    final transport = await KeystoneTransport.select(context);
    if (transport == null || !mounted) {
      widget.onCancel();
      return;
    }

    setState(() { _isSigning = true; _error = null; });

    try {
      final signed = await transport.signPczt(context, widget.redactedPczt);
      if (!mounted) return;
      widget.onSigned(signed);
    } catch (e) {
      log('SignKeystone: error: $e');
      if (!mounted) return;
      setState(() { _error = e.toString(); _isSigning = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign with Keystone'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: widget.onCancel,
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: _error != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, color: colors.error, size: 48),
                    const SizedBox(height: 16),
                    Text('Signing Failed', style: text.titleLarge),
                    const SizedBox(height: 8),
                    Text(_error!, textAlign: TextAlign.center,
                        style: text.bodyMedium?.copyWith(color: colors.outline)),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _startSigning,
                      child: const Text('Retry'),
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.usb, size: 64),
                    const SizedBox(height: 24),
                    Text('Confirm on Keystone', style: text.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                      'Check the transaction details on your\nKeystone device and confirm to sign.',
                      textAlign: TextAlign.center,
                      style: text.bodyMedium?.copyWith(color: colors.outline),
                    ),
                    const SizedBox(height: 32),
                    if (_isSigning) const CircularProgressIndicator(),
                  ],
                ),
        ),
      ),
    );
  }
}
