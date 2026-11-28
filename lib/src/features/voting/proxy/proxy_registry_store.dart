import 'dart:convert';
import 'dart:typed_data';

import '../../../services/voting/voting_file_cache.dart';

/// Folder of the voting cache directory that holds the proxy registry state.
const kProxyRegistryCacheFolder = 'proxy-registry';

/// The proxy registry state Vizor keeps between runs, in the voting cache
/// directory beside the wallet DB, as the app keeps other disposable voting
/// data (contracts-v1 sections 11.10 and 12.3).
///
/// Per network it holds the registry cache and the newest wallet list that
/// verified, each checked again in Rust before use. Account deletion and
/// wallet reset delete it all.
///
/// Callers write only while they hold the voting destructive-operation
/// lease, so a write cannot land after deletion.
class ProxyRegistryStore {
  /// Creates the store over [cache].
  ProxyRegistryStore(this._cache);

  final VotingFileCache _cache;

  /// The network's registry cache JSON, or null before a download.
  Future<String?> readRegistryCache(String network) =>
      _cache.read(_path(network, 'registry-cache.json'));

  /// Stores [json] as the network's registry cache.
  Future<void> writeRegistryCache(String network, String json) =>
      _cache.write(_path(network, 'registry-cache.json'), json);

  /// The newest wallet list that verified on [network], or null.
  Future<Uint8List?> readWalletList(String network) =>
      _readBytes(_path(network, 'wallet-list.json'));

  /// Stores [document] as the network's newest wallet list.
  Future<void> writeWalletList(String network, List<int> document) =>
      _cache.write(_path(network, 'wallet-list.json'), base64Encode(document));

  /// Deletes every network's registry state.
  Future<void> clear() => _cache.removeFolder(kProxyRegistryCacheFolder);

  /// Bytes stored as base64 at [path], or null when absent or unreadable.
  Future<Uint8List?> _readBytes(String path) async {
    final text = await _cache.read(path);
    if (text == null) return null;
    try {
      return base64Decode(text);
    } on FormatException {
      return null;
    }
  }

  /// The path of [name] in [network]'s folder.
  static String _path(String network, String name) {
    if (!_network.hasMatch(network)) {
      throw ArgumentError.value(network, 'network', 'not a network name');
    }
    return '$kProxyRegistryCacheFolder/$network/$name';
  }

  static final _network = RegExp(r'^[a-z]{1,16}$');
}
