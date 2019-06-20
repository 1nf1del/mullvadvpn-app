//
//  WireguardPrivateKey.swift
//  MullvadVPN
//
//  Created by pronebird on 20/06/2019.
//  Copyright © 2019 Amagicom AB. All rights reserved.
//

import Foundation

/// A convenience wrapper around the wireguard key
struct WireguardPrivateKey: Codable {
    let bytes: Data

    /// Initialize the new private key
    init() {
        bytes = Curve25519.generatePrivateKey()
    }

    /// Load with the existing private key
    init(bytes: Data) {
        self.bytes = bytes
    }

    /// Derive the public key
    func publicKey() -> Data {
        return Curve25519.generatePublicKey(fromPrivateKey: bytes)
    }
}
