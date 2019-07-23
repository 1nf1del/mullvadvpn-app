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
        let pushKey = MullvadAPI.pushWireguardKey(MullvadAPI.WireguardKeyRequest(
            accountToken: accountToken,
            publicKey: publicKey
        ))

        let parseResponse = TransformProcedure { try $0.result.get() }
            .injectResult(from: pushKey)

        let updateAssociatedAddresses = UpdateAssociatedAddressesProcedure()
            .injectResult(from: parseResponse) { (accountToken, $0) }

        let prepareConfiguration = PrepareSystemTunnelConfigurationProcedure()
            .injectResult(from: updateAssociatedAddresses)

        let saveConfiguration = SaveSystemTunnelConfigurationProcedure(configureUsing: {
            (tunnelManager) in
            // disable VPN configurations of other apps
            tunnelManager.isEnabled = true
        }).injectResult(from: prepareConfiguration)

        // Make sure we only update the system VPN configuration for the active account token
        saveConfiguration.addCondition(BlockCondition(block: { () -> Bool in
            let userDefaults = UserDefaultsInteractor.sharedApplicationGroupInteractor

            guard let activeAccountToken = userDefaults.accountToken else { return false }

            return activeAccountToken == accountToken
        }))

        queue.addOperation(GroupProcedure(operations: [
            pushKey,
            parseResponse,
            updateAssociatedAddresses,
            prepareConfiguration,
            saveConfiguration]))
    }
}

private class PrepareSystemTunnelConfigurationProcedure: Procedure, InputProcedure, OutputProcedure {
    var input: Pending<StoredTunnelConfiguration>
    var output: Pending<ProcedureResult<NETunnelProviderProtocol>> = .pending

    init(storedTunnelConfig: StoredTunnelConfiguration? = nil) {
        input = storedTunnelConfig.flatMap { .ready($0) } ?? .pending
        super.init()
    }

    override func execute() {
        guard let storedTunnelConfig = input.value else {
            finish(with: ProcedureKitError.requirementNotSatisfied())
            return
        }

        do {
            let tunnelConfig = try storedTunnelConfig.get()
            let protocolConfiguration = NETunnelProviderProtocol()

            protocolConfiguration.providerBundleIdentifier = ApplicationConfiguration.packetTunnelExtensionIdentifier
            protocolConfiguration.passwordReference = try storedTunnelConfig.makeKeychainRef()
            protocolConfiguration.serverAddress = "\(tunnelConfig.relayConstraints)"

            finish(withResult: .success(protocolConfiguration))
        } catch {
            finish(with: error)
        }
    }
}

private class UpdateStoredTunnelConfiguration: Procedure, InputProcedure {
    typealias UpdateBlock = (TunnelConfiguration) throws -> TunnelConfiguration

    var input: Pending<String>

    private let updateBlock: UpdateBlock

    init(accountToken: String? = nil, updateUsing updateBlock: @escaping UpdateBlock) {
        input = accountToken.flatMap { .ready($0) } ?? .pending
        self.updateBlock = updateBlock

        super.init()
    }

    override func execute() {
        guard let accountToken = input.value else {
            finish(with: ProcedureKitError.requirementNotSatisfied())
            return
        }
        
        let storedTunnelConfig = StoredTunnelConfiguration(accountToken: accountToken)

        do {
            let tunnelConfig = try storedTunnelConfig.get()
            let updatedTunnelConfig = try updateBlock(tunnelConfig)

            try storedTunnelConfig.update(updatedTunnelConfig)

            finish()
        } catch {
            finish(with: error)
        }
    }
}

private class UpdateAssociatedAddressesProcedure: Procedure, InputProcedure, OutputProcedure {
    var input: Pending<(accountToken: String, addresses: WireguardAssociatedAddresses)>
    var output: Pending<ProcedureResult<StoredTunnelConfiguration>> = .pending

    init(request: Input? = nil) {
        input = request.flatMap { .ready($0) } ?? .pending

        super.init()
    }

    override func execute() {
        guard let (accountToken, addresses) = input.value else {
            finish(with: ProcedureKitError.requirementNotSatisfied())
            return
        }

        do {
            let storedTunnelConfig = StoredTunnelConfiguration(accountToken: accountToken)

            var tunnelConfig = try storedTunnelConfig.get()
            tunnelConfig.interface.addresses = [
                addresses.ipv4Address,
                addresses.ipv6Address
            ]

            try storedTunnelConfig.update(tunnelConfig)

            finish(withResult: .success(storedTunnelConfig))
        } catch {
            finish(with: error)
        }
    }
}

private class SaveSystemTunnelConfigurationProcedure: GroupProcedure, InputProcedure {
    typealias ConfigurationBlock = (NETunnelProviderManager) -> Void

    var input: Pending<NETunnelProviderProtocol>

    init(dispatchQueue underlyingQueue: DispatchQueue? = nil,
         request: NETunnelProviderProtocol? = nil,
         configureUsing configurationBlock: @escaping ConfigurationBlock) {
        input = request.flatMap { .ready($0) } ?? .pending

        let loadTunnels = LoadTunnelProviderManagersProcedure()
        let makeTunnel = TransformProcedure { $0.first ?? NETunnelProviderManager() }
            .injectResult(from: loadTunnels)

        // Solely exists to capture the input from the group
        let inputConfig = TransformProcedure<NETunnelProviderProtocol, NETunnelProviderProtocol> { $0 }

        let collectOutputs = Collect2Procedure(from: makeTunnel, and: inputConfig)
        let assignConfig = TransformProcedure {  $0.protocolConfiguration = $1 }
            .injectResult(from: collectOutputs)

        let saveTunnel = SaveTunnelProviderManagerProcedure()
            .injectResult(from: makeTunnel)

        saveTunnel.addDependency(assignConfig)

        super.init(dispatchQueue: underlyingQueue, operations: [
            loadTunnels, makeTunnel, assignConfig, collectOutputs, saveTunnel])

        // Bind the input of the group procedure to the inputConfig procedure
        bindAndNotifySetInputReady(to: inputConfig)
    }
}
