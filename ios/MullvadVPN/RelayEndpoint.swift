//
//  RelayEndpoint.swift
//  MullvadVPN
//
//  Created by pronebird on 13/06/2019.
//  Copyright © 2019 Amagicom AB. All rights reserved.
//

import Foundation
import Network

struct RelayEndpoint: CustomStringConvertible {
    let address: IPv4Address
    let port: UInt16

    var description: String {
        return "\(address):\(port)"
    }
}
