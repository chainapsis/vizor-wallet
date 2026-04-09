import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Displays animated QR codes cycling through UR parts.
/// Used to transmit large data (e.g., PCZT) to Keystone device.
class AnimatedQrDisplay extends StatefulWidget {
  final List<String> urParts;
  final Duration frameDuration;

  const AnimatedQrDisplay({
    super.key,
    required this.urParts,
    this.frameDuration = const Duration(milliseconds: 100),
  });

  @override
  State<AnimatedQrDisplay> createState() => _AnimatedQrDisplayState();
}

class _AnimatedQrDisplayState extends State<AnimatedQrDisplay> {
  int _currentIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.urParts.length > 1) {
      _timer = Timer.periodic(widget.frameDuration, (_) {
        setState(() {
          _currentIndex = (_currentIndex + 1) % widget.urParts.length;
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
    if (widget.urParts.isEmpty) {
      return const Center(child: Text('No QR data'));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: QrImageView(
            data: widget.urParts[_currentIndex],
            version: QrVersions.auto,
            size: 280,
            errorCorrectionLevel: QrErrorCorrectLevel.L,
          ),
        ),
        if (widget.urParts.length > 1) ...[
          const SizedBox(height: 8),
          Text(
            'Frame ${_currentIndex + 1} / ${widget.urParts.length}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ],
    );
  }
}
