// SPDX-License-Identifier: MIT
// Copyright © 2018-2019 WireGuard LLC. All Rights Reserved.

import Foundation

struct Curve25519 {

    static let keyLength: Int = 32

    static func generatePrivateKey() -> Data {
        var privateKey = Data(repeating: 0, count: keyLength)
        privateKey.withUnsafeMutableUInt8Bytes { bytes in
            curve25519_generate_private_key(bytes)
        }
        assert(privateKey.count == keyLength)
        return privateKey
    }

    static func generatePublicKey(fromPrivateKey privateKey: Data) -> Data {
        assert(privateKey.count == keyLength)
        var publicKey = Data(repeating: 0, count: keyLength)
        privateKey.withUnsafeUInt8Bytes { privateKeyBytes in
            publicKey.withUnsafeMutableUInt8Bytes { bytes in
                curve25519_derive_public_key(bytes, privateKeyBytes)
            }
        }
        assert(publicKey.count == keyLength)
        return publicKey
    }
}

extension Data {
    func withUnsafeUInt8Bytes<R>(_ body: (UnsafePointer<UInt8>) -> R) -> R {
        assert(!isEmpty)
        return self.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> R in
            let bytes = ptr.bindMemory(to: UInt8.self)
            return body(bytes.baseAddress!) // might crash if self.count == 0
        }
    }

    mutating func withUnsafeMutableUInt8Bytes<R>(_ body: (UnsafeMutablePointer<UInt8>) -> R) -> R {
        assert(!isEmpty)
        return self.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) -> R in
            let bytes = ptr.bindMemory(to: UInt8.self)
            return body(bytes.baseAddress!) // might crash if self.count == 0
        }
    }

    mutating func withUnsafeMutableInt8Bytes<R>(_ body: (UnsafeMutablePointer<Int8>) -> R) -> R {
        assert(!isEmpty)
        return self.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) -> R in
            let bytes = ptr.bindMemory(to: Int8.self)
            return body(bytes.baseAddress!) // might crash if self.count == 0
        }
    }
}
