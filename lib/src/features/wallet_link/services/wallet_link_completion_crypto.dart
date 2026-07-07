import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../models/wallet_link_models.dart';

const kWalletLinkCompletionPlaintextBytes = 256;
const _walletLinkCompletionKeyDomain = 'vizor-wallet-link-completion-v1';

Future<WalletLinkEnvelope> encryptWalletLinkImportSummary({
  required WalletLinkImportSummary summary,
  required List<int> keyBytes,
}) async {
  final nonce = _randomBytes(12);
  final algorithm = AesGcm.with256bits();
  final secretBox = await algorithm.encrypt(
    _encodeFixedLengthCompletionPayload(summary),
    secretKey: await _deriveCompletionSecretKey(keyBytes),
    nonce: nonce,
  );
  return WalletLinkEnvelope(
    algorithm: 'aes-256-gcm',
    nonce: _base64UrlNoPadding(nonce),
    ciphertext: _base64UrlNoPadding(Uint8List.fromList(secretBox.cipherText)),
    tag: _base64UrlNoPadding(Uint8List.fromList(secretBox.mac.bytes)),
  );
}

Future<WalletLinkImportSummary> decryptWalletLinkImportSummary({
  required WalletLinkEnvelope envelope,
  required List<int> keyBytes,
}) async {
  if (envelope.algorithm != 'aes-256-gcm') {
    throw const FormatException(
      'Unsupported wallet link completion encryption.',
    );
  }
  final algorithm = AesGcm.with256bits();
  final clearText = await algorithm.decrypt(
    SecretBox(
      _base64UrlNoPaddingDecode(envelope.ciphertext),
      nonce: _base64UrlNoPaddingDecode(envelope.nonce),
      mac: Mac(_base64UrlNoPaddingDecode(envelope.tag)),
    ),
    secretKey: await _deriveCompletionSecretKey(keyBytes),
  );
  if (clearText.length != kWalletLinkCompletionPlaintextBytes) {
    throw const FormatException(
      'Wallet link completion payload size is invalid.',
    );
  }
  final payloadLength = (clearText[0] << 8) | clearText[1];
  if (payloadLength <= 0 ||
      payloadLength > kWalletLinkCompletionPlaintextBytes - 2) {
    throw const FormatException(
      'Wallet link completion payload length is invalid.',
    );
  }
  final decoded = jsonDecode(
    utf8.decode(clearText.sublist(2, 2 + payloadLength)),
  );
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('Wallet link completion payload is invalid.');
  }
  return WalletLinkImportSummary.fromJson(decoded);
}

Future<SecretKey> _deriveCompletionSecretKey(List<int> keyBytes) async {
  if (keyBytes.length != 32) {
    throw const FormatException('Wallet link key must be 32 bytes.');
  }
  final digest = await Sha256().hash([
    ...utf8.encode(_walletLinkCompletionKeyDomain),
    ...keyBytes,
  ]);
  return SecretKey(digest.bytes);
}

Uint8List _encodeFixedLengthCompletionPayload(WalletLinkImportSummary summary) {
  final jsonBytes = utf8.encode(jsonEncode(summary.toJson()));
  if (jsonBytes.length > kWalletLinkCompletionPlaintextBytes - 2) {
    throw const FormatException('Wallet link completion payload is too large.');
  }
  final bytes = _randomBytes(kWalletLinkCompletionPlaintextBytes);
  bytes[0] = (jsonBytes.length >> 8) & 0xff;
  bytes[1] = jsonBytes.length & 0xff;
  bytes.setRange(2, 2 + jsonBytes.length, jsonBytes);
  return bytes;
}

Uint8List _randomBytes(int length) {
  final random = Random.secure();
  return Uint8List.fromList([
    for (var i = 0; i < length; i++) random.nextInt(256),
  ]);
}

String _base64UrlNoPadding(Uint8List bytes) {
  return base64UrlEncode(bytes).replaceAll('=', '');
}

List<int> _base64UrlNoPaddingDecode(String value) {
  return base64Url.decode(base64Url.normalize(value));
}
