//
//  PrivateKeyStore.swift
//  MullvadVPN
//
//  Created by pronebird on 18/06/2019.
//  Copyright © 2019 Amagicom AB. All rights reserved.
//

import Foundation
import Security

/// A WireGuard private key storage using Keychain
struct PrivateKeyStore {

    private init() {}

    /// Open the Keychain reference and return the private key back
    static func openReference(_ ref: Data) throws -> Data {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecValuePersistentRef: ref,
            kSecReturnData: true
        ]

        var privateKey: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &privateKey)

        if let privateKey = privateKey as? Data, status == errSecSuccess {
            return privateKey
        } else {
            throw makeError(from: status)
        }
    }

    /// Store the private key in Keychain and return the persistent reference
    static func makeReference(privateKey: Data) throws -> Data {
        let attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecValueData: privateKey,

            // Return the peristent reference on save
            kSecReturnPersistentRef: true,

            // Share the key with the application group
            kSecAttrAccessGroup: ApplicationConfiguration.securityGroupIdentifier,

            // The data will be accessible after the user unlocks the device, and then until
            // the device is restarted.
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ]

        var ref: CFTypeRef?
        let status = SecItemAdd(attributes as CFDictionary, &ref)

        if let refData = ref as? Data, status == errSecSuccess {
            return refData
        } else {
            throw makeError(from: status)
        }
    }

    /// Delete the private key from Keychain using the persistent reference
    static func deleteReference(_ ref: Data) throws {
        let status = SecItemDelete([kSecValuePersistentRef: ref] as CFDictionary)

        if status != errSecSuccess {
            throw makeError(from: status)
        }
    }

    private static func makeError(from status: OSStatus) -> NSError {
        let localizedDescription = SecCopyErrorMessageString(status, nil)
            ?? "Unknown error" as CFString

        return NSError(domain: NSOSStatusErrorDomain,
                       code: Int(status),
                       userInfo: [NSLocalizedDescriptionKey: localizedDescription])
    }
}
