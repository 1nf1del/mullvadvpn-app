//
//  TunnelsManager.swift
//  MullvadVPN
//
//  Created by pronebird on 11/06/2019.
//  Copyright © 2019 Amagicom AB. All rights reserved.
//

import Foundation
import NetworkExtension
import os.log

private let kRelayConstraintKey = "relayConstraint"

class TunnelsManager {
    private(set) var tunnels: [NETunnelProviderManager]

    private init(tunnels: [NETunnelProviderManager]) {
        self.tunnels = tunnels
    }

    class func loadedFromPreferences(completion: @escaping (Result<TunnelsManager, Error>) -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { (tunnels, error) in
            if let error = error {
                completion(.failure(error))
            } else {
                let tunnelsManager = TunnelsManager(tunnels: tunnels ?? [])

                completion(.success(tunnelsManager))
            }
        }
    }

    func addTunnel(_ tunnel: NETunnelProviderManager, completion: @escaping (Result<Void, Error>) -> Void) {
        tunnel.saveToPreferences { (error) in
            if let error = error {
                completion(.failure(error))
            } else {
                self.tunnels.append(tunnel)

                completion(.success(()))
            }
        }
    }
}

extension NETunnelProviderManager {

    class func withPacketTunnelBundleIdentifier() -> NETunnelProviderManager {
        let protocolConfiguration = NETunnelProviderProtocol()
        protocolConfiguration.providerBundleIdentifier = ApplicationConfiguration.packetTunnelExtensionIdentifier

        let tunnelManager = NETunnelProviderManager()
        tunnelManager.protocolConfiguration = protocolConfiguration

        return tunnelManager
    }
}

extension NETunnelProviderProtocol {

    func getRelayConstraint() throws -> RelayConstraints? {
        return try decodeRelayConstraint()
    }

    func setRelayConstraint(_ relayConstraint: RelayConstraints) throws {
        var config = providerConfiguration ?? [:]
        config[kRelayConstraintKey] = try JSONEncoder().encode(relayConstraint)

        providerConfiguration = config
    }

    func getPrivateKey() throws -> Data? {
        if let passwordReference = passwordReference {
            return try PrivateKeyStore.openReference(passwordReference)
        } else {
            return nil
        }
    }

    func setPrivateKey(_ privateKey: Data) throws {
        if let oldPasswordReference = passwordReference {
            try PrivateKeyStore.deleteReference(oldPasswordReference)

            passwordReference = nil
        }

        passwordReference = try PrivateKeyStore.makeReference(privateKey: privateKey)
    }

    private func decodeRelayConstraint() throws -> RelayConstraints? {
        var constraint: RelayConstraints?

        if let relayConstraintData = providerConfiguration?[kRelayConstraintKey] as? Data {
            constraint = try JSONDecoder()
                .decode(RelayConstraints.self, from: relayConstraintData)
        }

        return constraint
    }

    private func encodeRelayConstraint(_ relayConstraint: RelayConstraints) throws {
        var config = providerConfiguration ?? [:]

        config[kRelayConstraintKey] = try JSONEncoder().encode(relayConstraint)

        providerConfiguration = config
    }

}
