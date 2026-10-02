import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../providers/app_security_provider.dart';
import '../../../onboarding/mobile/mobile_passcode_screen.dart'
    show kMobilePasscodeLength;
import '../../../onboarding/mobile/passcode_widgets.dart';

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
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: Column(
          children: [
            MobileTopNav.back(title: '', onBack: () => context.pop(false)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.md,
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              key: const ValueKey(
                                'mobile_account_removal_passcode',
                              ),
                              'Enter Passcode',
                              textAlign: TextAlign.center,
                              style: AppTypography.displayLarge.copyWith(
                                color: colors.text.accent,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.s),
                            Text(
                              widget.isLastAccount
                                  ? 'Enter your passcode to reset Vizor.'
                                  : 'Enter your passcode to remove this account.',
                              textAlign: TextAlign.center,
                              style: AppTypography.bodyMediumStrong.copyWith(
                                color: colors.text.primary,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            SizedBox(
                              height: kPasscodePromptDigitsHeight,
                              child: PasscodePromptField(
                                length: kMobilePasscodeLength,
                                filled: _entry.length,
                                error: _error,
                                minGap: 0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    PasscodeNumpad(
                      onDigit: _onDigit,
                      onBackspace: () {
                        if (_checking || _entry.isEmpty) return;
                        setState(
                          () => _entry = _entry.substring(0, _entry.length - 1),
                        );
                      },
                      canDelete: _entry.isNotEmpty,
                      enabled: !_checking,
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
