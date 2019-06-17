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

    var relayConstraint: RelayConstraint? {
        get {
            do {
                return try decodeRelayConstraint()
            } catch {
                os_log(.error, "Failed to decode RelayConstraint: %s", error.localizedDescription)
                return nil
            }
        }
        set {
            var config = providerConfiguration ?? [:]

            do {
                config[kRelayConstraintKey] = try JSONEncoder().encode(relayConstraint)
            } catch {
                os_log(.error, "Failed to encode the RelayConstraint: %s")
            }

            providerConfiguration = config
        }
    }

    private func decodeRelayConstraint() throws -> RelayConstraint? {
        var constraint: RelayConstraint?

        if let relayConstraintData = providerConfiguration?[kRelayConstraintKey] as? Data {
            constraint = try JSONDecoder()
                .decode(RelayConstraint.self, from: relayConstraintData)
        }

        return constraint
    }

    private func encodeRelayConstraint(_ relayConstraint: RelayConstraint) throws {
        var config = providerConfiguration ?? [:]

        config[kRelayConstraintKey] = try JSONEncoder().encode(relayConstraint)

        providerConfiguration = config
    }

}
