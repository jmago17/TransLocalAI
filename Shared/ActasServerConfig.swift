//
//  ActasServerConfig.swift
//  Transcriber (Shared between app and Share extension)
//
//  Connection settings for actas-server, persisted in the shared App Group so
//  the Share extension uses the same endpoint + token the app was paired with.
//

import Foundation

/// Where to reach the Mac and how to authenticate. Backed by the App Group
/// UserDefaults so the extension inherits whatever the app configured.
nonisolated struct ActasServerConfig: Sendable, Equatable {
    static let appGroup = "group.com.josumartinez.transcriber"

    var tailscaleHost: String
    var lanHost: String
    var mdnsHost: String
    var customHost: String      // user override, wins if non-empty
    var port: Int
    var token: String

    /// Sensible defaults for Josu's Mac mini (see reference_tailscale_mac_mini).
    static let `default` = ActasServerConfig(
        tailscaleHost: "100.123.146.23",
        lanHost: "192.168.31.108",
        mdnsHost: "Mac-mini-de-Josu.local",
        customHost: "",
        port: 8776,
        token: ""
    )

    var isConfigured: Bool { !token.isEmpty }

    /// Candidate base URLs in priority order. A custom host, if set, is tried
    /// first; otherwise we race Tailscale / LAN / mDNS and keep the fastest.
    var candidateBaseURLs: [URL] {
        var hosts: [String] = []
        if !customHost.isEmpty { hosts.append(customHost) }
        hosts.append(contentsOf: [tailscaleHost, lanHost, mdnsHost])
        var seen = Set<String>()
        return hosts.compactMap { host in
            guard seen.insert(host).inserted, !host.isEmpty else { return nil }
            return URL(string: "http://\(host):\(port)")
        }
    }
}

/// Persistence + change notifications for `ActasServerConfig`.
nonisolated enum ActasServerStore {
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: ActasServerConfig.appGroup) ?? .standard
    }

    private enum Key {
        static let tailscale = "actas.tailscaleHost"
        static let lan = "actas.lanHost"
        static let mdns = "actas.mdnsHost"
        static let custom = "actas.customHost"
        static let port = "actas.port"
        static let token = "actas.token"
        static let lastGood = "actas.lastGoodBaseURL"
    }

    static func load() -> ActasServerConfig {
        let d = defaults
        let def = ActasServerConfig.default
        return ActasServerConfig(
            tailscaleHost: d.string(forKey: Key.tailscale) ?? def.tailscaleHost,
            lanHost: d.string(forKey: Key.lan) ?? def.lanHost,
            mdnsHost: d.string(forKey: Key.mdns) ?? def.mdnsHost,
            customHost: d.string(forKey: Key.custom) ?? def.customHost,
            port: d.object(forKey: Key.port) as? Int ?? def.port,
            token: d.string(forKey: Key.token) ?? def.token
        )
    }

    static func save(_ config: ActasServerConfig) {
        let d = defaults
        d.set(config.tailscaleHost, forKey: Key.tailscale)
        d.set(config.lanHost, forKey: Key.lan)
        d.set(config.mdnsHost, forKey: Key.mdns)
        d.set(config.customHost, forKey: Key.custom)
        d.set(config.port, forKey: Key.port)
        d.set(config.token, forKey: Key.token)
    }

    /// Cache of the last base URL that answered /health, tried first next time.
    static var lastGoodBaseURL: URL? {
        get { (defaults.string(forKey: Key.lastGood)).flatMap(URL.init(string:)) }
        set { defaults.set(newValue?.absoluteString, forKey: Key.lastGood) }
    }
}
