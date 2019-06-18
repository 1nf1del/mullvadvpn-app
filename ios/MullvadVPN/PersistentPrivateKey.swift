//
//  PersistentPrivateKey.swift
//  MullvadVPN
//
//  Created by pronebird on 18/06/2019.
//  Copyright © 2019 Amagicom AB. All rights reserved.
//

import Foundation
import Security

struct PersistentPrivateKey {
    let accountToken: String

    init(accountToken: String) {
        self.accountToken = accountToken
    }

    func bytes() throws -> Data {
        if let bytes = try getPrivateKeyFromKeychain(returnRef: false) {
            return bytes
        } else {
            let privateKey = makePrivateKey()
            try addPrivateKeyToKeychain(privateKey)
            return privateKey
        }
    }

    func keychainReference() throws -> Data {
        if let ref = try getPrivateKeyFromKeychain(returnRef: true) {
            return ref
        } else {
            return try addPrivateKeyToKeychain(makePrivateKey())
        }
    }

    private func makePrivateKey() -> Data {
        return Curve25519.generatePrivateKey()
    }

    private func getPrivateKeyFromKeychain(returnRef: Bool) throws -> Data? {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: accountToken,
        ]

        if returnRef {
            query[kSecReturnPersistentRef] = true
        } else {
            query[kSecReturnData] = true
        }

        var ref: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &ref)

        if status == errSecSuccess {
            return ref as? Data
        } else {
            throw makeError(from: status)
        }
    }

    /// Store the private key in Keychain and return the persistent reference
    @discardableResult private func addPrivateKeyToKeychain(_ privateKey: Data) throws -> Data {
        let attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: accountToken,
            kSecValueData: privateKey,

            // Return persistent reference
            kSecReturnPersistentRef: true,

            // Share the key with the application group
            kSecAttrAccessGroup: ApplicationConfiguration.securityGroupIdentifier,

            // The data will be accessible after the user unlocks the device, and then until
            // the device is restarted.
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ]

        var ref: CFTypeRef?
        let status = SecItemAdd(attributes as CFDictionary, &ref)

        if status == errSecSuccess {
            return ref as! Data
        } else {
            throw makeError(from: status)
        }
    }
}

private func makeError(from status: OSStatus) -> NSError {
    let localizedDescription = SecCopyErrorMessageString(status, nil)
        ?? "Unknown error" as CFString

    return NSError(domain: NSOSStatusErrorDomain,
                   code: Int(status),
                   userInfo: [NSLocalizedDescriptionKey: localizedDescription])
}
