import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../providers/app_security_provider.dart';
import '../../../onboarding/mobile/mobile_passcode_screen.dart'
    show kMobilePasscodeLength;
import '../../../onboarding/mobile/mobile_passcode_layout.dart';

class MobileAccountRemovalPasscodeScreen extends ConsumerStatefulWidget {
  const MobileAccountRemovalPasscodeScreen({
    required this.isLastAccount,
    super.key,
  });

  final bool isLastAccount;

  @override
  ConsumerState<MobileAccountRemovalPasscodeScreen> createState() =>
      _MobileAccountRemovalPasscodeScreenState();
}

class _MobileAccountRemovalPasscodeScreenState
    extends ConsumerState<MobileAccountRemovalPasscodeScreen> {
  String _entry = '';
  String? _error;
  bool _checking = false;

  Future<void> _onDigit(int digit) async {
    if (_checking || _entry.length >= kMobilePasscodeLength) return;
    setState(() {
      _entry += '$digit';
      _error = null;
    });
    if (_entry.length != kMobilePasscodeLength) return;
    setState(() => _checking = true);
    try {
      final verified = await ref
          .read(appSecurityProvider.notifier)
          .confirmPassword(_entry);
      // A popped screen can stay mounted during its exit animation.
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      if (verified) {
        _entry = '';
        context.pop(true);
        return;
      }
      setState(() => _error = 'Incorrect passcode');
    } catch (_) {
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      setState(
        () => _error = "Couldn't check your passcode. Please try again.",
      );
    } finally {
      if (mounted) {
        setState(() {
          _entry = '';
          _checking = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MobilePasscodeLayout(
      key: const ValueKey('mobile_account_removal_passcode'),
      title: 'Enter Passcode',
      subtitle: widget.isLastAccount
          ? 'Enter your passcode to reset Vizor.'
          : 'Enter your passcode to remove this account.',
      navigation: MobileTopNav.back(
        title: '',
        onBack: () => context.pop(false),
      ),
      filled: _entry.length,
      error: _error,
      onDigit: _onDigit,
      onBackspace: () {
        if (_checking || _entry.isEmpty) return;
        setState(() => _entry = _entry.substring(0, _entry.length - 1));
      },
      enabled: !_checking,
    );
  }
}
