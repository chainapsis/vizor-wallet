import Foundation

enum RpcEndpointConfigStore {
    // iOS BGTasks cannot read Flutter secure storage directly. These keys are
    // a native mirror of Dart's RPC endpoint setting; keep defaults in sync
    // with rpc_endpoint_config.dart.
    private static let lightwalletdUrlKey = "zcash_rpc_endpoint_url_ios_mirror"
    private static let networkKey = "zcash_rpc_endpoint_network_ios_mirror"
    private static let presetIdKey = "zcash_rpc_endpoint_preset_ios_mirror"
    private static let defaultLightwalletdUrl = "https://us.zec.stardust.rest:443"
    private static let defaultNetwork = "main"
    private static let defaultPresetId = "default-mainnet"

    static var lightwalletdUrl: String {
        if UserDefaults.standard.string(forKey: presetIdKey) == defaultPresetId {
            return defaultLightwalletdUrl
        }
        UserDefaults.standard.string(forKey: lightwalletdUrlKey) ?? defaultLightwalletdUrl
    }

    static var network: String {
        UserDefaults.standard.string(forKey: networkKey) ?? defaultNetwork
    }

    static func save(lightwalletdUrl: String?, network: String? = nil, presetId: String? = nil) {
        if let presetId, !presetId.isEmpty {
            UserDefaults.standard.set(presetId, forKey: presetIdKey)
            if presetId == defaultPresetId {
                UserDefaults.standard.removeObject(forKey: lightwalletdUrlKey)
                if let network, !network.isEmpty {
                    UserDefaults.standard.set(network, forKey: networkKey)
                }
                return
            }
        }
        if let lightwalletdUrl, !lightwalletdUrl.isEmpty {
            UserDefaults.standard.set(lightwalletdUrl, forKey: lightwalletdUrlKey)
        }
        if let network, !network.isEmpty {
            UserDefaults.standard.set(network, forKey: networkKey)
        }
    }
}
