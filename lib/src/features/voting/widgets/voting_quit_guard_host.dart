import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/voting/voting_submission_job_provider.dart';

const kVotingQuitGuardChannelName = 'com.zcash.wallet/voting_quit_guard';
const kVotingQuitGuardConfirmMethod = 'confirmQuitDuringVotingSubmission';

class VotingQuitGuardHost extends ConsumerStatefulWidget {
  const VotingQuitGuardHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<VotingQuitGuardHost> createState() =>
      _VotingQuitGuardHostState();
}

class _VotingQuitGuardHostState extends ConsumerState<VotingQuitGuardHost> {
  static const _channel = MethodChannel(kVotingQuitGuardChannelName);

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<Object?> _handleMethodCall(MethodCall call) async {
    if (call.method != kVotingQuitGuardConfirmMethod) return true;
    return _confirmQuitIfNeeded();
  }

  Future<bool> _confirmQuitIfNeeded() async {
    final hasInFlightJobs = ref.read(votingSubmissionHasInFlightJobsProvider);
    if (!hasInFlightJobs) return true;
    if (!mounted) return false;

    final quit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Vote submission in progress'),
          content: const Text(
            'Your vote is still being submitted. Quitting now may interrupt the process.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Quit anyway'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep app open'),
            ),
          ],
        );
      },
    );
    return quit == true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
