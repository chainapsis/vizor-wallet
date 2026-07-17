import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../onboarding/mobile/mobile_passcode_screen.dart'
    show kMobilePasscodeLength;
import '../../../onboarding/mobile/passcode_widgets.dart';
import 'mobile_migration_progress_indicator.dart';

class MobileMigrationPasscodeView extends StatefulWidget {
  const MobileMigrationPasscodeView({required this.progress, super.key});

  final double progress;

  @override
  State<MobileMigrationPasscodeView> createState() =>
      _MobileMigrationPasscodeViewState();
}

class _MobileMigrationPasscodeViewState
    extends State<MobileMigrationPasscodeView> {
  var _entryLength = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background.window,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
          ),
          child: Column(
            children: [
              MobileMigrationPasscodeHero(progress: widget.progress),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                height: 82,
                child: Column(
                  children: [
                    SizedBox(
                      height: 57,
                      child: Center(
                        child: PasscodeDots(
                          length: kMobilePasscodeLength,
                          filled: _entryLength,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    const SizedBox(height: 17),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              PasscodeNumpad(
                onDigit: (_) {
                  if (_entryLength >= kMobilePasscodeLength) return;
                  setState(() => _entryLength += 1);
                },
                onBackspace: () {
                  if (_entryLength == 0) return;
                  setState(() => _entryLength -= 1);
                },
                canDelete: _entryLength > 0,
                onHelp: () {},
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
