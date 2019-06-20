//
//  TunnelConfiguration.swift
//  MullvadVPN
//
//  Created by pronebird on 19/06/2019.
//  Copyright © 2019 Amagicom AB. All rights reserved.
//

import Foundation
import Network
import NetworkExtension

/// A struct that holds a tun interface configuration
struct InterfaceConfiguration: Codable {
    var privateKey: WireguardPrivateKey
    var addresses: [IPAddressRange]

    static var `default`: InterfaceConfiguration {
        return InterfaceConfiguration(privateKey: WireguardPrivateKey(), addresses: [])
    }
}

/// A struct that holds the configuration passed via NETunnelProviderProtocol
struct TunnelConfiguration: Codable {
    var accountToken: String
    var relayConstraints: RelayConstraints
    var interface: InterfaceConfiguration
}

enum TunnelConfigurationParseError: Error {
    case emptyPasswordRef
    case keychain(Error)
}

extension NETunnelProviderProtocol {

    func asTunnelConfiguration() -> TunnelConfiguration? {
        guard let passwordReference = passwordReference else { return nil }

        return try? TunnelConfigurationManager.shared
            .getConfigurationFromKeychainRef(passwordReference)
    }

}
