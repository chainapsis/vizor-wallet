import 'package:url_launcher/url_launcher.dart';

import 'network_config.dart';

enum ZcashExplorerTxidOrder { protocol, display }

typedef ZcashExplorerLauncher = Future<bool> Function(Uri uri);

const kDefaultZcashExplorerLabel = 'CipherScan';

const kZcashExplorerPrivacyCopy =
    'Transaction links open in this explorer. Use CipherScan or another site '
    'you prefer. Opening a public explorer after you send can link your IP '
    'address to that transaction.';

const kZcashExplorerTemplateHint =
    'Use {txid} or {txHash} in the path, or enter just the origin.';

final _txidHexPattern = RegExp(r'^[0-9a-f]{64}$');
final _txidHexPathTailPattern = RegExp(r'/[0-9a-fA-F]{64}/?$');
final _txidPlaceholderPattern = RegExp(
  r'\{txid\}|\{txHash\}|\{tx_hash\}|\{hash\}',
  caseSensitive: false,
);

String defaultZcashExplorerHost(String networkName) {
  final network = zcashNetworkFromName(networkName);
  return switch (network) {
    ZcashNetwork.mainnet => 'cipherscan.app',
    ZcashNetwork.testnet => 'testnet.cipherscan.app',
    ZcashNetwork.regtest => 'testnet.cipherscan.app',
  };
}

/// Settings-row label: CipherScan when unset, otherwise the custom host.
String explorerSettingsLabel(
  String? customTemplate, {
  required String networkName,
}) {
  final template = customTemplate?.trim() ?? '';
  if (template.isEmpty) return kDefaultZcashExplorerLabel;
  try {
    return Uri.parse(normalizeExplorerUrlTemplate(template)).host;
  } on FormatException {
    return 'Custom';
  }
}

/// Normalize user input into a stored explorer URL template.
///
/// Accepts an origin (`https://explorer.example`), a path that already
/// includes `{txid}` / `{txHash}`, or a concrete `/tx/<64-hex>` URL.
String normalizeExplorerUrlTemplate(String input) {
  var raw = input.trim();
  if (raw.isEmpty) {
    throw const FormatException('Enter an explorer URL.');
  }

  final lower = raw.toLowerCase();
  if (lower.startsWith('javascript:') ||
      lower.startsWith('data:') ||
      lower.startsWith('file:') ||
      lower.startsWith('vbscript:')) {
    throw const FormatException('Enter an http or https URL.');
  }

  if (!raw.contains('://')) {
    raw = 'https://$raw';
  }

  final parsed = Uri.tryParse(raw);
  if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
    throw const FormatException('Enter a host, like explorer.example.');
  }
  if (parsed.scheme != 'http' && parsed.scheme != 'https') {
    throw const FormatException('Enter an http or https URL.');
  }

  return _decodeTxidPlaceholders(_ensureTxidPlaceholder(parsed).toString());
}

Uri applyExplorerUrlTemplate(String template, String txidHex) {
  final normalized = normalizeExplorerUrlTemplate(template);
  final filled = _decodeTxidPlaceholders(
    normalized,
  ).replaceAllMapped(_txidPlaceholderPattern, (_) => txidHex);
  final uri = Uri.parse(filled);
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    throw const FormatException('Enter an http or https URL.');
  }
  return uri;
}

Uri zcashExplorerTransactionUri({
  required String networkName,
  required String txidHex,
  required ZcashExplorerTxidOrder txidOrder,
  String? customTemplate,
}) {
  final displayTxid = _explorerTxidHex(txidHex, txidOrder);
  final template = customTemplate?.trim() ?? '';
  if (template.isNotEmpty) {
    return applyExplorerUrlTemplate(template, displayTxid);
  }
  return Uri.https(defaultZcashExplorerHost(networkName), '/tx/$displayTxid');
}

String _explorerTxidHex(String txidHex, ZcashExplorerTxidOrder txidOrder) {
  final normalized = txidHex.trim().toLowerCase();
  return switch (txidOrder) {
    ZcashExplorerTxidOrder.display => normalized,
    ZcashExplorerTxidOrder.protocol => _protocolOrderToDisplayTxidHex(
      normalized,
    ),
  };
}

String _protocolOrderToDisplayTxidHex(String normalizedTxidHex) {
  if (!_txidHexPattern.hasMatch(normalizedTxidHex)) {
    return normalizedTxidHex;
  }

  // Wallet DB txids are protocol-order bytes; explorers use byte-reversed text.
  final bytes = <String>[];
  for (var i = 0; i < normalizedTxidHex.length; i += 2) {
    bytes.add(normalizedTxidHex.substring(i, i + 2));
  }
  return bytes.reversed.join();
}

String _decodeTxidPlaceholders(String value) {
  return value.replaceAllMapped(
    RegExp(r'%7B(txid|txHash|tx_hash|hash)%7D', caseSensitive: false),
    (match) => '{${match[1]}}',
  );
}

Uri _ensureTxidPlaceholder(Uri uri) {
  final haystack = _decodeTxidPlaceholders(
    '${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}'
    '${uri.hasFragment ? '#${uri.fragment}' : ''}',
  );
  if (_txidPlaceholderPattern.hasMatch(haystack)) {
    return uri;
  }

  final path = uri.path;
  if (_txidHexPathTailPattern.hasMatch(path)) {
    return uri.replace(
      path: path.replaceFirst(_txidHexPathTailPattern, '/{txid}'),
    );
  }
  if (path.isEmpty || path == '/') {
    return uri.replace(path: '/tx/{txid}');
  }
  if (path.endsWith('/')) {
    return uri.replace(path: '$path{txid}');
  }
  return uri.replace(path: '$path/{txid}');
}

Future<bool> launchZcashExplorerTransaction({
  required String networkName,
  required String txidHex,
  required ZcashExplorerTxidOrder txidOrder,
  String? customTemplate,
  ZcashExplorerLauncher? launcher,
}) async {
  try {
    final uri = zcashExplorerTransactionUri(
      networkName: networkName,
      txidHex: txidHex,
      txidOrder: txidOrder,
      customTemplate: customTemplate,
    );
    return await (launcher ?? _launchExternalUrl)(uri);
  } on Exception {
    return false;
  }
}

Future<bool> _launchExternalUrl(Uri uri) {
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
