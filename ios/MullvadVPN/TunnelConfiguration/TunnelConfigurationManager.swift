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

/// The service name associated with the key store
private let kServiceName = "Tunnel Configuration Store"

typealias KeychainRef = Data

/// A tunnel configuration store
class TunnelConfigurationManager {

    static let shared = TunnelConfigurationManager()

    let queue: ProcedureQueue = {
        let queue = ProcedureQueue()
        queue.qualityOfService = .utility
        return queue
    }()

    private init() {}

    func addConfiguration(_ configuration: TunnelConfiguration) throws -> KeychainRef {
        let value = try JSONEncoder().encode(configuration)
        let keychainRef = try Keychain.makeReference(with: value, account: configuration.accountToken)

        pushPublicKey(
            accountToken: configuration.accountToken,
            publicKey: configuration.interface.privateKey.publicKey())

        return keychainRef
    }

    func getConfiguration(accountToken: String) throws -> TunnelConfiguration? {
        if let value = try Keychain.queryValue(account: accountToken) {
            return try JSONDecoder().decode(TunnelConfiguration.self, from: value)
        } else {
            return nil
        }
    }

    func getConfigurationKeychainRef(accountToken: String) throws -> KeychainRef? {
        return try Keychain.findReference(account: accountToken)
    }

    func getConfigurationFromKeychainRef(_ keychainRef: KeychainRef) throws -> TunnelConfiguration {
        let value = try Keychain.openReference(keychainRef)

        return try JSONDecoder().decode(TunnelConfiguration.self, from: value)
    }

    private func pushPublicKey(accountToken: String, publicKey: Data) {
        let request = MullvadAPI.WireguardKeyRequest(
            accountToken: accountToken, publicKey: publicKey)

        let pushKey = MullvadAPI.pushWireguardKey(request)

        let parseResponse = TransformProcedure { try $0.result.get() }
            .injectResult(from: pushKey)

        let saveAddresses = TransformProcedure { [weak self] (addresses) in
            try self?.saveAssociatedAddresses(accountToken: accountToken, addresses: addresses)
            }.injectResult(from: parseResponse)

        queue.addOperation(GroupProcedure(operations: [pushKey, parseResponse, saveAddresses]))
    }

    private func saveAssociatedAddresses(accountToken: String, addresses: WireguardAssociatedAddresses) throws {
        guard var tunnelConfig = try getConfiguration(accountToken: accountToken) else { return }
        tunnelConfig.interface.addresses = [addresses.ipv4Address, addresses.ipv6Address]

        let value = try JSONEncoder().encode(tunnelConfig)
        let keychainRef = try Keychain.makeReference(with: value, account: accountToken)

        updateSystemTunnelConfiguration(keychainRef: keychainRef)
    }

    func updateSystemTunnelConfiguration(keychainRef: KeychainRef) {
        NETunnelProviderManager.loadAllFromPreferences { (managers, error) in
            if let error = error {
                os_log(.error, "Failed to load NETunnelProviderManager from preferences: %s",
                       error.localizedDescription)
                return
            }

            let protocolConfiguration = NETunnelProviderProtocol()
            protocolConfiguration.providerBundleIdentifier = ApplicationConfiguration.packetTunnelExtensionIdentifier
            protocolConfiguration.passwordReference = keychainRef
            protocolConfiguration.serverAddress = "Multiple"

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

private struct Keychain {

    static func openReference(_ keychainRef: KeychainRef) throws -> Data {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecValuePersistentRef: keychainRef,
            kSecReturnData: true
        ]

        var dataRef: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &dataRef)

        if status == errSecSuccess {
            return dataRef as! Data
        } else {
            throw makeError(from: status)
        }
    }

    static func findReference(account: String) throws -> KeychainRef? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: account,
            kSecAttrService: kServiceName,
            kSecReturnPersistentRef: true
        ]

        var ref: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &ref)

        if status == errSecItemNotFound {
            return nil
        } else if status == errSecSuccess {
            return (ref as! Data)
        } else {
            throw makeError(from: status)
        }
    }

    static func makeReference(with value: Data, account: String) throws -> KeychainRef {
        let attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: account,
            kSecAttrService: kServiceName,
            kSecValueData: value,
            kSecReturnPersistentRef: true,

            // Share the key with the application group
            kSecAttrAccessGroup: ApplicationConfiguration.securityGroupIdentifier,

            // The data will be accessible after the user unlocks the device, and then until
            // the device is restarted.
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ]

        var ref: CFTypeRef?
        var status = SecItemAdd(attributes as CFDictionary, &ref)

        if status == errSecDuplicateItem {
            var query: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrAccount: account,
                kSecAttrService: kServiceName,
            ]

            let update: [CFString: Any] = [
                kSecValueData: value
            ]

            status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            if status == errSecSuccess {
                query[kSecReturnPersistentRef] = true
                status = SecItemCopyMatching(query as CFDictionary, &ref)
            }
        }

        if status == errSecSuccess {
            return ref as! Data
        } else {
            throw makeError(from: status)
        }
    }

    static func queryValue(account: String) throws -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: account,
            kSecAttrService: kServiceName,
            kSecReturnData: true
        ]

        var ref: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &ref)

        if status == errSecItemNotFound {
            return nil
        } else if status == errSecSuccess {
            return (ref as! Data)
        } else {
            throw makeError(from: status)
        }
    }

    static func makeError(from status: OSStatus) -> Error {
        let localizedDescription = SecCopyErrorMessageString(status, nil)
            ?? "Unknown error" as CFString

        return NSError(domain: NSOSStatusErrorDomain,
                       code: Int(status),
                       userInfo: [NSLocalizedDescriptionKey: localizedDescription])
    }

}
