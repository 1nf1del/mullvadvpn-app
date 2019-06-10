//
//  TunnelConfiguration.swift
//  MullvadVPN
//
//  Created by pronebird on 11/06/2019.
//  Copyright © 2019 Amagicom AB. All rights reserved.
//

import Foundation
import NetworkExtension
import os.log

private let kRelayConstraintKey = "relayConstraint"

/// A tunnel configuration object shared between the app and the packet tunnel extension
final class TunnelConfiguration {
    var relayConstraint = RelayConstraint()

    /// Private initializer
    private init() {}

    /// Default initializer
    init(with protocolConfiguration: NETunnelProviderProtocol) {
        guard let providerConfiguration = protocolConfiguration.providerConfiguration,
            let relayConstraintData = providerConfiguration[kRelayConstraintKey] as? Data else {
                return
        }

        do {
            relayConstraint = try JSONDecoder().decode(
                RelayConstraint.self, from: relayConstraintData)
        } catch {
            os_log(.info, "Failed to decode the RelayConstraint: %s", error.localizedDescription)
        }
    }

    /// A helper that loads the tunnel configuration from preferences
    class func loadFromPreferences(completion: @escaping (Result<TunnelConfiguration, Error>) -> Void) {
        let vpnManager = NEVPNManager.shared()

        vpnManager.loadFromPreferences { (error) in
            if let error = error {
                completion(.failure(error))
            } else {
                if let protocolConfiguration = vpnManager.protocolConfiguration as? NETunnelProviderProtocol {
                    completion(.success(TunnelConfiguration(with: protocolConfiguration)))
                } else {
                    completion(.success(TunnelConfiguration()))
                }
            }
        }
    }

    /// Save configuration into preferences
    func saveToPreferences(completion: @escaping (Result<Void, Error>) -> Void) {
        // Prepare vendor specific configuration
        var providerConfiguration = [String: Any]()

        // Encode relay constraint
        do {
            providerConfiguration[kRelayConstraintKey] = try JSONEncoder().encode(relayConstraint)
        } catch {
            completion(.failure(error))
            return
        }

        let config = NETunnelProviderProtocol()
        config.providerBundleIdentifier = ApplicationConfiguration.packetTunnelExtensionIdentifier
        config.providerConfiguration = providerConfiguration

        let vpnManager = NEVPNManager.shared()
        vpnManager.protocolConfiguration = config

        vpnManager.saveToPreferences { (error) in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
}

extension TunnelConfiguration {

    /// A shortcut to load, update and save preferences
    class func updateRelayConstraint(_ relayConstraint: RelayConstraint, completion: @escaping (Result<Void, Error>) -> Void) {
        TunnelConfiguration.loadFromPreferences { (result) in
            do {
                let tunnelConfiguration = try result.get()
                tunnelConfiguration.relayConstraint = relayConstraint
                tunnelConfiguration.saveToPreferences(completion: completion)
            } catch {
                completion(.failure(error))
            }

        }
    }

}
