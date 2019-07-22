//
//  WireguardPrivateKeyStore.swift
//  MullvadVPN
//
//  Created by pronebird on 19/06/2019.
//  Copyright © 2019 Amagicom AB. All rights reserved.
//

import Foundation
import ProcedureKit
import NetworkExtension
import os

/// A tunnel configuration store
class TunnelConfigurationManager {

    static let shared = TunnelConfigurationManager()

    let queue: ProcedureQueue = {
        let queue = ProcedureQueue()
        queue.qualityOfService = .utility
        return queue
    }()

    private init() {}

    func saveConfiguration(_ configuration: TunnelConfiguration) throws {
        let storedTunnelConfig = StoredTunnelConfiguration(accountToken: configuration.accountToken)

        try storedTunnelConfig.update(configuration)

        pushPublicKey(
            configuration.interface.privateKey.publicKey(),
            for: configuration.accountToken)
    }

    func getConfiguration(for accountToken: String) throws -> TunnelConfiguration {
        let storedTunnelConfig = StoredTunnelConfiguration(accountToken: accountToken)

        return try storedTunnelConfig.get()
    }

    private func pushPublicKey(_ publicKey: Data, for accountToken: String) {
        let request = MullvadAPI.WireguardKeyRequest(
            accountToken: accountToken,
            publicKey: publicKey
        )

        let pushKey = MullvadAPI.pushWireguardKey(request)

        let parseResponse = TransformProcedure { try $0.result.get() }
            .injectResult(from: pushKey)

        let saveAddresses = TransformProcedure { [weak self] (addresses) in
            try self?.updateAssociatedAddresses(
                accountToken: accountToken,
                addresses: addresses
            )
            }.injectResult(from: parseResponse)

        queue.addOperation(GroupProcedure(operations: [pushKey, parseResponse, saveAddresses]))
    }

    private func updateAssociatedAddresses(accountToken: String, addresses: WireguardAssociatedAddresses) throws {
        let storedTunnelConfig = StoredTunnelConfiguration(accountToken: accountToken)

        var tunnelConfig = try storedTunnelConfig.get()
        tunnelConfig.interface.addresses = [addresses.ipv4Address, addresses.ipv6Address]
        try storedTunnelConfig.update(tunnelConfig)

        let userDefaultsInteractor = UserDefaultsInteractor.sharedApplicationGroupInteractor

        // Make sure we only update the system tunnel configuration for the active account token
        // since we only use one system VPN profile.
        if tunnelConfig.accountToken == userDefaultsInteractor.accountToken {
            updateSystemTunnelConfiguration(
                keychainRef: try storedTunnelConfig.makeKeychainRef(),
                serverAddress: "\(tunnelConfig.relayConstraints)"
            )
        }
    }

    func updateSystemTunnelConfiguration(keychainRef: Data, serverAddress: String) {
        NETunnelProviderManager.loadAllFromPreferences { (managers, error) in
            if let error = error {
                os_log(.error, "Failed to load NETunnelProviderManager from preferences: %s",
                       error.localizedDescription)
                return
            }

            let protocolConfiguration = NETunnelProviderProtocol()
            protocolConfiguration.providerBundleIdentifier = ApplicationConfiguration.packetTunnelExtensionIdentifier
            protocolConfiguration.passwordReference = keychainRef
            protocolConfiguration.serverAddress = serverAddress

            let tunnelManagers = managers ?? []
            let firstTunnel = tunnelManagers.first ?? NETunnelProviderManager()
            firstTunnel.protocolConfiguration = protocolConfiguration
            firstTunnel.isEnabled = true

            firstTunnel.saveToPreferences(completionHandler: { (error) in
                if let error = error {
                    os_log(.error, "Failed to save tunnel to preferences: %s", error.localizedDescription)
                }
                do {
                    try firstTunnel.connection.startVPNTunnel()
                } catch {
                    os_log(.error, "Failed to start the VPN tunnel: %s", error.localizedDescription)
                }
            })
        }
    }
}
