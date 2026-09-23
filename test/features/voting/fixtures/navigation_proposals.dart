import 'package:zcash_wallet/src/features/voting/voting_flow_models.dart';

const proposals = [
  VotingProposalView(
    id: 7,
    title: 'First',
    description: 'First proposal',
    options: [VotingOptionView(index: 0, label: 'Accept')],
  ),
  VotingProposalView(
    id: 91,
    title: 'Last',
    description: 'Last proposal',
    options: [VotingOptionView(index: 0, label: 'Accept')],
  ),
];
