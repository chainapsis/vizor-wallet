import 'dart:convert';

import '../../../core/config/network_config.dart';
import '../../../core/payments/cross_chain_payment_request.dart';
import '../../../core/zcash/zip321_payment_request.dart';
import '../../address_book/models/address_book_contact.dart';
import '../../address_book/models/address_format_validator.dart';
import '../../pay/models/payment_request_resolution.dart';
import '../../swap/domain/swap_asset.dart';

/// The purpose of an input survives URI parsing and recipient extraction.
enum AddressInputContext { send, pay, swapRecipient, swapRefund, contact }

class AddressInputPolicy {
  const AddressInputPolicy({
    required this.context,
    required this.network,
    required this.zcashNetwork,
    this.assets = const [],
  });

  final AddressInputContext context;
  final AddressBookNetwork network;
  final ZcashNetwork zcashNetwork;
  final List<SwapAsset> assets;
}

enum AddressInputResultKind { address, paymentRequest, rejected }

class AddressInputResult {
  const AddressInputResult.address(this.address)
    : kind = AddressInputResultKind.address,
      rawPaymentUri = null,
      crossChainRequest = null,
      zcashRequest = null,
      reason = null;

  const AddressInputResult.paymentRequest({
    required this.rawPaymentUri,
    this.crossChainRequest,
    this.zcashRequest,
  }) : kind = AddressInputResultKind.paymentRequest,
       address = null,
       reason = null;

  const AddressInputResult.rejected(this.reason)
    : kind = AddressInputResultKind.rejected,
      address = null,
      rawPaymentUri = null,
      crossChainRequest = null,
      zcashRequest = null;

  final AddressInputResultKind kind;
  final String? address;
  final String? rawPaymentUri;
  final CrossChainPaymentRequest? crossChainRequest;
  final Zip321PaymentRequest? zcashRequest;
  final String? reason;
}

const _sendOnly =
    'Only Zcash addresses and payment requests can be scanned here.';
const _payOnly = 'Use Send for Zcash addresses and payment requests.';
const _swapAddressOnly =
    'Only wallet addresses can be used here. Scan payment requests in Pay.';
const _invalidRequest = 'This payment request is not valid.';
const _wrongNetwork = 'This address or request uses a different network.';

/// Resolves a complete scan/paste candidate without changing any application
/// state. Callers must also discard results after their input session changes.
/// [validateZcashAddress] returns null for a valid address on the given network.
Future<AddressInputResult> resolveAddressInput(
  String raw, {
  required AddressInputPolicy policy,
  required Future<String?> Function(String, ZcashNetwork) validateZcashAddress,
  required Future<CrossChainPaymentRequest> Function(String)
  parseCrossChainRequest,
}) async {
  final input = raw.trim();
  if (input.isEmpty) {
    return const AddressInputResult.rejected('Enter a wallet address.');
  }
  if (input.length > kMaxPaymentUriLength ||
      utf8.encode(input).length > kMaxPaymentUriLength) {
    return const AddressInputResult.rejected('Payment link is too long.');
  }
  try {
    // TON raw addresses use a numeric workchain prefix, which is not a URI
    // scheme. Validate the full address before the generic URI parser.
    if (policy.network == AddressBookNetwork.ton &&
        RegExp(r'^-?\d+:[0-9a-fA-F]{64}$').hasMatch(input)) {
      return await _validateAddress(input, policy, validateZcashAddress);
    }
    final uri = Uri.tryParse(input);
    if (uri == null) return const AddressInputResult.rejected(_invalidRequest);
    final scheme = uri.scheme.toLowerCase();
    // CashAddr's prefix is part of the address, rather than a payment scheme.
    final isCashAddress =
        policy.network == AddressBookNetwork.bitcoinCash &&
        {'bitcoincash', 'bchtest', 'bchreg'}.contains(scheme) &&
        !uri.hasQuery &&
        !uri.hasFragment;
    if (scheme.isEmpty || isCashAddress) {
      final result = await _validateAddress(
        input,
        policy,
        validateZcashAddress,
      );
      if (result.kind == AddressInputResultKind.rejected &&
          policy.context != AddressInputContext.send &&
          policy.context != AddressInputContext.contact &&
          _isZcashAddress(input)) {
        return const AddressInputResult.rejected(_payOnly);
      }
      return result;
    }
    if (scheme == 'zcash') {
      if (policy.context != AddressInputContext.send &&
          !(policy.context == AddressInputContext.contact &&
              policy.network == AddressBookNetwork.zcash)) {
        return const AddressInputResult.rejected(_payOnly);
      }
      final request = Zip321PaymentRequest.parse(input);
      if (request.unsupportedReason case final reason?) {
        return AddressInputResult.rejected(reason);
      }
      final checked = await _validateAddress(
        request.primaryPayment.address,
        policy,
        validateZcashAddress,
      );
      if (checked.kind == AddressInputResultKind.rejected) return checked;
      if (policy.context == AddressInputContext.contact) return checked;
      return AddressInputResult.paymentRequest(
        rawPaymentUri: input,
        zcashRequest: request,
      );
    }
    if (policy.context == AddressInputContext.send) {
      return const AddressInputResult.rejected(_sendOnly);
    }
    if (crossChainPaymentSchemes.contains(scheme)) {
      final request = await parseCrossChainRequest(input);
      if (request.unsupportedReason case final reason?) {
        return AddressInputResult.rejected(reason);
      }
      final explicitChain = request.isEvm
          ? request.chainId == null
                ? null
                : evmPaymentNetworks[request.chainId]?.chain
          : request.chain;
      if (request.isEvm && request.chainId != null && explicitChain == null) {
        return const AddressInputResult.rejected(
          'This request uses a network that Vizor does not support.',
        );
      }
      final hasTerms = _hasPaymentTerms(uri, request);
      if (policy.context == AddressInputContext.swapRefund && hasTerms) {
        return const AddressInputResult.rejected(_swapAddressOnly);
      }
      final isPaymentRequest =
          (policy.context == AddressInputContext.pay ||
              policy.context == AddressInputContext.swapRecipient) &&
          hasTerms;
      // A full payment request may change the selected asset only after the request
      // card is accepted. Address extraction must match the existing selection.
      if (!isPaymentRequest &&
          (explicitChain != null && explicitChain != policy.network.id ||
              request.isEvm && !policy.network.isEvm)) {
        return const AddressInputResult.rejected(_wrongNetwork);
      }
      final requestNetwork = explicitChain == null
          ? (request.isEvm ? AddressBookNetwork.ethereum : null)
          : AddressBookNetwork.tryFromId(explicitChain);
      if (requestNetwork == null) {
        return const AddressInputResult.rejected(_wrongNetwork);
      }
      final issue = addressFormatIssue(requestNetwork, request.address);
      if (request.address.isEmpty || issue != null) {
        return AddressInputResult.rejected(issue ?? _invalidRequest);
      }
      if (!isPaymentRequest) return AddressInputResult.address(request.address);
      // An empty or static fallback catalogue has no live asset IDs yet. The
      // request card owns catalogue loading; this is not an unsupported asset.
      if (policy.assets.any((asset) => asset.assetId != null)) {
        final resolution = resolveCrossChainPaymentRequest(
          request,
          policy.assets,
          selectedChain: policy.network.id,
        );
        if (resolution.message != null && !resolution.needsNetwork) {
          return AddressInputResult.rejected(resolution.message);
        }
      }
      return AddressInputResult.paymentRequest(
        rawPaymentUri: input,
        crossChainRequest: request,
      );
    }
    // Simple address URI families without a supported payment protocol. Query
    // parameters are never discarded to turn an unknown request into an address.
    final addressChain = switch (scheme) {
      // The legacy eth alias carries an address, not an explicit chain.
      'eth' => policy.network.isEvm ? policy.network.id : 'eth',
      'near' => 'near',
      'dogecoin' => 'doge',
      'tron' => 'tron',
      _ => null,
    };
    if (addressChain == null) {
      return const AddressInputResult.rejected(
        'This QR format is not supported.',
      );
    }
    if (addressChain != policy.network.id) {
      return const AddressInputResult.rejected(_wrongNetwork);
    }
    if (uri.hasQuery ||
        uri.hasFragment ||
        uri.hasAuthority ||
        uri.path.isEmpty) {
      return const AddressInputResult.rejected(_invalidRequest);
    }
    return await _validateAddress(
      Uri.decodeComponent(uri.path),
      policy,
      validateZcashAddress,
    );
  } on Zip321ParseException catch (error) {
    return AddressInputResult.rejected(error.message);
  } catch (_) {
    return const AddressInputResult.rejected(_invalidRequest);
  }
}

Future<AddressInputResult> _validateAddress(
  String address,
  AddressInputPolicy policy,
  Future<String?> Function(String, ZcashNetwork) validateZcashAddress,
) async {
  final network = policy.context == AddressInputContext.send
      ? AddressBookNetwork.zcash
      : policy.network;
  if (network == AddressBookNetwork.zcash) {
    if (policy.context != AddressInputContext.send &&
        policy.context != AddressInputContext.contact) {
      return const AddressInputResult.rejected(_payOnly);
    }
    if (!_looksLikeZcash(address)) {
      return AddressInputResult.rejected(
        policy.context == AddressInputContext.send
            ? _sendOnly
            : 'Invalid Zcash address',
      );
    }
    final issue = await validateZcashAddress(address, policy.zcashNetwork);
    return issue == null
        ? AddressInputResult.address(address)
        : AddressInputResult.rejected(issue);
  }
  final issue = addressFormatIssue(network, address);
  return issue == null
      ? AddressInputResult.address(address)
      : AddressInputResult.rejected(issue);
}

bool _hasPaymentTerms(Uri uri, CrossChainPaymentRequest request) =>
    uri.hasQuery ||
    uri.hasFragment ||
    uri.path.contains('/') ||
    request.amount != null ||
    request.contractAddress != null ||
    request.label != null ||
    request.message != null;

bool _looksLikeZcash(String address) => RegExp(
  r'^(u1|utest1|uregtest1|zs1|ztestsapling1|zregtestsapling1|tex1|textest1|texregtest1|t1|t3|tm|t2)',
  caseSensitive: false,
).hasMatch(address);

// This is only a best-effort hint after the selected network rejects an address.
// Zcash-looking prefixes can also start valid Solana public keys or NEAR names.
bool _isZcashAddress(String address) => ZcashNetwork.values.any(
  (network) =>
      addressFormatIssue(
        AddressBookNetwork.zcash,
        address,
        zcashNetwork: network,
      ) ==
      null,
);
