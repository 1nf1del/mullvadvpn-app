//
//  PacketTunnelSettingsGenerator.swift
//  PacketTunnel
//
//  Created by pronebird on 13/06/2019.
//  Copyright © 2019 Amagicom AB. All rights reserved.
//

import Foundation
import Network
import NetworkExtension

struct PacketTunnelSettingsGenerator {
    let privateKey: Data
    let mullvadEndpoint: MullvadEndpoint
    let interfaceAddresses: WireguardAssociatedAddresses

    func networkSettings() -> NEPacketTunnelNetworkSettings {
        let networkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "\(mullvadEndpoint.relay.address)")

        networkSettings.mtu = 1280
        networkSettings.dnsSettings = dnsSettings()
        networkSettings.ipv4Settings = ipv4Settings()

        return networkSettings
    }

    func wireguardEndpointUapiConfiguration() -> String {
        var config = [String]()

        config.append("public_key=\(mullvadEndpoint.publicKey)")
        config.append("endpoint=\(mullvadEndpoint.relay)")

        return config.joined(separator: "\n")
    }

    func wireguardUapiConfiguration() -> String {
        var config = [String]()

        config.append("private_key=\(privateKey.base64EncodedString())")
        config.append("listen_port=0")

        config.append("replace_peers=true")

        config.append("public_key=\(mullvadEndpoint.publicKey)")
        config.append("endpoint=\(mullvadEndpoint.relay)")

        config.append("replace_allowed_ips=true")
        config.append("allowed_ip=0.0.0.0/0")

        return config.joined(separator: "\n")
    }

    private func dnsSettings() -> NEDNSSettings {
        let serverAddresses = [mullvadEndpoint.ipv4Gateway, mullvadEndpoint.ipv6Gateway]
            .map { String(reflecting: $0) }

        let dnsSettings = NEDNSSettings(servers: serverAddresses)

        // All DNS queries must first go through the tunnel's DNS
        dnsSettings.matchDomains = [""]

        return dnsSettings
    }

    private func ipv4Settings() -> NEIPv4Settings {
        let ipv4Settings = NEIPv4Settings(
            addresses: ["\(interfaceAddresses.ipv4Address)"],
            subnetMasks: ["255.255.255.255"])

        ipv4Settings.includedRoutes = [
            NEIPv4Route(destinationAddress: "0.0.0.0", subnetMask: "0.0.0.0")
        ]

        ipv4Settings.excludedRoutes = [
            NEIPv4Route(
                destinationAddress: "\(mullvadEndpoint.relay.address)",
                subnetMask: "255.255.255.255")
        ]

        return ipv4Settings
    }
}
