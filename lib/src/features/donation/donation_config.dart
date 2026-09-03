import '../../core/config/network_config.dart';

/// Vizor's public mainnet donation address, documented in README.md.
const kVizorDonationAddress =
    'u15kdlm6j5tp4tptue4fdra4qa50d6zfl76anf7dagzu9y0yz875qhtvxgd6dju7l7epjwwxvuzh7z67gnxfw9msqxtnjg96x77x4y3vmzfehm0p9l6q2yhuskztxl8dlrswp6nf3u2j35krarnntc85h92h64g29f73ze5tewugq8tg3y';

bool donationFeatureEnabledForNetwork(String networkName) =>
    networkName.trim() == ZcashNetwork.mainnet.name;
