//
//  StoredTunnelConfiguration.swift
//  MullvadVPN
//
//  Created by pronebird on 26/06/2019.
//  Copyright © 2019 Amagicom AB. All rights reserved.
//

import Foundation

/// The service name associated with the key store
private let kServiceName = "Tunnel Configuration Store"

/// A class for manipulating the TunnelConfiguration stored in Keychain
class StoredTunnelConfiguration {
    let accountToken: String

    init(accountToken: String) {
        self.accountToken = accountToken
    }

    init(keychainRef: Data) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: kServiceName,
            kSecValuePersistentRef: keychainRef,
            kSecReturnData: true]

        var result: CFTypeRef?
        let status =  SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess {
            let tunnelConfig = try JSONDecoder().decode(TunnelConfiguration.self, from: result as! Data)

            self.accountToken = tunnelConfig.accountToken
        } else {
            throw makeSecError(from: status)
        }
    }

    func get() throws -> TunnelConfiguration {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: accountToken,
            kSecAttrService: kServiceName,
            kSecReturnData: true
        ]

        var ref: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &ref)

        if status == errSecSuccess {
            return try JSONDecoder().decode(TunnelConfiguration.self, from: ref as! Data)
        } else {
            throw makeSecError(from: status)
        }
    }

    func update(_ updatedConfiguration: TunnelConfiguration) throws {
        let value = try JSONEncoder().encode(updatedConfiguration)

        let attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: accountToken,
            kSecAttrService: kServiceName,
            kSecValueData: value,
            kSecReturnData: false,

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
                kSecAttrAccount: accountToken,
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

        if status != errSecSuccess {
            throw makeSecError(from: status)
        }
    }

    func makeKeychainRef() throws -> Data {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: accountToken,
            kSecAttrService: kServiceName,
            kSecReturnPersistentRef: true
        ]

        var ref: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &ref)

        if status == errSecSuccess {
            return (ref as! Data)
        } else {
            throw makeSecError(from: status)
        }
    }

}

private func makeSecError(from status: OSStatus) -> Error {
    let localizedDescription = SecCopyErrorMessageString(status, nil)
        ?? "Unknown error" as CFString

    return NSError(domain: NSOSStatusErrorDomain,
                   code: Int(status),
                   userInfo: [NSLocalizedDescriptionKey: localizedDescription])
}
