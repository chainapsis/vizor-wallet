import Foundation

enum RpcEndpointConfigStore {
    // iOS BGTasks cannot read Flutter secure storage directly. These keys are
    // a native mirror of Dart's RPC endpoint setting; keep defaults in sync
    // with rpc_endpoint_config.dart.
    private static let lightwalletdUrlKey = "zcash_rpc_endpoint_url_ios_mirror"
    private static let networkKey = "zcash_rpc_endpoint_network_ios_mirror"
    private static let defaultLightwalletdUrl = "https://us.zec.stardust.rest:443"
    private static let defaultNetwork = "main"

    static var lightwalletdUrl: String {
        UserDefaults.standard.string(forKey: lightwalletdUrlKey) ?? defaultLightwalletdUrl
    }

    static var network: String {
        UserDefaults.standard.string(forKey: networkKey) ?? defaultNetwork
    }

    static func save(lightwalletdUrl: String?, network: String? = nil) {
        if let lightwalletdUrl, !lightwalletdUrl.isEmpty {
            UserDefaults.standard.set(lightwalletdUrl, forKey: lightwalletdUrlKey)
        }
        if let network, !network.isEmpty {
            UserDefaults.standard.set(network, forKey: networkKey)
        }
    }
}
