import Foundation

enum RpcEndpointConfigStore {
    // iOS BGTasks cannot read Flutter secure storage directly. These keys are
    // a native mirror of Dart's RPC endpoint setting; keep defaults in sync
    // with rpc_endpoint_config.dart.
    private static let lightwalletdUrlKey = "zcash_rpc_endpoint_url_ios_mirror"
    private static let networkKey = "zcash_rpc_endpoint_network_ios_mirror"
    private static let presetIdKey = "zcash_rpc_endpoint_preset_ios_mirror"
    private static let dartDefinesInfoKey = "DART_DEFINES"

    static var lightwalletdUrl: String {
        let network = self.network
        let defaultUrl = defaultLightwalletdUrl(forNetwork: network)
        if UserDefaults.standard.string(forKey: presetIdKey) == defaultPresetId(forNetwork: network) {
            return defaultUrl
        }
        return UserDefaults.standard.string(forKey: lightwalletdUrlKey) ?? defaultUrl
    }

    static var network: String {
        if let network = UserDefaults.standard.string(forKey: networkKey) {
            return normalizeNetwork(network)
        }
        let rawDefines = Bundle.main.object(forInfoDictionaryKey: dartDefinesInfoKey) as? String
        return defaultNetwork(fromDartDefines: rawDefines)
    }

    static func save(lightwalletdUrl: String?, network: String? = nil, presetId: String? = nil) {
        let normalizedNetwork = network.map(normalizeNetwork) ?? self.network
        let defaultPresetId = defaultPresetId(forNetwork: normalizedNetwork)
        if let presetId, !presetId.isEmpty {
            UserDefaults.standard.set(presetId, forKey: presetIdKey)
            if presetId == defaultPresetId {
                UserDefaults.standard.removeObject(forKey: lightwalletdUrlKey)
                if network != nil {
                    UserDefaults.standard.set(normalizedNetwork, forKey: networkKey)
                }
                return
            }
        }
        if let lightwalletdUrl, !lightwalletdUrl.isEmpty {
            UserDefaults.standard.set(lightwalletdUrl, forKey: lightwalletdUrlKey)
        }
        if network != nil {
            UserDefaults.standard.set(normalizedNetwork, forKey: networkKey)
        }
    }

    static func defaultNetwork(fromDartDefines rawDefines: String?) -> String {
        guard let rawDefines, !rawDefines.isEmpty, rawDefines != "$(DART_DEFINES)" else {
            return "main"
        }

        for encodedDefine in rawDefines.split(separator: ",") {
            guard
                let data = Data(base64Encoded: String(encodedDefine)),
                let define = String(data: data, encoding: .utf8)
            else {
                continue
            }

            let prefix = "ZCASH_DEFAULT_NETWORK="
            if define.hasPrefix(prefix) {
                let value = String(define.dropFirst(prefix.count))
                return normalizeNetwork(value)
            }
        }

        return "main"
    }

    static func normalizeNetwork(_ networkName: String) -> String {
        switch networkName.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "test":
            return "test"
        case "regtest":
            return "regtest"
        default:
            return "main"
        }
    }

    static func defaultLightwalletdUrl(forNetwork networkName: String) -> String {
        switch normalizeNetwork(networkName) {
        case "test":
            return "https://testnet.zec.rocks:443"
        case "regtest":
            return "http://127.0.0.1:9067"
        default:
            return "https://us.zec.stardust.rest:443"
        }
    }

    static func defaultPresetId(forNetwork networkName: String) -> String {
        switch normalizeNetwork(networkName) {
        case "test":
            return "default-testnet"
        case "regtest":
            return "default-regtest"
        default:
            return "default-mainnet"
        }
    }
}
