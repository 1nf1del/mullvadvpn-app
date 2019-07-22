//
//  TunnelConfigurationInteractor.swift
//  MullvadVPN
//
//  Created by pronebird on 19/07/2019.
//  Copyright © 2019 Amagicom AB. All rights reserved.
//

import Foundation
import os

/// A class that performs the primary operations over the tunnel configuration
class TunnelConfigurationInteractor {

    private init() {}

    class func makeTunnelConfiguration(for accountToken: String) throws -> TunnelConfiguration {
        let tunnelConfigManager = TunnelConfigurationManager.shared

        if let tunnelConfig = try? tunnelConfigManager.getConfiguration(for: accountToken) {
            return tunnelConfig
        } else {
            let tunnelConfig = TunnelConfiguration.default(with: accountToken)
            try tunnelConfigManager.saveConfiguration(tunnelConfig)
            return tunnelConfig
        }
    }

    /// Updates the relay constraint for the current account
    class func updateRelayConstraints(_ constraints: RelayConstraints) throws {
        let tunnelConfigManager = TunnelConfigurationManager.shared

        guard let accountToken = UserDefaultsInteractor.sharedApplicationGroupInteractor.accountToken
            else { return }

        var tunnelConfig =
            (try? tunnelConfigManager.getConfiguration(for: accountToken))
                ?? TunnelConfiguration.default(with: accountToken)

        tunnelConfig.relayConstraints = constraints
        try tunnelConfigManager.saveConfiguration(tunnelConfig)
    }

}
