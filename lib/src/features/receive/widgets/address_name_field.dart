import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_text_field.dart';
import '../../../providers/address_labels_provider.dart';

/// An inline label editor for a shielded receive address.
///
/// Renders an [AppTextField] pre-filled with the current persisted label (if
/// any) for the given [accountUuid] + [address] pair.  On submit the label is
/// saved via [addressLabelsProvider]; submitting an empty or whitespace-only
/// value removes the label.
///
/// Key the widget on [address] so Flutter rebuilds it (and the controller
/// resets) whenever the user renews to a new diversified address.
class AddressNameField extends ConsumerStatefulWidget {
  const AddressNameField({
    required this.accountUuid,
    required this.address,
    super.key,
  });

  final String accountUuid;
  final String address;

  @override
  ConsumerState<AddressNameField> createState() => _AddressNameFieldState();
}

class _AddressNameFieldState extends ConsumerState<AddressNameField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  // Tracks the last address/account we synced the controller for, so we
  // can reset the controller when either key changes (address renewed or
  // account switched) without relying solely on keying the widget.
  String? _syncedAddress;
  String? _syncedAccount;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChanged);
    // Sync eagerly from current state; may be empty if async load hasn't
    // finished yet — build() will resync once the provider emits a value.
    _syncFromProvider(
      ref.read(addressLabelsProvider),
      force: true,
    );
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) {
      _save(_controller.text);
    }
  }

  void _save(String text) {
    ref
        .read(addressLabelsProvider.notifier)
        .setLabel(
          accountUuid: widget.accountUuid,
          address: widget.address,
          label: text,
        );
  }

  /// Syncs the controller text from [labels].
  ///
  /// Only updates the controller when:
  /// - [force] is true (address/account key changed), OR
  /// - the field is not focused (so we don't stomp on mid-edit text).
  ///
  /// Records the address+account pair we last synced so we can detect a
  /// key change on the next build.
  void _syncFromProvider(AddressLabelsState labels, {bool force = false}) {
    final label =
        labels.labelFor(widget.accountUuid, widget.address) ?? '';

    final keyChanged = _syncedAddress != widget.address ||
        _syncedAccount != widget.accountUuid;

    if (force || keyChanged || !_focusNode.hasFocus) {
      if (_controller.text != label) {
        _controller.text = label;
      }
    }

    _syncedAddress = widget.address;
    _syncedAccount = widget.accountUuid;
  }

  @override
  Widget build(BuildContext context) {
    // Watch so the field rebuilds (and resyncs) when the provider loads from
    // storage or when a mutation lands from another part of the UI.
    final labels = ref.watch(addressLabelsProvider);
    _syncFromProvider(labels);

    return AppTextField(
      key: const Key('address_name_field'),
      label: 'Address name (optional)',
      hintText: 'e.g. Donations',
      controller: _controller,
      focusNode: _focusNode,
      textInputAction: TextInputAction.done,
      onSubmitted: _save,
      showClearButton: true,
      clearButtonSemanticLabel: 'Clear address name',
    );
  }
}
