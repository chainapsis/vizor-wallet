// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'package:flutter/widgets.dart';

import '../src/core/layout/app_desktop_shell.dart';
import '../src/core/layout/app_pane_scroll_scaffold.dart';
import '../src/core/profile_pictures.dart';
import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_back_link.dart';
import '../src/core/widgets/app_icon.dart';
import '../src/core/widgets/app_pane_modal_overlay.dart';
import '../src/core/widgets/app_profile_picture.dart';
import '../src/features/address_book/models/address_book_contact.dart';
import '../src/features/address_book/models/address_format_validator.dart';
import '../src/features/pay/models/pay_recent_recipients.dart';
import '../src/features/pay/widgets/pay_add_contact_modal.dart';
import '../src/features/pay/widgets/pay_amount_step.dart';
import '../src/features/pay/widgets/pay_recipient_step.dart';
import '../src/features/pay/widgets/pay_review_step.dart';
import '../src/features/pay/widgets/pay_wizard_page.dart';
import '../src/features/swap/models/swap_models.dart';
import '../src/features/swap/models/swap_activity_status_mapper.dart';
import '../src/features/swap/widgets/pay_activity_status_content.dart';
import '../src/features/swap/widgets/swap_asset_selector_modal.dart';

const _previewWindowSize = Size(1080, 720);
const _contactAddress = '0x52908400098527886E0F7030069857D2E4169EE7';
const _newRecipientAddress = '0x1234567890123456789012345678901234567890';
const _recipientQuoteError =
    'This route or address was rejected.\n'
    'Edit the details and request a new quote.';

Widget buildPayAmountUseCase(BuildContext context) {
  return const _PayDesktopFrame(child: _PayAmountPreview());
}

Widget buildPayRecipientUseCase(BuildContext context) {
  return const _PayDesktopFrame(child: _PayRecipientPreview());
}

Widget buildPayRecipientNewAddressUseCase(BuildContext context) {
  return const _PayDesktopFrame(
    child: _PayRecipientPreview(initialAddress: _newRecipientAddress),
  );
}

Widget buildPayRecipientQuoteErrorUseCase(BuildContext context) {
  return const _PayDesktopFrame(
    child: _PayRecipientPreview(
      initialAddress: _newRecipientAddress,
      quoteError: _recipientQuoteError,
    ),
  );
}

Widget buildPayReviewUseCase(BuildContext context) {
  return const _PayDesktopFrame(child: _PayReviewPreview(expired: false));
}

Widget buildPayReviewExpiredUseCase(BuildContext context) {
  return const _PayDesktopFrame(child: _PayReviewPreview(expired: true));
}

Widget buildPayAssetSelectorUseCase(BuildContext context) {
  return const _PayDesktopFrame(child: _PayAssetSelectorPreview());
}

Widget buildPayAddContactUseCase(BuildContext context) {
  return const _PayDesktopFrame(child: _PayAddContactPreview());
}

Widget buildPayInProgressUseCase(BuildContext context) {
  return const _PayDesktopFrame(
    child: _PayStatusPreview(phase: PayActivityStatusPhase.inProgress),
  );
}

Widget buildPayCompletedUseCase(BuildContext context) {
  return const _PayDesktopFrame(
    child: _PayStatusPreview(phase: PayActivityStatusPhase.completed),
  );
}

class _PayDesktopFrame extends StatelessWidget {
  const _PayDesktopFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox.fromSize(
        size: _previewWindowSize,
        child: AppDesktopShell(
          sidebar: const _PayPreviewSidebar(),
          pane: AppDesktopPane(padding: EdgeInsets.zero, child: child),
        ),
      ),
    );
  }
}

class _PayAmountPreview extends StatefulWidget {
  const _PayAmountPreview();

  @override
  State<_PayAmountPreview> createState() => _PayAmountPreviewState();
}

class _PayAmountPreviewState extends State<_PayAmountPreview> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  var _state = const SwapState(
    direction: SwapDirection.zecToExternal,
    quoteMode: SwapQuoteMode.exactOutput,
    amountText: '',
    receiveAmountText: '',
    receiveFiatText: '',
    destinationText: '',
    externalAsset: SwapAsset.usdc,
    reviewVisible: false,
    intents: [],
    payMode: true,
  );

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _state.receiveAmountText);
    _focusNode = FocusNode(debugLabel: 'WidgetbookPayAmount');
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _toggleFiatMode() {
    final switchToFiat =
        _state.receiveAmountInputMode == SwapAmountInputMode.token;
    setState(() {
      _state = _state.copyWith(
        receiveAmountInputMode: switchToFiat
            ? SwapAmountInputMode.fiat
            : SwapAmountInputMode.token,
        receiveAmountText: '12',
        receiveFiatText: switchToFiat ? '840.00' : '',
      );
      _controller.value = TextEditingValue(
        text: switchToFiat ? '840.00' : '12',
        selection: TextSelection.collapsed(offset: switchToFiat ? 6 : 2),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return PayWizardPage(
      title: 'Pay in USDC',
      currentIndex: 0,
      backLabel: 'Home',
      onBack: () {},
      headingTrailing: const _PreviewSlippageControl(),
      actions: PayAmountAction(state: _state, onContinue: () {}),
      child: PayAmountStep(
        state: _state,
        controller: _controller,
        focusNode: _focusNode,
        onAmountChanged: (value) =>
            setState(() => _state = _state.copyWith(receiveAmountText: value)),
        onFiatAmountChanged: (value) =>
            setState(() => _state = _state.copyWith(receiveFiatText: value)),
        onToggleFiatInputMode: _toggleFiatMode,
        onOpenAssetSelector: () {},
      ),
    );
  }
}

class _PayRecipientPreview extends StatefulWidget {
  const _PayRecipientPreview({this.initialAddress = '', this.quoteError});

  final String initialAddress;
  final String? quoteError;

  @override
  State<_PayRecipientPreview> createState() => _PayRecipientPreviewState();
}

class _PayRecipientPreviewState extends State<_PayRecipientPreview> {
  late final TextEditingController _controller;
  late String _typedAddress;

  @override
  void initState() {
    super.initState();
    _typedAddress = widget.initialAddress;
    _controller = TextEditingController(text: _typedAddress);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _selectAddress(String address) {
    setState(() {
      _typedAddress = address;
      _controller.value = TextEditingValue(
        text: address,
        selection: TextSelection.collapsed(offset: address.length),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final issue = _typedAddress.isEmpty
        ? null
        : addressFormatIssue(AddressBookNetwork.ethereum, _typedAddress);
    final actions = PayRecipientActions(
      typedAddress: _typedAddress,
      addressError: issue,
      contacts: _previewContacts,
      busy: false,
      quoteError: widget.quoteError,
      onSelectRecipient: () {},
      onAddToContacts: () {},
    );
    return PayWizardPage(
      title: 'Select Recipient',
      currentIndex: 1,
      backLabel: 'Amount',
      onBack: () {},
      actions: actions.visible ? actions : null,
      onStepSelected: (_) {},
      child: PayRecipientStep(
        controller: _controller,
        typedAddress: _typedAddress,
        addressError: issue,
        contacts: _previewContacts,
        recents: _previewRecents,
        busy: false,
        onAddressChanged: (value) => setState(() => _typedAddress = value),
        onOpenScanner: () {},
        onChooseRecipient: _selectAddress,
      ),
    );
  }
}

class _PayReviewPreview extends StatelessWidget {
  const _PayReviewPreview({required this.expired});

  final bool expired;

  @override
  Widget build(BuildContext context) {
    return PayWizardPage(
      title: 'Review Payment',
      currentIndex: 2,
      backLabel: 'Recipient',
      onBack: () {},
      onStepSelected: (_) {},
      actions: PayReviewAction(
        expired: expired,
        starting: false,
        startBlockedReason: null,
        onConfirm: () {},
        onReviewAgain: () {},
      ),
      child: PayReviewStep(
        quote: _previewQuote,
        recipientAddress: _contactAddress,
        recipientContact: _previewContacts.first,
        payingFiatText: r'$990.10',
        convertedFiatText: r'$100.10',
        expiresInText: expired ? null : '1:30',
        expired: expired,
        starting: false,
        startBlockedReason: null,
        startError: null,
        onShowFullAddress: () {},
        onConfirm: () {},
        onReviewAgain: () {},
      ),
    );
  }
}

class _PayAssetSelectorPreview extends StatelessWidget {
  const _PayAssetSelectorPreview();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const _PayAmountPreview(),
        AppPaneModalOverlay(
          onDismiss: () {},
          child: SwapAssetSelectorModal(
            assets: swapExternalAssets,
            selected: SwapAsset.usdc,
            onSelected: (_) {},
          ),
        ),
      ],
    );
  }
}

class _PayAddContactPreview extends StatelessWidget {
  const _PayAddContactPreview();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const _PayRecipientPreview(initialAddress: _newRecipientAddress),
        AppPaneModalOverlay(
          onDismiss: () {},
          child: PayAddContactModal(
            network: AddressBookNetwork.ethereum,
            address: _newRecipientAddress,
            onCancel: () {},
            onSave: (_, _) async {},
          ),
        ),
      ],
    );
  }
}

class _PayStatusPreview extends StatelessWidget {
  const _PayStatusPreview({required this.phase});

  final PayActivityStatusPhase phase;

  @override
  Widget build(BuildContext context) {
    return AppPaneScrollScaffold(
      toolbar: AppPaneToolbar(
        leading: AppBackLink(label: 'Activity', minWidth: 60, onTap: () {}),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: PayActivityStatusContent(
          status: PayActivityStatusPresentation(
            phase: phase,
            timestampText: '25 May, 13:30',
            txIdText: '0123123124512512',
            convertedFromText: '2.45125 ZEC',
            // Synthetic Figma fixture. Production shows this only after the
            // matching ZEC deposit transaction is confirmed in wallet history.
            transactionFeeText: '0.012 ZEC',
          ),
          amountAsset: SwapAsset.usdc,
          amountText: '990 USDC',
          amountFiatText: r'$990.12',
          recipientAddress: _newRecipientAddress,
          onShowFullAddress: () {},
          onOpenExplorer: () {},
        ),
      ),
    );
  }
}

class _PreviewSlippageControl extends StatelessWidget {
  const _PreviewSlippageControl();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '2%',
            style: AppTypography.labelLarge.copyWith(
              fontWeight: FontWeight.w400,
              color: context.colors.text.secondary,
            ),
          ),
          const SizedBox(width: AppSpacing.xxs),
          AppIcon(AppIcons.cog, size: 16, color: context.colors.icon.muted),
        ],
      ),
    );
  }
}

class _PayPreviewSidebar extends StatelessWidget {
  const _PayPreviewSidebar();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppDesktopSidebarSurface(
      glass: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _PreviewAccountHeader(),
            const SizedBox(height: AppSpacing.md),
            const AppSidebarItem(
              label: 'Home',
              iconName: AppIcons.home,
              active: true,
            ),
            const SizedBox(height: AppSpacing.xs),
            AppSidebarItem(
              label: 'Swap',
              iconName: AppIcons.swapArrows,
              onTap: () {},
            ),
            const SizedBox(height: AppSpacing.xs),
            AppSidebarItem(
              label: 'Vote',
              iconName: AppIcons.scroll,
              onTap: () {},
            ),
            const SizedBox(height: AppSpacing.xs),
            AppSidebarItem(
              label: 'Activity',
              iconName: AppIcons.history,
              onTap: () {},
            ),
            const Spacer(),
            AppSidebarItem(
              label: 'Settings',
              iconName: AppIcons.cog,
              onTap: () {},
            ),
            const SizedBox(height: AppSpacing.xs),
            AppSidebarItem(
              label: 'Sign out',
              iconName: AppIcons.logOut,
              onTap: () {},
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: 20,
              child: Row(
                children: [
                  Container(
                    width: 5,
                    decoration: BoxDecoration(
                      color: colors.sync.lightSuccess,
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(AppRadii.full),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '34% Syncing...',
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.sync.textSyncing,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewAccountHeader extends StatelessWidget {
  const _PreviewAccountHeader();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          const AppProfilePicture(
            profilePictureId: kDefaultProfilePictureId,
            size: AppProfilePictureSize.large,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Username',
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  '142.23 ZEC',
                  style: AppTypography.labelLarge.copyWith(
                    fontWeight: FontWeight.w400,
                    color: colors.text.secondary,
                  ),
                ),
              ],
            ),
          ),
          AppIcon(AppIcons.copy, size: 16, color: colors.icon.muted),
        ],
      ),
    );
  }
}

final _previewContacts = [
  const AddressBookContact(
    id: 'mike',
    label: 'Mike',
    network: AddressBookNetwork.ethereum,
    address: _contactAddress,
    profilePictureId: 'pfp-01',
    createdAtMs: 0,
    updatedAtMs: 0,
  ),
  const AddressBookContact(
    id: 'contact-label',
    label: 'Contact label',
    network: AddressBookNetwork.ethereum,
    address: '0x1111111111111111111111111111111111111111',
    profilePictureId: 'pfp-02',
    createdAtMs: 0,
    updatedAtMs: 0,
  ),
];

final _previewRecents = [
  PayRecentRecipient(
    address: _contactAddress,
    amountText: '-24 USDC',
    lastUsedAt: DateTime.now().subtract(const Duration(days: 2)),
  ),
  PayRecentRecipient(
    address: '0x2222222222222222222222222222222222222222',
    amountText: '-18.50 USDC',
    lastUsedAt: DateTime.now().subtract(const Duration(days: 3)),
  ),
  PayRecentRecipient(
    address: '0x3333333333333333333333333333333333333333',
    amountText: '-12 USDC',
    lastUsedAt: DateTime(2026, 5, 14),
  ),
];

final _previewQuote = SwapQuote(
  direction: SwapDirection.zecToExternal,
  sellAsset: SwapAsset.zec,
  receiveAsset: SwapAsset.usdc,
  externalAsset: SwapAsset.usdc,
  mode: SwapQuoteMode.exactOutput,
  sellAmount: 2.124512,
  receiveAmount: 990,
  minimumReceiveAmount: 990,
  providerLabel: 'NEAR Intents',
  feeLabel: 'Included in shown rate',
  expiryLabel: '1:30',
  sellAmountTextOverride: '2.124512',
  receiveEstimateTextOverride: '990 USDC',
  minimumReceiveTextOverride: '990 USDC',
  depositInstruction: const SwapDepositInstruction(
    asset: SwapAsset.zec,
    address: 'widgetbook-zec-deposit',
    expiresInLabel: '1:30',
    reuseWarning: 'Do not reuse this address',
  ),
);
