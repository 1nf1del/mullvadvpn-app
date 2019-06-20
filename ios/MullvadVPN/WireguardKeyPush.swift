//
//  WireguardKeyPush.swift
//  MullvadVPN
//
//  Created by pronebird on 20/06/2019.
//  Copyright © 2019 Amagicom AB. All rights reserved.
//

import Foundation
import ProcedureKit
import NetworkExtension

class WireguardKeyPush {

    static let shared = WireguardKeyPush()

    let queue: ProcedureQueue = {
        let queue = ProcedureQueue()
        queue.qualityOfService = .utility
        return queue
    }()

    func pushKey(accountToken: String, publicKey: Data) {
        let request = MullvadAPI.WireguardKeyRequest(
            accountToken: accountToken, publicKey: publicKey)

        let pushKey = MullvadAPI.pushWireguardKey(request)

        let parseResponse = TransformProcedure { try $0.result.get() }
            .injectResult(from: pushKey)

        let saveAddresses = TransformProcedure { (addresses) in
            // TODO: save addresses
            print("Got addresses: \(addresses)")
        }.injectResult(from: parseResponse)

        queue.addOperation(GroupProcedure(operations: [pushKey, parseResponse, saveAddresses]))
    }

}
