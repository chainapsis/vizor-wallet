import '../../../core/profile_pictures.dart';

enum AddressBookNetwork {
  zcash('zec', 'Zcash', 'assets/swap/chains/zec.png'),
  ethereum('eth', 'Ethereum', 'assets/swap/chains/eth.png'),
  base('base', 'Base', 'assets/swap/chains/base.png'),
  arbitrum('arb', 'Arbitrum', 'assets/swap/chains/arb.png'),
  solana('sol', 'Solana', 'assets/swap/chains/sol.png'),
  near('near', 'NEAR', 'assets/swap/chains/near.png'),
  bitcoin('btc', 'Bitcoin', 'assets/swap/chains/btc.png'),
  binanceSmartChain('bsc', 'Binance Smart Chain', 'assets/swap/tokens/bnb.png'),
  tron('tron', 'Tron', 'assets/swap/chains/tron.png'),
  sui('sui', 'Sui', 'assets/swap/chains/sui.png'),
  aptos('aptos', 'Aptos', 'assets/swap/chains/aptos.png'),
  optimism('op', 'Optimism', 'assets/swap/chains/op.png'),
  avalanche('avax', 'Avalanche', 'assets/swap/chains/avax.png'),
  gnosis('gnosis', 'Gnosis', 'assets/swap/chains/gnosis.png'),
  polygon('pol', 'Polygon', 'assets/swap/chains/pol.png'),
  ton('ton', 'TON', 'assets/swap/chains/ton.png'),
  stellar('stellar', 'Stellar', 'assets/swap/chains/stellar.png'),
  xLayer('xlayer', 'X Layer', 'assets/swap/tokens/okb.png'),
  plasma('plasma', 'Plasma', 'assets/swap/chains/plasma.png'),
  abstractChain('abs', 'Abstract', 'assets/swap/chains/eth.png'),
  adi('adi', 'ADI', 'assets/swap/chains/adi.png'),
  aleo('aleo', 'Aleo', 'assets/swap/chains/aleo.png'),
  bitcoinCash('bch', 'Bitcoin Cash', 'assets/swap/chains/bch.png'),
  bera('bera', 'Bera', 'assets/swap/chains/bera.png'),
  cardano('cardano', 'Cardano', 'assets/swap/tokens/ada.png'),
  dash('dash', 'Dash', 'assets/swap/chains/dash.png'),
  dogecoin('doge', 'Dogecoin', 'assets/swap/chains/doge.png'),
  litecoin('ltc', 'Litecoin', 'assets/swap/chains/ltc.png'),
  monad('monad', 'Monad', 'assets/swap/chains/monad.png'),
  scroll('scroll', 'Scroll', 'assets/swap/chains/scroll.png'),
  starknet('starknet', 'Starknet', 'assets/swap/chains/starknet.png'),
  xrp('xrp', 'XRP', 'assets/swap/chains/xrp.png');

  const AddressBookNetwork(this.id, this.label, this.assetPath);

  final String id;
  final String label;
  final String assetPath;

  bool get canSendFromWallet => this == AddressBookNetwork.zcash;

  /// Whether this network uses the shared EVM address format (0x + 40 hex).
  /// EVM addresses are interchangeable across EVM chains — the same account
  /// works on every one — so a destination on any EVM chain can accept an
  /// address saved for any other EVM chain.
  bool get isEvm => switch (this) {
    AddressBookNetwork.ethereum ||
    AddressBookNetwork.base ||
    AddressBookNetwork.arbitrum ||
    AddressBookNetwork.optimism ||
    AddressBookNetwork.polygon ||
    AddressBookNetwork.binanceSmartChain ||
    AddressBookNetwork.avalanche ||
    AddressBookNetwork.gnosis ||
    AddressBookNetwork.scroll ||
    AddressBookNetwork.xLayer ||
    AddressBookNetwork.plasma ||
    AddressBookNetwork.abstractChain ||
    AddressBookNetwork.monad ||
    AddressBookNetwork.bera => true,
    _ => false,
  };

  static AddressBookNetwork? tryFromId(String id) {
    final normalized = id.trim().toLowerCase();
    final alias = switch (normalized) {
      'zcash' => 'zec',
      'ethereum' => 'eth',
      'solana' => 'sol',
      'polygon' => 'pol',
      'optimism' => 'op',
      'arbitrum' => 'arb',
      'avalanche' => 'avax',
      'usdc' => 'eth',
      _ => normalized,
    };
    for (final network in values) {
      if (network.id == alias) return network;
    }
    return null;
  }

  static AddressBookNetwork? tryFromChainTicker(String chainTicker) {
    return tryFromId(chainTicker);
  }
}

class AddressBookContact {
  const AddressBookContact({
    required this.id,
    required this.label,
    required this.network,
    required this.address,
    required this.profilePictureId,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  final String id;
  final String label;
  final AddressBookNetwork network;
  final String address;
  final String profilePictureId;
  final int createdAtMs;
  final int updatedAtMs;

  String get addressPreview => previewAddress(address);

  AddressBookContact copyWith({
    String? label,
    AddressBookNetwork? network,
    String? address,
    String? profilePictureId,
    int? updatedAtMs,
  }) {
    return AddressBookContact(
      id: id,
      label: label ?? this.label,
      network: network ?? this.network,
      address: address ?? this.address,
      profilePictureId: profilePictureId ?? this.profilePictureId,
      createdAtMs: createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'label': label,
      'network': network.id,
      'address': address,
      'profilePictureId': profilePictureId,
      'createdAtMs': createdAtMs,
      'updatedAtMs': updatedAtMs,
    };
  }

  static AddressBookContact? tryFromJson(Map<String, Object?> json) {
    final network = AddressBookNetwork.tryFromId(
      (json['network'] as String?)?.trim() ?? '',
    );
    if (network == null) return null;

    return AddressBookContact(
      id: (json['id'] as String?)?.trim() ?? '',
      label: (json['label'] as String?)?.trim() ?? '',
      network: network,
      address: (json['address'] as String?)?.trim() ?? '',
      profilePictureId: normalizeProfilePictureId(
        (json['profilePictureId'] as String?)?.trim() ??
            kDefaultProfilePictureId,
      ),
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
      updatedAtMs: (json['updatedAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

String previewAddress(String address) {
  final trimmed = address.trim();
  if (trimmed.length <= 15) return trimmed;
  return '${trimmed.substring(0, 6)} ... ${trimmed.substring(trimmed.length - 5)}';
}

String? validateAddressBookLabel(String label) {
  final trimmed = label.trim();
  if (trimmed.isEmpty) return 'Add a label';
  if (trimmed.length > 20) return 'Use 1-20 characters';
  return null;
}

String? validateAddressBookAddress(String address) {
  final trimmed = address.trim();
  if (trimmed.isEmpty) return 'Add an address';
  return null;
}
